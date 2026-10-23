--!strict
-- The player's own Roblox character runs on the treadmill of the Training Gym: in place, with the run
-- animation of its own avatar, held in the middle of the belt until a jump takes it off. It only
-- starts while the server says the player is training (on the pad with stamina left) and stops the
-- moment the player jumps, leaves the pad or runs out of stamina. During the level-up tutorial the
-- jump is off until the TP of the first level are in, then the runner steps off by itself. The bench
-- press is client/BenchPress. The TP are the server's: this only moves and animates the character,
-- nothing here pays.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Progress = require(ReplicatedStorage.Shared.Progress)
local State = require(script.Parent.State)

local player = Players.LocalPlayer

local TREADMILL_SPEED = 1.25 -- the run animation plays a little faster than normal
local HOLD_TOLERANCE = 0.3 -- studs the runner may drift from the middle of the belt
local HOP_DISTANCE = 12 -- a jump walks the runner this far back from the middle: down the ramp, off the pad
local BENCH_STEP_OFF = 6 -- getting up walks this far from the bench's centre, past its foot end

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
		local stopTutorial: (() -> ())? = nil
		-- The level-up tutorial holds the runner on the belt: no jump until the first TP are in.
		local held = Progress.tutorialTraining(State.data)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not held)
		local function release()
			if released then
				return
			end
			released = true
			holding:Disconnect()
			if jumping then
				jumping:Disconnect()
			end
			if stopTutorial then
				stopTutorial()
			end
			track:Stop(0.2)
			if humanoid.Parent then
				humanoid.WalkSpeed = oldSpeed
				humanoid.AutoRotate = oldAutoRotate
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			end
		end
		-- Off the belt: the humanoid damps a push, so it walks off instead (any input of the player
		-- takes over).
		local function stepOff()
			release()
			humanoid:MoveTo(middle - toConsole * HOP_DISTANCE)
		end
		jumping = humanoid.StateChanged:Connect(function(_, state)
			if state == Enum.HumanoidStateType.Jumping then
				stepOff()
			end
		end)
		if held then
			stopTutorial = State.onChange(function()
				if not Progress.tutorialTraining(State.data) then
					stepOff() -- the TP are in: off to level the player up
				end
			end)
		end
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
		if station == "treadmill" then
			task.spawn(runTreadmill, myRun, character, humanoid, root)
		end
	end

	-- Getting up from the bench (the Seat's jump) walks the character off its foot end, away from the
	-- rack, so it does not land on the seat again and lie straight back down.
	local function watchBench(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid == nil or not humanoid:IsA("Humanoid") then
			return
		end
		local bench: Model? = nil
		humanoid.Seated:Connect(function(active, seat)
			if active then
				local parent = if seat and seat.Name == "BenchSeat" then seat.Parent else nil
				bench = if parent and parent:IsA("Model") then parent else nil
			elseif bench then
				local pivot = bench:GetPivot()
				bench = nil
				humanoid:MoveTo(pivot.Position + pivot.RightVector * BENCH_STEP_OFF)
			end
		end)
	end

	player:GetAttributeChangedSignal("trainingStation"):Connect(refresh)
	player:GetAttributeChangedSignal("training"):Connect(refresh)
	player.CharacterRemoving:Connect(stopCurrent)
	player.CharacterAdded:Connect(watchBench)
	if player.Character then
		task.spawn(watchBench, player.Character)
	end
end

return GymRunner
