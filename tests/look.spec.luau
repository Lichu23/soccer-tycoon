--!nocheck
local T = require("./framework")
local Config = T.load("shared/Config")
local Look = T.load("shared/Look")

T.suite("player look")

T.test("a player always looks the same", function()
	local a, b = Look.of("rashford"), Look.of("rashford")
	T.eq(a.hair, b.hair)
	T.eq(a.pattern, b.pattern)
	T.eq(a.skin[1], b.skin[1])
	T.eq(a.hairColor[2], b.hairColor[2])
end)

T.test("the 35 players show real variety: skin tones, hair styles and kit patterns", function()
	local skins, hairs, patterns = {}, {}, {}
	local count = 0
	for _, def in Config.Players do
		local look = Look.of(def.id)
		skins[look.skin[1]] = true
		hairs[look.hair] = true
		patterns[look.pattern] = true
		count += 1
	end
	local function size(set)
		local n = 0
		for _ in set do
			n += 1
		end
		return n
	end
	T.eq(count >= 30, true)
	T.eq(size(skins) >= 4, true)
	T.eq(size(hairs) >= 4, true)
	T.eq(size(patterns) >= 3, true)
end)
