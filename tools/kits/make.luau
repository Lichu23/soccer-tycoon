--!nocheck
-- Draws the clothing images of the player figures (shared/Mannequin) from the team kits (shared/Kits):
-- one classic Shirt and one Pants template (585 x 559) per team, a plain white shirt that a colour
-- tints, plain dark pants for it, and the face decals. Writes PNGs to tools/kits/out. No real crest,
-- maker logo or sponsor: the badge on the chest is a made-up shield in the team's colours.
--
-- Usage from the project root: lune run tools/kits/make
-- Then upload the PNGs (Studio MCP upload_image) and put the ids in src/shared/KitImages.luau.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Kits = require("../../src/shared/Kits")

local OUT = "tools/kits/out"
local W, H = 585, 559

-- PNG ---------------------------------------------------------------------------------------------

local crcTable = {}
for n = 0, 255 do
	local c = n
	for _ = 1, 8 do
		if bit32.band(c, 1) == 1 then
			c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1))
		else
			c = bit32.rshift(c, 1)
		end
	end
	crcTable[n] = c
end

local function crc32(data: string): number
	local c = 0xFFFFFFFF
	for index = 1, #data do
		c = bit32.bxor(
			crcTable[bit32.band(bit32.bxor(c, string.byte(data, index)), 0xFF)],
			bit32.rshift(c, 8)
		)
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end

local function chunk(kind: string, data: string): string
	return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
end

type Image = { w: number, h: number, pixels: buffer }

local function newImage(w: number, h: number): Image
	return { w = w, h = h, pixels = buffer.create(w * h * 4) } -- all transparent
end

local function encode(image: Image): string
	local rows = buffer.create((image.w * 4 + 1) * image.h)
	for y = 0, image.h - 1 do
		local rowStart = y * (image.w * 4 + 1)
		buffer.writeu8(rows, rowStart, 0) -- no filter
		buffer.copy(rows, rowStart + 1, image.pixels, y * image.w * 4, image.w * 4)
	end
	local header = string.pack(">I4I4BBBBB", image.w, image.h, 8, 6, 0, 0, 0) -- 8-bit RGBA
	return "\137PNG\r\n\26\n"
		.. chunk("IHDR", header)
		.. chunk("IDAT", serde.compress("zlib", buffer.tostring(rows)))
		.. chunk("IEND", "")
end

-- Drawing -----------------------------------------------------------------------------------------

type Color = { number } -- r, g, b (0 to 255), optional alpha

local function put(image: Image, x: number, y: number, color: Color)
	if x < 0 or y < 0 or x >= image.w or y >= image.h then
		return
	end
	local at = (y * image.w + x) * 4
	buffer.writeu8(image.pixels, at, color[1])
	buffer.writeu8(image.pixels, at + 1, color[2])
	buffer.writeu8(image.pixels, at + 2, color[3])
	buffer.writeu8(image.pixels, at + 3, color[4] or 255)
end

local function rect(image: Image, x: number, y: number, w: number, h: number, color: Color)
	for py = math.floor(y), math.floor(y + h) - 1 do
		for px = math.floor(x), math.floor(x + w) - 1 do
			put(image, px, py, color)
		end
	end
end

-- Fills the pixels inside a polygon of { x, y } points (even-odd rule).
local function polygon(image: Image, points: { { number } }, color: Color)
	local minY, maxY = math.huge, -math.huge
	for _, p in points do
		minY = math.min(minY, p[2])
		maxY = math.max(maxY, p[2])
	end
	for py = math.floor(minY), math.ceil(maxY) do
		local y = py + 0.5
		local crossings = {}
		for i = 1, #points do
			local a, b = points[i], points[i % #points + 1]
			if (a[2] <= y and b[2] > y) or (b[2] <= y and a[2] > y) then
				table.insert(crossings, a[1] + (y - a[2]) / (b[2] - a[2]) * (b[1] - a[1]))
			end
		end
		table.sort(crossings)
		for i = 1, #crossings - 1, 2 do
			for px = math.floor(crossings[i] + 0.5), math.floor(crossings[i + 1] - 0.5) do
				put(image, px, py, color)
			end
		end
	end
end

local function ellipse(image: Image, cx: number, cy: number, rx: number, ry: number, color: Color)
	for py = math.floor(cy - ry), math.ceil(cy + ry) do
		for px = math.floor(cx - rx), math.ceil(cx + rx) do
			local dx, dy = (px + 0.5 - cx) / rx, (py + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1 then
				put(image, px, py, color)
			end
		end
	end
end

-- A thick arc of a circle, from angle `from` to `to` (radians, 0 is +x, y grows down).
local function arc(
	image: Image,
	cx: number,
	cy: number,
	r: number,
	thick: number,
	from: number,
	to: number,
	color: Color
)
	for py = math.floor(cy - r - thick), math.ceil(cy + r + thick) do
		for px = math.floor(cx - r - thick), math.ceil(cx + r + thick) do
			local dx, dy = px + 0.5 - cx, py + 0.5 - cy
			local d = math.sqrt(dx * dx + dy * dy)
			local a = math.atan2(dy, dx)
			if math.abs(d - r) <= thick / 2 and a >= from and a <= to then
				put(image, px, py, color)
			end
		end
	end
end

local function brightness(c: Color): number
	return (0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]) / 255
end

local function shade(c: Color, amount: number): Color
	local target = if amount < 0 then 0 else 255
	local t = math.abs(amount)
	return {
		math.floor(c[1] + (target - c[1]) * t + 0.5),
		math.floor(c[2] + (target - c[2]) * t + 0.5),
		math.floor(c[3] + (target - c[3]) * t + 0.5),
	}
end

local function same(a: Color, b: Color): boolean
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

-- The classic template layout ---------------------------------------------------------------------

-- Each face as { x, y, w, h } on the 585 x 559 template.
local TORSO = {
	front = { 231, 74, 128, 128 },
	back = { 427, 74, 128, 128 },
	left = { 361, 74, 64, 128 },
	right = { 165, 74, 64, 128 },
	up = { 231, 8, 128, 64 },
	down = { 231, 204, 128, 64 },
}
-- The right limb (right arm on the shirt, right leg on the pants) and the left one.
local LIMBS = {
	{
		up = { 217, 289, 64, 64 },
		down = { 217, 485, 64, 64 },
		front = { 217, 355, 64, 128 },
		back = { 85, 355, 64, 128 },
		left = { 151, 355, 64, 128 },
		right = { 19, 355, 64, 128 },
	},
	{
		up = { 308, 289, 64, 64 },
		down = { 308, 485, 64, 64 },
		front = { 308, 355, 64, 128 },
		back = { 440, 355, 64, 128 },
		left = { 506, 355, 64, 128 },
		right = { 374, 355, 64, 128 },
	},
}
local SIDES = { "front", "back", "left", "right" }

-- Shirt -------------------------------------------------------------------------------------------

local STRIPE = 22 -- stripe width in pixels: about six across the chest

-- The made-up badge: a shield with an accent edge, the top in the accent colour and the bottom split
-- into the shirt and trim colours, with a small white ball in the middle.
local function badge(image: Image, x: number, y: number, kit)
	local w, h = 22, 26
	local function shield(inset: number): { { number } }
		return {
			{ x + inset, y + inset },
			{ x + w - inset, y + inset },
			{ x + w - inset, y + h * 0.55 },
			{ x + w / 2, y + h - inset * 1.4 },
			{ x + inset, y + h * 0.55 },
		}
	end
	local edge = kit.accent
	polygon(image, shield(0), edge)
	local left = kit.shirt
	local right = if same(kit.trim, kit.shirt)
		then shade(kit.shirt, if brightness(kit.shirt) > 0.5 then -0.3 else 0.35)
		else kit.trim
	-- Split the inside: draw it whole in one colour, then the right half over it.
	polygon(image, shield(2), left)
	local inner = shield(2)
	local mid = x + w / 2
	polygon(image, { { mid, inner[1][2] }, inner[2], inner[3], inner[4] }, right)
	-- The top band.
	rect(image, x + 2, y + 2, w - 4, 6, edge)
	ellipse(image, mid, y + h * 0.52, 3.2, 3.2, { 250, 250, 250 })
end

local function shirtImage(kit, plain: boolean): Image
	local image = newImage(W, H)
	local shirt, trim, accent = kit.shirt, kit.trim, kit.accent
	-- The torso: the shirt colour on every face, then the pattern.
	for _, face in TORSO do
		rect(image, face[1], face[2], face[3], face[4], shirt)
	end
	if kit.pattern == "stripes" then
		-- Stripes run around the body: the sides continue the front.
		for _, name in { "right", "front", "left", "back" } do
			local face = TORSO[name]
			for px = 0, face[3] - 1 do
				if (px // STRIPE) % 2 == 1 then
					rect(image, face[1] + px, face[2], 1, face[4], trim)
				end
			end
		end
	elseif kit.pattern == "hem" then
		for _, name in SIDES do
			local face = TORSO[name]
			rect(image, face[1], face[2] + face[4] - 16, face[3], 16, trim)
		end
	end
	-- The collar: a V on the front, a band on the back and a ring on the top.
	local front = TORSO.front
	local cx = front[1] + front[3] / 2
	polygon(image, {
		{ cx - 22, front[2] },
		{ cx + 22, front[2] },
		{ cx, front[2] + 24 },
	}, accent)
	polygon(image, {
		{ cx - 15, front[2] },
		{ cx + 15, front[2] },
		{ cx, front[2] + 15 },
	}, if plain then { 230, 230, 230 } else shade(shirt, -0.35))
	local back = TORSO.back
	rect(image, back[1] + 34, back[2], back[3] - 68, 6, accent)
	local up = TORSO.up
	rect(image, up[1] + 30, up[2] + 16, up[3] - 60, 32, accent)
	rect(image, up[1] + 36, up[2] + 22, up[3] - 72, 20, shade(shirt, -0.35))
	-- Thin accent seams down the sides.
	for _, name in { "left", "right" } do
		local face = TORSO[name]
		rect(image, face[1] + face[3] / 2 - 2, face[2], 4, face[4], accent)
	end
	if not plain then
		-- The badge on the left breast (the right of the image, which is the wearer's left).
		badge(image, front[1] + 82, front[2] + 18, kit)
	end
	-- The sleeves: the top of each arm, with a cuff; the rest shows the skin.
	local sleeve = if kit.pattern == "sleeves" then trim else shirt
	for _, limb in LIMBS do
		rect(image, limb.up[1], limb.up[2], limb.up[3], limb.up[4], sleeve)
		for _, name in SIDES do
			local face = limb[name]
			rect(image, face[1], face[2], face[3], 44, sleeve)
			rect(image, face[1], face[2] + 44, face[3], 6, accent)
		end
	end
	return image
end

-- Pants -------------------------------------------------------------------------------------------

local BOOTS = { 28, 28, 34 }
local SOLE = { 235, 235, 235 }

local function pantsImage(kit): Image
	local image = newImage(W, H)
	local shorts, socks, accent = kit.shorts, kit.socks, kit.accent
	-- The shorts reach down over the hips: the bottom of the torso.
	for _, name in SIDES do
		local face = TORSO[name]
		rect(image, face[1], face[2] + face[4] - 14, face[3], 14, shorts)
	end
	rect(image, TORSO.down[1], TORSO.down[2], TORSO.down[3], TORSO.down[4], shorts)
	for _, limb in LIMBS do
		for _, name in SIDES do
			local face = limb[name]
			local x, y, w = face[1], face[2], face[3]
			rect(image, x, y, w, 50, shorts) -- the shorts
			rect(image, x, y + 58, w, 58, socks) -- the socks, under the knee
			rect(image, x, y + 58, w, 5, accent) -- the top of the socks
			rect(image, x, y + 112, w, 16, BOOTS) -- the boots
			rect(image, x, y + 125, w, 3, SOLE)
		end
		-- The side stripe of the shorts.
		for _, name in { "left", "right" } do
			local face = limb[name]
			rect(image, face[1] + face[3] / 2 - 3, face[2], 6, 44, accent)
		end
		rect(image, limb.down[1], limb.down[2], limb.down[3], limb.down[4], BOOTS)
	end
	return image
end

-- Faces -------------------------------------------------------------------------------------------

local INK = { 22, 22, 26 }
local FACE = 256

-- The eyes and the mouth of a face decal (the brows are a separate decal, tinted with the hair colour).
local function faceImage(kind: string): Image
	local image = newImage(FACE, FACE)
	local eyeY = 116
	for _, x in { 84, 172 } do
		ellipse(image, x, eyeY, 16, 23, INK)
		ellipse(image, x + 5, eyeY - 9, 5.5, 6.5, { 255, 255, 255 })
	end
	if kind == "smile" then
		arc(image, 128, 146, 46, 11, math.rad(25), math.rad(155), INK)
	elseif kind == "grin" then
		polygon(image, { { 84, 168 }, { 172, 168 }, { 160, 196 }, { 128, 206 }, { 96, 196 } }, INK)
		rect(image, 92, 170, 72, 9, { 255, 255, 255 })
	elseif kind == "focus" then
		rect(image, 100, 182, 56, 9, INK)
		arc(image, 128, 150, 38, 7, math.rad(70), math.rad(110), INK)
	elseif kind == "smirk" then
		arc(image, 120, 150, 36, 9, math.rad(35), math.rad(120), INK)
		arc(image, 160, 172, 14, 7, math.rad(-80), math.rad(20), INK)
	end
	return image
end

local function browsImage(kind: string): Image
	local image = newImage(FACE, FACE)
	local white = { 255, 255, 255 } -- tinted with the hair colour in the game
	if kind == "raised" then
		polygon(image, { { 58, 72 }, { 106, 62 }, { 108, 74 }, { 60, 84 } }, white)
		polygon(image, { { 150, 62 }, { 198, 72 }, { 196, 84 }, { 148, 74 } }, white)
	else -- "flat": a little frown towards the middle
		polygon(image, { { 58, 68 }, { 110, 78 }, { 108, 90 }, { 58, 80 } }, white)
		polygon(image, { { 146, 78 }, { 198, 68 }, { 198, 80 }, { 148, 90 } }, white)
	end
	return image
end

-- Write everything --------------------------------------------------------------------------------

if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end
local count = 0
local function save(name: string, image: Image)
	fs.writeFile(`{OUT}/{name}.png`, encode(image))
	count += 1
end

local names = {}
for team in Kits.teams do
	table.insert(names, team)
end
table.sort(names)
for _, team in names do
	local kit = Kits.teams[team]
	save(`shirt_{team}`, shirtImage(kit, false))
	save(`pants_{team}`, pantsImage(kit))
end

-- The plain kit: a white shirt for a tint, and dark shorts with white socks.
local WHITE = { 255, 255, 255 }
save(
	"shirt_plain",
	shirtImage(
		{
			shirt = WHITE,
			trim = WHITE,
			shorts = WHITE,
			socks = WHITE,
			accent = { 200, 200, 200 },
			pattern = "plain",
		},
		true
	)
)
save(
	"pants_plain",
	pantsImage({
		shirt = WHITE,
		trim = WHITE,
		shorts = { 35, 40, 60 },
		socks = { 240, 240, 240 },
		accent = { 35, 40, 60 },
		pattern = "plain",
	})
)

for _, kind in { "smile", "grin", "focus", "smirk" } do
	save(`face_{kind}`, faceImage(kind))
end
for _, kind in { "flat", "raised" } do
	save(`brows_{kind}`, browsImage(kind))
end

-- A buzz cut painted on the head (tinted with the hair colour in the game): the whole top, and the
-- upper part of the sides, the back and the front (above the brows), with a soft lower edge.
local function buzzImage(height: number): Image
	local image = newImage(FACE, FACE)
	local fade = 14
	for y = 0, math.floor(height) - 1 do
		local alpha = if y > height - fade then math.floor(235 * (height - y) / fade) else 235
		rect(image, 0, y, FACE, 1, { 255, 255, 255, alpha })
	end
	return image
end
save("buzz_top", buzzImage(FACE))
save("buzz_side", buzzImage(FACE * 0.42))
save("buzz_front", buzzImage(FACE * 0.2))

print(`wrote {count} images to {OUT}`)
