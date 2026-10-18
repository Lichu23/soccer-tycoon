--!strict
-- The guide (docs/PLAN.md, Step 2): a beam from the player to the next thing to do, and a bouncing
-- marker with a short caption above the target pad that shows through walls, so it is always clear
-- where to go. It only guides the first steps: to a free plot, then to the first player's pad.
-- After the first purchase it disappears. Then it shows once, for a short time, towards the Store
-- pad, only so the player knows the Store exists, and never again. Later goals are shown by the
-- goal row alone.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Goals = require(ReplicatedStorage.Shared.Goals)
local Roster = require(ReplicatedStorage.Shared.Roster)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local ARRIVED_DISTANCE = 7
local UPDATE_SECONDS = 0.25
local STORE_HINT_SECONDS = 20 -- how long the Store hint can show at most
local STORE_HINT_NEAR = 14 -- the hint ends when the player gets this close to the Store pad
local MARKER_HEIGHT = 12 -- studs above the pad
local GOLD = Color3.fromRGB(255, 220, 60)

local guide: { kind: string, caption: string, endsAt: number }? = nil -- asked for by a HUD icon
local lastOwned: number? = nil -- players owned at the last state change (nil before the first)
local storeHintStartedAt: number? = nil
local storeHintDone = false

local Arrow = {}

-- The nearest pad part of this kind (and pad id) the player may use.
local function nearestPad(root: BasePart, wantKind: string, wantId: string?): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, part in CollectionService:GetTagged("Pad") do
		if part:IsA("BasePart") and part:GetAttribute("Kind") == wantKind then
			local ownerId = part:GetAttribute("OwnerUserId")
			local mine = ownerId == 0 or ownerId == player.UserId
			local idMatches = wantId == nil or part:GetAttribute("PadId") == wantId
			if mine and idMatches then
				local distance = (part.Position - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = part, distance
				end
			end
		end
	end
	return best
end

-- The pad part to point at right now and the caption above it, or nil for no guidance.
local function target(root: BasePart): (BasePart?, string)
	-- A tapped HUD icon points at its spot for a short time.
	if guide ~= nil then
		if os.clock() > guide.endsAt then
			guide = nil
		else
			local spot = nearestPad(root, guide.kind, nil)
			if spot ~= nil then
				return spot, guide.caption
			end
		end
	end
	local goal = Goals.next(State.data, State.hasPlot())
	if goal.kind == "claim" then
		return nearestPad(root, "claim", nil), "Claim your plot"
	end
	-- Before the first purchase: the first player's pad.
	if goal.kind == "player" and Roster.ownedCount(State.data) == 0 then
		return nearestPad(root, "player", goal.id), "Buy your first player"
	end

	-- After it: the Store hint, once and for a short time.
	local startedAt = storeHintStartedAt
	if startedAt ~= nil and not storeHintDone then
		local store = nearestPad(root, "store", "cashPerMatch")
		local expired = os.clock() - startedAt > STORE_HINT_SECONDS
		local bought = State.data.storeLevels.cashPerMatch > 0
		local near = store ~= nil and (store.Position - root.Position).Magnitude < STORE_HINT_NEAR
		if expired or bought or near or store == nil then
			storeHintDone = true
			return nil, ""
		end
		return store, "Upgrades are here"
	end
	return nil, ""
end

-- A bouncing diamond with a caption, drawn on top of walls.
local function buildMarker(): (BillboardGui, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GuideMarker"
	billboard.Size = UDim2.fromOffset(190, 74)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.MaxDistance = 400

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.fromOffset(95, 0)
	caption.Size = UDim2.fromOffset(190, 30)
	caption.BackgroundColor3 = Style.ui.dark
	caption.BackgroundTransparency = 0.2
	caption.TextColor3 = GOLD
	caption.Font = Style.font
	caption.TextSize = 17
	caption.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = caption
	local outline = Instance.new("UIStroke")
	outline.Color = GOLD
	outline.Thickness = 2
	outline.Parent = caption

	local diamond = Instance.new("Frame")
	diamond.Name = "Diamond"
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromOffset(95, 52)
	diamond.Size = UDim2.fromOffset(24, 24)
	diamond.Rotation = 45
	diamond.BackgroundColor3 = GOLD
	diamond.BorderSizePixel = 0
	diamond.Parent = billboard
	local diamondOutline = Instance.new("UIStroke")
	diamondOutline.Color = Style.ui.dark
	diamondOutline.Thickness = 2
	diamondOutline.Parent = diamond

	return billboard, caption
end

-- Points the guide at the nearest pad of `kind` for `seconds` (a tapped daily icon uses this).
function Arrow.guide(kind: string, seconds: number, caption: string)
	guide = { kind = kind, caption = caption, endsAt = os.clock() + seconds }
end

function Arrow.init()
	-- The Store hint starts when the first player is bought during this session. A returning
	-- player who already owns players never sees it.
	State.onChange(function()
		if not State.loaded then
			return
		end
		local owned = Roster.ownedCount(State.data)
		if lastOwned == 0 and owned >= 1 and not storeHintDone and storeHintStartedAt == nil then
			storeHintStartedAt = os.clock()
		end
		lastOwned = owned
	end)

	local beam = Instance.new("Beam")
	beam.Name = "GuideArrow"
	beam.Color = ColorSequence.new(GOLD)
	beam.Width0 = 1.4
	beam.Width1 = 1.4
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Transparency = NumberSequence.new(0.15)
	beam.Enabled = false

	local from = Instance.new("Attachment")
	from.Name = "GuideFrom"
	local to = Instance.new("Attachment")
	to.Name = "GuideTo"
	beam.Attachment0 = from
	beam.Attachment1 = to

	local marker, caption = buildMarker()
	marker.Enabled = false

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		-- The marker bobs every frame.
		marker.StudsOffset = Vector3.new(0, MARKER_HEIGHT + math.sin(os.clock() * 4) * 0.8, 0)

		elapsed += dt
		if elapsed < UPDATE_SECONDS then
			return
		end
		elapsed = 0

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			beam.Enabled = false
			marker.Enabled = false
			return
		end
		local part, text = target(root)
		-- Hide the guide on the target itself or while the pad is filling.
		local onTarget = part ~= nil
			and (part.Position - root.Position).Magnitude < ARRIVED_DISTANCE
		if
			part == nil
			or onTarget
			or player:GetAttribute("padKey") == part:GetAttribute("PadKey")
		then
			beam.Enabled = false
			marker.Enabled = false
			return
		end

		if from.Parent ~= root then
			from.Parent = root
		end
		if to.Parent ~= part then
			to.Parent = part
		end
		if beam.Parent ~= root then
			beam.Parent = root
		end
		beam.Enabled = true

		caption.Text = text
		if marker.Adornee ~= part then
			marker.Adornee = part
		end
		if marker.Parent ~= part then
			marker.Parent = part
		end
		marker.Enabled = true
	end)
end

return Arrow
