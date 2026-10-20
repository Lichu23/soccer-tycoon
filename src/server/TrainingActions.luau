--!strict
-- Connects the Training Gym to the world (docs/PLAN.md, Steps 4 and 7). A loop checks who stands on
-- which station (the pad system already publishes each player's padKey), runs the stamina and the TP
-- with Training, and publishes what the HUD shows. A conditioning station (treadmill, agility ladder)
-- pays 10 TP a minute by itself. A skill station (keepie-uppies) pays for the game: the ball beats on
-- the server clock, the client draws it from `juggleStart`, the server judges each tap on the same
-- clock and keeps the round, the combo, the medal and the personal best. The dribble run works the same
-- way with a lane and rows of cones.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Dribble = require(ReplicatedStorage.Shared.Dribble)
local Economy = require(script.Parent.Economy)
local Juggle = require(ReplicatedStorage.Shared.Juggle)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(script.Parent.Remotes)
local Safe = require(script.Parent.Safe)
local Session = require(script.Parent.Session)
local Training = require(script.Parent.Training)

local TICK_SECONDS = 0.25

local carries: { [Player]: Training.Carry } = {}
local games: { [Player]: Juggle.State } = {}
local runs: { [Player]: Dribble.State } = {} -- the dribble run of a player
local training: { [Player]: boolean } = {} -- on a station with stamina left, as of the last tick
local started = false

local TrainingActions = {}

-- The stations of the Training Gym by marker name: a "conditioning" station runs by itself (stand
-- on it and earn), a "skill" station is played (the keepie-uppies). The station names are what the
-- HUD shows.
local STATIONS: { [string]: { field: string, station: string } } = {
	TrainingTreadmill = { field = "conditioning", station = "treadmill" },
	TrainingLadder = { field = "conditioning", station = "ladder" },
	TrainingKeepie = { field = "skill", station = "keepie" },
	TrainingDribble = { field = "skill", station = "dribble" },
}

-- Which station the player stands on, or nil. The pad system publishes each player's padKey, which
-- ends with the marker's name.
local function stationOf(session: Session.Session): { field: string, station: string }?
	local plot = session.runtime.plot
	if plot == nil or not Progress.trainingUnlocked(session.data) then
		return nil
	end
	local key = session.player:GetAttribute("padKey")
	if type(key) ~= "string" then
		return nil
	end
	for marker, info in STATIONS do
		if key == plot.Name .. ":" .. marker then
			return info
		end
	end
	return nil
end

-- The round as player attributes, so the client draws the same ball the server judges.
local function publishGame(player: Player, game_: Juggle.State?)
	player:SetAttribute("juggleState", if game_ then game_.phase else "off")
	player:SetAttribute("juggleStart", if game_ then game_.startedAt else 0)
	player:SetAttribute("juggleCooldownUntil", if game_ then game_.cooldownUntil else 0)
	player:SetAttribute("juggleCombo", if game_ then game_.combo else 0)
	player:SetAttribute("juggleHits", if game_ then game_.hits else 0)
	player:SetAttribute("juggleLast", if game_ then game_.lastIndex else 0)
	player:SetAttribute("juggleRoundEnds", if game_ then game_.roundEndsAt else 0)
end

-- The dribble run as player attributes, so the client draws the rows the server judges.
local function publishRun(player: Player, run: Dribble.State?)
	player:SetAttribute("dribbleState", if run then run.phase else "off")
	player:SetAttribute("dribbleStart", if run then run.startedAt else 0)
	player:SetAttribute("dribbleLane", if run then Dribble.lane(run) else 2)
	player:SetAttribute("dribbleLast", if run then run.lastRow else 0)
	player:SetAttribute("dribbleCombo", if run then run.combo else 0)
	player:SetAttribute("dribblePasses", if run then run.passes else 0)
	player:SetAttribute("dribbleStumbleUntil", if run then run.stumbleUntil else 0)
	player:SetAttribute("dribbleRoundEnds", if run then run.roundEndsAt else 0)
end

-- Handles what time alone changed in a dribble run: TP for rows passed, a stumble, the end of a round.
local function handleRunEvents(session: Session.Session, events: { Dribble.Event })
	local player = session.player
	for _, event in events do
		if event.kind == "pass" then
			local carry = carries[player]
			if carry and training[player] then
				local paid =
					Training.gamePay(session.data, carry, event.combo, Workspace:GetServerTimeNow())
				if paid > 0 then
					Economy.publish(player, session.data)
				end
				Remotes.fireClient("Notice", player, {
					kind = "dribbleResult",
					outcome = "pass",
					combo = event.combo,
					paid = paid,
					capped = paid <= 0,
				})
			end
		elseif event.kind == "stumble" then
			Remotes.fireClient(
				"Notice",
				player,
				{ kind = "dribbleResult", outcome = "stumble", combo = 0, paid = 0 }
			)
		elseif event.kind == "round" then
			local gym = session.data.gym
			local newBest = event.passes > gym.dribbleBestPasses
			if newBest then
				gym.dribbleBestPasses = math.min(event.passes, 10_000)
			end
			if event.medal > gym.dribbleBestMedal then
				gym.dribbleBestMedal = event.medal
			end
			player:SetAttribute("dribbleBestPasses", gym.dribbleBestPasses)
			player:SetAttribute("dribbleBestMedal", gym.dribbleBestMedal)
			Remotes.fireClient("Notice", player, {
				kind = "dribbleRound",
				passes = event.passes,
				bestCombo = event.bestCombo,
				medal = event.medal,
				newBest = newBest,
			})
		end
	end
end

-- Handles what time alone changed in a round (a dropped ball, the end of the round).
local function handleEvents(session: Session.Session, events: { Juggle.Event })
	for _, event in events do
		if event.kind == "round" then
			local gym = session.data.gym
			local newBest = event.hits > gym.keepieBestHits
			if newBest then
				gym.keepieBestHits = math.min(event.hits, 10_000)
			end
			if event.medal > gym.keepieBestMedal then
				gym.keepieBestMedal = event.medal
			end
			session.player:SetAttribute("keepieBestHits", gym.keepieBestHits)
			session.player:SetAttribute("keepieBestMedal", gym.keepieBestMedal)
			Remotes.fireClient("Notice", session.player, {
				kind = "juggleRound",
				hits = event.hits,
				bestCombo = event.bestCombo,
				medal = event.medal,
				newBest = newBest,
			})
		elseif event.kind == "drop" then
			Remotes.fireClient("Notice", session.player, { kind = "juggleDrop" })
		end
	end
end

local function step(session: Session.Session, dt: number)
	local player, data = session.player, session.data
	local carry = carries[player]
	if carry == nil then
		carry = Training.newCarry()
		carries[player] = carry
	end

	local at = stationOf(session)
	local field = if at then at.field else nil
	local standing = field ~= nil
	local paid = Training.step(data, carry, dt, standing, field == "conditioning")
	local active = standing and Training.hasStamina(data)
	training[player] = active

	-- The game exists only at a skill station. Stepping onto it starts a round at once; leaving it
	-- ends the game (nothing is kept but the personal best of finished rounds).
	local now = Workspace:GetServerTimeNow()
	if at and at.station == "keepie" then
		local round = games[player]
		if round == nil then
			round = Juggle.new(now)
			games[player] = round
		end
		handleEvents(session, Juggle.normalize(round, now))
		publishGame(player, round)
	elseif games[player] ~= nil then
		games[player] = nil
		publishGame(player, nil)
	end
	if at and at.station == "dribble" then
		local run = runs[player]
		if run == nil then
			run = Dribble.new(now)
			runs[player] = run
		end
		handleRunEvents(session, Dribble.normalize(run, now))
		publishRun(player, run)
	elseif runs[player] ~= nil then
		runs[player] = nil
		publishRun(player, nil)
	end
	player:SetAttribute("trainingField", field or "off")
	player:SetAttribute("trainingStation", if at then at.station else "off")
	player:SetAttribute("tpFraction", carry.fraction)
	player:SetAttribute("training", active)
	player:SetAttribute("staminaLeft", math.floor(data.staminaLeft * 10) / 10)
	if paid > 0 then
		Economy.publish(player, data)
	end
end

-- A tap at the keepie-uppies, judged on the server clock (see Juggle for the rules).
local function tap(player: Player)
	local session = Session.get(player)
	local round = games[player]
	if session == nil or round == nil or not training[player] then
		return
	end
	local now = Workspace:GetServerTimeNow()
	handleEvents(session, Juggle.normalize(round, now))
	local outcome = Juggle.press(round, now)
	if outcome == "ignored" then
		publishGame(player, round)
		return
	end
	local paid = 0
	local carry = carries[player]
	if outcome == "hit" and carry then
		paid = Training.gamePay(session.data, carry, round.combo, now)
		if paid > 0 then
			Economy.publish(player, session.data)
		end
	end
	publishGame(player, round)
	Remotes.fireClient("Notice", player, {
		kind = "juggleResult",
		outcome = outcome,
		combo = round.combo,
		paid = paid,
		capped = outcome == "hit" and paid <= 0,
	})
end

-- A lane change in the dribble run. The server never trusts the time the client sends by more than the
-- grace window (Dribble.move clamps it).
local function move(player: Player, ...: any)
	local direction, stamp = select(1, ...), select(2, ...)
	local session = Session.get(player)
	local run = runs[player]
	if session == nil or run == nil or not training[player] then
		return
	end
	if type(direction) ~= "string" or type(stamp) ~= "number" then
		return
	end
	local now = Workspace:GetServerTimeNow()
	handleRunEvents(session, Dribble.normalize(run, now))
	Dribble.move(run, now, if direction == "left" then -1 else 1, stamp)
	publishRun(player, run)
end

-- Call once, after Remotes.init and Session.init.
function TrainingActions.start()
	assert(not started, "TrainingActions.start called twice")
	started = true
	Remotes.on("TrainingTap", tap)
	Remotes.on("TrainingMove", move)
	Players.PlayerRemoving:Connect(function(player)
		carries[player] = nil
		games[player] = nil
		runs[player] = nil
		training[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK_SECONDS)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, session in Session.all() do
				local ok, err = Safe.call(step, session, dt)
				if not ok then
					warn("[TrainingActions] step failed: " .. tostring(err))
				end
			end
		end
	end)
end

return TrainingActions
