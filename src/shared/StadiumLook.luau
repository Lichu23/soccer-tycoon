--!strict
-- How a Locker room style shows on the pitch (docs/PLAN.md, Step 3). Each slot paints the parts of
-- CourtPlan it names: the crest picture over the gate, the sponsor boards (colours and names), the
-- glowing faces of the floodlights, the scoreboard (each style is its own design) and the outside of
-- the roof arena. The server paints the owner's choices for everyone (server/Stadium), and the
-- Locker room paints a style the player is looking at on its copy of the stadium only. The kit is
-- drawn on the players by the match (client/MatchView), and the floodlight model is built by
-- shared/CourtParts, not here.

local Config = require(script.Parent.Config)

local StadiumLook = {}

-- The parts each slot paints, by CourtPlan name.
StadiumLook.PARTS = {
	crest = { Crest = true },
	banners = { AdBoard = true },
	floodlights = { LightHead = true },
	scoreboard = { Scoreboard = true },
	stadium = { Roof = true, RoofPillar = true, StandRow = true, GatePillar = true },
} :: { [string]: { [string]: boolean } }

local DARK = { 20, 24, 35 } -- the dark of the boards (a table: Color3 is not there in unit tests)
local SCORE = "0 - 0"

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

-- The colour of the `index`th part (from 1) of a slot in style `def`, and its text colour if it has one.
function StadiumLook.colors(def: Config.CosmeticDef, index: number): (Color3, Color3?)
	local pattern = def.pattern
	local body = if pattern and #pattern > 0
		then rgb(pattern[(index - 1) % #pattern + 1])
		else rgb(def.color)
	return body, if def.accent then rgb(def.accent) else nil
end

local function new(className: string, props: { [string]: any }, parent: Instance): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local function label(
	parent: Instance,
	text: string,
	color: Color3,
	props: { [string]: any }?
): TextLabel
	local item = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = color,
	}, parent)
	if props then
		for key, value in props do
			(item :: any)[key] = value
		end
	end
	return item
end

-- A white tile with a dark digit (the retro board).
local function tile(parent: Instance, text: string, order: number)
	local box = new("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromScale(0.12, 0.9),
		BackgroundColor3 = Color3.fromRGB(245, 245, 240),
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0.15, 0) }, box)
	label(
		box,
		text,
		rgb(DARK),
		{ Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1) }
	)
end

-- Draws scoreboard style `def` on the face of `part`: the board's own text (its name or the score
-- line) in the style's design.
local function drawScoreboard(part: BasePart, def: Config.CosmeticDef)
	local gui = part:FindFirstChildOfClass("SurfaceGui")
	if gui == nil or part:GetAttribute("Style") == def.id then
		return
	end
	part:SetAttribute("Style", def.id)
	gui:ClearAllChildren()
	local text = tostring(part:GetAttribute("BaseText") or "")
	local accent = if def.accent then rgb(def.accent) else Color3.fromRGB(255, 220, 60)
	local design = def.design or "classic"
	if design == "framed" then
		local inner = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -16, 1, -16),
			BackgroundTransparency = 1,
		}, gui)
		new("UICorner", { CornerRadius = UDim.new(0, 10) }, inner)
		new("UIStroke", { Color = accent, Thickness = 6 }, inner)
		label(
			inner,
			text,
			accent,
			{ Size = UDim2.fromScale(0.92, 0.8), Position = UDim2.fromScale(0.04, 0.1) }
		)
	elseif design == "retro" then
		label(
			gui,
			text,
			accent,
			{ Size = UDim2.fromScale(0.9, 0.42), Position = UDim2.fromScale(0.05, 0.04) }
		)
		local row = new("Frame", {
			Position = UDim2.fromScale(0.05, 0.5),
			Size = UDim2.fromScale(0.9, 0.46),
			BackgroundTransparency = 1,
		}, gui)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0.02, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		label(row, "HOME", accent, { LayoutOrder = 1, Size = UDim2.fromScale(0.28, 0.8) })
		tile(row, "0", 2)
		tile(row, "0", 3)
		label(row, "AWAY", accent, { LayoutOrder = 4, Size = UDim2.fromScale(0.28, 0.8) })
	elseif design == "neon" then
		for _, y in { 0.06, 0.9 } do
			new("Frame", {
				Position = UDim2.fromScale(0.03, y),
				Size = UDim2.fromScale(0.94, 0.04),
				BackgroundColor3 = accent,
				BorderSizePixel = 0,
			}, gui)
		end
		local glow = label(
			gui,
			text,
			accent,
			{ Size = UDim2.fromScale(0.9, 0.62), Position = UDim2.fromScale(0.05, 0.19) }
		)
		new("UIStroke", { Color = accent, Thickness = 3, Transparency = 0.55 }, glow)
	elseif design == "split" then
		local pattern = def.pattern
		local home = if pattern and pattern[1] then rgb(pattern[1]) else rgb(def.color)
		local away = if pattern and pattern[2] then rgb(pattern[2]) else rgb(def.color)
		local top = new(
			"Frame",
			{ Size = UDim2.fromScale(1, 0.36), BackgroundColor3 = rgb(DARK), BorderSizePixel = 0 },
			gui
		)
		label(
			top,
			text,
			accent,
			{ Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1) }
		)
		for index, side in
			{ { name = "HOME", color = home, x = 0 }, { name = "AWAY", color = away, x = 0.65 } }
		do
			local half = new("Frame", {
				LayoutOrder = index,
				Position = UDim2.fromScale(side.x, 0.36),
				Size = UDim2.fromScale(0.35, 0.64),
				BackgroundColor3 = side.color,
				BorderSizePixel = 0,
			}, gui)
			label(
				half,
				side.name,
				accent,
				{ Size = UDim2.fromScale(0.8, 0.7), Position = UDim2.fromScale(0.1, 0.15) }
			)
		end
		local middle = new("Frame", {
			Position = UDim2.fromScale(0.35, 0.36),
			Size = UDim2.fromScale(0.3, 0.64),
			BackgroundColor3 = rgb(DARK),
			BorderSizePixel = 0,
		}, gui)
		label(
			middle,
			SCORE,
			Color3.new(1, 1, 1),
			{ Size = UDim2.fromScale(0.8, 0.7), Position = UDim2.fromScale(0.1, 0.15) }
		)
	else
		label(gui, text, accent)
	end
end

-- Paints the parts of `slotId` under `court` in style `def`. Parts are counted in the order of the
-- CourtPlan list (the server sets a "PlanIndex" on each), so a pattern alternates the same way on the
-- server and on every client.
function StadiumLook.paint(court: Instance, slotId: string, def: Config.CosmeticDef)
	local names = StadiumLook.PARTS[slotId]
	if names == nil then
		return
	end
	local parts: { BasePart } = {}
	for _, child in court:GetChildren() do
		if child:IsA("BasePart") and names[child.Name] then
			table.insert(parts, child)
		end
	end
	table.sort(parts, function(a, b)
		return (tonumber(a:GetAttribute("PlanIndex")) or 0)
			< (tonumber(b:GetAttribute("PlanIndex")) or 0)
	end)
	local brands = def.brands
	for index, part in parts do
		local body, text = StadiumLook.colors(def, index)
		if slotId == "scoreboard" then
			part.Color = rgb(def.color)
			drawScoreboard(part, def)
			continue
		end
		part.Color = body
		local gui = part:FindFirstChildOfClass("SurfaceGui")
		local words = gui and gui:FindFirstChildOfClass("TextLabel")
		if words and text then
			words.TextColor3 = text
		end
		if words and brands and #brands > 0 then
			words.Text = brands[(index - 1) % #brands + 1]
		end
		local picture = gui and gui:FindFirstChildOfClass("ImageLabel")
		if picture and def.image then
			picture.Image = def.image
		end
	end
end

-- Writes the stadium's name on the sign over the gate (nil puts the plan's own text back).
function StadiumLook.setName(court: Instance, name: string?)
	for _, child in court:GetChildren() do
		if child.Name == "GateSign" and child:IsA("BasePart") then
			local gui = child:FindFirstChildOfClass("SurfaceGui")
			local words = gui and gui:FindFirstChildOfClass("TextLabel")
			if words then
				words.Text = if name and name ~= ""
					then string.upper(name)
					else tostring(child:GetAttribute("BaseText") or words.Text)
			end
		end
	end
end

return StadiumLook
