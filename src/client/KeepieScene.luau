--!strict
-- The 3D scene of the keepie-uppies (client/KeepieUi drives it): the centre circle of a small stadium
-- built far from the map, only on this client, with a clone of the player's own avatar
-- (client/AvatarActor) keeping a ball up. The ball is drawn from the server's streak with the same
-- Juggle functions the server judges with: it leaves a foot at each beat, flies up and comes back to
-- the other foot on the next one, and after a drop it falls and rolls away. The legs follow the same
-- beats: the foot of the next touch comes up to meet the ball as it falls, and on a touch it flicks
-- up through the ball and goes back down. Every frame is drawn from scratch from the time
-- (docs/CINEMATICS.md). Display only: nothing here decides a touch.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AvatarActor = require(script.Parent.AvatarActor)
local Juggle = require(ReplicatedStorage.Shared.Juggle)

-- The pitch, in studs, from ORIGIN: the player stands on the centre spot and faces +z, towards the
-- camera; the far goal and its stand are behind him, towards -z.
local ORIGIN = Vector3.new(-6000, 400, 6000) -- far from the map and from the breakaway's stadium
local BALL_SIZE = 1.3
local BALL_R = BALL_SIZE / 2
local REST_Y = 0.75 -- the ball on the laces before the first kick
local REST_FORWARD = 0.8
local CONTACT_Y = 1.25 -- the ball meets the raised foot (the laces) here
local CONTACT_FORWARD = 1.4
local PEAK = 3 -- studs over the foot at the top of a flight (about chest height)
local GRAVITY = 70 -- the fall after a drop
local ROLL_SPEED = 3 -- how fast the dropped ball rolls away, towards the camera
local ROLL_SECONDS = 1.4
local CIRCLE_RADIUS = 9
local GOAL_Z = -52 -- the far goal line
local GOAL_HALF_WIDTH = 10
local GOAL_HEIGHT = 7.5

-- The legs, in degrees and seconds.
local KICK_HIP = 56 -- how far the kicking leg swings forward at the top of a touch
local KICK_KNEE = -25 -- a little bend: the foot, not the knee, meets the ball
local READY = 0.7 -- how far up (of a full touch) the foot waits for the falling ball
local FOOT_IN = 0.8 -- the ball lands this share of the hip's width out from the middle (on the laces)
local PREP_SECONDS = 0.28 -- the foot comes up this long before the ball arrives
local FLICK_SECONDS = 0.08 -- from waiting to the top of the touch
local DOWN_SECONDS = 0.22 -- and back down
local DROP_SECONDS = 0.2 -- the waiting foot goes back down when the ball is missed

local WHITE = Color3.fromRGB(240, 240, 240)
local LINE = Color3.fromRGB(245, 245, 245)
local GRASS = Color3.fromRGB(58, 138, 62)
local GRASS_LIGHT = Color3.fromRGB(68, 154, 72)
local CONCRETE = Color3.fromRGB(168, 168, 174)
local NAVY = Color3.fromRGB(32, 38, 56) -- Style.ui.panel
local NET = Color3.fromRGB(30, 60, 45)
local ORANGE = Color3.fromRGB(245, 140, 60)
local FANS = {
	Color3.fromRGB(230, 90, 90),
	Color3.fromRGB(90, 140, 230),
	Color3.fromRGB(240, 200, 70),
	Color3.fromRGB(120, 200, 130),
	Color3.fromRGB(230, 230, 235),
}

local KeepieScene = {}

-- What the frame needs: the server's streak and the time.
export type View = {
	round: Juggle.State,
	now: number,
}

export type Scene = {
	frame: (view: View) -> (),
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

-- A flat disc on the grass (a cylinder standing up), `height` thick.
local function disc(parent: Instance, radius: number, height: number, y: number, color: Color3)
	local part = block(parent, Vector3.new(height, radius * 2, radius * 2), Vector3.zero, color)
	part.Shape = Enum.PartType.Cylinder
	part.CFrame = CFrame.new(ORIGIN + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.pi / 2)
end

-- A stand of three tiers with fans, `length` long, its front at `front` and rising away along `away`
-- (the breakaway's stands).
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

-- The pitch around the centre circle: the stripes, the halfway line, the circle and the spot, the far
-- goal with its box, the stands, and a few training hurdles and balls by the circle.
local function buildField(parent: Instance)
	block(parent, Vector3.new(200, 1, 200), Vector3.new(0, -0.5, -20), GRASS)
	for index = 0, 9 do
		block(
			parent,
			Vector3.new(200, 0.05, 10),
			Vector3.new(0, 0.02, 25 - index * 20),
			GRASS_LIGHT
		)
	end
	local y = 0.06
	disc(parent, CIRCLE_RADIUS + 0.25, 0.07, y, LINE)
	disc(parent, CIRCLE_RADIUS - 0.25, 0.09, y, GRASS)
	block(parent, Vector3.new(180, 0.1, 0.5), Vector3.new(0, y, 0), LINE) -- the halfway line, over the circle
	disc(parent, 0.6, 0.11, y, LINE) -- the centre spot

	-- The far goal, its box and the stand behind it.
	block(parent, Vector3.new(180, 0.08, 0.5), Vector3.new(0, y, GOAL_Z), LINE)
	block(parent, Vector3.new(64, 0.08, 0.5), Vector3.new(0, y, GOAL_Z + 30), LINE)
	block(parent, Vector3.new(0.5, 0.08, 30), Vector3.new(-32, y, GOAL_Z + 15), LINE)
	block(parent, Vector3.new(0.5, 0.08, 30), Vector3.new(32, y, GOAL_Z + 15), LINE)
	local post = 0.6
	for _, x in { -GOAL_HALF_WIDTH, GOAL_HALF_WIDTH } do
		block(
			parent,
			Vector3.new(post, GOAL_HEIGHT, post),
			Vector3.new(x, GOAL_HEIGHT / 2, GOAL_Z),
			WHITE
		)
		block(
			parent,
			Vector3.new(0.12, GOAL_HEIGHT, 4),
			Vector3.new(x, GOAL_HEIGHT / 2, GOAL_Z - 2),
			NET,
			0.6
		)
	end
	block(
		parent,
		Vector3.new(GOAL_HALF_WIDTH * 2 + post, post, post),
		Vector3.new(0, GOAL_HEIGHT, GOAL_Z),
		WHITE
	)
	block(
		parent,
		Vector3.new(GOAL_HALF_WIDTH * 2, GOAL_HEIGHT, 0.12),
		Vector3.new(0, GOAL_HEIGHT / 2, GOAL_Z - 4),
		NET,
		0.5
	)
	stand(parent, Vector3.new(0, 0, GOAL_Z - 14), Vector3.new(0, 0, -1), 150)
	stand(parent, Vector3.new(-50, 0, -10), Vector3.new(-1, 0, 0), 140)
	stand(parent, Vector3.new(50, 0, -10), Vector3.new(1, 0, 0), 140)

	-- Training hurdles and a bag of balls outside the circle, one on each side of the picture.
	for index = 0, 1 do
		local x, z = -14 - index * 3.4, -6 + index * 1.6
		for _, side in { -1, 1 } do
			block(parent, Vector3.new(0.3, 1.6, 0.3), Vector3.new(x + side * 1.1, 0.8, z), WHITE)
		end
		block(parent, Vector3.new(2.6, 0.35, 0.35), Vector3.new(x, 1.5, z), ORANGE)
	end
	block(parent, Vector3.new(3, 1.6, 2.2), Vector3.new(14, 0.8, -8), NAVY)
	for index = 0, 3 do
		local ball = block(
			parent,
			Vector3.new(1.2, 1.2, 1.2),
			Vector3.new(13.1 + (index % 2) * 1.6, 2, -8.5 + (index // 2) * 1),
			WHITE
		)
		ball.Shape = Enum.PartType.Ball
	end
end

-- The match ball: white with navy patches, like the breakaway's.
local function buildBall(parent: Instance): Part
	local ball = new("Part", {
		Name = "Ball",
		Shape = Enum.PartType.Ball,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE),
		Color = WHITE,
		Material = Enum.Material.SmoothPlastic,
	}, parent)
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
	return ball
end

-- The foot that touches beat `index` (0 is the kick-up at the start): the right one first, then each
-- in turn.
local function sideFor(index: number): string
	return if index % 2 == 0 then "Right" else "Left"
end

-- How far up each leg is at `now` (0 down, 1 the top of a touch), from the beats alone: the foot of
-- the next beat waits for the ball, and the foot of the last touch flicks up and comes down.
local function legLifts(round: Juggle.State, now: number): { [string]: number }
	local lifts = { Right = 0, Left = 0 }
	local touched = round.lastIndex -- the last beat hit; 0 is the kick-up at the start
	local at = now - Juggle.beatTime(round, touched)
	if at >= 0 and at < FLICK_SECONDS + DOWN_SECONDS then
		local lift = if at < FLICK_SECONDS
			then lerp(READY, 1, smooth(at / FLICK_SECONDS))
			else 1 - smooth((at - FLICK_SECONDS) / DOWN_SECONDS)
		lifts[sideFor(touched)] = lift
	end
	local coming = touched + 1
	local beat = Juggle.beatTime(round, coming)
	local wait = if now <= beat
		then READY * smooth((now - (beat - PREP_SECONDS)) / PREP_SECONDS)
		else READY * (1 - smooth((now - beat) / DROP_SECONDS))
	local side = sideFor(coming)
	lifts[side] = math.max(lifts[side], wait)
	return lifts
end

-- The joints for the leg lifts: each knee comes up in front; the arms stay out for balance.
local function legJoints(lifts: { [string]: number }): { [string]: CFrame }
	local joints: { [string]: CFrame } = {
		RightShoulder = CFrame.Angles(math.rad(10), 0, math.rad(28)),
		LeftShoulder = CFrame.Angles(math.rad(10), 0, math.rad(-28)),
	}
	for side, lift in lifts do
		joints[side .. "Hip"] = CFrame.Angles(math.rad(6 + KICK_HIP * lift), 0, 0)
		joints[side .. "Knee"] = CFrame.Angles(math.rad(-12 + KICK_KNEE * lift), 0, 0)
	end
	return joints
end

function KeepieScene.new(): Scene
	local folder = new("Folder", { Name = "KeepiePitch" })
	buildField(folder)
	folder.Parent = Workspace
	local actor = AvatarActor.new(folder)
	local feet = ORIGIN + Vector3.new(0, 0.1, 0)
	local facing = CFrame.lookAt(feet, feet + Vector3.new(0, 0, 1))
	actor.place(facing)
	local ball = buildBall(folder)
	local camera = Workspace.CurrentCamera

	-- A point in front of the player: `side` 1 is his right foot, -1 his left (the front of `facing`
	-- is -z).
	local function inFront(side: number, y: number, forward: number): Vector3
		return facing:PointToWorldSpace(Vector3.new(side * actor.hipX * FOOT_IN, y, -forward))
	end
	local function sign(index: number): number
		return if sideFor(index) == "Right" then 1 else -1
	end

	-- Where the ball is at `now` while the streak runs: on the laces before the kick-up, then on a
	-- flight from the foot of the last beat to the foot of the next one (past it if no touch came).
	local function flightAt(round: Juggle.State, now: number): Vector3
		if now <= round.startedAt then
			return inFront(sign(0), REST_Y, REST_FORWARD)
		end
		local index = Juggle.beatAt(round, now)
		local from = Juggle.beatTime(round, index - 1)
		local p = (now - from) / Juggle.period(index)
		local fromY = if index == 1 then REST_Y else CONTACT_Y
		local fromForward = if index == 1 then REST_FORWARD else CONTACT_FORWARD
		local u = math.clamp(p, 0, 1)
		local y = lerp(fromY, CONTACT_Y, u) + 4 * p * (1 - p) * PEAK
		return inFront(
			lerp(sign(index - 1), sign(index), smooth(u)),
			math.max(y, BALL_R),
			lerp(fromForward, CONTACT_FORWARD, u)
		)
	end

	-- After a drop: the ball falls from where it was when the streak ended and rolls away.
	local function droppedAt(round: Juggle.State, now: number): Vector3
		local start = flightAt(round, round.overAt)
		local floor = ORIGIN.Y + BALL_R
		local t = math.max(now - round.overAt, 0)
		local fallTime = math.sqrt(2 * math.max(start.Y - floor, 0) / GRAVITY)
		local y = math.max(start.Y - 0.5 * GRAVITY * t * t, floor)
		local roll = math.min(math.max(t - fallTime, 0), ROLL_SECONDS)
		local eased = roll - roll * roll / (2 * ROLL_SECONDS) -- slows down to a stop
		return Vector3.new(start.X, y, start.Z + ROLL_SPEED * eased)
	end

	local function frame(view: View)
		local round, now = view.round, view.now
		local running = round.phase == "running"
		local position = if running then flightAt(round, now) else droppedAt(round, now)
		local spin = if running then (now - round.startedAt) * 6 else 0
		ball.CFrame = CFrame.new(position) * CFrame.Angles(spin, spin * 0.3, 0)

		-- The legs follow the beats while the ball is up; after a drop the player stands.
		actor.pose(if running then legJoints(legLifts(round, now)) else nil)

		-- The camera, low and three-quarters on, so a leg swinging forward shows in profile; it creeps
		-- in as the streak grows and follows the ball's height a little.
		local push = math.clamp(round.combo / 40, 0, 1)
		local sway = if GuiService.ReducedMotionEnabled then 0 else math.sin(now * 0.35) * 0.8
		local eye = ORIGIN
			+ Vector3.new(11.5 + sway, 4.4, 10.5)
				* Vector3.new(lerp(1, 0.85, push), 1, lerp(1, 0.85, push))
		local ballLift = math.clamp(position.Y - ORIGIN.Y, 0, 8)
		local target = ORIGIN + Vector3.new(0, 3.6 + ballLift * 0.12, 0)
		camera.CFrame = CFrame.lookAt(eye, target)
		camera.FieldOfView = 50
	end

	return {
		frame = frame,
		destroy = function()
			actor.destroy()
			folder:Destroy()
		end,
	}
end

return KeepieScene
