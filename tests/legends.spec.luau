--!nocheck
local T = require("./framework")
local Actions = T.load("server/Actions")
local Config = T.load("shared/Config")
local Legends = T.load("shared/Legends")
local NewSeason = T.load("server/NewSeason")
local PadInfo = T.load("shared/PadInfo")
local ProfileSchema = T.load("server/ProfileSchema")
local Roster = T.load("shared/Roster")

T.suite("legends")

local function ownFloors(data, floors)
	for _, def in Config.Players do
		if def.floor <= floors then
			Roster.add(data, def.id)
		end
	end
end

-- A profile that has met every goal of the first Legend and has the cash.
local function ready()
	local data = ProfileSchema.newProfile()
	ownFloors(data, 3)
	local trained = 0
	for _, def in Config.Players do
		if def.floor <= 3 and trained < 3 then
			data.players[def.id].level = 5
			trained += 1
		end
	end
	data.stadiumTier = 4
	data.cash = Config.PlayersById.ronaldinho.price
	return data
end

local function newSession(data)
	Actions.onChange = function() end
	return { data = data }
end

T.test("every Legend has a trial of goals that never use stars", function()
	for _, def in Config.Players do
		if def.floor >= Config.LegendFloor then
			local goals = Config.LegendTrials[def.id]
			T.truthy(goals ~= nil and #goals > 0, def.id)
			for _, goal in goals do
				T.truthy(
					goal.kind == "ownFloors" or goal.kind == "trained" or goal.kind == "tier",
					def.id
				)
			end
		end
	end
end)

T.test("later Legends ask for at least as much as the one before", function()
	local previous
	for _, def in Config.Players do
		if def.floor >= Config.LegendFloor then
			local train, tier
			for _, goal in Config.LegendTrials[def.id] do
				if goal.kind == "trained" then
					train = goal
				elseif goal.kind == "tier" then
					tier = goal
				end
			end
			if previous then
				T.truthy(train.target >= previous.train.target, def.id)
				T.truthy((train.level or 0) >= (previous.train.level or 0), def.id)
				T.truthy(tier.target >= previous.tier.target, def.id)
			end
			previous = { train = train, tier = tier }
		end
	end
end)

T.test("the first Legend needs floors 1 to 3, three players at level 5 and tier 4", function()
	local data = ProfileSchema.newProfile()
	local goals = Legends.goals(data, "ronaldinho")
	T.eq(#goals, 3)
	T.eq(goals[1].need, 30)
	T.eq(goals[2].need, 3)
	T.eq(goals[3].need, 4)
	T.eq(goals[1].done or goals[2].done or goals[3].done, false)
	local met = ready()
	T.eq(Legends.goalCount(met, "ronaldinho"), 3)
end)

T.test("progress counts what the player has and never goes past the goal", function()
	local data = ProfileSchema.newProfile()
	ownFloors(data, 1)
	data.stadiumTier = 5
	local goals = Legends.goals(data, "ronaldinho")
	T.eq(goals[1].have, 10)
	T.eq(goals[3].have, 4)
	T.eq(goals[3].done, true)
	T.eq(goals[1].done, false)
end)

T.test("status: locked before floor 4, goals open, cannot afford, ready, owned", function()
	local data = ProfileSchema.newProfile()
	T.eq(Legends.status(data, "ronaldinho"), "locked")
	ownFloors(data, 3)
	T.eq(Legends.status(data, "ronaldinho"), "goals")
	local met = ready()
	met.cash = 0
	T.eq(Legends.status(met, "ronaldinho"), "cannotAfford")
	met.cash = Config.PlayersById.ronaldinho.price
	T.eq(Legends.status(met, "ronaldinho"), "ready")
	Roster.add(met, "ronaldinho")
	T.eq(Legends.status(met, "ronaldinho"), "owned")
	T.eq(Legends.status(met, "nobody"), "unknown")
	T.eq(Legends.status(met, "rashford"), "unknown")
end)

T.test("a reached goal is recorded for good, even when the state moves back", function()
	local data = ready()
	Legends.record(data)
	T.eq(data.trials.ronaldinho.tier, true)
	data.stadiumTier = 1
	for _, owned in data.players do
		owned.level = 0
	end
	Legends.record(data)
	T.eq(data.trials.ronaldinho.tier, true)
	T.eq(Legends.goals(data, "ronaldinho")[3].done, true)
	T.eq(Legends.goals(data, "ronaldinho")[3].have, 1)
end)

T.test("buying a Legend needs the goals, floor 4 and the cash, and charges the price", function()
	local data = ProfileSchema.newProfile()
	data.cash = 1e15
	local session = newSession(data)
	T.eq(select(2, Actions.buyLegend(session, "ronaldinho")), "locked")
	ownFloors(data, 3)
	T.eq(select(2, Actions.buyLegend(session, "ronaldinho")), "goals")
	T.eq(data.cash, 1e15)

	local met = ready()
	met.cash = Config.PlayersById.ronaldinho.price - 1
	T.eq(select(2, Actions.buyLegend(newSession(met), "ronaldinho")), "cannotAfford")

	met.cash = Config.PlayersById.ronaldinho.price
	local ok = Actions.buyLegend(newSession(met), "ronaldinho")
	T.eq(ok, true)
	T.eq(met.cash, 0)
	T.eq(Roster.owns(met, "ronaldinho"), true)
	T.eq(met.players.ronaldinho.stars, 0)
	T.eq(select(2, Actions.buyLegend(newSession(met), "ronaldinho")), "owned")
end)

T.test("a Legend cannot be bought from a plain player pad or with a cash-floor id", function()
	local data = ready()
	T.eq(select(2, Actions.buyPlayer(newSession(data), "ronaldinho")), "legend")
	T.eq(select(2, Actions.buyLegend(newSession(data), "rashford")), "unknown")
end)

T.test("a New Season keeps the Legend and the goals reached, and resets the rest", function()
	local data = ready()
	data.cash = Config.PlayersById.ronaldinho.price
	Actions.buyLegend(newSession(data), "ronaldinho")
	data.stadiumTier = 4
	local ok = NewSeason.start(data, 1)
	T.truthy(ok)
	T.eq(Roster.owns(data, "ronaldinho"), true)
	T.eq(data.stadiumTier, 1)
	T.eq(data.trials.ronaldinho.tier, true)
	T.eq(data.trials.ronaldinho.train, true)
	T.eq(data.trials.ronaldinho.own, true)
	-- Floor 4 is shut again until floor 3 is re-climbed, but the goals stay done.
	T.eq(Legends.reached(data), false)
	T.eq(Legends.goalCount(data, "zidane") >= 1, true)
end)

T.test("a goal reached just before a New Season is kept even if nothing recorded it", function()
	local data = ready()
	T.eq(data.trials.ronaldinho, nil)
	NewSeason.start(data, 1)
	T.eq(data.trials.ronaldinho.tier, true)
end)

T.test("the profile still validates with trial flags", function()
	local data = ready()
	Legends.record(data)
	local ok = ProfileSchema.validate(data)
	T.eq(ok, true)
end)

T.test(
	"pad text: floor 3 first, goals count, price missing, ready, then the level-up text",
	function()
		local data = ProfileSchema.newProfile()
		T.eq(PadInfo.describe("legend", "ronaldinho", data).note, "Finish floor 3 first")
		ownFloors(data, 3)
		T.eq(PadInfo.describe("legend", "ronaldinho", data).note, "Trial goals 1/3")
		local met = ready()
		met.cash = 0
		T.eq(PadInfo.describe("legend", "ronaldinho", met).state, "cannotAfford")
		met.cash = Config.PlayersById.ronaldinho.price
		T.eq(PadInfo.describe("legend", "ronaldinho", met).state, "ready")
		Roster.add(met, "ronaldinho")
		T.eq(PadInfo.describe("legend", "ronaldinho", met).state, "cannotAfford") -- level-up: no TP
	end
)
