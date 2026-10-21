--!nocheck
local T = require("./framework")
local Actions = T.load("server/Actions")
local Config = T.load("shared/Config")
local NewSeason = T.load("server/NewSeason")
local ProfileSchema = T.load("server/ProfileSchema")
local Roster = T.load("shared/Roster")
local Season = T.load("shared/Season")

T.suite("new season")

local function ownFloors(data, floors)
	for _, def in Config.Players do
		if def.floor <= floors then
			Roster.add(data, def.id)
		end
	end
end

local function profile(floors)
	local data = ProfileSchema.newProfile()
	ownFloors(data, floors)
	return data
end

T.test("the button is hidden, then a locked preview from floor 3 open, then ready", function()
	T.eq(Season.state(profile(0)), "hidden")
	T.eq(Season.state(profile(1)), "hidden")
	T.eq(Season.state(profile(2)), "locked")
	T.eq(Season.state(profile(3)), "ready")
end)

T.test("floor 3 progress counts the owned players of floor 3", function()
	local data = profile(2)
	local owned, total = Season.lastFloorProgress(data)
	T.eq(owned, 0)
	T.truthy(total > 0)
	local first
	for _, def in Config.Players do
		if def.floor == 3 then
			first = def.id
			break
		end
	end
	Roster.add(data, first)
	T.eq((Season.lastFloorProgress(data)), 1)
end)

T.test(
	"head start: none for season 2 to 3 is floor 1, later seasons floors 1 and 2, never 3",
	function()
		T.eq(Season.keptFloors(1), 1)
		T.eq(Season.keptFloors(2), 2)
		T.eq(Season.keptFloors(9), 2)
		for finished = 1, 6 do
			for _, id in Season.headStartPlayers(finished) do
				T.truthy(Config.PlayersById[id].floor <= 2, id)
			end
		end
	end
)

T.test("trophies are generic names, then World Cup with a number", function()
	T.eq(Season.trophyName(1), "Street Cup")
	T.eq(Season.trophyName(5), "World Cup")
	T.eq(Season.trophyName(6), "World Cup 2")
	T.eq(Season.trophyName(7), "World Cup 3")
end)

T.test("it cannot start before floor 3 is complete", function()
	local data = profile(2)
	local result, reason = NewSeason.start(data, 1)
	T.eq(result, nil)
	T.eq(reason, "locked")
	T.eq(data.season.number, 1)
	T.eq(Roster.floorsComplete(data), 2)
end)

T.test(
	"starting resets cash, TP, Store, stadium and the cash floors, and grants the head start",
	function()
		local data = profile(3)
		data.cash = 12345
		data.tp = 40
		data.stadiumTier = 4
		data.storeLevels.offline = 3
		data.boosts.cashBoostLeft = 300
		data.boosts.stadiumBoostLeft = 200
		data.fieldStarted = true
		local result = NewSeason.start(data, 1)
		T.truthy(result)
		T.eq(result.season, 2)
		T.eq(result.trophy, "Street Cup")
		-- The celebration shows the lineup of the season that just ended (read before the reset).
		T.truthy(#result.field > 0)
		for _, id in result.field do
			T.truthy(Config.PlayersById[id], id)
		end
		T.eq(data.season.number, 2)
		T.eq(data.cash, Config.StartingCash)
		T.eq(data.tp, 0)
		T.eq(data.stadiumTier, 1)
		T.eq(data.storeLevels.offline, 0)
		T.eq(data.boosts.cashBoostLeft, 300) -- time bought with Robux is kept
		T.eq(data.boosts.stadiumBoostLeft, 0)
		T.eq(Roster.floorsComplete(data), 1) -- floor 1 kept, floor 2 and 3 gone
		T.eq(data.fieldStarted, true)
		for id, owned in data.players do
			T.eq(owned.level, 0, id)
			T.eq(owned.stars, 0, id)
		end
	end
)

T.test("floor 3 is never granted: it must be played every season", function()
	local data = profile(3)
	NewSeason.start(data, 1)
	T.eq(Roster.floorComplete(data, 3), false)
	-- complete floors 2 and 3 again, then season 3
	ownFloors(data, 3)
	NewSeason.start(data, 2)
	T.eq(data.season.number, 3)
	T.eq(Roster.floorsComplete(data), 2)
	T.eq(Roster.floorComplete(data, 3), false)
end)

T.test(
	"Legends, cosmetics, trials, receipts, daily state and the collection record stay",
	function()
		local data = profile(3)
		local legend
		for _, def in Config.Players do
			if def.floor >= Config.LegendFloor then
				legend = def.id
				break
			end
		end
		Roster.add(data, legend)
		data.players[legend].stars = 2
		data.cosmetics.owned.goldKit = true
		data.cosmetics.chosen.kit = "goldKit"
		data.trials.legend = { goalA = true }
		data.receipts.abc = { at = 1, result = {} }
		data.daily.caseClaimedAt = 99
		data.seenRarities.Epic = true
		data.flags.firstHatTrickDone = true
		data.boosts.bankedMatches = 5
		NewSeason.start(data, 1)
		T.truthy(data.players[legend])
		T.eq(data.players[legend].stars, 2)
		T.eq(data.cosmetics.owned.goldKit, true)
		T.eq(data.cosmetics.chosen.kit, "goldKit")
		T.eq(data.trials.legend.goalA, true)
		T.truthy(data.receipts.abc)
		T.eq(data.daily.caseClaimedAt, 99)
		T.eq(data.seenRarities.Epic, true)
		T.eq(data.flags.firstHatTrickDone, true)
		T.eq(data.boosts.bankedMatches, 5)
	end
)

T.test("a double tap cannot reset twice: the second call sees a stale season", function()
	local data = profile(3)
	T.truthy(NewSeason.start(data, 1))
	ownFloors(data, 3) -- even if floor 3 were complete again
	local result, reason = NewSeason.start(data, 1)
	T.eq(result, nil)
	T.eq(reason, "stale")
	T.eq(data.season.number, 2)
end)

T.test("the profile still validates after a season", function()
	local data = profile(3)
	NewSeason.start(data, 1)
	local ok, reason = ProfileSchema.validate(data)
	T.eq(ok, true, tostring(reason))
end)

T.test("Actions.startSeason resets once and tells the game", function()
	local session = { data = profile(3) }
	local changed = 0
	Actions.onChange = function(_, what)
		if what == "season" then
			changed += 1
		end
	end
	T.truthy(Actions.startSeason(session, 1))
	T.eq(Actions.startSeason(session, 1), nil)
	T.eq(changed, 1)
end)

T.test("the re-climb estimate is finite, and a later season is faster than the first", function()
	local first = Season.estimateSeconds(1)
	local second = Season.estimateSeconds(2)
	T.truthy(first > 0 and first < 24 * 3600)
	T.truthy(second > 0 and second < first)
end)
