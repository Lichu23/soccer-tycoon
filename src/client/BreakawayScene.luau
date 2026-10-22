--!strict
-- The 3D scene of the 1v1 breakaway (client/FreekickUi drives it): a small stadium built far from the
-- map, only on this client, with a clone of the player's own avatar, a defender and a keeper. While
-- the player gives the three inputs the camera waits behind the attacker (the move) or behind the
-- ball (the aim and the power); then the attack plays as a film in three cuts, all from the state the
-- server judged:
--   1. the dribble: a side tracking shot of the sprint, the skill move past the defender (or his
--      tackle), with speed lines and a light blur;
--   2. the strike: a slow-motion close-up from the front, the leg snapping back and through the ball;
--   3. the result: from behind the keeper, the camera swivels after the ball into the net, or the
--      keeper dives in slow motion for the save.
-- The daily penalty kicks use the same set in penalty mode (`new({ penalty = true })`): no defender,
-- the ball on the penalty spot, and the dribble cut makes way for a short run-up from the side, so
-- the film is `PENALTY_SKIP` seconds shorter (the screen moves its moments back by that much).
-- Display only: nothing here decides an outcome.

local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local AvatarActor = require(script.Parent.AvatarActor)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Freekick = require(game:GetService("ReplicatedStorage").Shared.Freekick)
local Mannequin = require(game:GetService("ReplicatedStorage").Shared.Mannequin)
local Penalty = require(game:GetService("ReplicatedStorage").Shared.Penalty)

-- The pitch, in studs, from ORIGIN: the goal line is at z 0, the attack runs towards -z. One goal unit
-- of the shot maths is GOAL_HALF_WIDTH across and GOAL_HEIGHT up.
local ORIGIN = Vector3.new(6000, 400, 6000)
local GOAL_HALF_WIDTH = 10
local GOAL_HEIGHT = 7.5
local NET_DEPTH = 4
local BALL_SIZE = 1.3
local BALL_R = BALL_SIZE / 2
local RUN_FROM = 62 -- where the attacker takes the through-ball
local DEFENDER_Z = 40
local SHOT_Z = 22 -- where the ball is struck
local STRIKE_BACK = 1.1 -- the attacker stands this far behind the ball to strike it
local KEEPER_Z = 1.6
local CUT_X = 3.2 -- how far across the skill move takes the attacker

-- The film, in seconds from the start of the shot step.
local CUT_STRIKE = 2 -- the dribble cut ends, the strike cut starts
local CUT_RESULT = 3.6 -- the strike cut ends, the result cut starts
local STRIKE_SECONDS = CUT_RESULT - CUT_STRIKE
local CONTACT_SHARE = 0.56 -- how far into the strike the foot meets the ball
local SLOW_FLIGHT = 0.12 -- how much of the flight the ball covers per second in the slow strike cut
local FLIGHT_SECONDS = 1 -- the rest of the flight, in the result cut
local TACKLE_AT = 1.05
local MOVE_AT = 0.85 -- the skill move starts
local RUN_UP = 1.2 -- the penalty's run-up cut, which takes the end of the dribble cut's place
local RUN_UP_BACK = 6.5 -- the penalty taker starts the run-up this far behind the ball
local RUN_UP_SIDE = 3 -- and this far to the left
local RUN_UP_REACH = 0.7 -- the share of the run-up shown before the cut to the strike (he is still running)

local BreakawayScene = {}

BreakawayScene.CONTACT_AT = CUT_STRIKE + STRIKE_SECONDS * CONTACT_SHARE
BreakawayScene.ARRIVE_AT = CUT_RESULT + FLIGHT_SECONDS
BreakawayScene.TACKLE_AT = TACKLE_AT
BreakawayScene.CUT_STRIKE = CUT_STRIKE
BreakawayScene.CUT_RESULT = CUT_RESULT
BreakawayScene.PENALTY_SKIP = CUT_STRIKE - RUN_UP -- the film time a penalty starts at

local WHITE = Color3.fromRGB(240, 240, 240)
local LINE = Color3.fromRGB(245, 245, 245)
local GRASS = Color3.fromRGB(58, 138, 62)
local GRASS_LIGHT = Color3.fromRGB(68, 154, 72)
local CONCRETE = Color3.fromRGB(168, 168, 174)
local NAVY = Color3.fromRGB(32, 38, 56) -- Style.ui.panel
local NET = Color3.fromRGB(30, 60, 45)
local KEEPER_KIT = Color3.fromRGB(240, 200, 50)
local DEFENDER_KIT = Color3.fromRGB(200, 50, 60)
local FANS = {
	Color3.fromRGB(230, 90, 90),
	Color3.fromRGB(90, 140, 230),
	Color3.fromRGB(240, 200, 70),
	Color3.fromRGB(120, 200, 130),
	Color3.fromRGB(230, 230, 235),
}

-- What the frame needs: the server's state and, during the aim, where the reticle is now.
export type View = {
	state: Freekick.State,
	now: number,
	reticleX: number,
	reticleY: number,
}

export type Options = { penalty: boolean? }

export type Scene = {
	frame: (view: View) -> (),
	goalPoint: (x: number, y: number) -> Vector3,
	destroy: () -> (),
}

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function lerp(a: number, b: number, u: number): number
	return a + (b - a) * u
end

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

local function block(
	parent: Instance,
	size: Vector3,
	position: Vector3,
	color: Color3,
	transparency: number?
): Part
	return new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Size = size,
		CFrame = CFrame.new(ORIGIN + position),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Transparency = transparency or 0,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}, parent)
end

-- A stand of three tiers with fans, `length` long, its front at `front` and rising away along `away`.
local function stand(parent: Instance, front: Vector3, away: Vector3, length: number)
	local along = Vector3.new(-away.Z, 0, away.X)
	for row = 0, 2 do
		local top = 2 * (row + 1)
		local middle = front + away * (2 + row * 4)
		local size = if math.abs(away.X) > 0
			then Vector3.new(4, top, length)
			else Vector3.new(length, top, 4)
		block(parent, size, middle + Vector3.new(0, top / 2, 0), CONCRETE)
		local k = 0
		for offset = -length / 2 + 2, length / 2 - 2, 4 do
			k += 1
			if (row * 7 + k * 3) % 5 ~= 0 then
				block(
					parent,
					Vector3.new(1.4, 2, 1.4),
					middle + along * offset + Vector3.new(0, top + 1, 0),
					FANS[(row + k) % #FANS + 1]
				)
			end
		end
	end
end

-- The pitch, the goal with its net, the stands around it. Returns the net's back, which bulges.
local function buildPitch(parent: Instance): Part
	block(parent, Vector3.new(300, 1, 220), Vector3.new(0, -0.5, 50), GRASS)
	for index = 0, 10 do
		block(
			parent,
			Vector3.new(300, 0.05, 10),
			Vector3.new(0, 0.02, -45 + index * 20),
			GRASS_LIGHT
		)
	end
	local y = 0.06
	block(parent, Vector3.new(180, 0.08, 0.5), Vector3.new(0, y, 0), LINE) -- the goal line
	block(parent, Vector3.new(64, 0.08, 0.5), Vector3.new(0, y, 30), LINE) -- the box
	block(parent, Vector3.new(0.5, 0.08, 30), Vector3.new(-32, y, 15), LINE)
	block(parent, Vector3.new(0.5, 0.08, 30), Vector3.new(32, y, 15), LINE)
	block(parent, Vector3.new(32, 0.08, 0.5), Vector3.new(0, y, 10), LINE) -- the six-yard box
	block(parent, Vector3.new(0.5, 0.08, 10), Vector3.new(-16, y, 5), LINE)
	block(parent, Vector3.new(0.5, 0.08, 10), Vector3.new(16, y, 5), LINE)

	local post = 0.6
	for _, x in { -GOAL_HALF_WIDTH, GOAL_HALF_WIDTH } do
		block(
			parent,
			Vector3.new(post, GOAL_HEIGHT, post),
			Vector3.new(x, GOAL_HEIGHT / 2, 0),
			WHITE
		)
		block(parent, Vector3.new(0.2, 0.2, NET_DEPTH), Vector3.new(x, 0.1, -NET_DEPTH / 2), WHITE)
		block(
			parent,
			Vector3.new(0.12, GOAL_HEIGHT, NET_DEPTH),
			Vector3.new(x, GOAL_HEIGHT / 2, -NET_DEPTH / 2),
			NET,
			0.6
		)
	end
	block(
		parent,
		Vector3.new(GOAL_HALF_WIDTH * 2 + post, post, post),
		Vector3.new(0, GOAL_HEIGHT, 0),
		WHITE
	)
	block(
		parent,
		Vector3.new(GOAL_HALF_WIDTH * 2, 0.12, NET_DEPTH),
		Vector3.new(0, GOAL_HEIGHT, -NET_DEPTH / 2),
		NET,
		0.6
	)
	local back = block(
		parent,
		Vector3.new(GOAL_HALF_WIDTH * 2, GOAL_HEIGHT, 0.12),
		Vector3.new(0, GOAL_HEIGHT / 2, -NET_DEPTH),
		NET,
		0.5
	)
	back.Name = "NetBack"
	-- The mesh of the net, on the back panel (it bulges with it).
	for x = -GOAL_HALF_WIDTH + 1, GOAL_HALF_WIDTH - 1 do
		local strand = block(parent, Vector3.new(0.07, GOAL_HEIGHT, 0.07), Vector3.zero, LINE, 0.4)
		strand.CFrame = back.CFrame * CFrame.new(x, 0, 0.08)
		new("WeldConstraint", { Part0 = back, Part1 = strand }, strand)
		strand.Anchored = false
	end
	for row = 1, math.floor(GOAL_HEIGHT) do
		local strand =
			block(parent, Vector3.new(GOAL_HALF_WIDTH * 2, 0.07, 0.07), Vector3.zero, LINE, 0.4)
		strand.CFrame = back.CFrame * CFrame.new(0, row - GOAL_HEIGHT / 2, 0.08)
		new("WeldConstraint", { Part0 = back, Part1 = strand }, strand)
		strand.Anchored = false
	end

	stand(parent, Vector3.new(0, 0, -16), Vector3.new(0, 0, -1), 150) -- behind the goal
	stand(parent, Vector3.new(0, 0, 112), Vector3.new(0, 0, 1), 150) -- the far end
	stand(parent, Vector3.new(-72, 0, 50), Vector3.new(-1, 0, 0), 190) -- the sides
	stand(parent, Vector3.new(72, 0, 50), Vector3.new(1, 0, 0), 190)
	return back
end

type Pose = AvatarActor.Pose
local poseFigure = AvatarActor.poseFigure

-- The leg swing of the strike at share `g` (0 to 1) of the strike cut: back, through, follow-through.
local function strikeJoints(g: number): { [string]: CFrame }
	local hip, knee
	if g < 0.45 then
		local u = smooth(g / 0.45)
		hip, knee = lerp(0, -55, u), lerp(0, -95, u)
	elseif g < 0.62 then
		local u = (g - 0.45) / 0.17
		hip, knee = lerp(-55, 75, u), lerp(-95, -5, u)
	else
		local u = smooth((g - 0.62) / 0.38)
		hip, knee = lerp(75, 95, u), lerp(-5, -20, u)
	end
	local out = math.rad(lerp(20, 55, smooth(g / 0.5)))
	return {
		RightHip = CFrame.Angles(math.rad(hip), 0, 0),
		RightKnee = CFrame.Angles(math.rad(knee), 0, 0),
		LeftHip = CFrame.Angles(math.rad(-12), 0, 0),
		LeftKnee = CFrame.Angles(math.rad(-18), 0, 0),
		RightShoulder = CFrame.Angles(math.rad(-20), 0, out),
		LeftShoulder = CFrame.Angles(math.rad(25), 0, -out),
		Waist = CFrame.Angles(math.rad(-8 * smooth(g / 0.6)), 0, 0),
	}
end

-- The step-over: the right leg circles over the ball at share `u` (0 to 1).
local function stepOverJoints(u: number): { [string]: CFrame }
	local around = math.sin(math.pi * u)
	return {
		RightHip = CFrame.Angles(
			math.rad(35 * around),
			0,
			math.rad(-30 * math.sin(2 * math.pi * u))
		),
		RightKnee = CFrame.Angles(math.rad(-50 * around), 0, 0),
	}
end

local function facing(position: Vector3, direction: Vector3): CFrame
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(position, position + flat)
end

function BreakawayScene.new(options: Options?): Scene
	local penalty = options ~= nil and options.penalty == true
	local folder = new("Folder", { Name = if penalty then "PenaltySpot" else "Breakaway" })
	local netBack = buildPitch(folder)
	local netRest = netBack.CFrame
	if penalty then
		local spot = block(folder, Vector3.new(0.12, 1.4, 1.4), Vector3.zero, LINE)
		spot.Shape = Enum.PartType.Cylinder
		spot.CFrame = CFrame.new(ORIGIN + Vector3.new(0, 0.06, SHOT_Z))
			* CFrame.Angles(0, 0, math.pi / 2)
	end
	folder.Parent = Workspace

	local attacker = AvatarActor.new(folder)
	local defender: Model? = nil
	if not penalty then
		local built = Mannequin.build(Config.Players[2] or Config.Players[1], DEFENDER_KIT, false)
		built.Parent = folder
		defender = built
	end
	local keeper = Mannequin.build(Config.Players[3] or Config.Players[1], KEEPER_KIT, false)
	keeper.Parent = folder
	local ball = new("Part", {
		Name = "Ball",
		Shape = Enum.PartType.Ball,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE),
		Color = WHITE,
		Material = Enum.Material.SmoothPlastic,
	}, folder)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Top, Enum.NormalId.Left } do
		local spot = new(
			"SurfaceGui",
			{ Face = face, CanvasSize = Vector2.new(50, 50), LightInfluence = 1 },
			ball
		)
		local patch = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.4, 0.4),
			BackgroundColor3 = NAVY,
		}, spot)
		new("UICorner", { CornerRadius = UDim.new(0.3, 0) }, patch)
	end

	local camera = Workspace.CurrentCamera
	local blur = new("BlurEffect", { Size = 0, Enabled = true }, camera)
	local grade = new("ColorCorrectionEffect", { Saturation = 0, Enabled = true }, camera)

	local function at(x: number, y: number, z: number): Vector3
		return ORIGIN + Vector3.new(x, y, z)
	end
	local function look(position: Vector3, target: Vector3, fov: number)
		camera.CFrame = CFrame.lookAt(position, target)
		camera.FieldOfView = fov
	end
	local function setBall(position: Vector3, spin: number)
		ball.CFrame = CFrame.new(position) * CFrame.Angles(spin, 0, 0)
	end

	-- The defender, facing the attacker (+z), in his stance or doing something else.
	local function defenderAt(position: Vector3, roll: number, pitch: number, pose: Pose)
		if defender == nil then
			return
		end
		local base = CFrame.new(position + Vector3.new(0, Mannequin.FEET_TO_TORSO, 0))
			* CFrame.Angles(pitch, 0, roll)
			* CFrame.Angles(0, math.pi, 0)
		poseFigure(defender, base, pose)
	end
	-- Where the keeper stands for this attack or kick, in studs across the goal.
	local function keeperRestX(state: Freekick.State): number
		local x = if penalty
			then Penalty.KEEPER_X
			else Freekick.setup(state.seed, state.kick).keeperX
		return x * GOAL_HALF_WIDTH
	end
	local STANCE: Pose = {
		leftArm = 0.3,
		rightArm = 0.3,
		leftLeg = 0,
		rightLeg = 0,
		armsOut = 0.7,
		legsOut = 0.3,
	}
	local function keeperAt(position: Vector3, roll: number, armsUp: number)
		local base = CFrame.new(position) * CFrame.Angles(0, 0, roll) * CFrame.Angles(0, math.pi, 0)
		poseFigure(keeper, base, {
			leftArm = 0,
			rightArm = 0,
			leftLeg = 0,
			rightLeg = 0,
			armsOut = armsUp,
			legsOut = 0.25,
		})
	end
	local KEEPER_REST_Y = Mannequin.FEET_TO_TORSO - 0.3 -- a little crouched

	-- Where the shot ends (the reticle's point, its height lifted by the power) and how it flies.
	local function shotStart(move: number): Vector3
		if penalty then
			return at(0, BALL_R, SHOT_Z) -- the ball on the spot, the taker's feet just left of it
		end
		local x = if move == Freekick.LEFT then -CUT_X else CUT_X
		return at(x + 0.8, BALL_R, SHOT_Z)
	end
	local function shotEnd(state: Freekick.State): Vector3
		local height = Freekick.height(state.aimY, state.power)
		-- The free kick's green zone narrows with the streak; the penalty's stays the same.
		local low, high
		if penalty then
			low, high = Freekick.penaltyZone()
		else
			low, high = Freekick.goodZone(state.kick)
		end
		if state.power < low then
			height = 0 -- it rolls
		elseif state.power > high and state.outcome == "over" then
			height = math.max(height, 1.2) -- struck too hard: it clears the bar
		end
		return at(state.aimX * GOAL_HALF_WIDTH, height * GOAL_HEIGHT + BALL_R, 0)
	end
	local function flightPoint(state: Freekick.State, p: number): Vector3
		local from, to = shotStart(state.move), shotEnd(state)
		local bend = (if state.aimX >= 0 then 1 else -1) * 1.4 -- it curls in from the outside
		local arc = 4 * p * (1 - p)
		return from:Lerp(to, p) + Vector3.new(bend * arc, (to.Y > 1.5 and 1.2 or 0) * arc, 0)
	end
	-- How far along its flight the ball is at film time `t`.
	local function flightShare(t: number): number
		local contact = BreakawayScene.CONTACT_AT
		if t < contact then
			return 0
		end
		local slow = math.min(t, CUT_RESULT) - contact
		local p0 = (CUT_RESULT - contact) * SLOW_FLIGHT
		if t < CUT_RESULT then
			return slow * SLOW_FLIGHT
		end
		return math.min(p0 + (t - CUT_RESULT) / FLIGHT_SECONDS * (1 - p0), 1)
	end

	-- The attacker's path in the dribble cut: down the pitch, across with the move.
	local sprintSpeed = (RUN_FROM - (SHOT_Z + STRIKE_BACK)) / CUT_STRIKE
	local function dribbleX(move: number, tackled: boolean, t: number): number
		if tackled then
			return 0
		end
		local cut = smooth((t - MOVE_AT) / 0.35)
		if move == Freekick.LEFT then
			return -CUT_X * cut
		elseif move == Freekick.RIGHT then
			return CUT_X * cut
		end
		-- The step-over: a feint to the left, then away to the right.
		local feint = -0.9 * math.sin(math.pi * math.clamp((t - 0.7) / 0.3, 0, 1))
		return feint + CUT_X * smooth((t - 0.95) / 0.35)
	end
	local function dribbleZ(tackled: boolean, t: number): number
		if tackled and t > TACKLE_AT then
			-- He stumbles to a stop.
			local after = math.min(t - TACKLE_AT, 0.5)
			return RUN_FROM - sprintSpeed * (TACKLE_AT + after - after * after)
		end
		return RUN_FROM - sprintSpeed * math.min(t, CUT_STRIKE)
	end

	-- The defender beaten by the move at film time `t`: he steps in, bites the wrong way and goes down.
	local function defenderBeaten(move: number, t: number)
		local step = smooth((t - 0.5) / 0.4) * 1.5
		local wrong = if move == Freekick.LEFT then 1 else -1
		local bite = smooth((t - MOVE_AT) / 0.3)
		local fall = smooth((t - MOVE_AT - 0.35) / 0.4)
		local spot = at(wrong * (2.2 * bite + 1 * fall), -1.8 * fall, DEFENDER_Z + step)
		local pose = table.clone(STANCE)
		pose.legsOut = lerp(0.3, 0.7, bite)
		defenderAt(spot, -wrong * math.rad(30 * bite + 50 * fall), 0, pose)
	end

	-- The camera behind the attacker before the move; the move's ring closing pushes it in.
	local function framePrep(state: Freekick.State, now: number)
		blur.Size = 0
		local window = Freekick.moveWindow(state.kick)
		local waiting = now < state.stageAt
		grade.Saturation = if waiting then 0 else -0.35 -- the "bullet time" of the move
		local push = if waiting then 0 else smooth((now - state.stageAt) / window)
		look(
			at(6 - push * 1.5, 8 - push * 1.2, RUN_FROM + 13 - push * 3),
			at(-1, 2.4, DEFENDER_Z - 4),
			55
		)
		local feet = at(0, 0, RUN_FROM)
		attacker.place(facing(feet, Vector3.new(0, 0, -1)))
		attacker.run(0.35)
		attacker.pose(nil)
		-- The through-ball rolls in from behind and to the left, to the attacker's feet.
		local lead = Config.Training.freekickLeadSeconds
		local u = if waiting then 1 - (state.stageAt - now) / lead else 1
		local from = at(-12, BALL_R, RUN_FROM + 18)
		local to = at(0.4, BALL_R, RUN_FROM - 1.3)
		setBall(from:Lerp(to, 1 - (1 - math.clamp(u, 0, 1)) ^ 2), now * 6)
		local sway = math.sin(now * 2.2) * 0.4
		defenderAt(at(sway, 0, DEFENDER_Z), 0, 0, STANCE)
		keeperAt(at(keeperRestX(state), KEEPER_REST_Y, KEEPER_Z), 0, 0.5)
	end

	-- The camera behind the ball, the goal ahead, for the aim and the power.
	local function frameShoot(state: Freekick.State, now: number)
		blur.Size = 0
		grade.Saturation = 0
		local start = shotStart(state.move)
		local feet = start + Vector3.new(-0.8, -BALL_R, STRIKE_BACK)
		if penalty then
			-- The taker waits at the start of the run-up, eyes on the ball; the camera looks over his
			-- shoulder at the goal.
			local waitAt = feet + Vector3.new(-RUN_UP_SIDE, 0, RUN_UP_BACK)
			attacker.place(facing(waitAt, feet - waitAt))
			look(at(-1, 6.2, SHOT_Z + 17), at(0, GOAL_HEIGHT * 0.45, 0), 42)
		else
			attacker.place(facing(feet, Vector3.new(0, 0, -1)))
			look(
				at((start.X - ORIGIN.X) * 0.4 + 4, 6.6, SHOT_Z + 14),
				at(0, GOAL_HEIGHT * 0.45, 0),
				42
			)
		end
		attacker.run(0)
		attacker.pose(nil)
		setBall(start, 0)
		defenderBeaten(state.move, CUT_STRIKE) -- on the ground, behind the camera
		local sway = if penalty then 0 else math.sin(now * 3) * 0.5 -- the penalty keeper keeps the middle
		keeperAt(at(keeperRestX(state) + sway, KEEPER_REST_Y, KEEPER_Z), 0, 0.5)
	end

	-- Cut 1: the dribble, from the side.
	local function filmDribble(state: Freekick.State, t: number)
		local tackled = state.outcome == "tackled"
		local x, z = dribbleX(state.move, tackled, t), dribbleZ(tackled, t)
		local ahead = dribbleX(state.move, tackled, t + 0.05)
		local feet = at(x, 0, z)
		local direction = Vector3.new(ahead - x, 0, -sprintSpeed * 0.05)
		local stumble = if tackled then smooth((t - TACKLE_AT) / 0.3) else 0
		attacker.place(facing(feet, direction) * CFrame.Angles(math.rad(-18 * stumble), 0, 0))
		attacker.run(if tackled and t > TACKLE_AT + 0.4 then 0 else 1.5)
		if not tackled and state.move == Freekick.STEP_OVER and t > 0.6 and t < 0.95 then
			attacker.pose(stepOverJoints((t - 0.6) / 0.35))
		else
			attacker.pose(nil)
		end
		blur.Size = if t < CUT_STRIKE - 0.1 and not GuiService.ReducedMotionEnabled then 3 else 0
		grade.Saturation = 0

		-- The ball: at his feet, a touch ahead with every few strides; a tackle knocks it away.
		local touch = 1.3 + 0.5 * math.abs(math.sin(t * math.pi * 2.5))
		local atFeet = feet + Vector3.new(0.4, BALL_R, 0) + direction.Unit * touch
		if tackled and t > TACKLE_AT then
			local u = math.min((t - TACKLE_AT) / 0.9, 1)
			local hit = at(0.4, BALL_R, dribbleZ(true, TACKLE_AT) - 1.6)
			local away = Vector3.new(-8 * u, 2.2 * 4 * u * (1 - u), 3 * u)
			setBall(hit + away, t * 8)
		else
			setBall(atFeet, t * 12)
		end

		-- The defender steps in, then bites the wrong way and goes down, or slides in for the ball.
		local step = smooth((t - 0.5) / 0.4) * 1.5
		local defender0 = at(0, 0, DEFENDER_Z + step)
		if tackled then
			local slide = smooth((t - 0.8) / 0.3)
			local spot = defender0:Lerp(at(-1.2, 0, dribbleZ(true, TACKLE_AT) - 1), slide)
			local pose = table.clone(STANCE)
			pose.rightLeg = lerp(0, 1.4, slide)
			pose.leftLeg = lerp(0, 0.6, slide)
			defenderAt(spot + Vector3.new(0, -1.6 * slide, 0), 0, math.rad(-60 * slide), pose)
		else
			defenderBeaten(state.move, t)
		end
		keeperAt(at(keeperRestX(state), KEEPER_REST_Y, KEEPER_Z), 0, 0.5)

		-- The camera runs alongside, on his right.
		local track = if tackled
			then at(x, 0, dribbleZ(true, math.min(t, TACKLE_AT + 0.25)))
			else feet
		look(track + Vector3.new(17, 3.8, -1.5), track + Vector3.new(0, 2.6, -2.5), 50)
	end

	-- Cut 1 of a penalty: the run-up, from behind and to the right of the taker, pushing in.
	local function filmRunUp(state: Freekick.State, t: number)
		local u = math.clamp((t - (CUT_STRIKE - RUN_UP)) / RUN_UP, 0, 1)
		local start = shotStart(state.move)
		local feet = start + Vector3.new(-0.8, -BALL_R, STRIKE_BACK)
		local from = feet + Vector3.new(-RUN_UP_SIDE, 0, RUN_UP_BACK)
		-- A steady run that the cut to the strike interrupts before he reaches the ball, so the camera
		-- never waits behind him at the ball.
		local position = from:Lerp(feet, RUN_UP_REACH * u)
		attacker.place(facing(position, feet - from))
		attacker.run(1.2)
		attacker.pose(nil)
		blur.Size = 0
		grade.Saturation = -0.35 * smooth((u - 0.5) / 0.5) -- the bullet time of the strike comes in
		setBall(start, 0)
		keeperAt(at(keeperRestX(state), KEEPER_REST_Y, KEEPER_Z), 0, lerp(0.5, 0.9, u))
		local camera0 = at(7, 5.5, SHOT_Z + 15)
		local camera1 = at(5.5, 4.8, SHOT_Z + 13)
		look(camera0:Lerp(camera1, smooth(u)), at(0, GOAL_HEIGHT * 0.4, 0), 44)
	end

	-- Cut 2: the strike, in slow motion from the front.
	local function filmStrike(state: Freekick.State, t: number)
		local g = (t - CUT_STRIKE) / STRIKE_SECONDS
		local start = shotStart(state.move)
		local feet = start + Vector3.new(-0.8, -BALL_R, STRIKE_BACK)
		attacker.place(facing(feet, Vector3.new(0, 0, -1)))
		attacker.run(0)
		attacker.pose(strikeJoints(g))
		blur.Size = 0
		grade.Saturation = if penalty then -0.35 * (1 - smooth((g - 0.7) / 0.3)) else 0
		local p = flightShare(t)
		setBall(if p > 0 then flightPoint(state, p) else start, p * 40)
		local camera0 = feet + Vector3.new(4, 3, -11)
		local target = feet + Vector3.new(0.4, 2.6, -0.4)
		look(camera0:Lerp(target, 0.15 * g), target, 45)
		keeperAt(at(keeperRestX(state), KEEPER_REST_Y, KEEPER_Z), 0, 0.5)
	end

	-- Cut 3: the result, from behind the keeper.
	local function filmResult(state: Freekick.State, t: number)
		local outcome = state.outcome
		local start = shotStart(state.move)
		local finish = shotEnd(state)
		local feet = start + Vector3.new(-0.8, -BALL_R, STRIKE_BACK)
		attacker.place(facing(feet, Vector3.new(0, 0, -1)))
		attacker.run(0)
		attacker.pose(strikeJoints(1))
		blur.Size = 0
		grade.Saturation = 0
		local arrive = BreakawayScene.ARRIVE_AT
		local after = t - arrive
		local side = if finish.X - ORIGIN.X >= 0 then 1 else -1

		-- The ball.
		local ballAt: Vector3
		local p = flightShare(t)
		if after <= 0 then
			ballAt = flightPoint(state, p)
		elseif outcome == "goal" then
			local u = smooth(after / 0.3)
			local back = Vector3.new(
				finish.X * 0.98 + ORIGIN.X * 0.02,
				finish.Y,
				ORIGIN.Z - NET_DEPTH + BALL_R + 0.2
			)
			ballAt = finish:Lerp(back, u)
			local drop = smooth((after - 0.3) / 0.5)
			ballAt = Vector3.new(ballAt.X, lerp(ballAt.Y, ORIGIN.Y + BALL_R, drop), ballAt.Z)
		elseif outcome == "saved" then
			local u = math.min(after / 0.7, 1)
			local away = Vector3.new(side * 6 * u, 3 * 4 * u * (1 - u), 5 * u)
			ballAt = finish + away - Vector3.new(0, (finish.Y - ORIGIN.Y - BALL_R) * u, 0)
		elseif outcome == "post" or outcome == "bar" then
			local u = math.min(after / 0.6, 1)
			ballAt = finish + Vector3.new(-side * 2 * u, -(finish.Y - ORIGIN.Y - BALL_R) * u, 7 * u)
		else -- wide or over: on past the goal
			local direction = (finish - start).Unit
			ballAt = finish + direction * math.min(after, 1) * 14
		end
		setBall(ballAt, t * 10)

		-- The net bulges when the ball hits it.
		local bulge = if outcome == "goal"
			then math.sin(math.pi * math.clamp((after - 0.2) / 0.5, 0, 1))
			else 0
		netBack.CFrame = netRest * CFrame.new(0, 0, 0.9 * bulge)

		-- The keeper dives: to the ball for a save, short of it otherwise; then lies on the ground.
		local restX = keeperRestX(state)
		local targetX = finish.X - ORIGIN.X
		local reachX: number
		if outcome == "saved" then
			reachX = targetX - side * 2.2
		else
			local gap = math.max(math.abs(targetX - restX) - 4.6, 0.8)
			reachX = restX + side * gap
		end
		local dive = smooth((t - CUT_RESULT - 0.1) / (FLIGHT_SECONDS - 0.1))
		local land = smooth((after - 0.2) / 0.6)
		local diveY =
			lerp(KEEPER_REST_Y, math.clamp(finish.Y - ORIGIN.Y - 1, 1.4, GOAL_HEIGHT - 1.5), dive)
		keeperAt(
			at(lerp(restX, reachX, dive), lerp(diveY, 1.2, land), KEEPER_Z),
			-side * math.rad(lerp(0, 75, dive) + 15 * land),
			lerp(0.5, 2.7, dive)
		)
		defenderBeaten(state.move, CUT_STRIKE)

		-- The camera, high behind the net, over the keeper: it swivels after the ball.
		local follow = smooth((t - CUT_RESULT) / 0.7)
		local position = at(lerp(-side * 4, side * 2, follow), 12, -NET_DEPTH - 11)
		local lookAt = start:Lerp(ballAt, follow * 0.65)
		look(position, lookAt + Vector3.new(0, 0.4, 0), lerp(58, 50, follow))
	end

	local function frame(view: View)
		local state, now = view.state, view.now
		local phase = state.phase
		if phase == "dribble" then
			netBack.CFrame = netRest
			framePrep(state, now)
		elseif phase == "aim" or phase == "power" then
			netBack.CFrame = netRest
			frameShoot(state, now)
		else
			-- The film, or its last frame while the result shows. A penalty's film starts at the run-up,
			-- PENALTY_SKIP into the breakaway's.
			local filmEnd = if penalty
				then Config.Daily.penaltyFilmSeconds
				else Freekick.filmSeconds(state.outcome)
			local t = (if phase == "shot" then now - state.stageAt else filmEnd)
				+ (if penalty then BreakawayScene.PENALTY_SKIP else 0)
			if penalty and t < CUT_STRIKE then
				filmRunUp(state, t)
			elseif t < CUT_STRIKE or state.outcome == "tackled" then
				filmDribble(state, t)
			elseif t < CUT_RESULT then
				filmStrike(state, t)
			else
				filmResult(state, t)
			end
		end
	end

	return {
		frame = frame,
		goalPoint = function(x: number, y: number): Vector3
			return at(x * GOAL_HALF_WIDTH, y * GOAL_HEIGHT, 0)
		end,
		destroy = function()
			attacker.destroy()
			blur:Destroy()
			grade:Destroy()
			folder:Destroy()
		end,
	}
end

return BreakawayScene
