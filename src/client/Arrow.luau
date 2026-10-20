--!strict
-- The guide (docs/PLAN.md, Step 2): a trail of yellow chevrons on the ground from the player to the
-- next thing to do, marching towards it. There is no
-- caption or marker above the pad (the pads and the goal row already say what to do). It only guides
-- the first steps: to a free plot, then to the first player's pad.
-- After the first purchase it disappears. Then it shows once, for a short time, towards the Store
-- pad, only so the player knows the Store exists, and never again. Later goals are shown by the
-- goal row alone.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Goals = require(ReplicatedStorage.Shared.Goals)
local Roster = require(ReplicatedStorage.Shared.Roster)
local State = require(script.Parent.State)

local player = Players.LocalPlayer

local ARRIVED_DISTANCE = 7
local UPDATE_SECONDS = 0.25
local STORE_HINT_SECONDS = 20 -- how long the Store hint can show at most
local STORE_HINT_NEAR = 14 -- the hint ends when the player gets this close to the Store pad
local GOLD = Color3.fromRGB(255, 205, 20)
local CHEVRONS = 12 -- the most chevrons on the ground at once
local SPACING = 5 -- studs between two chevrons
local FIRST_DISTANCE = 4 -- the first chevron is this far ahead of the player
local CHEVRON_SIZE = 5.5 -- studs, the square the chevron is drawn on
local MARCH_SPEED = 3 -- studs per second the trail moves towards the target
local GROUND_OFFSET = 0.12

local guide: { kind: string, endsAt: number }? = nil -- asked for by a HUD icon
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

-- The pad part to point at right now, or nil for no guidance.
local function target(root: BasePart): BasePart?
	-- A tapped HUD icon points at its spot for a short time.
	if guide ~= nil then
		if os.clock() > guide.endsAt then
			guide = nil
		else
			local spot = nearestPad(root, guide.kind, nil)
			if spot ~= nil then
				return spot
			end
		end
	end
	local goal = Goals.next(State.data, State.hasPlot())
	if goal.kind == "claim" then
		return nearestPad(root, "claim", nil)
	end
	-- Before the first purchase: the first player's pad.
	if goal.kind == "player" and Roster.ownedCount(State.data) == 0 then
		return nearestPad(root, "player", goal.id)
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
			return nil
		end
		return store
	end
	return nil
end

-- Points the guide at the nearest pad of `kind` for `seconds` (a tapped daily icon uses this).
function Arrow.guide(kind: string, seconds: number)
	guide = { kind = kind, endsAt = os.clock() + seconds }
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

	-- The chevrons: flat squares lying on the ground, each with two rounded bars that meet in a point
	-- (a ">" pointing along the trail). They exist only on this client.
	local folder = Instance.new("Folder")
	folder.Name = "GuideChevrons"
	folder.Parent = Workspace

	type Chevron = { part: Part, gui: SurfaceGui, group: CanvasGroup }
	local chevrons: { Chevron } = {}
	local function bar(parent: Instance, x: number, rotation: number)
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(x, 0.45)
		frame.Size = UDim2.fromScale(0.62, 0.26)
		frame.Rotation = rotation
		frame.BackgroundColor3 = GOLD
		frame.BorderSizePixel = 0
		frame.Parent = parent
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
	end
	for index = 1, CHEVRONS do
		local part = Instance.new("Part")
		part.Name = "Chevron" .. index
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(CHEVRON_SIZE, 0.1, CHEVRON_SIZE)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(200, 200)
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.Enabled = false
		gui.Parent = part
		local group = Instance.new("CanvasGroup")
		group.Size = UDim2.fromScale(1, 1)
		group.BackgroundTransparency = 1
		group.Rotation = 90 -- the top of a part's surface gui points sideways: turn the tip to the front
		group.Parent = gui
		bar(group, 0.28, -45)
		bar(group, 0.72, 45)
		part.Parent = folder
		table.insert(chevrons, { part = part, gui = gui, group = group })
	end

	local aim: BasePart? = nil -- the pad the trail points at, nil for no trail
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < UPDATE_SECONDS then
			return
		end
		elapsed = 0

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			aim = nil
			return
		end
		local part = target(root)
		-- Hide the guide on the target itself or while the pad is filling.
		local onTarget = part ~= nil
			and (part.Position - root.Position).Magnitude < ARRIVED_DISTANCE
		if
			part == nil
			or onTarget
			or player:GetAttribute("padKey") == part:GetAttribute("PadKey")
		then
			aim = nil
			return
		end
		aim = part
	end)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local goal = aim
		if goal == nil or not root or not root:IsA("BasePart") then
			for _, chevron in chevrons do
				chevron.gui.Enabled = false
			end
			return
		end
		rayParams.FilterDescendantsInstances = { folder, character }
		local from = Vector3.new(root.Position.X, 0, root.Position.Z)
		local to = Vector3.new(goal.Position.X, 0, goal.Position.Z)
		local flat = to - from
		local distance = flat.Magnitude
		if distance < 0.1 then
			return
		end
		local direction = flat / distance
		local lastDistance = distance - ARRIVED_DISTANCE -- no chevron on the pad itself
		local march = (os.clock() * MARCH_SPEED) % SPACING
		for index, chevron in chevrons do
			local along = FIRST_DISTANCE + (index - 1) * SPACING + march
			-- Fades in just ahead of the player and out before the pad, so nothing pops.
			local strength =
				math.min((along - FIRST_DISTANCE) / SPACING, (lastDistance - along) / SPACING, 1)
			local gui = chevron.gui
			if strength <= 0 then
				gui.Enabled = false
			else
				local spot = from + direction * along
				local hit = Workspace:Raycast(
					Vector3.new(spot.X, root.Position.Y + 3, spot.Z),
					Vector3.new(0, -40, 0),
					rayParams
				)
				local y = if hit then hit.Position.Y + GROUND_OFFSET else root.Position.Y - 3
				local position = Vector3.new(spot.X, y, spot.Z)
				chevron.part.CFrame = CFrame.lookAt(position, position + direction)
				chevron.group.GroupTransparency = 1 - strength
				gui.Enabled = true
			end
		end
	end)
end

return Arrow
