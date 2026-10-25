--!strict
-- The shape of the pitch for each stadium tier (docs/PLAN.md, Step 7), as plain data so it can be
-- unit tested. The six tiers are a street cage court, a walled F5 hall with a gate, a small stadium
-- with stands and a crowd, a bigger one with roofs, a full bowl arena with lamps round its roofs, and
-- the same bowl under a retractable roof. Every tier has floodlight masts; the model on them is the
-- player's Locker room choice (LED light, twin panels, lamp bank, towers, halo). The server
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
	shape: string?, -- "wedge" (the slope faces the front, -z before turning) or "disc" (a round face to the front)
	yaw: number?, -- degrees round the vertical; with a yaw or tilt the box is the part's own size round its centre
	tilt: number?, -- degrees, after the yaw: below 0 the front looks down
	image: string?, -- an image on `face` instead of text (the crest), set by the Locker room style
	slide: { number }?, -- a retractable roof panel: how far it moves (x, y, z) from open to closed
	lamp: boolean?, -- part of a floodlight on a mast (the Locker room swaps the model)
	solid: boolean?, -- players cannot walk through it: the walls, fences, stands and roof pillars
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
local HALO = { 150, 90, 220 } -- the frame of the halo floodlight
local ROOF_PANEL = { 190, 220, 248 } -- the retractable roof, a light blue so it reads apart from the ring
local BOARD = { 25, 25, 30 }
local GOAL = { 245, 245, 245 }
local FLAG = { 240, 200, 60 }
local WOOD = { 150, 120, 90 }
local ADS = { { 200, 50, 60 }, { 30, 110, 200 }, { 240, 190, 50 }, { 40, 150, 90 } }
-- Made-up sponsors on the boards (never real brands); the Locker room banner sets change them.
local BRANDS = { "VOLTA", "FIZZUP", "ZOOMR", "PIXEL" }
local PANEL = { 32, 38, 56 } -- the dark backs of the lamps
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

-- Marks every part added since `first` as solid (players bump into it).
local function solidFrom(list: { PartSpec }, first: number)
	for i = first, #list do
		list[i].solid = true
	end
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

-- A part turned by `yaw` and `tilt` (degrees), centred on (cx, cy, cz) with its own size sx, sy, sz.
local function turned(
	list: { PartSpec },
	name: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	yaw: number,
	tilt: number,
	color: { number },
	material: string?,
	shape: string?
): PartSpec
	box(
		list,
		name,
		cx - sx / 2,
		cx + sx / 2,
		cy - sy / 2,
		cy + sy / 2,
		cz - sz / 2,
		cz + sz / 2,
		color,
		material
	)
	local spec = list[#list]
	spec.yaw = yaw
	spec.tilt = tilt
	spec.shape = shape
	return spec
end

-- Where the point (x, y, z) of a part turned by `yaw` then `tilt` ends up, from the part's centre.
local function rotate(
	yaw: number,
	tilt: number,
	x: number,
	y: number,
	z: number
): (number, number, number)
	local t, a = math.rad(tilt), math.rad(yaw)
	local y1, z1 = y * math.cos(t) - z * math.sin(t), y * math.sin(t) + z * math.cos(t)
	return x * math.cos(a) + z1 * math.sin(a), y1, -x * math.sin(a) + z1 * math.cos(a)
end

-- The yaw that turns a part's front (-z) along the direction (dx, dz).
local function aim(dx: number, dz: number): number
	return math.deg(math.atan2(-dx, -dz))
end

-- The yaw from (x, z) to the middle of the pitch.
local function aimAtPitch(x: number, z: number): number
	return aim(-x, CENTER_Z - z)
end

-- A flat LED flood panel: a dark back and a glowing face, turned to `yaw` and tilted down.
local function floodPanel(
	list: { PartSpec },
	cx: number,
	cy: number,
	cz: number,
	yaw: number,
	tilt: number,
	w: number,
	h: number
)
	turned(list, "LightFrame", cx, cy, cz, w, h, 0.5, yaw, tilt, PANEL)
	local dx, dy, dz = rotate(yaw, tilt, 0, 0, -0.3)
	turned(
		list,
		"LightHead",
		cx + dx,
		cy + dy,
		cz + dz,
		w - 0.5,
		h - 0.5,
		0.1,
		yaw,
		tilt,
		LIGHT,
		"Neon"
	)
end

-- A round lamp: a grey rim and a glowing face.
local function roundLamp(
	list: { PartSpec },
	cx: number,
	cy: number,
	cz: number,
	yaw: number,
	tilt: number,
	size: number
)
	turned(
		list,
		"LightFrame",
		cx,
		cy,
		cz,
		size + 0.35,
		size + 0.35,
		0.5,
		yaw,
		tilt,
		STEEL,
		nil,
		"disc"
	)
	local dx, dy, dz = rotate(yaw, tilt, 0, 0, -0.3)
	turned(
		list,
		"LightHead",
		cx + dx,
		cy + dy,
		cz + dz,
		size,
		size,
		0.1,
		yaw,
		tilt,
		LIGHT,
		"Neon",
		"disc"
	)
end

local function pole(list: { PartSpec }, x: number, z: number, height: number, thick: number)
	local h = thick / 2
	box(list, "LightPole", x - h, x + h, FLOOR, FLOOR + height, z - h, z + h, STEEL)
end

-- Tier 1: a street light, a square pole with a short arm and one LED panel looking down at the court.
local function streetLight(list: { PartSpec }, x: number, z: number, height: number)
	local yaw = aimAtPitch(x, z)
	pole(list, x, z, height, 0.8)
	local top = FLOOR + height
	local ax, _, az = rotate(yaw, 0, 0, 0, -1.2)
	turned(list, "LightArm", x + ax, top - 0.3, z + az, 0.5, 0.5, 2.4, yaw, 0, STEEL)
	local px, _, pz = rotate(yaw, 0, 0, 0, -2.8)
	floodPanel(list, x + px, top - 0.6, z + pz, yaw, -55, 3.4, 2.6)
end

-- Tier 2: a pole with a crossbar and two flood panels side by side, turned a little apart.
local function twinLight(list: { PartSpec }, x: number, z: number, height: number)
	local yaw = aimAtPitch(x, z)
	pole(list, x, z, height, 0.8)
	local top = FLOOR + height
	turned(list, "LightArm", x, top + 0.2, z, 6, 0.4, 0.4, yaw, 0, STEEL)
	for _, side in { -1, 1 } do
		local px, _, pz = rotate(yaw, 0, side * 1.9, 0, -0.7)
		floodPanel(list, x + px, top + 1.2, z + pz, yaw - side * 14, -30, 3, 2.4)
	end
end

-- Tier 3: a pole with a bank of round lamps on two bars, seven on top and five under them.
local function lampBank(list: { PartSpec }, x: number, z: number, height: number)
	local yaw = aimAtPitch(x, z)
	pole(list, x, z, height, 0.8)
	local top = FLOOR + height
	for _, row in { { y = 2.4, count = 7 }, { y = 0.7, count = 5 } } do
		turned(list, "LightArm", x, top + row.y, z, row.count * 1.75 + 0.4, 0.3, 0.3, yaw, 0, STEEL)
		for i = 1, row.count do
			local lx = (i - (row.count + 1) / 2) * 1.75
			local px, _, pz = rotate(yaw, 0, lx, 0, -0.6)
			roundLamp(list, x + px, top + row.y, z + pz, yaw, -20, 1.4)
		end
	end
end

-- A tall tower with a square frame of `size` by `size` round lamps, in `frame` colour.
local function gridTower(
	list: { PartSpec },
	x: number,
	z: number,
	height: number,
	size: number,
	frame: { number }
)
	local yaw = aimAtPitch(x, z)
	local tilt = -15
	local half = size * 2.05 / 2 + 0.25
	box(list, "LightPole", x - 0.6, x + 0.6, FLOOR, FLOOR + height, z - 0.6, z + 0.6, frame)
	local cy = FLOOR + height + half
	turned(list, "LightArm", x, cy, z, half * 2, half * 2, 0.5, yaw, tilt, frame)
	local middle = (size + 1) / 2
	for row = 1, size do
		for col = 1, size do
			local px, py, pz =
				rotate(yaw, tilt, (col - middle) * 2.05, (row - middle) * 2.05, -0.35)
			turned(
				list,
				"LightHead",
				x + px,
				cy + py,
				z + pz,
				1.7,
				1.7,
				0.3,
				yaw,
				tilt,
				LIGHT,
				"Neon",
				"disc"
			)
		end
	end
end

local function lampTower(list: { PartSpec }, x: number, z: number, height: number)
	gridTower(list, x, z, height, 4, STEEL)
end

local function arenaTower(list: { PartSpec }, x: number, z: number, height: number)
	gridTower(list, x, z, height, 5, STEEL)
end

local function goldTower(list: { PartSpec }, x: number, z: number, height: number)
	gridTower(list, x, z, height, 5, GOLD)
end

-- A pole with a round purple frame, eight lamps round its rim and one in the middle.
local function halo(list: { PartSpec }, x: number, z: number, height: number)
	local yaw = aimAtPitch(x, z)
	local tilt = -15
	pole(list, x, z, height, 0.9)
	local cy = FLOOR + height + 3.2
	turned(list, "LightArm", x, cy, z, 6.6, 6.6, 0.5, yaw, tilt, HALO, nil, "disc")
	for i = 0, 8 do
		local lx, ly = 0, 0
		if i > 0 then
			local angle = (i - 1) * math.pi / 4
			lx, ly = math.cos(angle) * 2.3, math.sin(angle) * 2.3
		end
		local px, py, pz = rotate(yaw, tilt, lx, ly, -0.35)
		turned(
			list,
			"LightHead",
			x + px,
			cy + py,
			z + pz,
			1.5,
			1.5,
			0.3,
			yaw,
			tilt,
			LIGHT,
			"Neon",
			"disc"
		)
	end
end

-- The floodlight models the Locker room sells (Config, slot "lamps"), by id.
local LAMPS: { [string]: (list: { PartSpec }, x: number, z: number, height: number) -> () } = {
	led = streetLight,
	twin = twinLight,
	bank = lampBank,
	tower = lampTower,
	arena = arenaTower,
	gold = goldTower,
	halo = halo,
}
CourtPlan.LAMP_MODELS = { "led", "twin", "bank", "tower", "arena", "gold", "halo" }

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
	local first = #list + 1
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
	solidFrom(list, first)
end

-- Invisible walls 2 studs thick along a thin fence or net (the same four sides, the gate open): a
-- fast jumping character slips into a thin part and is flung over it, a thick one stops it.
local function blockers(list: { PartSpec }, l: number, r: number, n: number, f: number)
	perimeter(list, "Blocker", l, r, n, f, FLOOR, FLOOR + 14, 2, STEEL, nil, 1, GATE_HALF)
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
		list[#list].solid = true
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

-- Low sponsor boards round the pitch, none in the gate: wedges lying on the grass with the sloped
-- face, and the sponsor's name on it, towards the pitch.
local function adBoards(list: { PartSpec }, l: number, r: number, n: number, f: number)
	local count = 0
	local function board(cx: number, cz: number, length: number, facing: number)
		count += 1
		local color = ADS[count % #ADS + 1]
		local spec = turned(
			list,
			"AdBoard",
			cx,
			FLOOR + 0.8,
			cz,
			length,
			1.6,
			1.6,
			facing,
			0,
			color,
			nil,
			"wedge"
		)
		spec.text = BRANDS[count % #BRANDS + 1]
		spec.face = "Front"
		spec.textColor = WHITE
	end
	local step = 8
	local x = l
	while x < r - 0.1 do
		local xb = math.min(x + step, r)
		board((x + xb) / 2, f - 0.5, xb - x, aim(0, -1))
		if xb <= -GATE_HALF or x >= GATE_HALF then
			board((x + xb) / 2, n + 0.5, xb - x, aim(0, 1))
		end
		x = xb
	end
	local z = n
	while z < f - 0.1 do
		local zb = math.min(z + step, f)
		board(l + 0.5, (z + zb) / 2, zb - z, aim(1, 0))
		board(r - 0.5, (z + zb) / 2, zb - z, aim(-1, 0))
		z = zb
	end
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
		local first = #list + 1
		if axis == "z" then
			box(list, "StandRow", a0, a1, FLOOR, top, lo, hi, CONCRETE, "Concrete")
			box(list, "StandSeats", a0, a1, top, top + 0.25, seatLo, seatHi, seatColor)
		else
			box(list, "StandRow", lo, hi, FLOOR, top, a0, a1, CONCRETE, "Concrete")
			box(list, "StandSeats", seatLo, seatHi, top, top + 0.25, a0, a1, seatColor)
		end
		solidFrom(list, first)
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
	a1: number,
	lights: boolean
)
	local back = start + dir * rows * STAND_DEPTH
	local front = start - dir * 2 -- the roof reaches a little over the first row
	local lo, hi = math.min(front, back + dir), math.max(front, back + dir)
	local pillars = math.max(2, math.ceil((a1 - a0) / 24))
	if lights then
		-- A row of round lamps under the front edge, looking down at the pitch (one part each, there
		-- are many).
		local count = math.max(1, math.floor((a1 - a0) / 10))
		for i = 1, count do
			local along = a0 + (a1 - a0) * (i - 0.5) / count
			local across = front + dir * 1.2
			local cx, cz, yaw = along, across, aim(0, -dir)
			if axis == "x" then
				cx, cz, yaw = across, along, aim(-dir, 0)
			end
			turned(
				list,
				"LightHead",
				cx,
				FLOOR + y - 0.6,
				cz,
				1.5,
				1.5,
				0.3,
				yaw,
				-50,
				LIGHT,
				"Neon",
				"disc"
			)
		end
	end
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
			list[#list].solid = true
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
			list[#list].solid = true
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
	-- The club crest on top of the sign: the Locker room crest's image on a see-through board
	-- (shared/StadiumLook).
	box(
		list,
		"Crest",
		-2.8,
		2.8,
		FLOOR + height,
		FLOOR + height + 5.6,
		z - 0.2,
		z + 0.2,
		WHITE,
		nil,
		1
	)
	list[#list].image = ""
	list[#list].face = "Front"
end

-- Where the floodlight masts of `tier` stand: x, z and the height of the pole.
local function lampSites(index: number): { { x: number, z: number, height: number } }
	local def = Config.StadiumTiers[index]
	local length, width = def.courtLength, def.courtWidth
	local z0, z1 = CENTER_Z - width / 2, CENTER_Z + width / 2
	local sites = {}
	for _, side in { -1, 1 } do
		if index == 1 then
			table.insert(sites, { x = side * (length / 2 + 5), z = z0 - 5, height = 13 })
		elseif index == 2 then
			table.insert(sites, { x = side * (length / 2 + 3), z = z0 - 3.5, height = 15 })
		elseif index == 3 then
			for _, z in { z0 - 4, z1 + 4 } do
				table.insert(sites, { x = side * (length / 2 + 10), z = z, height = 18 })
			end
		elseif index == 4 then
			for _, z in { z0 - 6, z1 + 6 } do
				table.insert(sites, { x = side * (length / 2 + 6), z = z, height = 22 })
			end
		else
			-- Outside the bowl, at its corners.
			local x = length / 2 + 6 + 8 * STAND_DEPTH + 5
			for _, z in { z0 - 5 - 5 * STAND_DEPTH + 2, z1 + 6 + 6 * STAND_DEPTH - 3 } do
				table.insert(sites, { x = side * x, z = z, height = 26 })
			end
		end
	end
	return sites
end

-- The floodlights of `tier` in `model` (an id of CourtPlan.LAMP_MODELS; an unknown one is the LED).
function CourtPlan.lamps(tier: number, model: string?): { PartSpec }
	local index = clamp(math.floor(tier), 1, #Config.StadiumTiers)
	local build = LAMPS[model or "led"] or LAMPS.led
	local list: { PartSpec } = {}
	for _, site in lampSites(index) do
		build(list, site.x, site.z, site.height)
	end
	for _, spec in list do
		spec.lamp = true
	end
	return list
end

-- All the parts of the pitch of `tier` (1 to 6), with the floodlights in `model`.
function CourtPlan.parts(tier: number, model: string?): { PartSpec }
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
		blockers(list, l, r, n, f)
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
		blockers(list, l, r, n, f)
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
	else
		-- Tier 3 and up: advertising boards round the pitch, benches, an entrance arch and stands.
		local o = 5
		local l, r, n, f = x0 - o, x1 + o, z0 - o, z1 + o
		box(list, "Apron", x0 - 3, x1 + 3, 0.5, 0.65, z0 - 3, z1 + 3, surfaceColor)
		adBoards(list, l, r, n, f)
		-- The roof arena has no arch: its name and crest stand on its front, outside (see `dome`).
		if index < 6 then
			arch(list, n, if index == 5 then "ARENA" else "STADIUM", 11)
		end
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
			canopy(list, "z", 1, z1 + 8, 6, 14, -reach, reach, false)
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
		else
			-- Tier 5, the arena: a full bowl of stands with roofs all round, lamps under the roofs, big
			-- screens. Tier 6 is the same bowl under one ring of roof, with a retractable roof over the
			-- pitch (open; the upgrade cinematic closes and opens it) and lamp towers outside.
			local dome = index >= 6
			local nearStart, farStart = z0 - 5, z1 + 6
			local sideX = x1 + 6
			local endLo, endHi = nearStart - 5 * STAND_DEPTH, farStart + 6 * STAND_DEPTH
			local farY, nearY, endY = 15, 12, 17
			-- Under one ring the long roofs stop where the end roofs begin, so no two roofs overlap.
			-- The end stands have fans on every third row (the arenas are the heaviest pitches).
			local inset, fans = 0, 3
			if dome then
				farY, nearY, endY, inset = 22, 22, 22, 3
			end
			stand(list, "z", 1, farStart, 6, -sideX, sideX, 2, 0)
			canopy(list, "z", 1, farStart, 6, farY, -sideX + inset, sideX - inset, true)
			stand(list, "z", -1, nearStart, 5, -sideX, -GATE_HALF - 1, 2, 0)
			stand(list, "z", -1, nearStart, 5, GATE_HALF + 1, sideX, 2, 0)
			canopy(list, "z", -1, nearStart, 5, nearY, -sideX + inset, -GATE_HALF - 1, true)
			canopy(list, "z", -1, nearStart, 5, nearY, GATE_HALF + 1, sideX - inset, true)
			stand(list, "x", 1, sideX, 8, endLo, endHi, fans, 1)
			stand(list, "x", -1, -sideX, 8, endLo, endHi, fans, 1)
			canopy(list, "x", 1, sideX, 8, endY, endLo, endHi, true)
			canopy(list, "x", -1, -sideX, 8, endY, endLo, endHi, true)
			if dome then
				-- The ring closes over the aisle to the gate (no pillars there).
				box(
					list,
					"Roof",
					-GATE_HALF - 2,
					GATE_HALF + 2,
					FLOOR + 22,
					FLOOR + 22.8,
					nearStart - 5 * STAND_DEPTH - 1,
					nearStart + 2,
					ROOF
				)
				-- The retractable roof: four panels a side, stacked open on the end roofs. Closed they
				-- cover the opening between the roofs (x -open..open, z nearEdge..farEdge).
				local open = sideX - 2
				local nearEdge, farEdge = nearStart + 2, farStart - 2
				local panelWidth = open / 4
				for _, side in { -1, 1 } do
					for k = 1, 4 do
						local closedA = side * (open - (k - 1) * panelWidth)
						local closedB = side * (open - k * panelWidth)
						local openA, openB = side * (open + 2), side * (open + 2 + panelWidth)
						local cx0 = math.min(closedA, closedB)
						local ox0, ox1 = math.min(openA, openB), math.max(openA, openB)
						local closedY = FLOOR + 22.8
						local openY = closedY + (k - 1) * 0.7
						box(
							list,
							"RoofPanel",
							ox0,
							ox1,
							openY,
							openY + 0.6,
							nearEdge,
							farEdge,
							ROOF_PANEL
						)
						list[#list].slide = { cx0 - ox0, closedY - openY, 0 }
					end
				end
			end
			if dome then
				-- The front of the arena: the stadium's name on a long board across the back of the
				-- near stand (over the gate) and a big club crest standing on the roof above it, both
				-- facing the path outside (shared/StadiumLook writes the name and paints the crest).
				local face = nearStart - 5 * STAND_DEPTH - 1.2
				sign(
					list,
					"NameBoard",
					-30,
					30,
					FLOOR + 10.5,
					FLOOR + 20.5,
					face - 0.6,
					face,
					"ROOF ARENA",
					"Front",
					WHITE
				)
				box(list, "Crest", -7, 7, FLOOR + 23, FLOOR + 37, face - 0.4, face, WHITE, nil, 1)
				list[#list].image = ""
				list[#list].face = "Front"
			end
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
			-- Fireworks launch from the two near floodlight masts outside the bowl.
			for _, side in { -1, 1 } do
				local fx, fy, fz = side * (sideX + 8 * STAND_DEPTH + 5), FLOOR + 38, endLo + 2
				box(list, "Firework", fx - 0.5, fx + 0.5, fy, fy + 1, fz - 0.5, fz + 0.5, LIGHT)
				list[#list].emitter = true
				list[#list].transparency = 1
			end
		end
	end

	for _, spec in CourtPlan.lamps(index, model) do
		table.insert(list, spec)
	end
	return list
end

return CourtPlan
