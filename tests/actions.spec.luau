--!nocheck
local T = require("./framework")
local Actions = T.load("server/Actions")
local Roster = T.load("shared/Roster")
local Config = T.load("shared/Config")
local ProfileSchema = T.load("server/ProfileSchema")

T.suite("actions")

local changes
local function newSession(cash)
	local session = { data = ProfileSchema.newProfile() }
	session.data.cash = cash or 15
	changes = {}
	Actions.onChange = function(_, what, id)
		table.insert(changes, what .. ":" .. tostring(id))
	end
	return session
end

T.test("buying the first player costs $10 and puts it in the roster", function()
	local session = newSession()
	local ok = Actions.buyPlayer(session, "rashford")
	T.eq(ok, true)
	T.eq(session.data.cash, 5)
	T.eq(Roster.owns(session.data, "rashford"), true)
	T.deepEq(changes, { "player:rashford" })
end)

T.test("a player can only be bought once", function()
	local session = newSession(100)
	Actions.buyPlayer(session, "rashford")
	local ok, reason = Actions.buyPlayer(session, "rashford")
	T.eq(ok, false)
	T.eq(reason, "owned")
	T.eq(session.data.cash, 90)
end)

T.test("too little cash buys nothing and charges nothing", function()
	local session = newSession(15)
	local ok, reason = Actions.buyPlayer(session, "sterling") -- $70
	T.eq(ok, false)
	T.eq(reason, "cannotAfford")
	T.eq(session.data.cash, 15)
	T.eq(Roster.ownedCount(session.data), 0)
	T.deepEq(changes, {})
end)

T.test("locked, Legend and unknown players cannot be bought", function()
	local session = newSession(1e15)
	T.eq(select(2, Actions.buyPlayer(session, "lautaro")), "locked")
	T.eq(select(2, Actions.buyPlayer(session, "pele")), "legend")
	T.eq(select(2, Actions.buyPlayer(session, "nobody")), "unknown")
	T.eq(session.data.cash, 1e15)
end)

T.test("the first match speed upgrade costs $120 and adds a level", function()
	local session = newSession(120)
	session.data.stadiumTier = 2
	local ok = Actions.buyStore(session, "matchSpeed", 0)
	T.eq(ok, true)
	T.eq(session.data.cash, 0)
	T.eq(session.data.storeLevels.matchSpeed, 1)
	T.deepEq(changes, { "store:matchSpeed" })
end)

T.test("a double tap on a Store upgrade cannot buy two levels", function()
	local session = newSession(10_000) -- enough for the second level too, so only the level stops it
	session.data.stadiumTier = 2
	local first = Actions.buyStore(session, "matchSpeed", 0)
	local second, reason = Actions.buyStore(session, "matchSpeed", 0) -- the client still saw level 0
	T.eq(first, true)
	T.eq(second, false)
	T.eq(reason, "stale")
	T.eq(session.data.storeLevels.matchSpeed, 1)
	T.eq(session.data.cash, 9_880)
end)

T.test("a Store upgrade that is locked or maxed is refused", function()
	local session = newSession(1e9)
	T.eq(select(2, Actions.buyStore(session, "matchSpeed", 0)), "locked")
	session.data.stadiumTier = 2
	session.data.storeLevels.matchSpeed = 5
	T.eq(select(2, Actions.buyStore(session, "matchSpeed", 5)), "maxed")
end)

T.test("the stadium upgrade costs $250, adds a tier and starts a x2 boost", function()
	local session = newSession(250)
	local ok = Actions.upgradeStadium(session, 1)
	T.eq(ok, true)
	T.eq(session.data.cash, 0)
	T.eq(session.data.stadiumTier, 2)
	T.eq(session.data.boosts.stadiumBoostLeft, Config.Boost.stadiumSeconds)
	T.deepEq(changes, { "stadium:nil" })
end)

T.test("a double tap on the stadium upgrade cannot buy two tiers", function()
	local session = newSession(1e9)
	local first = Actions.upgradeStadium(session, 1)
	local second, reason = Actions.upgradeStadium(session, 1)
	T.eq(first, true)
	T.eq(second, false)
	T.eq(reason, "stale")
	T.eq(session.data.stadiumTier, 2)
end)

T.test("a new stadium upgrade resets the boost timer, it does not add up", function()
	local session = newSession(1e9)
	Actions.upgradeStadium(session)
	session.data.boosts.stadiumBoostLeft = 100
	Actions.upgradeStadium(session)
	T.eq(session.data.boosts.stadiumBoostLeft, Config.Boost.stadiumSeconds)
end)

T.test("the stadium upgrade is refused without cash and at the top tier", function()
	local session = newSession(249)
	T.eq(select(2, Actions.upgradeStadium(session)), "cannotAfford")
	session.data.stadiumTier = 5
	session.data.cash = 1e12
	T.eq(select(2, Actions.upgradeStadium(session)), "maxed")
end)

T.test("buying the first player starts the matches, there is no separate button", function()
	local session = newSession(100)
	T.eq(session.data.fieldStarted, false)
	T.eq(Actions.buyPlayer(session, "rashford"), true)
	T.eq(session.data.fieldStarted, true)
	Actions.buyPlayer(session, "grealish")
	T.eq(session.data.fieldStarted, true)
end)

T.test("a failed purchase does not start the matches", function()
	local session = newSession(5)
	Actions.buyPlayer(session, "rashford") -- $10, cannot afford
	T.eq(session.data.fieldStarted, false)
end)

T.test("a cash style is paid once, owned and put on, and a second tap charges nothing", function()
	local session = newSession(5_000)
	local ok = Actions.buyCosmetic(session, "kit_red") -- $2,000
	T.eq(ok, true)
	T.eq(session.data.cash, 3_000)
	T.eq(session.data.cosmetics.owned.kit_red, true)
	T.eq(session.data.cosmetics.chosen.kit, "kit_red")
	T.deepEq(changes, { "cosmetic:kit_red" })
	local again, reason = Actions.buyCosmetic(session, "kit_red")
	T.eq(again, false)
	T.eq(reason, "owned")
	T.eq(session.data.cash, 3_000)
end)

T.test(
	"a cash style needs its tier and the cash, and Robux or free styles are not sold for cash",
	function()
		local session = newSession(100)
		T.eq(select(2, Actions.buyCosmetic(session, "kit_red")), "cannotAfford")
		T.eq(select(2, Actions.buyCosmetic(session, "crest_ruby")), "tier")
		T.eq(select(2, Actions.buyCosmetic(session, "kit_gold")), "free")
		T.eq(select(2, Actions.buyCosmetic(session, "kit_blue")), "free")
		T.eq(session.data.cash, 100)
		T.deepEq(changes, {})
	end
)
