--!strict
-- The bench press of the Training Gym, as every client sees it: a character lying on a bench seat
-- (server/BenchSeats lays it down) keeps its legs on the bench with the feet on the floor, and while
-- its player trains it pushes the barbell up and lowers it to the chest; the barbell follows the
-- hands. When nobody presses, the barbell rests on the rack. Only a picture: the server pays the TP.
-- The pose is set on the joints after the animations (Stepped), for R15 characters; an R6 one just
-- lies there.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local REP_SECONDS = 1.8 -- one push up and down
local ARM_OUT = math.rad(70) -- the upper arms out to the sides at the bottom of the press

-- At the bottom the upper arms point out and the forearms up (to the bar); at the top the arms are
-- straight up. The body lies on its back, so "forward" is up.
local SHOULDER_BOTTOM_RIGHT = CFrame.Angles(0, 0, ARM_OUT)
local SHOULDER_BOTTOM_LEFT = CFrame.Angles(0, 0, -ARM_OUT)
local SHOULDER_TOP = CFrame.Angles(math.rad(90), 0, 0)
local ELBOW_BOTTOM = CFrame.Angles(math.rad(90), 0, 0)
local ELBOW_TOP = CFrame.identity
local KNEE_DOWN = CFrame.Angles(math.rad(-90), 0, 0) -- the shins hang down to the floor

local BenchPress = {}

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

-- A joint is a Motor6D, or an AnimationConstraint on avatars with the newer joints; both animate
-- through Transform.
local function setJoint(character: Model, partName: string, jointName: string, transform: CFrame)
	local part = character:FindFirstChild(partName)
	local joint = if part then part:FindFirstChild(jointName) else nil
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		(joint :: any).Transform = transform
	end
end

function BenchPress.init()
	local restPivots: { [Model]: CFrame } = {} -- where each barbell lies on its rack
	local pressing: { [Model]: boolean } = {} -- the barbells held up by a presser this frame

	-- The press: 0 at the chest, 1 at the top.
	local function pressAmount(): number
		return 0.5 - 0.5 * math.cos(os.clock() / REP_SECONDS * 2 * math.pi)
	end

	local function trains(player: Player): boolean
		return player:GetAttribute("training") == true
			and player:GetAttribute("trainingStation") == "bench"
	end

	RunService.Stepped:Connect(function()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character == nil or benchOf(character) == nil then
				continue
			end
			-- Legs along the bench, shins down; the press only while training (else arms by the side).
			for _, side in { "Right", "Left" } do
				setJoint(character, side .. "UpperLeg", side .. "Hip", CFrame.identity)
				setJoint(character, side .. "LowerLeg", side .. "Knee", KNEE_DOWN)
			end
			if trains(player) then
				local amount = pressAmount()
				local shoulderBottom =
					{ Right = SHOULDER_BOTTOM_RIGHT, Left = SHOULDER_BOTTOM_LEFT }
				for _, side in { "Right", "Left" } do
					setJoint(
						character,
						side .. "UpperArm",
						side .. "Shoulder",
						shoulderBottom[side]:Lerp(SHOULDER_TOP, amount)
					)
					setJoint(
						character,
						side .. "LowerArm",
						side .. "Elbow",
						ELBOW_BOTTOM:Lerp(ELBOW_TOP, amount)
					)
				end
			end
		end
	end)

	-- After the physics step the hands are where the pose put them: the barbell goes between them.
	RunService.Heartbeat:Connect(function()
		table.clear(pressing)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local bench = if character then benchOf(character) else nil
			local barbell = if bench then bench:FindFirstChild("Barbell") else nil
			if
				character == nil
				or barbell == nil
				or not barbell:IsA("Model")
				or not trains(player)
			then
				continue
			end
			local right, left =
				character:FindFirstChild("RightHand"), character:FindFirstChild("LeftHand")
			if
				right == nil
				or left == nil
				or not right:IsA("BasePart")
				or not left:IsA("BasePart")
			then
				continue
			end
			local rest = restPivots[barbell] or barbell:GetPivot()
			restPivots[barbell] = rest
			pressing[barbell] = true
			barbell:PivotTo(rest.Rotation + (right.Position + left.Position) / 2)
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
