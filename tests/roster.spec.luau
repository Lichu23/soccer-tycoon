--!nocheck
local T = require("./framework")
local Roster = T.load("shared/Roster")
local Config = T.load("shared/Config")
local ProfileSchema = T.load("server/ProfileSchema")

T.suite("roster")

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

T.test("add and owns", function()
	local data = newData()
	T.eq(Roster.ownedCount(data), 0)
	T.eq(Roster.add(data, "rashford"), true)
	T.eq(Roster.owns(data, "rashford"), true)
	T.eq(Roster.ownedCount(data), 1)
	T.deepEq(data.players.rashford, { level = 0, stars = 0 })
end)

T.test("adding twice or adding an unknown id changes nothing", function()
	local data = newData()
	Roster.add(data, "rashford")
	T.eq(Roster.add(data, "rashford"), false)
	T.eq(Roster.add(data, "not_a_player"), false)
	T.eq(Roster.ownedCount(data), 1)
end)

T.test("income uses the level and the stars", function()
	local data = newData()
	T.eq(Roster.income(data, "rashford"), 0) -- not owned
	Roster.add(data, "rashford")
	T.near(Roster.income(data, "rashford"), 3)
	data.players.rashford.level = 5
	data.players.rashford.stars = 2
	T.near(Roster.income(data, "rashford"), 3 * 1.15 * 1.2)
end)

T.test("a floor is complete when every player on it is owned", function()
	local data = newData()
	T.eq(Roster.floorComplete(data, 1), false)
	ownFloor(data, 1)
	T.eq(Roster.floorComplete(data, 1), true)
	T.eq(Roster.floorComplete(data, 2), false)
	T.eq(Roster.floorComplete(data, 9), false) -- no such floor
end)

T.test("floors count one after another, a gap stops the count", function()
	local data = newData()
	T.eq(Roster.floorsComplete(data), 0)
	ownFloor(data, 2)
	T.eq(Roster.floorsComplete(data), 0) -- floor 1 is missing
	ownFloor(data, 1)
	T.eq(Roster.floorsComplete(data), 2)
	ownFloor(data, 3)
	T.eq(Roster.floorsComplete(data), 3)
	ownFloor(data, 4)
	T.eq(Roster.floorsComplete(data), 4)
end)

T.test("a floor's gate opens when the floor before it is complete", function()
	local data = newData()
	T.eq(Roster.floorUnlocked(data, 1), true)
	T.eq(Roster.floorUnlocked(data, 2), false)
	T.eq(Roster.floorUnlocked(data, 3), false)
	T.eq(Roster.floorUnlocked(data, 4), false)
	ownFloor(data, 1)
	T.eq(Roster.floorUnlocked(data, 2), true)
	T.eq(Roster.floorUnlocked(data, 3), false)
	ownFloor(data, 2)
	T.eq(Roster.floorUnlocked(data, 3), true)
	T.eq(Roster.floorUnlocked(data, 4), false)
	ownFloor(data, 3)
	T.eq(Roster.floorUnlocked(data, 4), true)
end)

T.test("owning a later floor without the earlier one does not open its gate", function()
	local data = newData()
	ownFloor(data, 2) -- for example players won from cases
	T.eq(Roster.floorUnlocked(data, 2), false)
	T.eq(Roster.floorUnlocked(data, 3), false)
end)

T.test("canBuy explains why not", function()
	local data = newData()
	local ok, reason = Roster.canBuy(data, "rashford")
	T.eq(ok, true)
	T.eq(reason, nil)
	local _, unknown = Roster.canBuy(data, "nobody")
	T.eq(unknown, "unknown")
	local _, locked = Roster.canBuy(data, "lautaro") -- floor 2 while floor 1 is not complete
	T.eq(locked, "locked")
	local _, legend = Roster.canBuy(data, "pele")
	T.eq(legend, "legend")
	Roster.add(data, "rashford")
	local _, owned = Roster.canBuy(data, "rashford")
	T.eq(owned, "owned")
end)

T.test("floor 2 opens when floor 1 is complete, floor 3 when floor 2 is", function()
	local data = newData()
	ownFloor(data, 1)
	T.eq((Roster.canBuy(data, "lautaro")), true)
	T.eq((Roster.canBuy(data, "foden")), false)
	ownFloor(data, 2)
	T.eq((Roster.canBuy(data, "foden")), true)
end)

T.test("the next player to buy is the cheapest one on an open floor", function()
	local data = newData()
	T.eq(Roster.nextUnowned(data).id, "rashford")
	Roster.add(data, "rashford")
	T.eq(Roster.nextUnowned(data).id, "grealish")
	ownFloor(data, 1)
	T.eq(Roster.nextUnowned(data).id, "lautaro")
	ownFloor(data, 2)
	ownFloor(data, 3)
	T.eq(Roster.nextUnowned(data), nil) -- only Legends are left
end)

T.test("the field holds the top earners up to the tier capacity", function()
	local data = newData()
	for _, id in { "rashford", "grealish", "sterling", "joao_felix", "son", "saka" } do
		Roster.add(data, id)
	end
	T.deepEq(Roster.field(data), { "saka", "son", "joao_felix", "sterling" }) -- tier 1: 4 players
	data.stadiumTier = 2
	T.eq(#Roster.field(data), 5)
	data.stadiumTier = 3
	T.eq(#Roster.field(data), 6)
	data.stadiumTier = 5
	T.eq(#Roster.field(data), 6) -- only six are owned
end)

T.test("training changes who earns the most", function()
	local data = newData()
	Roster.add(data, "rashford") -- 3
	Roster.add(data, "grealish") -- 5
	data.stadiumTier = 1
	data.players.rashford.level = 5
	data.players.rashford.stars = 5 -- 3 x 1.15 x 1.5 = 5.175, above 5
	T.eq(Roster.field(data)[1], "rashford")
end)

T.test("a bench player is not on the field and does not earn", function()
	local data = newData()
	for _, id in { "rashford", "grealish", "sterling", "joao_felix", "son" } do
		Roster.add(data, id)
	end
	local field = Roster.field(data)
	T.eq(#field, 4)
	T.eq(table.find(field, "rashford"), nil)
	local total = 0
	for _, income in Roster.fieldIncomes(data) do
		total += income
	end
	T.near(total, 5 + 9 + 16 + 26) -- the four best, not Rashford's 3
end)

T.test("an empty roster has an empty field", function()
	local data = newData()
	T.deepEq(Roster.field(data), {})
	T.deepEq(Roster.fieldIncomes(data), {})
end)
