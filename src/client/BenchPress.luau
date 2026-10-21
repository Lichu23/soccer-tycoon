--!strict
-- The bench press of the Training Gym, as every client sees it. A character lying on a bench seat
-- (server/BenchSeats lays it down) bends its knees over the sides of the bench, and while its
-- player trains it does real reps: the hands hold the bar a little wider than the shoulders, lower
-- it slowly to the chest, pause, press it back up to straight arms and hold it there a moment. The
-- arms reach the hands by solving the shoulder and elbow angles each frame (two-bone IK), and the
-- barbell sits in the hands. When nobody presses, the barbell rests on the rack. Only a picture:
-- the server pays the TP. R15 characters only (an R6 one just lies there).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- One rep, in seconds: hold at the top, lower, pause on the chest, press.
local HOLD_TOP = 0.35
local LOWER = 1.0
local PAUSE = 0.15
local PRESS = 0.7
local REP = HOLD_TOP + LOWER + PAUSE + PRESS

local GRIP_OUT = 0.55 -- the hands this much wider than the shoulders
local GRIP_DOWN = 0.35 -- and this much lower (towards the feet): the bar comes down on the chest
local BAR_CLEARANCE = 0.35 -- the hands this far off the chest at the bottom
local REACH = 0.97 -- the arms almost straight at the top
local HIP = CFrame.Angles(math.rad(-20), 0, 0) -- the thighs tilt down over the bench sides
local KNEE = CFrame.Angles(math.rad(-80), 0, 0) -- and the shins hang to the floor
local HIP_OUT = math.rad(28)

local BenchPress = {}

-- How far the arms are pushed up at `time`: 1 at the top, 0 on the chest.
local function extension(time: number): number
	local t = time % REP
	local function smooth(x: number): number
		return x * x * (3 - 2 * x)
	end
	if t < HOLD_TOP then
		return 1
	end
	t -= HOLD_TOP
	if t < LOWER then
		return 1 - smooth(t / LOWER)
	end
	t -= LOWER
	if t < PAUSE then
		return 0
	end
	return smooth((t - PAUSE) / PRESS)
end

-- The bench a character lies on (the model of its bench seat), or nil.
local function benchOf(character: Model): Model?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local seat = if humanoid then humanoid.SeatPart else nil
	if seat == nil or seat.Name ~= "BenchSeat" then
		return nil
	end
	local bench = seat.Parent
	return if bench and bench:IsA("Model") then bench else nil
end

-- A joint is a Motor6D, or an AnimationConstraint on avatars with the newer joints. Both place
-- Part1 at Part0 * c0 * Transform * c1:Inverse().
type Joint = { instance: any, c0: CFrame, c1: CFrame }

local function joint(character: Model, partName: string, jointName: string): Joint?
	local part = character:FindFirstChild(partName)
	local found = if part then part:FindFirstChild(jointName) else nil
	if found and found:IsA("Motor6D") then
		return { instance = found, c0 = found.C0, c1 = found.C1 }
	elseif found and found:IsA("AnimationConstraint") then
		local a0, a1 = found.Attachment0, found.Attachment1
		if a0 and a1 then
			return { instance = found, c0 = a0.CFrame, c1 = a1.CFrame }
		end
	end
	return nil
end

-- The rotation that turns direction `from` into direction `to`.
local function between(from: Vector3, to: Vector3): CFrame
	local a, b = from.Unit, to.Unit
	local axis = a:Cross(b)
	local sine = axis.Magnitude
	if sine < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis / sine, math.atan2(sine, a:Dot(b)))
end

-- Bends one arm so its hand reaches `target` (in the UpperTorso's space). `side` is 1 for the
-- right arm, -1 for the left. Returns false when the rig is not R15.
local function reach(character: Model, sideName: string, side: number, target: Vector3): boolean
	local shoulder = joint(character, sideName .. "UpperArm", sideName .. "Shoulder")
	local elbow = joint(character, sideName .. "LowerArm", sideName .. "Elbow")
	local wrist = joint(character, sideName .. "Hand", sideName .. "Wrist")
	if shoulder == nil or elbow == nil or wrist == nil then
		return false
	end
	-- The bones at rest, each in its joint's frame: shoulder to elbow, elbow to the middle of the hand.
	local upperRest = shoulder.c1:Inverse() * elbow.c0.Position
	local handInLower = (wrist.c0 * wrist.c1:Inverse()).Position
	local lowerRest = elbow.c1:Inverse() * handInLower
	local upperLength, lowerLength = upperRest.Magnitude, lowerRest.Magnitude

	-- Two-bone IK: the elbow points out to the side and down past the bench, like a real press.
	local start = shoulder.c0.Position
	local toTarget = target - start
	local distance = math.clamp(toTarget.Magnitude, 0.05, (upperLength + lowerLength) * 0.999)
	local along = toTarget.Unit
	local pole = Vector3.new(side, -0.3, 1)
	local perpendicular = pole - along * pole:Dot(along)
	perpendicular = if perpendicular.Magnitude > 1e-4
		then perpendicular.Unit
		else Vector3.new(side, 0, 0)
	local cosine = (upperLength ^ 2 + distance ^ 2 - lowerLength ^ 2) / (2 * upperLength * distance)
	local angle = math.acos(math.clamp(cosine, -1, 1))
	local elbowPoint = start
		+ along * (upperLength * math.cos(angle))
		+ perpendicular * (upperLength * math.sin(angle))

	local shoulderTransform =
		between(upperRest, shoulder.c0:VectorToObjectSpace(elbowPoint - start))
	local elbowFrame = shoulder.c0 * shoulderTransform * shoulder.c1:Inverse() * elbow.c0
	local elbowTransform =
		between(lowerRest, elbowFrame:VectorToObjectSpace(target - elbowFrame.Position))
	shoulder.instance.Transform = shoulderTransform
	elbow.instance.Transform = elbowTransform
	wrist.instance.Transform = CFrame.identity
	return true
end

-- Where the hands hold the bar now (UpperTorso space), for one side.
local function gripPoint(character: Model, sideName: string, side: number, amount: number): Vector3?
	local torso = character:FindFirstChild("UpperTorso")
	local shoulder = joint(character, sideName .. "UpperArm", sideName .. "Shoulder")
	local elbow = joint(character, sideName .. "LowerArm", sideName .. "Elbow")
	local wrist = joint(character, sideName .. "Hand", sideName .. "Wrist")
	if
		torso == nil
		or not torso:IsA("BasePart")
		or shoulder == nil
		or elbow == nil
		or wrist == nil
	then
		return nil
	end
	local start = shoulder.c0.Position
	local x = start.X + side * GRIP_OUT
	local y = start.Y - GRIP_DOWN
	-- On the chest at the bottom (the front of the torso is -z), arms almost straight at the top.
	local bottom = -(torso.Size.Z / 2 + BAR_CLEARANCE)
	local armLength = (shoulder.c1:Inverse() * elbow.c0.Position).Magnitude
		+ (elbow.c1:Inverse() * (wrist.c0 * wrist.c1:Inverse()).Position).Magnitude
	local flat = (x - start.X) ^ 2 + (y - start.Y) ^ 2
	local top = start.Z - math.sqrt(math.max((armLength * REACH) ^ 2 - flat, 0))
	return Vector3.new(x, y, bottom + (top - bottom) * amount)
end

local function setJoint(character: Model, partName: string, jointName: string, transform: CFrame)
	local found = joint(character, partName, jointName)
	if found then
		found.instance.Transform = transform
	end
end

function BenchPress.init()
	local restPivots: { [Model]: CFrame } = {} -- where each barbell lies on its rack
	local pressing: { [Model]: boolean } = {}

	local function trains(player: Player): boolean
		return player:GetAttribute("training") == true
			and player:GetAttribute("trainingStation") == "bench"
	end

	-- After the animations (Stepped), so the pose wins over the sitting animation.
	RunService.Stepped:Connect(function()
		table.clear(pressing)
		local amount = extension(os.clock())
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local bench = if character then benchOf(character) else nil
			if character == nil or bench == nil then
				continue
			end
			-- Knees over the sides of the bench, feet down to the floor.
			setJoint(character, "RightUpperLeg", "RightHip", CFrame.Angles(0, 0, HIP_OUT) * HIP)
			setJoint(character, "LeftUpperLeg", "LeftHip", CFrame.Angles(0, 0, -HIP_OUT) * HIP)
			setJoint(character, "RightLowerLeg", "RightKnee", KNEE)
			setJoint(character, "LeftLowerLeg", "LeftKnee", KNEE)
			if not trains(player) then
				continue
			end
			local torso = character:FindFirstChild("UpperTorso")
			local right = gripPoint(character, "Right", 1, amount)
			local left = gripPoint(character, "Left", -1, amount)
			if torso == nil or not torso:IsA("BasePart") or right == nil or left == nil then
				continue
			end
			if not (reach(character, "Right", 1, right) and reach(character, "Left", -1, left)) then
				continue
			end
			-- The barbell in the hands, across the bench as on the rack.
			local barbell = bench:FindFirstChild("Barbell")
			if barbell and barbell:IsA("Model") then
				local rest = restPivots[barbell] or barbell:GetPivot()
				restPivots[barbell] = rest
				pressing[barbell] = true
				barbell:PivotTo(rest.Rotation + torso.CFrame:PointToWorldSpace((right + left) / 2))
			end
		end
		-- A barbell nobody presses any more goes back on its rack.
		for barbell, rest in restPivots do
			if not pressing[barbell] then
				if barbell.Parent then
					barbell:PivotTo(rest)
				end
				restPivots[barbell] = nil
			end
		end
	end)
end

return BenchPress
