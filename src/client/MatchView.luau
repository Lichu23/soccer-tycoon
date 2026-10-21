--!strict
-- Draws the match on the pitch (docs/PLAN.md, Step 7). The server decides the match: at kick-off it
-- sends the score (MatchStarted) and at the whistle it pays (MatchResult). The client only plays it with
-- local figures, so nothing here is replicated and the server never simulates a match.
--
-- The ball is in play the whole match: the players dribble, pass and tackle, the nearest players chase
-- it and the rest move with play. The goals come from MatchScript: each one has its own attack that ends
-- in a shot into the net, the scorers celebrate and play restarts from the middle. How the attack is
-- played depends on the team: a 1-on-1 duel with a feint for one player, one-twos for two or three,
-- passing moves for more. A scoreboard over the pitch shows the score and the time left.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CourtPlan = require(ReplicatedStorage.Shared.CourtPlan)
local Formation = require(ReplicatedStorage.Shared.Formation)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)
local MatchScript = require(ReplicatedStorage.Shared.MatchScript)
local Net = require(script.Parent.Net)
local Roster = require(ReplicatedStorage.Shared.Roster)
local Sounds = require(script.Parent.Sounds)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local COURT_CENTER_Z = CourtPlan.CENTER_Z -- the middle of every pitch, in plot space
local TORSO_HEIGHT = 0.7 + Mannequin.FEET_TO_TORSO - 1 -- in gate space (the gate is 1 stud up)
local BALL_SIZE = 1.4
local BALL_LIFT = -Mannequin.FEET_TO_TORSO + BALL_SIZE / 2 -- the ball on the grass, from the torso
local RIVAL_KIT = Color3.fromRGB(70, 190, 100) -- a green no team of ours wears, so the rivals always stand out
local JOG = 6 -- studs per second
local SPRINT = 9
local PASS_SECONDS = 0.45
local SHOT_SECONDS = 0.4
local CONTROL = 1.3 -- the ball is this far in front of the player who has it
local TACKLE_REACH = 1.8
local SPACE = 1.7 -- the closest two players stand
local TACKLE_COOLDOWN = 1.6
local FAR_AWAY = 240 -- studs from the camera: do not animate
local OTHER_PLOT_SECONDS = 40
local FALLBACK_SECONDS = 3 -- a result with no kick-off seen (joined mid-match) plays its goals this fast
local BOARD_HEIGHT = 18 -- the scoreboard over the middle of the pitch, studs above the grass

type Runner = {
	model: Model,
	side: number, -- 1 our team (attacks towards +x), -1 the rivals
	home: Vector3, -- court space: x along the length, z across, y unused
	position: Vector3,
	stride: number, -- the running animation's phase
	yaw: number,
	stumbleUntil: number, -- beaten in a duel: slow and leaning
	kickUntil: number, -- the leg is swinging through the ball
	wanderAt: number,
	wander: Vector3,
	target: Vector3, -- where he heads this frame
	speed: number,
}

type Board = { part: Part, gui: BillboardGui, score: TextLabel, clock: TextLabel }

type Team = {
	plot: Model,
	gate: BasePart,
	key: string,
	runners: { Runner },
	size: number, -- players per team
	length: number,
	width: number,
	goalHalf: number, -- half the goal opening
	ball: Part,
	board: Board,
	celebrateSide: number,
	celebrateUntil: number,
	lastUsed: number,
}

-- The ball's flight from one place to another (a pass, an interception or a shot).
type Flight = {
	from: Vector3,
	to: Vector3,
	startedAt: number,
	seconds: number,
	height: number,
	receiver: Runner?, -- nil for a shot
}

type Play = {
	startedAt: number, -- os.clock() of the kick-off
	duration: number,
	script: MatchScript.Script,
	random: Random,
	ball: Vector3, -- court space
	ballSpin: number,
	holder: Runner?,
	flight: Flight?,
	segment: number, -- which stretch of the match the ball was last set up for
	kickoffSide: number,
	nextPassAt: number,
	lastTackleAt: number,
	movesDone: number, -- passes and feints made in the current attack
	shot: { [number]: boolean }, -- goals whose shot is on its way
	scored: { [number]: boolean }, -- goals already in the net
}

local teams: { [Model]: Team } = {}
local plays: { [Model]: Play } = {}
local folder: Folder

local MatchView = {}

local function gateCFrame(team: Team, x: number, z: number, lift: number): CFrame
	return team.gate.CFrame * CFrame.new(x, TORSO_HEIGHT + lift, COURT_CENTER_Z + z)
end

local function tierFor(count: number): Config.StadiumTierDef
	for _, def in Config.StadiumTiers do
		if def.field >= count then
			return def
		end
	end
	return Config.StadiumTiers[#Config.StadiumTiers]
end

-- The kit the plot's owner chose (set by the server on the plot), nil = the team kits.
local function kitOf(plot: Model): Color3?
	local id = plot:GetAttribute("KitId")
	local def = if type(id) == "string" then Config.CosmeticsById[id] else nil
	if def == nil then
		return nil
	end
	return Color3.fromRGB(def.color[1], def.color[2], def.color[3])
end

local function teamKey(plot: Model, fieldIds: { string }, tier: Config.StadiumTierDef): string
	local kit = plot:GetAttribute("KitId")
	return table.concat(fieldIds, ",") .. "|" .. tier.tier .. "|" .. tostring(kit)
end

local function opponentDef(index: number): Config.PlayerDef
	return {
		id = "rival" .. index,
		name = "",
		nationality = "",
		number = index,
		rarity = "Common",
		floor = 0,
		slot = 0,
		price = 0,
		income = 0,
	}
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function destroyTeam(team: Team)
	for _, runner in team.runners do
		runner.model:Destroy()
	end
	team.ball:Destroy()
	team.board.part:Destroy()
	teams[team.plot] = nil
end

-- The scoreboard: a dark plate high over the middle of the pitch with the score and the time left.
local function buildBoard(team: Team): Board
	local part = Instance.new("Part")
	part.Name = "MatchBoard"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = gateCFrame(team, 0, 0, BOARD_HEIGHT - Mannequin.FEET_TO_TORSO)
	part.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Name = "Board"
	gui.Size = UDim2.fromOffset(170, 64)
	gui.MaxDistance = 180
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Parent = part
	local plate = Instance.new("Frame")
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Style.ui.dark
	plate.BackgroundTransparency = 0.15
	plate.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Color = Style.ui.gold
	stroke.Thickness = 2
	stroke.Parent = plate
	local score = Instance.new("TextLabel")
	score.Name = "Score"
	score.BackgroundTransparency = 1
	score.Size = UDim2.new(1, 0, 0, 40)
	score.Font = Style.font
	score.TextSize = 32
	score.TextColor3 = Style.ui.gold
	score.Text = "0 - 0"
	score.Parent = plate
	local clock = Instance.new("TextLabel")
	clock.Name = "Clock"
	clock.BackgroundTransparency = 1
	clock.Position = UDim2.fromOffset(0, 38)
	clock.Size = UDim2.new(1, 0, 0, 22)
	clock.Font = Style.font
	clock.TextSize = 16
	clock.TextColor3 = Style.ui.text
	clock.Text = ""
	clock.Parent = plate
	return { part = part, gui = gui, score = score, clock = clock }
end

-- Builds both teams for a plot: our field players and as many rival figures, and the ball.
local function buildTeam(plot: Model, fieldIds: { string }, tier: Config.StadiumTierDef): Team?
	local gate = plot:FindFirstChild("Gate")
	if not gate or not gate:IsA("BasePart") then
		return nil
	end
	local count = #fieldIds
	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE)
	ball.Color = Color3.fromRGB(250, 250, 250)
	ball.Material = Enum.Material.SmoothPlastic
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Parent = folder
	local team: Team = {
		plot = plot,
		gate = gate,
		key = teamKey(plot, fieldIds, tier),
		runners = {},
		size = count,
		length = tier.courtLength,
		width = tier.courtWidth,
		goalHalf = if tier.tier <= 2 then 4 else 5,
		ball = ball,
		board = nil :: any,
		celebrateSide = 0,
		celebrateUntil = 0,
		lastUsed = os.clock(),
	}
	team.board = buildBoard(team)
	local ours = Formation.spots(count, team.length, team.width, -1)
	local theirs = Formation.spots(count, team.length, team.width, 1)
	local function add(model: Model, side: number, spot: Formation.Spot)
		model.Parent = folder
		local home = Vector3.new(spot.x, 0, spot.z)
		table.insert(team.runners, {
			model = model,
			side = side,
			home = home,
			position = home,
			stride = 0,
			yaw = if side == 1 then -math.pi / 2 else math.pi / 2,
			stumbleUntil = 0,
			kickUntil = 0,
			wanderAt = 0,
			wander = Vector3.zero,
			target = home,
			speed = JOG,
		})
	end
	for index = 1, count do
		local def = Config.PlayersById[fieldIds[index]]
		if def then
			add(Mannequin.build(def, kitOf(plot), false), 1, ours[index])
			add(Mannequin.build(opponentDef(index), RIVAL_KIT, false), -1, theirs[index])
		end
	end
	teams[plot] = team
	return team
end

-- The team of a plot, rebuilt when the players on the field changed.
local function ensureTeam(plot: Model, fieldIds: { string }, tier: Config.StadiumTierDef): Team?
	local existing = teams[plot]
	local key = teamKey(plot, fieldIds, tier)
	if existing and existing.key == key then
		existing.lastUsed = os.clock()
		return existing
	end
	if existing then
		destroyTeam(existing)
	end
	if #fieldIds == 0 then
		return nil
	end
	return buildTeam(plot, fieldIds, tier)
end

local function nearCamera(team: Team): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and (team.gate.Position - camera.CFrame.Position).Magnitude < FAR_AWAY
end

local function ownPlot(): Model?
	local slot = player:GetAttribute("plotSlot")
	local plots = Workspace:FindFirstChild("Plots")
	local plot = if type(slot) == "number" and plots
		then plots:FindFirstChild("Plot_" .. slot)
		else nil
	return if plot and plot:IsA("Model") then plot else nil
end

-- The ball and the players ------------------------------------------------------------------------

local function nearest(team: Team, side: number, point: Vector3, except: Runner?): Runner?
	local best: Runner? = nil
	local bestDistance = math.huge
	for _, runner in team.runners do
		if runner.side == side and runner ~= except then
			local distance = (flat(runner.position) - flat(point)).Magnitude
			if distance < bestDistance then
				best, bestDistance = runner, distance
			end
		end
	end
	return best
end

-- The team-mate furthest up the pitch (towards the goal `side` attacks), or nil when alone.
local function forwardMate(team: Team, holder: Runner): Runner?
	local best: Runner? = nil
	for _, runner in team.runners do
		if runner.side == holder.side and runner ~= holder then
			if best == nil or runner.position.X * holder.side > best.position.X * holder.side then
				best = runner
			end
		end
	end
	return best
end

local function launch(play: Play, to: Vector3, seconds: number, height: number, receiver: Runner?)
	play.flight = {
		from = play.ball,
		to = to,
		startedAt = os.clock(),
		seconds = seconds,
		height = height,
		receiver = receiver,
	}
	if play.holder then
		play.holder.kickUntil = os.clock() + 0.25
	end
	play.holder = nil
end

-- A pass to `receiver`, aimed where he will be.
local function pass(play: Play, receiver: Runner)
	launch(
		play,
		flat(receiver.position) + Vector3.new(receiver.side * 1.5, 0, 0),
		PASS_SECONDS,
		0.6,
		receiver
	)
end

local function holderSide(play: Play): number
	if play.holder then
		return play.holder.side
	elseif play.flight and play.flight.receiver then
		return play.flight.receiver.side
	end
	return 0
end

-- The stretch of the match at `time`: 0 the line-up, then for goal i: 2i-1 open play before it and 2i its
-- attack, celebration and reset. Returns the stretch, the goal it leads to and whether it is the attack.
local function stretchAt(play: Play, time: number): (number, MatchScript.Goal?, number)
	if time < play.script.kickoff then
		return 0, nil, 0
	end
	for index, goal in play.script.goals do
		if time < goal.resetAt then
			if time < goal.attackFrom then
				return index * 2 - 1, goal, index
			end
			return index * 2, goal, index
		end
	end
	return #play.script.goals * 2 + 1, nil, 0
end

-- Moves the ball on in its flight; at the end the receiver has it (a shot stays in the net).
local function advanceFlight(play: Play, now: number)
	local flight = play.flight
	if flight == nil then
		return
	end
	local progress = math.clamp((now - flight.startedAt) / flight.seconds, 0, 1)
	play.ball = flight.from:Lerp(flight.to, progress)
		+ Vector3.new(0, math.sin(progress * math.pi) * flight.height, 0)
	if progress >= 1 then
		play.flight = nil
		play.ball = flight.to
		if flight.receiver and flight.receiver.model.Parent then
			play.holder = flight.receiver
		end
	end
end

-- Where each player heads this frame, and how fast. `attack` is the side attacking for a goal (0 in
-- open play).
local function runnerGoal(
	team: Team,
	play: Play,
	runner: Runner,
	now: number,
	attack: number
): (Vector3, number)
	local ball = flat(play.ball)
	local holder = play.holder
	local side = runner.side
	local goalX = side * team.length / 2
	if runner == holder then
		if attack == side then
			-- Run at the goal: to the shooting spot, wherever the defence is.
			local lane = runner.wander.Z * 0.4
			local spot = Vector3.new(goalX - side * 7, 0, lane)
			return spot, SPRINT
		end
		-- Open play: carry it up the pitch but not into shooting range, drifting across.
		if now >= runner.wanderAt then
			runner.wanderAt = now + 0.8 + play.random:NextNumber()
			runner.wander = Vector3.new(0, 0, (play.random:NextNumber() - 0.5) * team.width * 0.6)
		end
		local limit = team.length * 0.2
		local x = math.clamp(runner.position.X + side * 6, -limit, limit)
		return Vector3.new(x, 0, runner.wander.Z), JOG
	end
	local attacking = holderSide(play)
	if attacking ~= 0 and attacking ~= side then
		-- Defending: the nearest one presses the ball, the rest drop between it and their goal.
		local presser = nearest(team, side, ball)
		if runner == presser then
			-- Close down the ball from the goal side, a step off the player who has it.
			local ownGoal = Vector3.new(-goalX, 0, 0)
			local cover = ball + (ownGoal - ball).Unit * 1.8
			local speed = if attack == -side then JOG * 0.85 else JOG
			return cover, speed
		end
		local back = runner.home:Lerp(Vector3.new(-goalX * 0.5, 0, ball.Z), 0.3)
		return back, JOG
	end
	if attacking == side then
		-- Supporting: move up with the ball, wide of the holder, further when attacking for a goal.
		local push = if attack == side then team.length * 0.3 else team.length * 0.12
		local x = runner.home.X + side * push + (ball.X - runner.home.X) * 0.25
		return Vector3.new(x, 0, runner.home.Z), if attack == side then SPRINT * 0.9 else JOG
	end
	-- Loose ball: the nearest of each team goes for it, the rest hold their shape.
	if runner == nearest(team, side, ball) then
		return ball, SPRINT
	end
	return runner.home:Lerp(Vector3.new(ball.X, 0, runner.home.Z), 0.25), JOG
end

-- Sets up the ball for a new stretch of the match: at the line-up and after a goal the ball goes back
-- to the centre spot, and the team that kicks off runs to it.
local function enterStretch(play: Play, stretch: number, now: number)
	play.segment = stretch
	play.movesDone = 0
	if stretch == 0 or (stretch % 2 == 1 and play.flight == nil and play.holder == nil) then
		play.flight = nil
		play.holder = nil
		play.ball = Vector3.zero
		play.nextPassAt = now + 1.2
	end
end

-- One frame of a match with a timeline.
local function updatePlay(team: Team, play: Play, now: number, own: boolean)
	local time = now - play.startedAt
	local stretch, goal, goalIndex = stretchAt(play, time)
	if stretch ~= play.segment then
		enterStretch(play, stretch, now)
	end
	advanceFlight(play, now)
	local attack = 0
	if goal and stretch % 2 == 0 then
		if time >= goal.at then
			-- In the net: the scorers celebrate until the reset, then the conceding team kicks off.
			if not play.scored[goalIndex] then
				play.scored[goalIndex] = true
				play.flight = nil
				play.holder = nil
				play.ball = Vector3.new(goal.side * (team.length / 2 + 1.5), 0, play.ball.Z)
				team.celebrateSide = goal.side
				team.celebrateUntil = now + (goal.resetAt - time)
				play.kickoffSide = -goal.side
				if own then
					Sounds.play("net")
				end
			end
		else
			attack = goal.side
			local attackProgress = (time - goal.attackFrom) / (goal.at - goal.attackFrom)
			local remaining = goal.at - time
			local holder = play.holder
			local flight = play.flight
			if remaining <= SHOT_SECONDS and not play.shot[goalIndex] then
				-- The shot: whoever is on the ball for the attacking side strikes it into the net.
				if holder == nil or holder.side ~= attack then
					holder = nearest(team, attack, play.ball)
					play.holder = holder
				end
				if holder then
					play.ball = flat(holder.position) + Vector3.new(attack * CONTROL, 0, 0)
				end
				local corner = (play.random:NextNumber() * 2 - 1) * (team.goalHalf - 1)
				launch(
					play,
					Vector3.new(attack * (team.length / 2 + 1.5), 0, corner),
					remaining,
					1.4,
					nil
				)
				play.shot[goalIndex] = true
			elseif flight == nil and (holder == nil or holder.side ~= attack) then
				-- The attacking side wins the ball: the nearest one takes it.
				local winner = nearest(team, attack, play.ball)
				if winner then
					launch(play, flat(winner.position), 0.25, 0.2, winner)
					play.lastTackleAt = now
				end
			elseif holder and holder.side == attack then
				if team.size == 1 then
					-- The duel: the defender comes to block, the striker feints past and he stumbles.
					if play.movesDone == 0 and attackProgress >= 0.45 then
						play.movesDone = 1
						local defender = nearest(team, -attack, holder.position)
						holder.wander = Vector3.new(0, 0, if holder.position.Z > 0 then -9 else 9)
						if defender then
							defender.stumbleUntil = now + 1.1
						end
					end
				elseif play.movesDone < 2 and attackProgress >= 0.25 + play.movesDone * 0.3 then
					-- One-twos and through balls: to the team-mate furthest forward.
					local mate = forwardMate(team, holder)
					if mate then
						play.movesDone += 1
						pass(play, mate)
					end
				end
			end
		end
	elseif stretch % 2 == 1 and goal then
		-- Open play: keep the ball moving, a tackle now and then.
		local holder = play.holder
		if holder == nil and play.flight == nil then
			local chaser = nearest(team, play.kickoffSide, play.ball)
			if chaser and (flat(chaser.position) - flat(play.ball)).Magnitude < CONTROL + 0.4 then
				play.holder = chaser
			end
		elseif holder then
			if team.size > 1 and now >= play.nextPassAt then
				play.nextPassAt = now + 0.9 + play.random:NextNumber() * 0.7
				local mates = {}
				for _, runner in team.runners do
					if runner.side == holder.side and runner ~= holder then
						table.insert(mates, runner)
					end
				end
				if #mates > 0 then
					pass(play, mates[play.random:NextInteger(1, #mates)])
				end
			elseif team.size > 1 and now - play.lastTackleAt > TACKLE_COOLDOWN then
				local tackler = nearest(team, -holder.side, holder.position)
				if
					tackler
					and (flat(tackler.position) - flat(holder.position)).Magnitude
						< TACKLE_REACH
				then
					play.lastTackleAt = now
					play.holder = tackler
					play.kickoffSide = tackler.side
				end
			end
		end
	end

	-- Where the players head.
	local over = stretch == 0 or stretch > #play.script.goals * 2
	for _, runner in team.runners do
		local target, speed = runnerGoal(team, play, runner, now, attack)
		if team.celebrateSide ~= 0 and now < team.celebrateUntil then
			-- The scorers celebrate where they are; the others are already running back.
			local scorer = runner.side == team.celebrateSide
			target = if scorer then runner.position else runner.home
			speed = if scorer then 0 else SPRINT * 1.6
		elseif
			over and not (stretch == 0 and runner == nearest(team, play.kickoffSide, Vector3.zero))
		then
			-- The line-up: back to the formation fast, so the kick-off is never kept waiting; the
			-- kick-off taker goes to the ball.
			target = runner.home
			speed = SPRINT * 1.6
		end
		if now < runner.stumbleUntil then
			speed *= 0.3
		end
		runner.target = target
		runner.speed = speed
	end
end

-- Keeps the players from standing inside each other.
local function separate(team: Team)
	local runners = team.runners
	for i = 1, #runners do
		for j = i + 1, #runners do
			local a, b = runners[i], runners[j]
			local gap = flat(b.position) - flat(a.position)
			local distance = gap.Magnitude
			if distance < SPACE and distance > 1e-3 then
				local push = gap.Unit * (SPACE - distance) / 2
				a.position -= push
				b.position += push
			end
		end
	end
end

-- Moves the players and the ball one frame and draws them.
local function drawTeam(team: Team, play: Play?, now: number, dt: number)
	local moved: { [Runner]: boolean } = {}
	for _, runner in team.runners do
		local target, speed = runner.target, runner.speed
		if play == nil then
			-- No match: a gentle jog around the home spot.
			if now >= runner.wanderAt then
				runner.wanderAt = now + 1 + math.random() * 1.5
				runner.wander = Vector3.new((math.random() - 0.5) * 8, 0, (math.random() - 0.5) * 8)
			end
			target = runner.home + runner.wander
			speed = JOG * 0.7
		end
		local offset = flat(target) - flat(runner.position)
		local moving = offset.Magnitude > 0.2
		moved[runner] = moving
		if moving then
			runner.position += offset.Unit * math.min(speed * dt, offset.Magnitude)
			runner.yaw = math.atan2(-offset.X, -offset.Z)
			runner.stride += dt * speed * 1.6
		elseif play then
			local toBall = flat(play.ball) - flat(runner.position)
			if toBall.Magnitude > 0.5 then
				runner.yaw = math.atan2(-toBall.X, -toBall.Z)
			end
		end
	end
	separate(team)
	for _, runner in team.runners do
		local moving = moved[runner] == true
		local celebrating = team.celebrateSide == runner.side and now < team.celebrateUntil
		local bob = if celebrating then math.abs(math.sin(now * 9 + runner.home.Z)) * 2 else 0
		local lean = if now < runner.stumbleUntil
			then CFrame.Angles(-0.5, 0, 0)
			else CFrame.identity
		local base = gateCFrame(team, runner.position.X, runner.position.Z, bob)
			* CFrame.Angles(0, runner.yaw, 0)
			* lean
		runner.model:PivotTo(base)
		-- The limbs: legs and arms swing while running, the kicking leg swings through, arms up to celebrate.
		local swing = if moving then math.sin(runner.stride) * 0.7 else 0
		local kick = if now < runner.kickUntil then 1.1 else 0
		local hip, shoulder = Mannequin.HIP, Mannequin.SHOULDER
		for _, limb in
			{
				{
					name = "Right Leg",
					x = hip.X,
					y = hip.Y,
					reach = Mannequin.LEG_REACH,
					angle = swing + kick,
					side = 0,
				},
				{
					name = "Left Leg",
					x = -hip.X,
					y = hip.Y,
					reach = Mannequin.LEG_REACH,
					angle = -swing,
					side = 0,
				},
				{
					name = "Right Arm",
					x = shoulder.X,
					y = shoulder.Y,
					reach = Mannequin.ARM_REACH,
					angle = -swing * 0.8,
					side = 1,
				},
				{
					name = "Left Arm",
					x = -shoulder.X,
					y = shoulder.Y,
					reach = Mannequin.ARM_REACH,
					angle = swing * 0.8,
					side = -1,
				},
			}
		do
			local part = runner.model:FindFirstChild(limb.name)
			if part and part:IsA("BasePart") then
				local turn = if celebrating and limb.side ~= 0
					then CFrame.Angles(0, 0, limb.side * math.rad(150))
					else CFrame.Angles(limb.angle, 0, 0)
				part.CFrame = base
					* CFrame.new(limb.x, limb.y, 0)
					* turn
					* CFrame.new(0, -limb.reach, 0)
			end
		end
	end
	if play then
		-- The ball rolls at the holder's feet, a touch ahead, or flies.
		local holder = play.holder
		if holder and play.flight == nil then
			local ahead = CONTROL + math.abs(math.sin(now * 5)) * 0.5
			local forward = Vector3.new(-math.sin(holder.yaw), 0, -math.cos(holder.yaw))
			local spot = flat(holder.position) + forward * ahead
			play.ballSpin += (spot - flat(play.ball)).Magnitude / (BALL_SIZE / 2)
			play.ball = spot
		end
		team.ball.CFrame = gateCFrame(team, play.ball.X, play.ball.Z, BALL_LIFT + play.ball.Y)
			* CFrame.Angles(play.ballSpin, 0, 0)
	else
		team.ball.CFrame = gateCFrame(team, 0, 0, BALL_LIFT)
	end
end

local function updateBoard(team: Team, play: Play?, now: number)
	local board = team.board
	if play == nil then
		board.gui.Enabled = false
		return
	end
	local time = now - play.startedAt
	local ours, theirs = MatchScript.score(play.script, time)
	board.gui.Enabled = true
	board.score.Text = string.format("%d - %d", ours, theirs)
	local left = math.max(0, math.ceil(play.duration - time))
	board.clock.Text = if time >= play.duration then "FULL TIME" else string.format("0:%02d", left)
end

-- A match starts on a plot: build the teams if needed and play it from its timeline.
local function startPlay(
	plot: Model,
	fieldIds: { string },
	tierNumber: any,
	duration: number,
	goalsFor: number,
	goalsAgainst: number,
	startedAt: number
)
	local tier = if type(tierNumber) == "number" and Config.StadiumTiers[tierNumber]
		then Config.StadiumTiers[tierNumber]
		else tierFor(#fieldIds)
	local team = ensureTeam(plot, fieldIds, tier)
	if team == nil then
		return
	end
	local previous = plays[plot]
	plays[plot] = {
		startedAt = startedAt,
		duration = duration,
		script = MatchScript.build(duration, goalsFor, goalsAgainst),
		random = Random.new(),
		ball = if previous then previous.ball else Vector3.zero,
		ballSpin = 0,
		holder = nil,
		flight = nil,
		segment = -1,
		kickoffSide = 1,
		nextPassAt = 0,
		lastTackleAt = 0,
		movesDone = 0,
		shot = {},
		scored = {},
	}
end

local function readCount(value: any, low: number, high: number, default: number): number
	return if type(value) == "number" then math.clamp(math.floor(value), low, high) else default
end

local function syncOwnTeam()
	local plot = ownPlot()
	if plot == nil then
		return
	end
	if State.data.fieldStarted then
		ensureTeam(plot, Roster.field(State.data), Config.StadiumTiers[State.data.stadiumTier])
	elseif teams[plot] then
		destroyTeam(teams[plot])
		plays[plot] = nil
	end
end

function MatchView.init()
	folder = Instance.new("Folder")
	folder.Name = "ClientMatch"
	folder.Parent = Workspace

	Net.on("MatchStarted", function(plot: any, info: any)
		if typeof(plot) ~= "Instance" or not plot:IsA("Model") or type(info) ~= "table" then
			return
		end
		if
			type(info.fieldIds) ~= "table"
			or #info.fieldIds == 0
			or type(info.startedAt) ~= "number"
		then
			return
		end
		local duration = readCount(info.duration, 3, 60, 10)
		local goalsFor = readCount(info.goalsFor, 1, 6, 1)
		local goalsAgainst = readCount(info.goalsAgainst, 0, goalsFor - 1, 0)
		-- The kick-off in this machine's clock.
		local startedAt = os.clock() - math.max(0, Workspace:GetServerTimeNow() - info.startedAt)
		startPlay(
			plot,
			info.fieldIds,
			info.stadiumTier,
			duration,
			goalsFor,
			goalsAgainst,
			startedAt
		)
	end)
	Net.on("MatchResult", function(plot: any, info: any)
		if typeof(plot) ~= "Instance" or not plot:IsA("Model") or type(info) ~= "table" then
			return
		end
		local play = plays[plot]
		if play and os.clock() - play.startedAt >= play.duration - 1 then
			return -- the match was drawn from its kick-off
		end
		-- No kick-off seen (joined mid-match): play the goals quickly now.
		if type(info.fieldIds) == "table" and #info.fieldIds > 0 then
			local goalsFor = readCount(info.goalsFor, 1, 6, 1)
			startPlay(
				plot,
				info.fieldIds,
				info.stadiumTier,
				FALLBACK_SECONDS,
				goalsFor,
				readCount(info.goalsAgainst, 0, goalsFor - 1, 0),
				os.clock()
			)
		end
	end)
	State.onChange(syncOwnTeam)

	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		local mine = ownPlot()
		for plot, team in teams do
			-- Other players' pitches are dropped when they have not been used for a while.
			if
				plot.Parent == nil or (plot ~= mine and now - team.lastUsed > OTHER_PLOT_SECONDS)
			then
				destroyTeam(team)
				plays[plot] = nil
			elseif nearCamera(team) then
				local play = plays[plot]
				if play and play.holder and play.holder.model.Parent == nil then
					play.holder = nil -- the team was rebuilt under the match
				end
				if play then
					updatePlay(team, play, now, plot == mine)
				end
				drawTeam(team, play, now, dt)
				updateBoard(team, play, now)
			end
		end
	end)
	syncOwnTeam()
end

return MatchView
