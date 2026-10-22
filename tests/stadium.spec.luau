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
	-- Tier 3: a stadium with stands, a crowd, a scoreboard and four floodlight masts.
	T.eq(count(CourtPlan.parts(3), "WallNearA"), 0)
	T.eq(count(CourtPlan.parts(3), "StandRow"), 5 + 4 + 4)
	T.truthy(count(CourtPlan.parts(3), "Fan") > 20)
	T.truthy(count(CourtPlan.parts(3), "AdBoard") > 20)
	T.eq(count(CourtPlan.parts(3), "Scoreboard"), 1)
	T.eq(count(CourtPlan.parts(3), "LightPole"), 4)
	T.eq(count(CourtPlan.parts(3, "bank"), "LightHead"), 4 * 12)
	T.eq(count(CourtPlan.parts(3), "Roof"), 0)
	-- Tier 4: stands on every side, a roof over the main one, four floodlight masts.
	T.eq(count(CourtPlan.parts(4), "StandRow"), 6 + 4 + 4 + 4 + 4)
	T.eq(count(CourtPlan.parts(4), "LightPole"), 4)
	T.eq(count(CourtPlan.parts(4, "tower"), "LightHead"), 4 * 16)
	T.eq(count(CourtPlan.parts(4), "Roof"), 1)
	-- Tier 5: the arena, roofs all round with lamps under them, masts outside, screens and fireworks.
	T.eq(count(CourtPlan.parts(5), "Roof"), 5)
	T.eq(count(CourtPlan.parts(5), "Scoreboard"), 1)
	T.eq(count(CourtPlan.parts(5), "Screen"), 2)
	T.eq(count(CourtPlan.parts(5), "LightPole"), 4)
	T.truthy(count(CourtPlan.parts(5), "LightHead") > 40)
	T.eq(count(CourtPlan.parts(5), "Firework"), 2)
	T.truthy(count(CourtPlan.parts(5), "Fan") > 60)
	-- Tier 6: the roof arena, one ring of roof, eight retractable panels, masts outside.
	T.eq(count(CourtPlan.parts(6), "RoofPanel"), 8)
	T.eq(count(CourtPlan.parts(6), "LightPole"), 4)
	T.eq(count(CourtPlan.parts(6), "Firework"), 2)
	T.truthy(count(CourtPlan.parts(6), "Fan") > 60)
	-- The sponsor boards are wedges with a made-up name, every lamp face is a disc or a panel.
	for tier = 3, #Config.StadiumTiers do
		for _, part in CourtPlan.parts(tier) do
			if part.name == "AdBoard" then
				T.eq(part.shape, "wedge")
				T.truthy(part.text ~= nil and #part.text > 0)
			end
		end
	end
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
			local isGateSign = (part.name == "GateSign" or part.name == "Crest")
				and part.y0 > CourtPlan.FLOOR + 5
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

T.test("the retractable roof closes over the pitch and opens onto the end roofs", function()
	local def = Config.StadiumTiers[6]
	local x0, x1 = -def.courtLength / 2, def.courtLength / 2
	local covered = { left = false, right = false }
	for _, part in CourtPlan.parts(6) do
		if part.name == "RoofPanel" then
			local slide = part.slide
			T.truthy(slide ~= nil, "a panel knows where it closes")
			-- Open, the panel sits outside the pitch; closed, it is over it.
			T.truthy(part.x1 <= x0 or part.x0 >= x1, "an open panel is off the pitch")
			local closed0, closed1 = part.x0 + slide[1], part.x1 + slide[1]
			T.truthy(closed1 > x0 - 6 and closed0 < x1 + 6, "a closed panel is over the pitch")
			if closed0 <= 0.01 and closed0 >= -0.01 then
				covered.right = true
			end
			if closed1 <= 0.01 and closed1 >= -0.01 then
				covered.left = true
			end
		end
	end
	T.truthy(covered.left and covered.right, "the two halves meet in the middle")
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
	T.eq(StadiumLogic.upgradeInfo(6, false).fieldFrom, 11)
	T.eq(StadiumLogic.upgradeInfo(6, false).fieldTo, 11)
end)

T.test("every slot the Locker room paints has parts from the tier that opens it", function()
	local StadiumLook = T.load("shared/StadiumLook")
	for _, slot in Config.CosmeticSlots do
		local names = StadiumLook.PARTS[slot.id]
		if names then
			for tier = slot.tier, #Config.StadiumTiers do
				local found = 0
				for _, part in CourtPlan.parts(tier) do
					if names[part.name] then
						found += 1
					end
				end
				T.truthy(found > 0, slot.id .. " has nothing to paint at tier " .. tier)
			end
		end
	end
end)

T.test("every floodlight model fits the plot and the part budget at every tier", function()
	for tier = 1, #Config.StadiumTiers do
		for _, model in CourtPlan.LAMP_MODELS do
			local parts = CourtPlan.parts(tier, model)
			T.truthy(#parts <= 700, model .. " at tier " .. tier .. ": " .. #parts .. " parts")
			local lamps = 0
			for _, part in parts do
				if part.lamp then
					lamps += 1
					T.truthy(part.x0 >= -Config.Plot.width / 2 and part.x1 <= Config.Plot.width / 2)
					T.truthy(part.z0 >= CourtPlan.FRONT_Z and part.z1 <= Config.Plot.depth - 2)
					T.truthy(part.y1 <= 40, model .. " too tall at tier " .. tier)
				end
			end
			T.truthy(lamps > 0, model .. " has no parts at tier " .. tier)
		end
	end
end)

T.test("every floodlight style is a model the plan can build", function()
	for _, def in Config.Cosmetics do
		if def.slot == "lamps" then
			T.truthy(table.find(CourtPlan.LAMP_MODELS, def.model) ~= nil, def.id)
		end
	end
end)

T.test("each scoreboard style is its own design or colours", function()
	local seen = {}
	for _, def in Config.Cosmetics do
		if def.slot == "scoreboard" then
			T.truthy(def.design ~= nil, def.id)
			local key = def.design .. table.concat(def.color, ",")
			T.eq(seen[key], nil, def.id .. " looks like another style")
			seen[key] = true
		end
	end
end)
