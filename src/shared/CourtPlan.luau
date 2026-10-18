--!strict
-- The shape of the pitch for each stadium tier (docs/PLAN.md, Step 7), as plain data so it can be
-- unit tested. The server builds these boxes under the plot (server/Stadium) and the client lifts
-- them out of the ground during the upgrade cinematic. Coordinates are in plot space: x across the
-- plot, z from the street gate (0) towards the building (about 120), y up from the ground reference.

local Config = require(script.Parent.Config)

export type PartSpec = {
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	color: { number }, -- r, g, b from 0 to 255
	material: string, -- an Enum.Material name
	transparency: number,
	cylinder: boolean, -- a disc standing on its flat side (centre circle)
	text: string?, -- drawn on the face towards the court (the scoreboard)
	emitter: boolean, -- a firework launch point
}

local CourtPlan = {}

CourtPlan.CENTER_Z = 235 -- the middle of every pitch, in the stadium zone at the back of the plot
CourtPlan.FLOOR = 0.7 -- the walkable height of the pitch
-- The way from the street to the building door stays free of tall things.
CourtPlan.DOOR_GAP = { x0 = 0, x1 = 0 } -- no door gap any more: the building has its own side
CourtPlan.FRONT_Z = 175 -- nothing of the pitch comes closer to the gate than this (the pad stands here)

local FLOOR = CourtPlan.FLOOR
local CENTER_Z = CourtPlan.CENTER_Z

local COURT = { 70, 110, 170 }
local APRON = { 60, 90, 140 }
local LINE = { 240, 240, 240 }
local WALL = { 215, 205, 190 }
local FENCE = { 150, 120, 90 }
local CONCRETE = { 160, 160, 165 }
local SEAT = { 200, 60, 60 }
local POLE = { 90, 90, 100 }
local LIGHT = { 255, 244, 214 }
local ROOF = { 80, 85, 100 }
local BOARD = { 25, 25, 30 }
local GOAL = { 245, 245, 245 }
local FLAG = { 240, 200, 60 }
local MURAL_A = { 240, 140, 60 }
local MURAL_B = { 90, 190, 120 }
local FANS = {
	{ 230, 90, 90 },
	{ 90, 140, 230 },
	{ 240, 200, 70 },
	{ 120, 200, 130 },
	{ 230, 230, 235 },
	{ 190, 110, 220 },
}

local function clamp(value: number, low: number, high: number): number
	return math.max(low, math.min(high, value))
end

local function box(
	list: { PartSpec },
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	color: { number },
	material: string?,
	transparency: number?
)
	table.insert(list, {
		name = name,
		x0 = x0,
		x1 = x1,
		y0 = y0,
		y1 = y1,
		z0 = z0,
		z1 = z1,
		color = color,
		material = material or "SmoothPlastic",
		transparency = transparency or 0,
		cylinder = false,
		text = nil,
		emitter = false,
	})
end

-- A strip along x from xa to xb at depth z0..z1, split around the door gap.
local function stripAlongX(
	list: { PartSpec },
	name: string,
	xa: number,
	xb: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	color: { number },
	material: string?,
	transparency: number?
)
	local gap = CourtPlan.DOOR_GAP
	local leftEnd, rightStart = math.min(xb, gap.x0), math.max(xa, gap.x1)
	if leftEnd - xa > 0.1 then
		box(list, name .. "A", xa, leftEnd, y0, y1, z0, z1, color, material, transparency)
	end
	if xb - rightStart > 0.1 then
		box(list, name .. "B", rightStart, xb, y0, y1, z0, z1, color, material, transparency)
	end
end

-- All the parts of the pitch of `tier` (1 to 5).
function CourtPlan.parts(tier: number): { PartSpec }
	local index = clamp(math.floor(tier), 1, #Config.StadiumTiers)
	local def = Config.StadiumTiers[index]
	local length, width = def.courtLength, def.courtWidth
	local x0, x1 = -length / 2, length / 2
	local z0, z1 = CENTER_Z - width / 2, CENTER_Z + width / 2
	local list: { PartSpec } = {}

	-- The court itself: surface, lines, centre circle, goals and corner flags (every tier).
	box(list, "Surface", x0, x1, FLOOR - 0.2, FLOOR, z0, z1, COURT)
	local lineY0, lineY1 = FLOOR, FLOOR + 0.05
	local lt = 0.5
	box(list, "LineNear", x0, x1, lineY0, lineY1, z0, z0 + lt, LINE)
	box(list, "LineFar", x0, x1, lineY0, lineY1, z1 - lt, z1, LINE)
	box(list, "LineLeft", x0, x0 + lt, lineY0, lineY1, z0, z1, LINE)
	box(list, "LineRight", x1 - lt, x1, lineY0, lineY1, z0, z1, LINE)
	box(list, "LineCenter", -lt / 2, lt / 2, lineY0, lineY1, z0, z1, LINE)
	local ring = 6
	box(list, "CircleOuter", -ring, ring, lineY0, lineY1, CENTER_Z - ring, CENTER_Z + ring, LINE)
	box(
		list,
		"CircleInner",
		-ring + lt,
		ring - lt,
		lineY1,
		lineY1 + 0.03,
		CENTER_Z - ring + lt,
		CENTER_Z + ring - lt,
		COURT
	)
	list[#list - 1].cylinder = true
	list[#list].cylinder = true

	for _, side in { -1, 1 } do
		local gx = side * (length / 2)
		local post, goalHeight = 0.5, 6
		box(
			list,
			"GoalPostA",
			gx - post / 2,
			gx + post / 2,
			FLOOR,
			FLOOR + goalHeight,
			CENTER_Z - 5,
			CENTER_Z - 5 + post,
			GOAL
		)
		box(
			list,
			"GoalPostB",
			gx - post / 2,
			gx + post / 2,
			FLOOR,
			FLOOR + goalHeight,
			CENTER_Z + 5 - post,
			CENTER_Z + 5,
			GOAL
		)
		box(
			list,
			"GoalBar",
			gx - post / 2,
			gx + post / 2,
			FLOOR + goalHeight - post,
			FLOOR + goalHeight,
			CENTER_Z - 5,
			CENTER_Z + 5,
			GOAL
		)
		for _, zSide in { -1, 1 } do
			local fx = side * (length / 2)
			local fz = if zSide < 0 then z0 else z1
			local inDoorWay = fz > z0 and fx > CourtPlan.DOOR_GAP.x0 and fx < CourtPlan.DOOR_GAP.x1
			if inDoorWay then
				continue -- the far corner flag would stand in the way to the door
			end
			box(
				list,
				"FlagPole",
				fx - 0.15,
				fx + 0.15,
				FLOOR,
				FLOOR + 4.5,
				fz - 0.15,
				fz + 0.15,
				POLE
			)
			box(
				list,
				"Flag",
				fx - 0.1,
				fx + 0.1,
				FLOOR + 3.5,
				FLOOR + 4.5,
				fz - 0.7,
				fz + 0.7,
				FLAG
			)
		end
	end

	if index == 1 then
		-- Street futsal: a painted mural board behind each goal.
		for side, colour in { [-1] = MURAL_A, [1] = MURAL_B } do
			local mx = side * (length / 2 + 2)
			box(
				list,
				"Mural",
				mx - 0.2,
				mx + 0.2,
				FLOOR,
				FLOOR + 3.2,
				CENTER_Z - 8,
				CENTER_Z + 8,
				colour
			)
		end
	end

	if index >= 2 then
		-- Proper lines: a penalty box at each end.
		for _, side in { -1, 1 } do
			local inner = side * (length / 2 - 10)
			local goalLine = side * (length / 2)
			local xa, xb = math.min(inner, goalLine), math.max(inner, goalLine)
			box(
				list,
				"BoxFront",
				inner - lt / 2,
				inner + lt / 2,
				lineY0,
				lineY1,
				CENTER_Z - 11,
				CENTER_Z + 11,
				LINE
			)
			box(list, "BoxSideA", xa, xb, lineY0, lineY1, CENTER_Z - 11, CENTER_Z - 11 + lt, LINE)
			box(list, "BoxSideB", xa, xb, lineY0, lineY1, CENTER_Z + 11 - lt, CENTER_Z + 11, LINE)
		end
		-- A bench for the substitutes, on the near side.
		local benchZ = z0 - 6
		box(list, "BenchSeat", -14, -2, FLOOR, FLOOR + 1.1, benchZ - 1, benchZ + 1, FENCE, "Wood")
		box(
			list,
			"BenchBack",
			-14,
			-2,
			FLOOR + 1.1,
			FLOOR + 2.6,
			benchZ - 1,
			benchZ - 0.6,
			FENCE,
			"Wood"
		)
	end

	if index == 2 then
		-- Tier 2: a low wall all round the court.
		local o = 2
		box(list, "Apron", x0 - 3, x1 + 3, 0.5, 0.65, z0 - 3, z1 + 3, APRON)
		box(list, "WallNear", x0 - o - 1, x1 + o + 1, FLOOR, FLOOR + 2.5, z0 - o - 1, z0 - o, WALL)
		stripAlongX(
			list,
			"WallFar",
			x0 - o - 1,
			x1 + o + 1,
			FLOOR,
			FLOOR + 2.5,
			z1 + o,
			z1 + o + 1,
			WALL
		)
		box(list, "WallLeft", x0 - o - 1, x0 - o, FLOOR, FLOOR + 2.5, z0 - o, z1 + o, WALL)
		box(list, "WallRight", x1 + o, x1 + o + 1, FLOOR, FLOOR + 2.5, z0 - o, z1 + o, WALL)
	end

	if index >= 3 then
		-- Tier 3 and up: a see-through fence all round, outside the bench.
		local o = 8
		box(list, "Apron", x0 - 3, x1 + 3, 0.5, 0.65, z0 - 3, z1 + 3, APRON)
		box(
			list,
			"FenceNear",
			x0 - o - 1,
			x1 + o + 1,
			FLOOR,
			FLOOR + 5,
			z0 - o - 1,
			z0 - o,
			FENCE,
			"Wood",
			0.5
		)
		stripAlongX(
			list,
			"FenceFar",
			x0 - o - 1,
			x1 + o + 1,
			FLOOR,
			FLOOR + 5,
			z1 + o,
			z1 + o + 1,
			FENCE,
			"Wood",
			0.5
		)
		box(
			list,
			"FenceLeft",
			x0 - o - 1,
			x0 - o,
			FLOOR,
			FLOOR + 5,
			z0 - o,
			z1 + o,
			FENCE,
			"Wood",
			0.5
		)
		box(
			list,
			"FenceRight",
			x1 + o,
			x1 + o + 1,
			FLOOR,
			FLOOR + 5,
			z0 - o,
			z1 + o,
			FENCE,
			"Wood",
			0.5
		)

		-- The stand on the left side: 3 rows at tier 3, 5 from tier 4.
		local rows = if index >= 4 then 5 else 3
		local inner = x0 - 10
		local sz0, sz1 = CENTER_Z - width * 0.45, CENTER_Z + width * 0.45
		for row = 0, rows - 1 do
			local xa, xb = inner - (row + 1) * 3, inner - row * 3
			local top = FLOOR + 1.6 * (row + 1)
			box(list, "StandRow", xa, xb, FLOOR, top, sz0, sz1, CONCRETE)
			box(list, "StandSeats", xb - 2.2, xb - 0.4, top, top + 0.25, sz0 + 1, sz1 - 1, SEAT)
			if index >= 5 then
				local seats = 0
				local z = sz0 + 2
				while z < sz1 - 1.5 do
					seats += 1
					if (row * 7 + seats * 3) % 5 ~= 0 then
						local palette = FANS[(row + seats) % #FANS + 1]
						local fx = xb - 1.3
						box(
							list,
							"Fan",
							fx - 0.6,
							fx + 0.6,
							top + 0.25,
							top + 1.65,
							z - 0.6,
							z + 0.6,
							palette
						)
					end
					z += 3
				end
			end
		end
	end

	if index >= 4 then
		-- Floodlights on four towers.
		for _, side in { -1, 1 } do
			for _, zTower in { z0 - 6, z1 + 6 } do
				local tx = side * (length / 2 + 6)
				box(
					list,
					"LightPole",
					tx - 0.5,
					tx + 0.5,
					FLOOR,
					FLOOR + 20,
					zTower - 0.5,
					zTower + 0.5,
					POLE
				)
				box(
					list,
					"LightHead",
					tx - 2.5,
					tx + 2.5,
					FLOOR + 20,
					FLOOR + 22.5,
					zTower - 0.6,
					zTower + 0.6,
					LIGHT,
					"Neon"
				)
			end
		end
	end

	if index >= 5 then
		-- A roof over the left stand.
		local inner = x0 - 10
		local sz0, sz1 = CENTER_Z - width * 0.45, CENTER_Z + width * 0.45
		box(list, "Roof", inner - 17, inner + 1, FLOOR + 13, FLOOR + 14, sz0 - 1, sz1 + 1, ROOF)
		for _, z in { sz0, sz0 + (sz1 - sz0) / 3, sz0 + (sz1 - sz0) * 2 / 3, sz1 } do
			box(
				list,
				"RoofPillar",
				inner - 16.5,
				inner - 15.5,
				FLOOR,
				FLOOR + 13,
				z - 0.5,
				z + 0.5,
				POLE
			)
		end

		-- A second stand along the far side, away from the door.
		local farInner = z1 + 10
		for row = 0, 2 do
			local za, zb = farInner + row * 2.6, farInner + (row + 1) * 2.6
			local top = FLOOR + 1.6 * (row + 1)
			box(list, "FarRow", -4, 56, FLOOR, top, za, zb, CONCRETE)
			box(list, "FarSeats", -4, 56, top, top + 0.25, za + 0.4, za + 1.8, SEAT)
			local seats = 0
			local x = -2
			while x < 54 do
				seats += 1
				if (row * 5 + seats * 3) % 4 ~= 0 then
					local palette = FANS[(row + seats * 2) % #FANS + 1]
					box(
						list,
						"Fan",
						x - 0.6,
						x + 0.6,
						top + 0.25,
						top + 1.65,
						za + 0.6,
						za + 1.6,
						palette
					)
				end
				x += 3
			end
		end

		-- The scoreboard on two posts, facing the court.
		local bx = x1 + 11
		box(
			list,
			"ScoreboardPostA",
			bx - 0.5,
			bx + 0.5,
			FLOOR,
			FLOOR + 11,
			CENTER_Z - 14,
			CENTER_Z - 13,
			POLE
		)
		box(
			list,
			"ScoreboardPostB",
			bx - 0.5,
			bx + 0.5,
			FLOOR,
			FLOOR + 11,
			CENTER_Z + 13,
			CENTER_Z + 14,
			POLE
		)
		box(
			list,
			"Scoreboard",
			bx - 0.6,
			bx + 0.6,
			FLOOR + 11,
			FLOOR + 19,
			CENTER_Z - 16,
			CENTER_Z + 16,
			BOARD
		)
		list[#list].text = "SOCCER TYCOON"

		-- Fireworks launch from the two near floodlight towers.
		for _, side in { -1, 1 } do
			local tx = side * (length / 2 + 6)
			box(
				list,
				"Firework",
				tx - 0.5,
				tx + 0.5,
				FLOOR + 23,
				FLOOR + 24,
				z0 - 6.5,
				z0 - 5.5,
				LIGHT
			)
			list[#list].emitter = true
			list[#list].transparency = 1
		end
	end

	return list
end

return CourtPlan
