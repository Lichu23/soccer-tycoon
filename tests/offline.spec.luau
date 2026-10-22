--!nocheck
local T = require("./framework")
local Config = T.load("shared/Config")
local Formulas = T.load("shared/Formulas")
local Offline = T.load("server/Offline")
local ProfileSchema = T.load("server/ProfileSchema")
local Roster = T.load("shared/Roster")

T.suite("offline earnings")

local HOUR = 3600

local function playing()
	local data = ProfileSchema.newProfile()
	Roster.add(data, "rashford")
	data.fieldStarted = true
	data.lastSeen = 1_000_000
	return data
end

-- What the formula pays for `seconds` away at the player's current levels.
local function expected(data, seconds)
	local base = Formulas.basePayout({
		fieldIncomes = Roster.fieldIncomes(data),
		stadiumTier = data.stadiumTier,
		season = data.season.number,
	})
	return Formulas.offlineEarnings(
		seconds,
		Formulas.storeValue("matchSpeed", data.storeLevels.matchSpeed),
		base,
		Config.Offline.rate
	)
end

T.test("an hour away pays whole matches at the 25% rate", function()
	local data = playing()
	local earned, away = Offline.preview(data, data.lastSeen + HOUR)
	T.eq(away, HOUR)
	T.eq(earned, expected(data, HOUR))
	T.truthy(earned > 0)
end)

T.test("apply adds the cash and a second apply pays nothing", function()
	local data = playing()
	local now = data.lastSeen + HOUR
	local before = data.cash
	local earned = Offline.apply(data, now)
	T.eq(data.cash, before + earned)
	T.eq(data.lastSeen, now)
	local again = Offline.apply(data, now + 5)
	T.eq(again, 0)
	T.eq(data.cash, before + earned)
end)

T.test("time away is capped at 4 hours", function()
	local data = playing()
	local capped = Offline.preview(data, data.lastSeen + Config.Offline.capSeconds)
	local long = Offline.preview(data, data.lastSeen + 30 * 24 * HOUR)
	T.eq(long, capped)
end)

T.test("the hat-trick upgrade does not change offline earnings", function()
	local data = playing()
	local base = Offline.preview(data, data.lastSeen + HOUR)
	data.storeLevels.hatTrick = 3
	T.eq(Offline.preview(data, data.lastSeen + HOUR), base)
end)

T.test("nothing is paid for a new profile, no field, a negative gap or a tiny gap", function()
	local fresh = ProfileSchema.newProfile()
	T.eq(Offline.preview(fresh, 5_000_000), 0)

	local noField = playing()
	noField.fieldStarted = false
	T.eq(Offline.preview(noField, noField.lastSeen + HOUR), 0)

	local back = playing()
	T.eq(Offline.preview(back, back.lastSeen - HOUR), 0)

	local tiny = playing()
	T.eq(Offline.preview(tiny, tiny.lastSeen + 30), 0)
end)

T.test("a negative gap still moves lastSeen to now so it cannot be replayed", function()
	local data = playing()
	local now = data.lastSeen - HOUR
	T.eq(Offline.apply(data, now), 0)
	T.eq(data.lastSeen, now)
end)
