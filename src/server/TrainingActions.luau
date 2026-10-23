--!strict
-- Connects the Training Gym to the world (docs/PLAN.md, Steps 4 and 7). A loop checks who stands on
-- which station (the pad system already publishes each player's padKey), runs the stamina and the TP
-- with Training, and publishes what the HUD shows. A conditioning station (treadmill, bench press)
-- pays the idle rate by itself. A skill station pays for the game, an endless streak: at the
-- keepie-uppies the ball beats on the server clock, the client draws it from `juggleStart`, the
-- server judges each tap on the same clock and pays each clean touch; at the free-kick spot (the 1v1
-- breakaway) the move, the reticle and the meter run on the server clock, the server judges each input
-- and the shot and pays each goal. The longest streak
-- of each game is kept in the profile as it grows, so walking off the mat never loses a record.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DevFlags = require(script.Parent.DevFlags)
local Economy = require(script.Parent.Economy)
local Freekick = require(ReplicatedStorage.Shared.Freekick)
local Juggle = require(ReplicatedStorage.Shared.Juggle)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(script.Parent.Remotes)
local Safe = require(script.Parent.Safe)
local Session = require(script.Parent.Session)
local Training = require(script.Parent.Training)

local TICK_SECONDS = 0.25
local BEST_MAX = 100_000 -- the profile check allows streaks up to this

local carries: { [Player]: Training.Carry } = {}
local games: { [Player]: Juggle.State } = {}
local kicks: { [Player]: Freekick.State } = {} -- the breakaway of a player
local training: { [Player]: boolean } = {} -- on a station with stamina left, as of the last tick
-- Whether the streak running now has beaten the record it started with, for the "new best" line.
local keepieNewBest: { [Player]: boolean } = {}
local freekickNewBest: { [Player]: boolean } = {}
local started = false

local TrainingActions = {}

-- The stations of the Training Gym by marker name: a "conditioning" station runs by itself (stand
-- on it and earn), a "skill" station is played. The station names are what the HUD shows.
local STATIONS: { [string]: { field: string, station: string } } = {
	TrainingTreadmill = { field = "conditioning", station = "treadmill" },
	TrainingBench = { field = "conditioning", station = "bench" },
	TrainingKeepie = { field = "skill", station = "keepie" },
	TrainingFreekick = { field = "skill", station = "freekick" },
}

local BELT_HEIGHT = 6 -- studs over the treadmill's belt that still count as on it (a jump)

-- Whether the player is on the machine itself, not just on its pad: on the treadmill's belt (its
-- invisible Stand), or lying on the bench (its BenchSeat). A jump off lands beside the machine, so it
-- never starts the training again.
local function onMachine(plot: Instance, player: Player, station: string): boolean
	local gym = plot:FindFirstChild("Gym")
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if gym == nil or humanoid == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	if station == "bench" then
		local seat = humanoid.SeatPart
		return seat ~= nil and seat.Name == "BenchSeat" and seat:IsDescendantOf(gym)
	end
	local treadmill = gym:FindFirstChild("Treadmill")
	local stand = if treadmill then treadmill:FindFirstChild("Stand") else nil
	if stand == nil or not stand:IsA("BasePart") then
		return false
	end
	local at = stand.CFrame:PointToObjectSpace(root.Position)
	return math.abs(at.X) <= stand.Size.X / 2
		and math.abs(at.Z) <= stand.Size.Z / 2
		and at.Y >= 0
		and at.Y <= BELT_HEIGHT
end

-- Which station the player stands on, or nil. The pad system publishes each player's padKey, which
-- ends with the marker's name. A conditioning station also needs the player on the machine.
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
			-- Until the first level-up only the treadmill is open (the level-up tutorial).
			if info.station ~= "treadmill" and not Progress.firstLevelDone(session.data) then
				return nil
			end
			if
				info.field == "conditioning" and not onMachine(plot, session.player, info.station)
			then
				return nil
			end
			return info
		end
	end
	return nil
end

-- The streak as player attributes, so the client draws the same ball the server judges.
local function publishGame(player: Player, game_: Juggle.State?)
	player:SetAttribute("juggleState", if game_ then game_.phase else "off")
	player:SetAttribute("juggleStart", if game_ then game_.startedAt else 0)
	player:SetAttribute("juggleCombo", if game_ then game_.combo else 0)
	player:SetAttribute("juggleLast", if game_ then game_.lastIndex else 0)
	player:SetAttribute("juggleOverAt", if game_ then game_.overAt else 0)
end

-- The breakaway as player attributes, so the client draws the reticle, the meter and the shot the
-- server judges.
local function publishKick(player: Player, state: Freekick.State?)
	player:SetAttribute("freekickState", if state then state.phase else "off")
	player:SetAttribute("freekickSeed", if state then state.seed else 0)
	player:SetAttribute("freekickKick", if state then state.kick else 1)
	player:SetAttribute("freekickStageAt", if state then state.stageAt else 0)
	player:SetAttribute("freekickMove", if state then state.move else 1)
	player:SetAttribute("freekickAimX", if state then state.aimX else 0)
	player:SetAttribute("freekickAimY", if state then state.aimY else 0)
	player:SetAttribute("freekickHoldAt", if state then state.holdAt else 0)
	player:SetAttribute("freekickPower", if state then state.power else 0)
	player:SetAttribute("freekickShotBy", if state then state.shotBy else 0)
	player:SetAttribute("freekickOutcome", if state then state.outcome else "")
	player:SetAttribute("freekickStreak", if state then state.streak else 0)
	player:SetAttribute("freekickOverAt", if state then state.overAt else 0)
	player:SetAttribute("freekickPractice", if state then state.practice else false)
end

-- Keeps the longest keepie-uppies streak as it grows.
local function recordKeepie(session: Session.Session, streak: number)
	local gym = session.data.gym
	if streak > gym.keepieBestStreak then
		gym.keepieBestStreak = math.min(streak, BEST_MAX)
		keepieNewBest[session.player] = true
		session.player:SetAttribute("keepieBestStreak", gym.keepieBestStreak)
	end
end

local function recordFreekick(session: Session.Session, streak: number)
	local gym = session.data.gym
	if streak > gym.freekickBestStreak then
		gym.freekickBestStreak = math.min(streak, BEST_MAX)
		freekickNewBest[session.player] = true
		session.player:SetAttribute("freekickBestStreak", gym.freekickBestStreak)
	end
end

-- Says that a keepie-uppies streak ended (a dropped ball or a tap in the air).
local function handleEvents(session: Session.Session, events: { Juggle.Event })
	local player = session.player
	for _, event in events do
		Remotes.fireClient("Notice", player, {
			kind = "juggleOver",
			streak = event.streak,
			medal = event.medal,
			newBest = keepieNewBest[player] == true,
		})
		keepieNewBest[player] = nil
	end
end

-- Says that a breakaway streak ended (the film of the attack that failed has played).
local function handleKickEvents(session: Session.Session, events: { Freekick.Event })
	local player = session.player
	for _, event in events do
		Remotes.fireClient("Notice", player, {
			kind = "freekickOver",
			streak = event.streak,
			medal = event.medal,
			newBest = freekickNewBest[player] == true,
		})
		freekickNewBest[player] = nil
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

	-- The game exists only at a skill station. Stepping onto it starts a streak (after a short text
	-- on how to play); leaving it ends the game (the record is already kept).
	local now = Workspace:GetServerTimeNow()
	if at and at.station == "keepie" then
		local round = games[player]
		if round == nil then
			local intro = if DevFlags.skipIntros() then 0 else Config.Training.juggleIntroSeconds
			round = Juggle.new(now + intro)
			games[player] = round
		end
		handleEvents(session, Juggle.normalize(round, now))
		publishGame(player, round)
	elseif games[player] ~= nil then
		games[player] = nil
		keepieNewBest[player] = nil
		publishGame(player, nil)
	end
	if at and at.station == "freekick" then
		local state = kicks[player]
		if state == nil then
			local intro = if DevFlags.skipIntros() then 0 else Config.Training.freekickIntroSeconds
			-- Until the first goal ever, the first attack is practice (its move waits for the key).
			state = Freekick.new(now + intro, data.gym.freekickBestStreak <= 0)
			kicks[player] = state
		end
		handleKickEvents(session, Freekick.normalize(state, now))
		publishKick(player, state)
	elseif kicks[player] ~= nil then
		kicks[player] = nil
		freekickNewBest[player] = nil
		publishKick(player, nil)
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
	-- A tap while "how to play" shows skips it: the countdown starts at once.
	if Juggle.skipIntro(round, now) then
		publishGame(player, round)
		return
	end
	local outcome, event = Juggle.press(round, now)
	if outcome == "ignored" then
		publishGame(player, round)
		return
	end
	local paid = 0
	if outcome == "hit" then
		recordKeepie(session, round.combo)
		local carry = carries[player]
		if carry then
			paid = Training.gamePay(session.data, carry, Juggle.tpFor(round.combo), now, false)
			if paid > 0 then
				Economy.publish(player, session.data)
			end
		end
	end
	publishGame(player, round)
	Remotes.fireClient("Notice", player, {
		kind = "juggleResult",
		outcome = outcome,
		combo = round.combo,
		paid = paid,
	})
	if event then
		handleEvents(session, { event })
	end
end

-- The breakaway's state for an input of `player`, caught up to now, or nil when it does not count.
-- The server never trusts the time the client sends by more than the grace window (Freekick clamps it).
local function kickInput(player: Player, stamp: any): (Session.Session?, Freekick.State?, number)
	local session = Session.get(player)
	local state = kicks[player]
	if session == nil or state == nil or not training[player] or type(stamp) ~= "number" then
		return nil, nil, 0
	end
	local now = Workspace:GetServerTimeNow()
	handleKickEvents(session, Freekick.normalize(state, now))
	return session, state, now
end

-- A skill move against the defender.
local function kickMove(player: Player, ...: any)
	local move, stamp = select(1, ...), select(2, ...)
	local session, state, now = kickInput(player, stamp)
	if session == nil or state == nil or type(move) ~= "number" then
		return
	end
	Freekick.move(state, now, move, stamp)
	publishKick(player, state)
end

-- A tap: locks the reticle, or stops the moving power meter and shoots. The shot is judged and
-- paid at once (the film shows it afterwards).
local function kickTap(player: Player, ...: any)
	local stamp = select(1, ...)
	local session, state, now = kickInput(player, stamp)
	if session == nil or state == nil then
		return
	end
	if Freekick.lock(state, now, stamp) or not Freekick.strike(state, now, stamp) then
		publishKick(player, state)
		return
	end
	local paid = 0
	if state.outcome == "goal" then
		recordFreekick(session, state.streak)
		local carry = carries[player]
		if carry then
			paid = Training.gamePay(session.data, carry, Freekick.tpFor(state.streak), now, true)
			if paid > 0 then
				Economy.publish(player, session.data)
			end
		end
	end
	Remotes.fireClient("Notice", player, {
		kind = "freekickShot",
		outcome = state.outcome,
		streak = state.streak,
		paid = paid,
		capped = state.outcome == "goal" and paid <= 0,
	})
	publishKick(player, state)
end

-- Call once, after Remotes.init and Session.init.
function TrainingActions.start()
	assert(not started, "TrainingActions.start called twice")
	started = true
	Remotes.on("TrainingTap", tap)
	Remotes.on("FreekickTap", kickTap)
	Remotes.on("FreekickMove", kickMove)
	Players.PlayerRemoving:Connect(function(player)
		carries[player] = nil
		games[player] = nil
		kicks[player] = nil
		training[player] = nil
		keepieNewBest[player] = nil
		freekickNewBest[player] = nil
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
