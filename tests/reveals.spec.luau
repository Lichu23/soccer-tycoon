--!nocheck
local T = require("./framework")
local Actions = T.load("server/Actions")
local Config = T.load("shared/Config")
local ProfileSchema = T.load("server/ProfileSchema")
local Reveals = T.load("server/Reveals")
local Roster = T.load("shared/Roster")

T.suite("rarity reveals")

local function newData()
	return ProfileSchema.newProfile()
end

T.test(
	"the first purchase is the first Common reveal: short, and the rarity is now seen",
	function()
		local data = newData()
		local entry = Reveals.grant(data, "rashford", false)
		T.truthy(entry)
		T.eq(entry.playerId, "rashford")
		T.eq(entry.isNew, true)
		T.eq(entry.firstOfRarity, true)
		T.eq(entry.short, true)
		T.eq(data.seenRarities.Common, true)
		T.eq(Roster.owns(data, "rashford"), true)
		T.eq(#data.pendingReveals, 1)
	end
)

T.test("a later player of a known rarity bought from a pad has no big reveal", function()
	local data = newData()
	Reveals.grant(data, "rashford", false)
	T.eq(Reveals.grant(data, "grealish", false), nil)
	T.eq(Roster.owns(data, "grealish"), true)
	T.eq(#data.pendingReveals, 1)
end)

T.test("the first player of each other rarity gets a full reveal, once", function()
	local data = newData()
	for _, rarity in { "Rare", "VeryRare", "Epic", "Legend" } do
		local id
		for _, def in Config.Players do
			if def.rarity == rarity then
				id = def.id
				break
			end
		end
		local entry = Reveals.grant(data, id, false)
		T.truthy(entry, rarity)
		T.eq(entry.firstOfRarity, true, rarity)
		T.eq(entry.short, false, rarity)
		T.eq(data.seenRarities[rarity], true, rarity)
	end
	T.eq(Reveals.grant(data, "saka", false), nil) -- a second Rare
end)

T.test("a Common that is not the first player is not the short reveal", function()
	local data = newData()
	Roster.add(data, "grealish")
	local entry = Reveals.grant(data, "rashford", false)
	T.eq(entry.firstOfRarity, true)
	T.eq(entry.short, false)
end)

T.test("every player won from a case gets a reveal, new or not", function()
	local data = newData()
	Reveals.grant(data, "rashford", false)
	local entry = Reveals.grant(data, "grealish", true) -- known rarity, from a case
	T.truthy(entry)
	T.eq(entry.isNew, true)
	T.eq(entry.firstOfRarity, false)
	T.eq(entry.short, false)
	T.eq(#data.pendingReveals, 2)
end)

T.test("a duplicate from a case adds one star and shows it, up to the cap", function()
	local data = newData()
	Reveals.grant(data, "rashford", false)
	local entry = Reveals.grant(data, "rashford", true)
	T.eq(entry.isNew, false)
	T.eq(entry.starsGained, 1)
	T.eq(entry.stars, 1)
	T.eq(data.players.rashford.stars, 1)
	data.players.rashford.stars = Config.Stars.maxStars
	local capped = Reveals.grant(data, "rashford", true)
	T.eq(capped.starsGained, 0)
	T.eq(capped.stars, Config.Stars.maxStars)
	T.eq(data.players.rashford.stars, Config.Stars.maxStars)
end)

T.test("a duplicate that does not come from a case changes nothing", function()
	local data = newData()
	Reveals.grant(data, "rashford", false)
	T.eq(Reveals.grant(data, "rashford", false), nil)
	T.eq(data.players.rashford.stars, 0)
	T.eq(#data.pendingReveals, 1)
end)

T.test("an unknown player gives nothing", function()
	local data = newData()
	T.eq(Reveals.grant(data, "nobody", true), nil)
	T.eq(#data.pendingReveals, 0)
end)

T.test("acknowledge removes the oldest reveal of that player and only that one", function()
	local data = newData()
	Reveals.grant(data, "rashford", false)
	Reveals.grant(data, "rashford", true)
	Reveals.grant(data, "son", true)
	T.eq(#data.pendingReveals, 3)
	T.eq(Reveals.acknowledge(data, "rashford"), true)
	T.eq(#data.pendingReveals, 2)
	T.eq(data.pendingReveals[1].isNew, false) -- the duplicate is left
	T.eq(Reveals.acknowledge(data, "nobody"), false)
	T.eq(#data.pendingReveals, 2)
end)

T.test("a client that never acknowledges cannot grow the save without limit", function()
	local data = newData()
	Reveals.grant(data, "rashford", false)
	for _ = 1, 50 do
		Reveals.grant(data, "rashford", true)
	end
	T.eq(#data.pendingReveals, Reveals.MAX_PENDING)
end)

T.test("a profile with pending reveals still validates", function()
	local data = newData()
	Reveals.grant(data, "rashford", false)
	Reveals.grant(data, "rashford", true)
	local ok, reason = ProfileSchema.validate(data)
	T.eq(ok, true, tostring(reason))
end)

T.test("buying a player from a pad records the reveal", function()
	local session = { data = newData() }
	session.data.cash = 15
	Actions.onChange = function() end
	T.eq(Actions.buyPlayer(session, "rashford"), true)
	T.eq(#session.data.pendingReveals, 1)
	T.eq(session.data.pendingReveals[1].short, true)
	T.eq(session.data.seenRarities.Common, true)
end)
