--!nocheck
local T = require("./framework")
local Progress = T.load("shared/Progress")
local Goals = T.load("shared/Goals")
local PadInfo = T.load("shared/PadInfo")
local Roster = T.load("shared/Roster")
local Config = T.load("shared/Config")
local NumberFormat = T.load("shared/NumberFormat")
local ProfileSchema = T.load("server/ProfileSchema")

local function newData()
	return ProfileSchema.newProfile()
end

local function ownFloor(data, floor)
	for _, def in Config.Players do
		if def.floor == floor then
			Roster.add(data, def.id)
		end
	end
end

T.suite("progress players")

T.test("player status follows cash, floors and ownership", function()
	local data = newData() -- $15
	T.eq(Progress.playerStatus(data, "rashford"), "ready") -- $10
	T.eq(Progress.playerStatus(data, "sterling"), "cannotAfford") -- $70
	T.eq(Progress.playerStatus(data, "lautaro"), "locked")
	T.eq(Progress.playerStatus(data, "pele"), "legend")
	T.eq(Progress.playerStatus(data, "nobody"), "unknown")
	Roster.add(data, "rashford")
	T.eq(Progress.playerStatus(data, "rashford"), "owned")
end)

T.test("exactly the price is enough", function()
	local data = newData()
	data.cash = 10
	T.eq(Progress.playerStatus(data, "rashford"), "ready")
	data.cash = 9
	T.eq(Progress.playerStatus(data, "rashford"), "cannotAfford")
end)

T.suite("progress store")

T.test("match speed unlocks at stadium tier 2", function()
	local data = newData()
	data.cash = 1000
	T.eq(Progress.storeStatus(data, "matchSpeed"), "locked")
	data.stadiumTier = 2
	T.eq(Progress.storeStatus(data, "matchSpeed"), "ready")
end)

T.test("hat-trick and offline upgrades unlock when floor 1 is complete", function()
	local data = newData()
	data.cash = 1_000_000
	T.eq(Progress.storeStatus(data, "hatTrick"), "locked")
	T.eq(Progress.storeStatus(data, "offline"), "locked")
	ownFloor(data, 1)
	T.eq(Progress.storeStatus(data, "hatTrick"), "ready")
	T.eq(Progress.storeStatus(data, "offline"), "ready")
end)

T.test("an upgrade at its last level is maxed", function()
	local data = newData()
	data.stadiumTier = 2
	data.storeLevels.matchSpeed = 5
	T.eq(Progress.storeStatus(data, "matchSpeed"), "maxed")
	T.eq(Progress.storePrice(data, "matchSpeed"), nil)
end)

T.test("match speed, hat-trick chance and offline rate follow the levels", function()
	local data = newData()
	T.eq(Progress.matchSeconds(data), 10)
	T.eq(Progress.hatTrickChance(data), 0.10)
	T.eq(Progress.offlineRate(data), 0.10)
	data.storeLevels.matchSpeed = 3
	data.storeLevels.hatTrick = 2
	data.storeLevels.offline = 5
	T.eq(Progress.matchSeconds(data), 7)
	T.eq(Progress.hatTrickChance(data), 0.14)
	T.eq(Progress.offlineRate(data), 0.35)
end)

T.suite("progress stadium")

T.test("the stadium upgrade needs the tier price", function()
	local data = newData()
	data.cash = 249
	T.eq(Progress.stadiumStatus(data), "cannotAfford")
	data.cash = 250
	T.eq(Progress.stadiumStatus(data), "ready")
	T.eq(Progress.nextTier(data).tier, 2)
end)

T.test("the top tier is maxed", function()
	local data = newData()
	data.stadiumTier = 5
	T.eq(Progress.stadiumStatus(data), "maxed")
	T.eq(Progress.nextTier(data), nil)
end)

T.suite("goals")

T.test("the goal path of the first five minutes", function()
	local data = newData()
	T.eq(Goals.next(data, false).kind, "claim")

	local goal = Goals.next(data, true)
	T.eq(goal.kind, "player")
	T.eq(goal.id, "rashford")
	T.eq(goal.label, "Buy your first player")
	T.eq(goal.cost, 10)

	-- buying the first player also starts the matches
	Roster.add(data, "rashford")
	data.fieldStarted = true
	goal = Goals.next(data, true) -- no Store step any more: straight to the next player
	T.eq(goal.kind, "player")
	T.eq(goal.id, "grealish")
	T.eq(goal.cost, 30)

	for _, id in { "grealish", "sterling", "joao_felix" } do
		Roster.add(data, id)
	end
	goal = Goals.next(data, true) -- 4 owned = field capacity at tier 1
	T.eq(goal.kind, "stadium")
	T.eq(goal.cost, 250)

	data.stadiumTier = 2
	goal = Goals.next(data, true)
	T.eq(goal.kind, "player")
	T.eq(goal.id, "son")
end)

T.test("with everything bought there is nothing to chase", function()
	local data = newData()
	data.fieldStarted = true
	data.stadiumTier = 5
	ownFloor(data, 1)
	ownFloor(data, 2)
	ownFloor(data, 3)
	T.eq(Goals.next(data, true).kind, "none")
end)

T.suite("pad info")

T.test("the claim ring and player pads: name above, price in the ring, note below", function()
	local data = newData()
	local claim = PadInfo.describe("claim", "claim", data)
	T.eq(claim.title, "Claim this plot")
	T.eq(claim.price, "FREE")
	T.eq(claim.state, "ready")

	local ready = PadInfo.describe("player", "rashford", data)
	T.eq(ready.title, "Marcus Rashford")
	T.eq(ready.price, "$10")
	T.eq(ready.note, "")
	T.eq(ready.state, "ready")

	local short = PadInfo.describe("player", "sterling", data)
	T.eq(short.title, "Raheem Sterling")
	T.eq(short.price, "$70")
	T.eq(short.note, "Need $55 more")
	T.eq(short.state, "cannotAfford")

	local locked = PadInfo.describe("player", "lautaro", data)
	T.eq(locked.state, "locked")
	T.eq(locked.price, NumberFormat.money(Config.PlayersById.lautaro.price))
	T.eq(locked.note, "Finish floor " .. (Config.PlayersById.lautaro.floor - 1) .. " first")

	Roster.add(data, "rashford")
	local owned = PadInfo.describe("player", "rashford", data)
	T.eq(owned.state, "owned")
	T.eq(owned.price, "OWNED")
end)

T.test("there is no text for the start-the-game pad any more", function()
	local data = newData()
	T.eq(PadInfo.describe("field", "field", data).state, "info")
	T.eq(PadInfo.describe("field", "field", data).price, "")
end)

T.test("an unknown pad id shows nothing useful but does not fail", function()
	local data = newData()
	T.eq(PadInfo.describe("player", "nobody", data).state, "locked")
	T.eq(PadInfo.describe("store", "nothing", data).state, "locked")
end)

T.test("store and stadium pads", function()
	local data = newData()
	T.eq(PadInfo.describe("store", "matchSpeed", data).state, "locked")
	data.stadiumTier = 2
	data.cash = 120
	local store = PadInfo.describe("store", "matchSpeed", data)
	T.eq(store.title, "Faster matches")
	T.eq(store.price, "$120")
	T.eq(store.state, "ready")
	data.storeLevels.matchSpeed = 5
	T.eq(PadInfo.describe("store", "matchSpeed", data).price, "MAX")
	data.stadiumTier = 1

	data.cash = 100
	local stadium = PadInfo.describe("stadium", "stadium", data)
	T.eq(stadium.price, "$250")
	T.eq(stadium.note, "Need $150 more")
	data.cash = 250
	T.eq(PadInfo.describe("stadium", "stadium", data).note, "")
	data.stadiumTier = 5
	T.eq(PadInfo.describe("stadium", "stadium", data).state, "maxed")
end)
