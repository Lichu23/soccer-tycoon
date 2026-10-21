--!nocheck
local T = require("./framework")
local Config = T.load("shared/Config")
local Kits = T.load("shared/Kits")

T.suite("team kits")

local PATTERNS = { stripes = true, sleeves = true, hem = true, plain = true }

local function valid(color)
	if type(color) ~= "table" or #color ~= 3 then
		return false
	end
	for _, value in color do
		if type(value) ~= "number" or value < 0 or value > 255 then
			return false
		end
	end
	return true
end

T.test("every player has a kit with valid colours and a known pattern", function()
	for _, def in Config.Players do
		local kit = Kits.of(def.id)
		T.eq(kit ~= nil, true, def.id .. " has no kit")
		T.eq(
			valid(kit.shirt)
				and valid(kit.trim)
				and valid(kit.shorts)
				and valid(kit.socks)
				and valid(kit.accent),
			true,
			def.id
		)
		T.eq(PATTERNS[kit.pattern], true, def.id .. " pattern")
	end
end)

T.test("players of one team wear the same kit", function()
	T.eq(Kits.of("pedri"), Kits.of("gavi"))
	T.eq(Kits.of("haaland"), Kits.of("foden"))
end)

T.test("a name with no team has no kit", function()
	T.eq(Kits.of("nobody"), nil)
end)

T.test("every team has its clothing images", function()
	local KitImages = T.load("shared/KitImages")
	for team in Kits.teams do
		T.eq(type(KitImages.shirts[team]), "string", team .. " shirt")
		T.eq(type(KitImages.pants[team]), "string", team .. " pants")
	end
end)
