--!strict
-- The shape of the pitch for each stadium tier (docs/PLAN.md, Step 7), as plain data so it can be
-- unit tested. The five tiers are a street cage court, a walled F5 hall with a gate, a small stadium
-- with stands and a crowd, a bigger one with roofs and floodlights, and a full bowl arena. The server
-- builds these boxes under the plot (server/Stadium) and the client lifts them out of the ground
-- during the upgrade cinematic. Coordinates are in plot space: x across the plot, z from the street
-- gate (0) towards the back, y up from the ground reference.

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
	text: string?, -- drawn on one face of the part (signs, the scoreboard)
	face: string?, -- the face the text is on: "Left" (towards -x, the default), "Right" or "Front" (towards -z)
	textColor: { number }?, -- the colour of the text, gold when nil
	emitter: boolean, -- a firework launch point
}

local CourtPlan = {}

CourtPlan.CENTER_Z = 235 -- the middle of every pitch, in the stadium zone at the back of the plot
CourtPlan.FLOOR = 0.7 -- the walkable height of the pitch
-- The gate in the near wall, and the aisle between the near stands, reach this far each side of x 0.
CourtPlan.GATE_HALF = 7
CourtPlan.FRONT_Z = 175 -- nothing of the pitch comes closer to the gate than this (the pad stands here)

local FLOOR = CourtPlan.FLOOR
local CENTER_Z = CourtPlan.CENTER_Z
local GATE_HALF = CourtPlan.GATE_HALF

-- Colours (r, g, b from 0 to 255).
local LINE = { 240, 240, 240 }
local RUBBER = { 58, 128, 92 } -- tier 1, the cage floor
local TURF = { 64, 154, 82 } -- tier 2, artificial turf
local EVA = { 38, 92, 170 } -- the blue border of the F5 hall
local GRASS = { 58, 138, 62 }
local GRASS_LIGHT = { 68, 154, 72 } -- the mown stripes
local MESH = { 70, 76, 86 }
local STEEL = { 82, 88, 100 }
local WALL = { 232, 232, 236 }
local WALL_BAND = { 38, 92, 170 }
local KICKBOARD = { 150, 150, 156 }
local CONCRETE = { 168, 168, 174 }
local SEAT_A = { 32, 72, 150 }
local SEAT_B = { 150, 32, 62 }
local LIGHT = { 255, 244, 214 }
local ROOF = { 226, 229, 236 }
local BOARD = { 25, 25, 30 }
local GOAL = { 245, 245, 245 }
local FLAG = { 240, 200, 60 }
local WOOD = { 150, 120, 90 }
local ADS = { { 200, 50, 60 }, { 30, 110, 200 }, { 240, 190, 50 }, { 40, 150, 90 } }
local MURAL_A = { 240, 140, 60 }
local MURAL_B = { 90, 190, 120 }
local WHITE = { 255, 255, 255 }
local GOLD = { 255, 220, 60 }
local FANS = {
	{ 230, 90, 90 },
	{ 90, 140, 230 },
	{ 240, 200, 70 },
	{ 120, 200, 130 },
	{ 230, 230, 235 },
	{ 190, 110, 220 },
}

local STAND_DEPTH = 3 -- each stand row is this deep
local STAND_RISE = 1.6 -- and this much higher than the row before
local FAN_STEP = 3.2 -- studs between two fans on a row

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
		face = nil,
		textColor = nil,
		emitter = false,
	})
end

-- A dark board with a line of text on one face.
local function sign(
	list: { PartSpec },
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	text: string,
	face: string,
	textColor: { number }?
)
	box(list, name, x0, x1, y0, y1, z0, z1, BOARD)
	local part = list[#list]
	part.text = text
	part.face = face
	part.textColor = textColor
end

-- Four walls round a rectangle (`l`, `r` along x, `n`, `f` along z; n is the near side, the one with
-- the gate). `gateHalf` > 0 opens the near wall that far each side of x 0.
local function perimeter(
	list: { PartSpec },
	name: string,
	l: number,
	r: number,
	n: number,
	f: number,
	y0: number,
	y1: number,
	thick: number,
	color: { number },
	material: string?,
	transparency: number?,
	gateHalf: number
)
	local h = thick / 2
	if gateHalf > 0 then
		box(
			list,
			name .. "NearA",
			l - h,
			-gateHalf,
			y0,
			y1,
			n - h,
			n + h,
			color,
			material,
			transparency
		)
		box(
			list,
			name .. "NearB",
			gateHalf,
			r + h,
			y0,
			y1,
			n - h,
			n + h,
			color,
			material,
			transparency
		)
	else
		box(list, name .. "Near", l - h, r + h, y0, y1, n - h, n + h, color, material, transparency)
	end
	box(list, name .. "Far", l - h, r + h, y0, y1, f - h, f + h, color, material, transparency)
	box(list, name .. "Left", l - h, l + h, y0, y1, n - h, f + h, color, material, transparency)
	box(list, name .. "Right", r - h, r + h, y0, y1, n - h, f + h, color, material, transparency)
end

-- Thin posts along the same four sides, about `step` apart, none inside the gate.
local function posts(
	list: { PartSpec },
	name: string,
	l: number,
	r: number,
	n: number,
	f: number,
	y1: number,
	step: number,
	gateHalf: number
)
	local function post(x: number, z: number)
		box(list, name, x - 0.25, x + 0.25, FLOOR, y1, z - 0.25, z + 0.25, STEEL, "Metal")
	end
	local across = math.max(1, math.ceil((r - l) / step))
	for i = 0, across do
		local x = l + (r - l) * i / across
		post(x, f)
		if gateHalf <= 0 or math.abs(x) > gateHalf + 0.5 then
			post(x, n)
		end
	end
	if gateHalf > 0 then
		post(-gateHalf, n)
		post(gateHalf, n)
	end
	local along = math.max(1, math.ceil((f - n) / step))
	for i = 1, along - 1 do
		local z = n + (f - n) * i / along
		post(l, z)
		post(r, z)
	end
end

-- Low advertising boards in alternating colours round the pitch, none in the gate.
local function adBoards(list: { PartSpec }, l: number, r: number, n: number, f: number)
	local count = 0
	local function board(x0: number, x1: number, z0: number, z1: number)
		count += 1
		box(list, "AdBoard", x0, x1, FLOOR, FLOOR + 1.4, z0, z1, ADS[count % #ADS + 1])
	end
	local step = 8
	local x = l
	while x < r - 0.1 do
		local xb = math.min(x + step, r)
		board(x, xb, f - 0.3, f + 0.3)
		if xb <= -GATE_HALF or x >= GATE_HALF then
			board(x, xb, n - 0.3, n + 0.3)
		end
		x = xb
	end
	local z = n
	while z < f - 0.1 do
		local zb = math.min(z + step, f)
		board(l - 0.3, l + 0.3, z, zb)
		board(r - 0.3, r + 0.3, z, zb)
		z = zb
	end
end

-- A tall mast with a lamp head on top.
local function mast(list: { PartSpec }, x: number, z: number, height: number)
	box(
		list,
		"LightPole",
		x - 0.5,
		x + 0.5,
		FLOOR,
		FLOOR + height,
		z - 0.5,
		z + 0.5,
		STEEL,
		"Metal"
	)
	box(
		list,
		"LightHead",
		x - 2.5,
		x + 2.5,
		FLOOR + height,
		FLOOR + height + 2.4,
		z - 0.6,
		z + 0.6,
		LIGHT,
		"Neon"
	)
end

-- The two goal frames with their nets. `width` is the opening along z, `height` the bar.
local function goals(list: { PartSpec }, length: number, width: number, height: number)
	local post = 0.5
	local half = width / 2
	local deep = 3.5 -- how far the net goes behind the line
	local top = FLOOR + height
	for _, side in { -1, 1 } do
		local gx = side * (length / 2)
		local nx0, nx1 = math.min(gx, gx + side * deep), math.max(gx, gx + side * deep)
		local zA, zB = CENTER_Z - half, CENTER_Z + half
		box(list, "GoalPostA", gx - post / 2, gx + post / 2, FLOOR, top, zA, zA + post, GOAL)
		box(list, "GoalPostB", gx - post / 2, gx + post / 2, FLOOR, top, zB - post, zB, GOAL)
		box(list, "GoalBar", gx - post / 2, gx + post / 2, top - post, top, zA, zB, GOAL)
		-- The net: back, two sides and top, see-through.
		local back = gx + side * deep
		box(list, "GoalNet", back - 0.05, back + 0.05, FLOOR, top, zA, zB, WHITE, nil, 0.7)
		box(list, "GoalNet", nx0, nx1, FLOOR, top, zA - 0.05, zA + 0.05, WHITE, nil, 0.7)
		box(list, "GoalNet", nx0, nx1, FLOOR, top, zB - 0.05, zB + 0.05, WHITE, nil, 0.7)
		box(list, "GoalNet", nx0, nx1, top - 0.05, top + 0.05, zA, zB, WHITE, nil, 0.7)
	end
end

-- A block of seating rows stepping up away from the pitch. `axis` "z" has the rows one behind the
-- other along z (`sign` 1 away from the pitch to +z, -1 to -z) and the stand spans x a0..a1; axis "x"
-- is the same turned a quarter. A fan stands on every row where (row + fanOffset) % fanEvery == 0.
local function stand(
	list: { PartSpec },
	axis: string,
	dir: number,
	start: number,
	rows: number,
	a0: number,
	a1: number,
	fanEvery: number,
	fanOffset: number
)
	for row = 0, rows - 1 do
		local inner = start + dir * row * STAND_DEPTH
		local outer = inner + dir * STAND_DEPTH
		local lo, hi = math.min(inner, outer), math.max(inner, outer)
		local top = FLOOR + STAND_RISE * (row + 1)
		local seat0, seat1 = inner + dir * 0.3, inner + dir * 2.5
		local seatLo, seatHi = math.min(seat0, seat1), math.max(seat0, seat1)
		local seatColor = if row % 2 == 0 then SEAT_A else SEAT_B
		if axis == "z" then
			box(list, "StandRow", a0, a1, FLOOR, top, lo, hi, CONCRETE, "Concrete")
			box(list, "StandSeats", a0, a1, top, top + 0.25, seatLo, seatHi, seatColor)
		else
			box(list, "StandRow", lo, hi, FLOOR, top, a0, a1, CONCRETE, "Concrete")
			box(list, "StandSeats", seatLo, seatHi, top, top + 0.25, a0, a1, seatColor)
		end
		if fanEvery > 0 and (row + fanOffset) % fanEvery == 0 then
			local across = inner + dir * 1.4
			local along = a0 + 1.6
			local k = 0
			while along < a1 - 1 do
				k += 1
				if (row * 7 + k * 3) % 5 ~= 0 then
					local palette = FANS[(row + k) % #FANS + 1]
					local y0, y1 = top + 0.25, top + 1.95
					if axis == "z" then
						box(
							list,
							"Fan",
							along - 0.55,
							along + 0.55,
							y0,
							y1,
							across - 0.5,
							across + 0.5,
							palette
						)
					else
						box(
							list,
							"Fan",
							across - 0.5,
							across + 0.5,
							y0,
							y1,
							along - 0.55,
							along + 0.55,
							palette
						)
					end
				end
				along += FAN_STEP
			end
		end
	end
end

-- A flat roof over a stand with pillars at the back, same axes as `stand`. `y` is the underside
-- above the pitch floor.
local function canopy(
	list: { PartSpec },
	axis: string,
	dir: number,
	start: number,
	rows: number,
	y: number,
	a0: number,
	a1: number
)
	local back = start + dir * rows * STAND_DEPTH
	local front = start - dir * 2 -- the roof reaches a little over the first row
	local lo, hi = math.min(front, back + dir), math.max(front, back + dir)
	local pillars = math.max(2, math.ceil((a1 - a0) / 24))
	if axis == "z" then
		box(list, "Roof", a0 - 1, a1 + 1, FLOOR + y, FLOOR + y + 0.8, lo, hi, ROOF)
		for i = 0, pillars do
			local x = a0 + (a1 - a0) * i / pillars
			box(
				list,
				"RoofPillar",
				x - 0.5,
				x + 0.5,
				FLOOR,
				FLOOR + y,
				back - 0.5,
				back + 0.5,
				STEEL,
				"Metal"
			)
		end
	else
		box(list, "Roof", lo, hi, FLOOR + y, FLOOR + y + 0.8, a0 - 1, a1 + 1, ROOF)
		for i = 0, pillars do
			local z = a0 + (a1 - a0) * i / pillars
			box(
				list,
				"RoofPillar",
				back - 0.5,
				back + 0.5,
				FLOOR,
				FLOOR + y,
				z - 0.5,
				z + 0.5,
				STEEL,
				"Metal"
			)
		end
	end
end

-- The entrance arch over the gate in the near wall, with a sign facing the player on the path.
local function arch(list: { PartSpec }, z: number, text: string, height: number)
	for _, side in { -1, 1 } do
		local x = side * GATE_HALF
		box(
			list,
			"GatePillar",
			x - 0.7,
			x + 0.7,
			FLOOR,
			FLOOR + height,
			z - 0.7,
			z + 0.7,
			STEEL,
			"Metal"
		)
	end
	sign(
		list,
		"GateSign",
		-GATE_HALF - 1.5,
		GATE_HALF + 1.5,
		FLOOR + height - 3,
		FLOOR + height,
		z - 0.5,
		z + 0.5,
		text,
		"Front",
		WHITE
	)
	-- The club crest on top of the sign, painted with the Locker room crest (shared/StadiumLook).
	sign(
		list,
		"Crest",
		-2.2,
		2.2,
		FLOOR + height,
		FLOOR + height + 4.4,
		z - 0.4,
		z + 0.4,
		"ST",
		"Front",
		WHITE
	)
end

-- All the parts of the pitch of `tier` (1 to 5).
function CourtPlan.parts(tier: number): { PartSpec }
	local index = clamp(math.floor(tier), 1, #Config.StadiumTiers)
	local def = Config.StadiumTiers[index]
	local length, width = def.courtLength, def.courtWidth
	local x0, x1 = -length / 2, length / 2
	local z0, z1 = CENTER_Z - width / 2, CENTER_Z + width / 2
	local list: { PartSpec } = {}
	local surfaceColor = if index == 1 then RUBBER elseif index == 2 then TURF else GRASS

	-- The court itself: surface, mown stripes, lines, centre circle (every tier).
	box(list, "Surface", x0, x1, FLOOR - 0.2, FLOOR, z0, z1, surfaceColor)
	if index >= 3 then
		local stripes = math.floor(length / 7)
		local w = length / stripes
		for i = 1, stripes - 1, 2 do
			box(
				list,
				"Stripe",
				x0 + i * w,
				x0 + (i + 1) * w,
				FLOOR,
				FLOOR + 0.02,
				z0,
				z1,
				GRASS_LIGHT
			)
		end
	end
	local lineY0, lineY1 = FLOOR + 0.02, FLOOR + 0.07
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
		surfaceColor
	)
	list[#list - 1].cylinder = true
	list[#list].cylinder = true

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
	end

	-- Goals: small ones in the cage and the hall, full size from tier 3.
	goals(list, length, if index <= 2 then 8 else 10, if index <= 2 then 4 else 5)

	if index >= 3 then
		for _, side in { -1, 1 } do
			for _, fz in { z0, z1 } do
				local fx = side * (length / 2)
				box(
					list,
					"FlagPole",
					fx - 0.15,
					fx + 0.15,
					FLOOR,
					FLOOR + 4.5,
					fz - 0.15,
					fz + 0.15,
					STEEL
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
	end

	if index == 1 then
		-- Tier 1, the street cage: a chain-link fence round the court on a low concrete kickboard,
		-- an opening in the near side, a lamp at each near corner, a bench and painted boards.
		local o = 3
		local l, r, n, f = x0 - o, x1 + o, z0 - o, z1 + o
		perimeter(
			list,
			"Kickboard",
			l,
			r,
			n,
			f,
			FLOOR,
			FLOOR + 1.2,
			0.5,
			KICKBOARD,
			"Concrete",
			0,
			GATE_HALF
		)
		perimeter(
			list,
			"Mesh",
			l,
			r,
			n,
			f,
			FLOOR + 1.2,
			FLOOR + 8,
			0.15,
			MESH,
			"SmoothPlastic",
			0.55,
			GATE_HALF
		)
		perimeter(
			list,
			"TopRail",
			l,
			r,
			n,
			f,
			FLOOR + 8,
			FLOOR + 8.4,
			0.4,
			STEEL,
			"Metal",
			0,
			GATE_HALF
		)
		posts(list, "FencePost", l, r, n, f, FLOOR + 8.4, 5, GATE_HALF)
		sign(
			list,
			"GateSign",
			-GATE_HALF,
			GATE_HALF,
			FLOOR + 8.8,
			FLOOR + 11.2,
			n - 0.3,
			n + 0.3,
			"STREET CAGE",
			"Front",
			WHITE
		)
		for _, side in { -1, 1 } do
			local lx = side * (length / 2 + o + 2)
			box(
				list,
				"LampPole",
				lx - 0.4,
				lx + 0.4,
				FLOOR,
				FLOOR + 13,
				n - 2.4,
				n - 1.6,
				STEEL,
				"Metal"
			)
			box(
				list,
				"LampHead",
				lx - 1.8,
				lx + 1.8,
				FLOOR + 13,
				FLOOR + 14.2,
				n - 2.8,
				n - 1.2,
				LIGHT,
				"Neon"
			)
		end
		box(list, "BenchSeat", 12, 24, FLOOR, FLOOR + 1.1, n - 3, n - 1, WOOD, "Wood")
		box(list, "BenchBack", 12, 24, FLOOR + 1.1, FLOOR + 2.6, n - 3, n - 2.6, WOOD, "Wood")
		for side, colour in { [-1] = MURAL_A, [1] = MURAL_B } do
			local mx = side * (length / 2 + o + 1.5)
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
	elseif index == 2 then
		-- Tier 2, the F5 hall: a blue border of EVA round the turf, white walls with a blue band, a net
		-- above them, a gate in the near wall under an arch, benches and a board over the far wall.
		local o = 4
		local l, r, n, f = x0 - o, x1 + o, z0 - o, z1 + o
		box(list, "Apron", x0 - 3, x1 + 3, 0.5, 0.65, z0 - 3, z1 + 3, EVA)
		perimeter(list, "Wall", l, r, n, f, FLOOR, FLOOR + 5, 0.8, WALL, "Concrete", 0, GATE_HALF)
		perimeter(
			list,
			"Band",
			l,
			r,
			n,
			f,
			FLOOR,
			FLOOR + 1.6,
			1,
			WALL_BAND,
			"Concrete",
			0,
			GATE_HALF
		)
		perimeter(
			list,
			"Net",
			l,
			r,
			n,
			f,
			FLOOR + 5,
			FLOOR + 11,
			0.15,
			MESH,
			"SmoothPlastic",
			0.55,
			GATE_HALF
		)
		posts(list, "NetPost", l, r, n, f, FLOOR + 11, 7, GATE_HALF)
		arch(list, n, "F5 ARENA", 12)
		box(list, "BenchSeat", -26, -14, FLOOR, FLOOR + 1.1, n + 1.2, n + 3.2, WOOD, "Wood")
		box(list, "BenchBack", -26, -14, FLOOR + 1.1, FLOOR + 2.6, n + 1.2, n + 1.6, WOOD, "Wood")
		sign(
			list,
			"Scoreboard",
			-9,
			9,
			FLOOR + 12,
			FLOOR + 15.5,
			f - 0.4,
			f + 0.4,
			"F5 ARENA",
			"Front",
			GOLD
		)
		for _, side in { -1, 1 } do
			mast(list, side * (length / 2 + o - 1), n + 0.5, 15)
		end
	else
		-- Tier 3 and up: advertising boards round the pitch, benches, an entrance arch and stands.
		local o = 5
		local l, r, n, f = x0 - o, x1 + o, z0 - o, z1 + o
		box(list, "Apron", x0 - 3, x1 + 3, 0.5, 0.65, z0 - 3, z1 + 3, surfaceColor)
		adBoards(list, l, r, n, f)
		arch(list, n, if index == 5 then "ARENA" else "STADIUM", 11)
		for _, side in { -1, 1 } do
			local bx0, bx1 = if side < 0 then -24 else 10, if side < 0 then -10 else 24
			box(list, "BenchSeat", bx0, bx1, FLOOR, FLOOR + 1.1, z0 - 3.5, z0 - 1.5, WOOD, "Wood")
			box(
				list,
				"BenchBack",
				bx0,
				bx1,
				FLOOR + 1.1,
				FLOOR + 2.6,
				z0 - 3.5,
				z0 - 3.1,
				WOOD,
				"Wood"
			)
		end

		if index == 3 then
			-- A small stadium: one stand behind the far touchline, two short ones on the near side.
			local reach = length / 2 + 6
			stand(list, "z", 1, z1 + 8, 5, -reach, reach, 1, 0)
			stand(list, "z", -1, z0 - 8, 4, -reach, -GATE_HALF - 1, 1, 0)
			stand(list, "z", -1, z0 - 8, 4, GATE_HALF + 1, reach, 1, 0)
			sign(
				list,
				"Scoreboard",
				-9,
				9,
				FLOOR + 10,
				FLOOR + 13.5,
				z1 + 6.6,
				z1 + 7.4,
				"HOME 0 - 0 AWAY",
				"Front",
				GOLD
			)
			box(
				list,
				"ScoreboardPostA",
				-8.5,
				-7.5,
				FLOOR,
				FLOOR + 10,
				z1 + 6.8,
				z1 + 7.2,
				STEEL,
				"Metal"
			)
			box(
				list,
				"ScoreboardPostB",
				7.5,
				8.5,
				FLOOR,
				FLOOR + 10,
				z1 + 6.8,
				z1 + 7.2,
				STEEL,
				"Metal"
			)
		elseif index == 4 then
			-- A bigger stadium: stands on every side, a roof over the main one, floodlights.
			local reach = length / 2 + 8
			stand(list, "z", 1, z1 + 8, 6, -reach, reach, 1, 0)
			canopy(list, "z", 1, z1 + 8, 6, 14, -reach, reach)
			stand(list, "z", -1, z0 - 8, 4, -reach, -GATE_HALF - 1, 2, 0)
			stand(list, "z", -1, z0 - 8, 4, GATE_HALF + 1, reach, 2, 0)
			stand(list, "x", 1, x1 + 8, 4, z0, z1, 2, 1)
			stand(list, "x", -1, x0 - 8, 4, z0, z1, 2, 1)
			sign(
				list,
				"Scoreboard",
				-12,
				12,
				FLOOR + 10,
				FLOOR + 14,
				z1 + 6.6,
				z1 + 7.4,
				"SOCCER TYCOON",
				"Front",
				GOLD
			)
			for _, side in { -1, 1 } do
				for _, mz in { z0 - 6, z1 + 6 } do
					mast(list, side * (length / 2 + 6), mz, 24)
				end
			end
		else
			-- Tier 5, the arena: a full bowl of stands with roofs all round, big screens, tall masts.
			local nearStart, farStart = z0 - 5, z1 + 6
			local sideX = x1 + 6
			stand(list, "z", 1, farStart, 6, -sideX, sideX, 2, 0)
			canopy(list, "z", 1, farStart, 6, 15, -sideX, sideX)
			stand(list, "z", -1, nearStart, 5, -sideX, -GATE_HALF - 1, 2, 0)
			stand(list, "z", -1, nearStart, 5, GATE_HALF + 1, sideX, 2, 0)
			canopy(list, "z", -1, nearStart, 5, 12, -sideX, -GATE_HALF - 1)
			canopy(list, "z", -1, nearStart, 5, 12, GATE_HALF + 1, sideX)
			local endLo, endHi = nearStart - 5 * STAND_DEPTH, farStart + 6 * STAND_DEPTH
			stand(list, "x", 1, sideX, 8, endLo, endHi, 2, 1)
			stand(list, "x", -1, -sideX, 8, endLo, endHi, 2, 1)
			canopy(list, "x", 1, sideX, 8, 17, endLo, endHi)
			canopy(list, "x", -1, -sideX, 8, 17, endLo, endHi)
			sign(
				list,
				"Scoreboard",
				-18,
				18,
				FLOOR + 9,
				FLOOR + 14,
				farStart - 2.4,
				farStart - 1.6,
				"SOCCER TYCOON ARENA",
				"Front",
				GOLD
			)
			for _, screen in
				{
					{ x = sideX - 2.2, face = "Left" },
					{ x = -sideX + 2.2, face = "Right" },
				}
			do
				sign(
					list,
					"Screen",
					screen.x - 0.4,
					screen.x + 0.4,
					FLOOR + 12,
					FLOOR + 16.5,
					CENTER_Z - 9,
					CENTER_Z + 9,
					"GOAL",
					screen.face,
					WHITE
				)
			end
			local mastX = sideX + 8 * STAND_DEPTH + 5
			for _, side in { -1, 1 } do
				for _, mz in { endLo - 3, endHi + 1.5 } do
					mast(list, side * mastX, mz, 34)
				end
				-- Fireworks launch from the two near masts.
				box(
					list,
					"Firework",
					side * mastX - 0.5,
					side * mastX + 0.5,
					FLOOR + 37,
					FLOOR + 38,
					endLo - 3.5,
					endLo - 2.5,
					LIGHT
				)
				list[#list].emitter = true
				list[#list].transparency = 1
			end
		end
	end

	return list
end

return CourtPlan
