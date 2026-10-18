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
		T.truthy(#parts <= 450, "tier " .. tier .. " has too many parts: " .. #parts)
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
			T.truthy(part.x0 >= -100 and part.x1 <= 100, part.name .. " x, tier " .. tier)
			T.truthy(part.z0 >= 2 and part.z1 <= 119, part.name .. " z, tier " .. tier)
			T.truthy(part.y0 >= 0.45 and part.y1 <= 40, part.name .. " y, tier " .. tier)
		end
	end
end)

T.test("nothing tall blocks the way to the building door", function()
	local gap = CourtPlan.DOOR_GAP
	for tier = 1, #Config.StadiumTiers do
		for _, part in CourtPlan.parts(tier) do
			local tall = part.y1 - CourtPlan.FLOOR > 0.5
			local inDoorWay = part.x1 > gap.x0
				and part.x0 < gap.x1
				and part.z1 > CourtPlan.DOOR_Z - 20
			T.falsy(tall and inDoorWay, part.name .. " blocks the door at tier " .. tier)
		end
	end
end)

T.test("each tier adds the thing the plan promises", function()
	T.eq(count(CourtPlan.parts(1), "Mural"), 2)
	T.eq(count(CourtPlan.parts(1), "BenchSeat"), 0)
	T.eq(count(CourtPlan.parts(2), "BenchSeat"), 1)
	T.eq(count(CourtPlan.parts(2), "BoxFront"), 2)
	T.eq(count(CourtPlan.parts(2), "WallNear"), 1)
	T.eq(count(CourtPlan.parts(3), "WallNear"), 0)
	T.eq(count(CourtPlan.parts(3), "FenceNear"), 1)
	T.eq(count(CourtPlan.parts(3), "StandRow"), 3)
	T.eq(count(CourtPlan.parts(3), "LightPole"), 0)
	T.eq(count(CourtPlan.parts(4), "StandRow"), 5)
	T.eq(count(CourtPlan.parts(4), "LightPole"), 4)
	T.eq(count(CourtPlan.parts(4), "Roof"), 0)
	T.eq(count(CourtPlan.parts(5), "Roof"), 1)
	T.eq(count(CourtPlan.parts(5), "Scoreboard"), 1)
	T.eq(count(CourtPlan.parts(5), "Firework"), 2)
	T.truthy(count(CourtPlan.parts(5), "Fan") > 20)
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
