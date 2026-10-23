--!nocheck
local T = require("./framework")
local Config = T.load("shared/Config")
local ProfileSchema = T.load("server/ProfileSchema")
local Roster = T.load("shared/Roster")
local Unlocks = T.load("shared/Unlocks")

T.suite("unlocks")

local function ids(list)
	local out = {}
	for _, unlock in list do
		table.insert(out, unlock.id)
	end
	return out
end

local function ownFloor(data, floor)
	for _, def in Config.Players do
		if def.floor == floor then
			Roster.add(data, def.id)
		end
	end
end

T.test("a new profile has nothing open", function()
	local data = ProfileSchema.newProfile()
	T.deepEq(ids(Unlocks.newlyOpen(data, data.flags.unlocksShown)), {})
end)

T.test("the field filling up opens the stadium upgrade", function()
	local data = ProfileSchema.newProfile()
	local owned = 0
	for _, def in Config.Players do
		if def.floor == 1 and owned < Config.StadiumTiers[1].field then
			Roster.add(data, def.id)
			owned += 1
		end
	end
	T.deepEq(ids(Unlocks.newlyOpen(data, {})), { "stadium" })
end)

T.test(
	"finishing floor 1 opens floor 2 and the hat-trick upgrade together, in list order",
	function()
		local data = ProfileSchema.newProfile()
		ownFloor(data, 1)
		data.stadiumTier = #Config.StadiumTiers -- no stadium upgrade left, so it stays out
		local open = ids(Unlocks.newlyOpen(data, {}))
		T.truthy(table.find(open, "floor2"))
		T.truthy(table.find(open, "store_hatTrick"))
		T.truthy(table.find(open, "floor2") > table.find(open, "store_hatTrick"))
		T.eq(table.find(open, "floor3"), nil)
	end
)

T.test("an unlock already shown is never offered again", function()
	local data = ProfileSchema.newProfile()
	ownFloor(data, 1)
	local shown = {}
	Unlocks.seed(data, shown)
	T.deepEq(ids(Unlocks.newlyOpen(data, shown)), {})
	ownFloor(data, 2)
	T.truthy(table.find(ids(Unlocks.newlyOpen(data, shown)), "floor3"))
end)

T.test("the skill games open with the first level-up, not before", function()
	local data = ProfileSchema.newProfile()
	Roster.add(data, "rashford")
	data.flags.milestones.first_match = 1
	T.eq(table.find(ids(Unlocks.newlyOpen(data, {})), "keepie"), nil)
	data.players.rashford.level = 1
	local open = ids(Unlocks.newlyOpen(data, {}))
	T.truthy(table.find(open, "keepie"))
	T.truthy(table.find(open, "breakaway"))
end)

T.test("every unlock points at a pad of the plot template's kinds", function()
	local kinds = { player = true, legend = true, store = true, stadium = true, training = true }
	for _, unlock in Unlocks.LIST do
		T.truthy(kinds[unlock.padKind], unlock.id)
		T.truthy(unlock.title ~= "" and unlock.detail ~= "", unlock.id)
	end
end)
