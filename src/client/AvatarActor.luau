--!strict
-- The player in the full-screen cinematic games (docs/CINEMATICS.md): a clone of the player's own
-- avatar, animated with its own run and idle, its joints posed by hand for kicks and skill moves. With
-- no avatar to clone, a mannequin stands in. Used by the 1v1 breakaway and the penalties
-- (client/BreakawayScene) and the keepie-uppies (client/KeepieScene). Also the posing of the
-- mannequins (the defender, the keeper). Display only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)

local player = Players.LocalPlayer

local AvatarActor = {}

export type Actor = {
	place: (cframe: CFrame) -> (), -- where the feet are and which way it faces
	run: (speed: number) -> (), -- 0 stops the run and stands
	pose: (joints: { [string]: CFrame }?) -> (), -- hand-posed joints (R15 names), nil to let go
	hipX: number, -- how far each leg hangs from the middle, sideways
	destroy: () -> (),
}

-- Poses a mannequin: its torso at `base` (the front is -Z of `base`), each limb swung forward by its
-- angle (radians) and spread out to the side by `armsOut` and `legsOut`.
export type Pose = {
	leftArm: number,
	rightArm: number,
	leftLeg: number,
	rightLeg: number,
	armsOut: number,
	legsOut: number,
}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function AvatarActor.poseFigure(model: Model, base: CFrame, pose: Pose)
	model:PivotTo(base)
	local function limb(name: string, joint: Vector3, reach: number, swing: number, out: number)
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.CFrame = base
				* CFrame.new(joint)
				* CFrame.Angles(swing, 0, out)
				* CFrame.new(0, -reach, 0)
		end
	end
	local shoulder, hip = Mannequin.SHOULDER, Mannequin.HIP
	limb("Right Arm", shoulder, Mannequin.ARM_REACH, pose.rightArm, pose.armsOut)
	limb(
		"Left Arm",
		shoulder * Vector3.new(-1, 1, 1),
		Mannequin.ARM_REACH,
		pose.leftArm,
		-pose.armsOut
	)
	limb("Right Leg", hip, Mannequin.LEG_REACH, pose.rightLeg, pose.legsOut)
	limb("Left Leg", hip * Vector3.new(-1, 1, 1), Mannequin.LEG_REACH, pose.leftLeg, -pose.legsOut)
end

function AvatarActor.runPose(cycle: number, stride: number): Pose
	local swing = math.sin(cycle) * stride
	return {
		leftArm = swing,
		rightArm = -swing,
		leftLeg = -swing,
		rightLeg = swing,
		armsOut = 0.15,
		legsOut = 0.05,
	}
end

local function animation(character: Model, folder: string, name: string): string?
	local animate = character:FindFirstChild("Animate")
	local holder = if animate then animate:FindFirstChild(folder) else nil
	local found = if holder
		then (holder:FindFirstChild(name) or holder:FindFirstChildWhichIsA("Animation"))
		else nil
	return if found and found:IsA("Animation") then found.AnimationId else nil
end

local function cloneAvatar(parent: Instance): Actor?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if character == nil or humanoid == nil then
		return nil
	end
	local runId = animation(character, "run", "RunAnim")
	local idleId = animation(character, "idle", "Animation1")
	local archivable = character.Archivable
	character.Archivable = true
	local ok, cloned = pcall(function()
		return character:Clone()
	end)
	character.Archivable = archivable
	if not ok or cloned == nil then
		return nil
	end
	local model = cloned :: Model
	for _, item in model:GetDescendants() do
		if item:IsA("BaseScript") or item:IsA("ForceField") or item:IsA("Sound") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.Massless = true
		end
	end
	local cloneHumanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if cloneHumanoid == nil or root == nil or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	cloneHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	cloneHumanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	cloneHumanoid.EvaluateStateMachine = false
	root.Anchored = true
	local r15 = cloneHumanoid.RigType == Enum.HumanoidRigType.R15
	-- The root's height over the feet.
	local lift = if r15 then cloneHumanoid.HipHeight + root.Size.Y / 2 else root.Size.Y / 2 + 2
	-- How far the right foot is from the middle (the ball is kept up in front of it).
	local foot = model:FindFirstChild(if r15 then "RightFoot" else "Right Leg")
	local hipX = if foot and foot:IsA("BasePart")
		then math.clamp(math.abs(root.CFrame:PointToObjectSpace(foot.Position).X), 0.3, 1.2)
		else 0.5
	model.Name = "Attacker"
	model.Parent = parent

	local animator = cloneHumanoid:FindFirstChildOfClass("Animator")
		or new("Animator", {}, cloneHumanoid)
	local function load(id: string?): AnimationTrack?
		if id == nil then
			return nil
		end
		local anim = new("Animation", { AnimationId = id })
		local loaded, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		return if loaded then track else nil
	end
	local runTrack = load(runId)
	local idleTrack = load(idleId)
	if runTrack then
		runTrack.Looped = true
		runTrack.Priority = Enum.AnimationPriority.Movement
	end
	if idleTrack then
		idleTrack.Looped = true
		idleTrack.Priority = Enum.AnimationPriority.Idle
		idleTrack:Play(0)
	end

	-- The joints posed by hand, applied after the animations each frame (R15 names; R6 has hips only).
	-- A joint is a Motor6D, or an AnimationConstraint on avatars with the newer joints; both have a Transform.
	local held: { [string]: CFrame }? = nil
	local joints: { [string]: Instance } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") or item:IsA("AnimationConstraint") then
			joints[item.Name] = item
		end
	end
	local R6_HIPS = { RightHip = "Right Hip", LeftHip = "Left Hip" }
	local stepped = RunService.Stepped:Connect(function()
		if held == nil then
			return
		end
		for name, transform in held do
			local motor = joints[name]
			if motor == nil and not r15 and R6_HIPS[name] then
				motor = joints[R6_HIPS[name]]
				-- An R6 hip turns about the side axis: the right one forward, the left one mirrored.
				local x = transform:ToEulerAnglesXYZ()
				transform = CFrame.Angles(0, 0, if name == "RightHip" then x else -x)
			end
			if motor then
				(motor :: any).Transform = transform
			end
		end
	end)

	local running = false
	return {
		place = function(cframe: CFrame)
			root.CFrame = cframe + Vector3.new(0, lift, 0)
		end,
		run = function(speed: number)
			if runTrack == nil then
				return
			end
			if speed > 0 then
				if not running then
					runTrack:Play(0.1)
					running = true
				end
				runTrack:AdjustSpeed(speed)
			elseif running then
				runTrack:Stop(0.15)
				running = false
			end
		end,
		pose = function(posed: { [string]: CFrame }?)
			held = posed
		end,
		hipX = hipX,
		destroy = function()
			stepped:Disconnect()
			model:Destroy()
		end,
	}
end

-- The stand-in when the avatar cannot be cloned: a mannequin in the player's best colours.
local function mannequinActor(parent: Instance): Actor
	local model = Mannequin.build(Config.Players[1], Color3.fromRGB(90, 170, 255), false)
	model.Parent = parent
	local at = CFrame.identity
	local speed = 0
	local held: { [string]: CFrame }? = nil
	local connection = RunService.RenderStepped:Connect(function()
		local base = at * CFrame.new(0, Mannequin.FEET_TO_TORSO, 0)
		local pose = AvatarActor.runPose(os.clock() * 10 * speed, if speed > 0 then 0.8 else 0)
		if held then
			local right = held.RightHip
			pose.rightLeg = if right then (right:ToEulerAnglesXYZ()) else 0
			local left = held.LeftHip
			pose.leftLeg = if left then (left:ToEulerAnglesXYZ()) else 0
			pose.armsOut = 0.6
		end
		AvatarActor.poseFigure(model, base, pose)
	end)
	return {
		place = function(cframe: CFrame)
			at = cframe
		end,
		run = function(value: number)
			speed = value
		end,
		pose = function(posed: { [string]: CFrame }?)
			held = posed
		end,
		hipX = Mannequin.HIP.X,
		destroy = function()
			connection:Disconnect()
			model:Destroy()
		end,
	}
end

-- The player in a scene: the own avatar, or the mannequin when it cannot be cloned.
function AvatarActor.new(parent: Instance): Actor
	return cloneAvatar(parent) or mannequinActor(parent)
end

return AvatarActor
