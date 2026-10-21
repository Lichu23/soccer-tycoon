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

T.test("every player has a chosen skin tone that is one of the six", function()
	for _, def in Config.Players do
		local index = Look.skinOf[def.id]
		T.eq(index ~= nil and index >= 1 and index <= #Look.skinTones, true, def.id)
		T.eq(Look.of(def.id).skin, Look.skinTones[index])
	end
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

T.test("every player has a chosen hair style and colour", function()
	local styles =
		{ short = true, tall = true, long = true, mohawk = true, buzz = true, bald = true }
	for _, def in Config.Players do
		local hair = Look.hairOf[def.id]
		T.eq(hair ~= nil and styles[hair[1]] == true, true, def.id)
		T.eq(Look.hairColors[hair[2]] ~= nil, true, def.id .. " colour")
		T.eq(Look.of(def.id).hair, hair[1])
	end
end)
