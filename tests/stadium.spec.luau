--!nocheck
local T = require("./framework")
local Config = T.load("shared/Config")
local CourtPlan = T.load("shared/CourtPlan")
local StadiumLogic = T.load("server/StadiumLogic")

T.suite("stadium")

local function count(parts, name)
	local n = 0
	for _, part in parts do
		if part.name == name then
			n += 1
		end
	end
	return n
end

T.test("every tier builds a sensible number of parts", function()
	for tier = 1, #Config.StadiumTiers do
		local parts = CourtPlan.parts(tier)
		T.truthy(#parts >= 20, "tier " .. tier .. " has too few parts")
		T.truthy(#parts <= 700, "tier " .. tier .. " has too many parts: " .. #parts)
	end
end)

T.test("the court surface follows the tier size", function()
	for tier, def in Config.StadiumTiers do
		for _, part in CourtPlan.parts(tier) do
			if part.name == "Surface" then
				T.eq(part.x1 - part.x0, def.courtLength)
				T.eq(part.z1 - part.z0, def.courtWidth)
			end
		end
	end
end)

T.test("every part has a positive size and stays inside the plot", function()
	for tier = 1, #Config.StadiumTiers do
		for _, part in CourtPlan.parts(tier) do
			T.truthy(part.x1 > part.x0 and part.y1 > part.y0 and part.z1 > part.z0, part.name)
			T.truthy(
				part.x0 >= -Config.Plot.width / 2 and part.x1 <= Config.Plot.width / 2,
				part.name .. " x, tier " .. tier
			)
			T.truthy(
				part.z0 >= CourtPlan.FRONT_Z and part.z1 <= Config.Plot.depth - 2,
				part.name .. " z, tier " .. tier
			)
			T.truthy(part.y0 >= 0.45 and part.y1 <= 40, part.name .. " y, tier " .. tier)
		end
	end
end)

T.test("nothing of the pitch stands on the path or the stadium pad in front of it", function()
	for tier = 1, #Config.StadiumTiers do
		for _, part in CourtPlan.parts(tier) do
			T.truthy(part.z0 >= CourtPlan.FRONT_Z, part.name .. " reaches the pad at tier " .. tier)
		end
	end
end)

T.test("each tier is a bigger, more real stadium", function()
	-- Tier 1: a street cage with a fence, a gate sign, painted boards and mini goals.
	T.eq(count(CourtPlan.parts(1), "MeshNearA"), 1)
	T.eq(count(CourtPlan.parts(1), "GateSign"), 1)
	T.eq(count(CourtPlan.parts(1), "Mural"), 2)
	T.eq(count(CourtPlan.parts(1), "BoxFront"), 0)
	T.eq(count(CourtPlan.parts(1), "StandRow"), 0)
	-- Tier 2: a walled F5 hall with a gate arch, benches and penalty boxes.
	T.eq(count(CourtPlan.parts(2), "WallNearA"), 1)
	T.eq(count(CourtPlan.parts(2), "GateSign"), 1)
	T.eq(count(CourtPlan.parts(2), "GatePillar"), 2)
	T.eq(count(CourtPlan.parts(2), "BenchSeat"), 1)
	T.eq(count(CourtPlan.parts(2), "BoxFront"), 2)
	T.eq(count(CourtPlan.parts(2), "StandRow"), 0)
	-- Tier 3: a stadium with stands, a crowd and a scoreboard, no floodlights yet.
	T.eq(count(CourtPlan.parts(3), "WallNearA"), 0)
	T.eq(count(CourtPlan.parts(3), "StandRow"), 5 + 4 + 4)
	T.truthy(count(CourtPlan.parts(3), "Fan") > 20)
	T.truthy(count(CourtPlan.parts(3), "AdBoard") > 20)
	T.eq(count(CourtPlan.parts(3), "Scoreboard"), 1)
	T.eq(count(CourtPlan.parts(3), "LightPole"), 0)
	T.eq(count(CourtPlan.parts(3), "Roof"), 0)
	-- Tier 4: stands on every side, a roof over the main one, four floodlight masts.
	T.eq(count(CourtPlan.parts(4), "StandRow"), 6 + 4 + 4 + 4 + 4)
	T.eq(count(CourtPlan.parts(4), "LightPole"), 4)
	T.eq(count(CourtPlan.parts(4), "Roof"), 1)
	-- Tier 5: the arena, roofs all round, screens, masts and fireworks.
	T.eq(count(CourtPlan.parts(5), "Roof"), 5)
	T.eq(count(CourtPlan.parts(5), "Scoreboard"), 1)
	T.eq(count(CourtPlan.parts(5), "Screen"), 2)
	T.eq(count(CourtPlan.parts(5), "LightPole"), 4)
	T.eq(count(CourtPlan.parts(5), "Firework"), 2)
	T.truthy(count(CourtPlan.parts(5), "Fan") > 60)
	for tier = 1, #Config.StadiumTiers do
		T.eq(count(CourtPlan.parts(tier), "GoalNet"), 8, "tier " .. tier)
	end
end)

T.test("the way in stays open: nothing blocks the gate or the aisle at the near side", function()
	local gate = CourtPlan.GATE_HALF
	for tier = 1, #Config.StadiumTiers do
		local front = CourtPlan.CENTER_Z - Config.StadiumTiers[tier].courtWidth / 2 - 12
		for _, part in CourtPlan.parts(tier) do
			local nearSide = part.z0 < CourtPlan.CENTER_Z - Config.StadiumTiers[tier].courtWidth / 2
			local overGate = part.x0 < gate - 0.8 and part.x1 > -gate + 0.8 -- the gate frame itself is allowed
			local tall = part.y1 - part.y0 > 1
			local isGateSign = part.name == "GateSign" and part.y0 > CourtPlan.FLOOR + 5
			if nearSide and overGate and tall and part.z0 >= front and not isGateSign then
				T.eq(part.name, "an open gate", "tier " .. tier .. " blocks the gate")
			end
		end
	end
end)

T.test("a sign names the face its text is on", function()
	for tier = 1, #Config.StadiumTiers do
		for _, part in CourtPlan.parts(tier) do
			if part.text then
				T.truthy(
					part.face == "Front" or part.face == "Left" or part.face == "Right",
					part.name
				)
			end
		end
	end
end)

T.test("a tier outside the range uses the nearest one", function()
	T.eq(#CourtPlan.parts(0), #CourtPlan.parts(1))
	T.eq(#CourtPlan.parts(99), #CourtPlan.parts(#Config.StadiumTiers))
end)

T.test("the first upgrade cannot be skipped, later ones can", function()
	T.eq(StadiumLogic.upgradeInfo(2, true).canSkip, false)
	T.eq(StadiumLogic.upgradeInfo(3, false).canSkip, true)
end)

T.test("the cinematic info shows the field growing and the boost", function()
	local info = StadiumLogic.upgradeInfo(2, true)
	T.eq(info.tier, 2)
	T.eq(info.fieldFrom, 4)
	T.eq(info.fieldTo, 5)
	T.eq(info.boostSeconds, 300)
	T.eq(info.boostMultiplier, 2)
	T.truthy(info.maxSeconds > info.seconds)
	T.eq(StadiumLogic.upgradeInfo(5, false).fieldFrom, 8)
	T.eq(StadiumLogic.upgradeInfo(5, false).fieldTo, 11)
end)
