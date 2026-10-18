--!strict
-- The guide arrow (docs/PLAN.md, Step 2): a beam from the player to the next thing to do. It points
-- at a free plot first, then follows the "Next goal" path, and hides when the player is there.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Goals = require(ReplicatedStorage.Shared.Goals)
local State = require(script.Parent.State)

local player = Players.LocalPlayer

local ARRIVED_DISTANCE = 7
local UPDATE_SECONDS = 0.25

local Arrow = {}

-- The pad part the player should go to next, or nil.
local function targetPart(root: BasePart): BasePart?
	local goal = Goals.next(State.data, State.hasPlot())
	local wantKind: string, wantId: string? = "", nil
	if goal.kind == "claim" then
		wantKind = "claim"
	elseif goal.kind == "player" then
		wantKind, wantId = "player", goal.id
	elseif goal.kind == "store" then
		wantKind, wantId = "store", goal.id
	elseif goal.kind == "stadium" then
		wantKind = "stadium"
	else
		return nil
	end

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

function Arrow.init()
	local beam = Instance.new("Beam")
	beam.Name = "GuideArrow"
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 220, 60))
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
			beam.Enabled = false
			return
		end
		local target = targetPart(root)
		-- Hide the arrow on the target itself or while the pad is filling.
		local onTarget = target ~= nil
			and (target.Position - root.Position).Magnitude < ARRIVED_DISTANCE
		if
			target == nil
			or onTarget
			or player:GetAttribute("padKey") == target:GetAttribute("PadKey")
		then
			beam.Enabled = false
			return
		end

		if from.Parent ~= root then
			from.Parent = root
		end
		if to.Parent ~= target then
			to.Parent = target
		end
		if beam.Parent ~= root then
			beam.Parent = root
		end
		beam.Enabled = true
	end)
end

return Arrow
