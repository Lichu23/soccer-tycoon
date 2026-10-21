--!strict
-- The player's own Roblox character works out at the conditioning stations of the Training Gym: on the
-- agility ladder it runs along the ladder and back in a loop, on the treadmill it runs in place with the
-- run animation of its own avatar, held in the middle of the belt until a jump takes it off. It only
-- starts while the server says the player is training (on the pad with stamina left) and stops the
-- moment the player takes the controls (a jump on the treadmill), leaves the pad or runs out of
-- stamina. The TP are the server's: this only moves and animates the character, nothing here pays.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local LADDER_SPEED = 10 -- studs per second along the ladder (the normal walk speed is faster)
local LADDER_HALF_LENGTH = 6 -- the ladder lies along x of its marker, inside the 14 stud pad
local RETURN_LANE = 4.5 -- the way back runs beside the ladder
local REACH_DISTANCE = 1.2
local LEG_TIMEOUT = 4
local TREADMILL_SPEED = 1.25 -- the run animation plays a little faster than normal
local HOLD_TOLERANCE = 0.3 -- studs the runner may drift from the middle of the belt
local HOP_DISTANCE = 12 -- a jump walks the runner this far back from the middle: down the ramp, off the pad

local GymRunner = {}

local function ownPlot(): Instance?
	local plots = Workspace:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

-- The own plot's marker with this name (the markers carry the position of the stations).
local function ownMarker(name: string): BasePart?
	local plot = ownPlot()
	local markers = if plot then plot:FindFirstChild("Markers") else nil
	local marker = if markers then markers:FindFirstChild(name) else nil
	return if marker and marker:IsA("BasePart") then marker else nil
end

-- The middle of the own treadmill's belt (its invisible Stand) and the flat way to its console, or nil.
local function treadmillSpot(): (Vector3?, Vector3?)
	local plot = ownPlot()
	local gym = if plot then plot:FindFirstChild("Gym") else nil
	local treadmill = if gym then gym:FindFirstChild("Treadmill") else nil
	local stand = if treadmill then treadmill:FindFirstChild("Stand") else nil
	local console = if treadmill then treadmill:FindFirstChild("Console") else nil
	if stand == nil or not stand:IsA("BasePart") or console == nil or not console:IsA("Model") then
		return nil, nil
	end
	local toConsole = console:GetPivot().Position - stand.Position
	toConsole = Vector3.new(toConsole.X, 0, toConsole.Z)
	if toConsole.Magnitude < 0.01 then
		return nil, nil
	end
	return stand.Position, toConsole.Unit
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

	-- On the treadmill the character is held in the middle of the belt, facing the console: walking does
	-- nothing, and a jump is the way off (it walks back down the ramp, and the controls come back).
	local function runTreadmill(myRun: number, character: Model, humanoid: Humanoid, root: BasePart)
		local animation = runAnimation(character)
		local animator = humanoid:FindFirstChildOfClass("Animator")
		local middle, toConsole = treadmillSpot()
		if animation == nil or animator == nil or middle == nil or toConsole == nil then
			return
		end
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play(0.2)
		track:AdjustSpeed(TREADMILL_SPEED)

		local oldSpeed = humanoid.WalkSpeed
		local oldAutoRotate = humanoid.AutoRotate
		humanoid.WalkSpeed = 0
		humanoid.AutoRotate = false
		local function hold()
			local spot = Vector3.new(middle.X, root.Position.Y, middle.Z)
			root.CFrame = CFrame.lookAt(spot, spot + toConsole)
		end
		hold()
		local holding = RunService.Heartbeat:Connect(function()
			-- Only a push (another player, a bump) moves it off the middle; put it back.
			local offset = root.Position - middle
			if Vector3.new(offset.X, 0, offset.Z).Magnitude > HOLD_TOLERANCE then
				hold()
			end
		end)
		local released = false
		local jumping: RBXScriptConnection? = nil
		local function release()
			if released then
				return
			end
			released = true
			holding:Disconnect()
			if jumping then
				jumping:Disconnect()
			end
			track:Stop(0.2)
			if humanoid.Parent then
				humanoid.WalkSpeed = oldSpeed
				humanoid.AutoRotate = oldAutoRotate
			end
		end
		jumping = humanoid.StateChanged:Connect(function(_, state)
			if state == Enum.HumanoidStateType.Jumping then
				release()
				-- The humanoid damps a push, so it walks off instead (any input of the player takes over).
				humanoid:MoveTo(middle - toConsole * HOP_DISTANCE)
			end
		end)
		cleanup = release
		while runNumber == myRun and character.Parent and not released do
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
			task.spawn(runTreadmill, myRun, character, humanoid, root)
		end
	end

	player:GetAttributeChangedSignal("trainingStation"):Connect(refresh)
	player:GetAttributeChangedSignal("training"):Connect(refresh)
	player.CharacterRemoving:Connect(stopCurrent)
end

return GymRunner
