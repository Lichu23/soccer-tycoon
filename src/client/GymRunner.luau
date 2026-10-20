--!strict
-- The player's own Roblox character works out at the conditioning stations of the Training Gym: on the
-- agility ladder it runs along the ladder and back in a loop, on the treadmill it runs in place with the
-- run animation of its own avatar. It only starts while the server says the player is training (on the
-- pad with stamina left) and stops the moment the player takes the controls, leaves the pad or runs out
-- of stamina. The TP are the server's: this only moves and animates the character, nothing here pays.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local LADDER_SPEED = 10 -- studs per second along the ladder (the normal walk speed is faster)
local LADDER_HALF_LENGTH = 6 -- the ladder lies along x of its marker, inside the 14 stud pad
local RETURN_LANE = 4.5 -- the way back runs beside the ladder
local REACH_DISTANCE = 1.2
local LEG_TIMEOUT = 4
local TREADMILL_SPEED = 1.25 -- the run animation plays a little faster than normal

local GymRunner = {}

-- The own plot's marker with this name (the markers carry the position of the stations).
local function ownMarker(name: string): BasePart?
	local plots = Workspace:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			local markers = plot:FindFirstChild("Markers")
			local marker = if markers then markers:FindFirstChild(name) else nil
			return if marker and marker:IsA("BasePart") then marker else nil
		end
	end
	return nil
end

-- The run animation of the player's own avatar (the Animate script keeps it, whatever the rig).
local function runAnimation(character: Model): Animation?
	local animate = character:FindFirstChild("Animate")
	local run = if animate then animate:FindFirstChild("run") else nil
	if run == nil then
		return nil
	end
	local anim = run:FindFirstChild("RunAnim") or run:FindFirstChildWhichIsA("Animation")
	return if anim and anim:IsA("Animation") then anim else nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function GymRunner.init()
	-- Each change of station starts a new "run"; an old one stops itself when it sees its number is stale.
	local runNumber = 0
	local cleanup: (() -> ())? = nil

	local function stopCurrent()
		runNumber += 1
		if cleanup then
			cleanup()
			cleanup = nil
		end
	end

	local function runLadder(myRun: number, character: Model, humanoid: Humanoid, root: BasePart)
		local marker = ownMarker("TrainingLadder")
		if marker == nil then
			return
		end
		local oldSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = LADDER_SPEED
		cleanup = function()
			if humanoid.Parent then
				humanoid.WalkSpeed = oldSpeed
				humanoid:Move(Vector3.zero)
			end
		end
		-- Along the ladder, across to the return lane, back, and across again.
		local points = {
			Vector3.new(-LADDER_HALF_LENGTH, 0, 0),
			Vector3.new(LADDER_HALF_LENGTH, 0, 0),
			Vector3.new(LADDER_HALF_LENGTH, 0, RETURN_LANE),
			Vector3.new(-LADDER_HALF_LENGTH, 0, RETURN_LANE),
		}
		local index = 1
		while runNumber == myRun and character.Parent do
			local target = marker.CFrame:PointToWorldSpace(points[index])
			humanoid:MoveTo(target)
			local startedAt = os.clock()
			while
				runNumber == myRun
				and flatDistance(root.Position, target) > REACH_DISTANCE
				and os.clock() - startedAt < LEG_TIMEOUT
			do
				task.wait(0.1)
			end
			index = index % #points + 1
		end
	end

	local function runTreadmill(myRun: number, character: Model, humanoid: Humanoid)
		local animation = runAnimation(character)
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animation == nil or animator == nil then
			return
		end
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play(0.2)
		track:AdjustSpeed(TREADMILL_SPEED)
		cleanup = function()
			track:Stop(0.2)
		end
		while runNumber == myRun and character.Parent do
			task.wait(0.25)
		end
	end

	local function refresh()
		stopCurrent()
		local myRun = runNumber
		if player:GetAttribute("training") ~= true then
			return
		end
		local station = player:GetAttribute("trainingStation")
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if character == nil or humanoid == nil or root == nil or not root:IsA("BasePart") then
			return
		end
		if station == "ladder" then
			task.spawn(runLadder, myRun, character, humanoid, root)
		elseif station == "treadmill" then
			task.spawn(runTreadmill, myRun, character, humanoid)
		end
	end

	player:GetAttributeChangedSignal("trainingStation"):Connect(refresh)
	player:GetAttributeChangedSignal("training"):Connect(refresh)
	player.CharacterRemoving:Connect(stopCurrent)
end

return GymRunner
