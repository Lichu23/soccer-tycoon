-- Builds what stands outside the building door in ServerStorage.PlotTemplate: the trophy case on the
-- right (Entrance folder: five empty TrophySlot_k pedestals and a name plaque each) and the six
-- Robux pack pads on the left (RobuxPad_* in Markers). Run through the Studio MCP (execute_luau,
-- Edit mode). Safe to run again: it rebuilds the folder. Plot space, like the rest of the template:
-- the building door is at x 50, z 90 and the path is x -20 to 20. The case faces the path (-x). Seen
-- from the door (looking +x) the left is -z and the right is +z.
-- The server fills the case (src/server/TrophyCase.luau) and runs the pads (PadActions, "robux").

local ServerStorage = game:GetService("ServerStorage")

local template = ServerStorage:WaitForChild("PlotTemplate")
local old = template:FindFirstChild("Entrance")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "Entrance"
folder.Parent = template

local GROUND = 0.5
local X = 40
-- The case fills the gap between the walkway (z 97) and the glass front of the building (z 126); its
-- front stays at x 38 and it is deep enough for the trophy models (ServerStorage.Trophies).
local CASE_X = 41
local CASE_Z = 111.7
local CASE_DEPTH = 6
local GLASS_DEPTH = 5.6
local GLASS_HEIGHT = 6.8
local COLORS = {
	wood = Color3.fromRGB(200, 140, 70),
	dark = Color3.fromRGB(70, 74, 92),
	gold = Color3.fromRGB(235, 190, 70),
	glass = Color3.fromRGB(190, 225, 240),
	plaque = Color3.fromRGB(32, 38, 56),
	white = Color3.fromRGB(240, 240, 240),
}

local function box(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Anchored = true
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder
	return part
end

-- Text on the side that faces the path (the -X face of an unturned part).
local function sign(
	part: BasePart,
	text: string,
	textColor: Color3,
	pixelsPerStud: number,
	name: string?,
	fixedSize: number?
)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = name or "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.92, 0.8)
	label.Position = UDim2.fromScale(0.04, 0.1)
	label.Text = text
	label.TextColor3 = textColor
	label.Font = Enum.Font.GothamBold
	if fixedSize then
		-- The same size on every plaque; a long name ("CONTINENTAL CUP") wraps to two lines.
		label.TextSize = fixedSize
	else
		label.TextScaled = true
	end
	label.Parent = gui
end

-- The Robux packs: six pads side by side in one row on the ground left of the door, on the same line as the trophy case (x 40), cash first, then TP. The
-- server turns each into a pad (Kind "robux", PadId = the product key in Config.Products); the
-- client draws the disc, the picture above it and the text.
local PADS = {
	{ "cash_small", 40, 23 },
	{ "cash_medium", 40, 34 },
	{ "cash_large", 40, 45 },
	{ "tp_small", 40, 56 },
	{ "tp_medium", 40, 67 },
	{ "tp_large", 40, 78 },
}
local markers = template:FindFirstChild("Markers")
assert(markers, "the template has no Markers folder")
for _, entry in PADS do
	local old = markers:FindFirstChild("RobuxPad_" .. entry[1])
	if old then
		old:Destroy() -- only the packs: the boost pads of floor 1 are BuildPlotTemplate's
	end
end
for _, entry in PADS do
	local pad = Instance.new("Part")
	pad.Name = "RobuxPad_" .. entry[1]
	pad.Size = Vector3.new(7, 0.2, 7)
	pad.CFrame = CFrame.new(entry[2], GROUND + 0.3, entry[3])
	pad.Anchored = true
	pad.Color = Color3.fromRGB(226, 184, 84)
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.4
	pad.CanCollide = false
	pad.CanTouch = false
	pad.CanQuery = false
	pad:SetAttribute("PadId", entry[1])
	pad:SetAttribute("Kind", "robux")
	pad.Parent = markers
end

-- The trophy case: a low base, five pedestals in a row inside a glass box with a dark back panel, a
-- name plaque in front of each, a title board above.
local slots = 5
local pitch = 5.3
local width = slots * pitch + 1.4
local baseTop = GROUND + 1.6
local front = CASE_X - CASE_DEPTH / 2
box("CaseBase", Vector3.new(CASE_DEPTH, 1.6, width), Vector3.new(CASE_X, GROUND + 0.8, CASE_Z), COLORS.dark)
local glass = box("CaseGlass", Vector3.new(GLASS_DEPTH, GLASS_HEIGHT, width), Vector3.new(CASE_X, baseTop + GLASS_HEIGHT / 2, CASE_Z), COLORS.glass, Enum.Material.Glass)
glass.Transparency = 0.75 -- solid: nobody walks into the case
box("CaseBack", Vector3.new(0.2, GLASS_HEIGHT, width - 0.4), Vector3.new(CASE_X + GLASS_DEPTH / 2 - 0.15, baseTop + GLASS_HEIGHT / 2, CASE_Z), COLORS.plaque)
box("CaseTop", Vector3.new(CASE_DEPTH, 0.6, width), Vector3.new(CASE_X, baseTop + GLASS_HEIGHT + 0.3, CASE_Z), COLORS.dark)
local title = box("CaseTitle", Vector3.new(0.4, 2.4, width - 2), Vector3.new(front - 0.1, baseTop + GLASS_HEIGHT + 1.8, CASE_Z), COLORS.plaque)
sign(title, "TROPHIES", COLORS.gold, 40)
for k = 1, slots do
	local z = CASE_Z + (k - (slots + 1) / 2) * pitch
	local pedestal = box("TrophySlot_" .. k, Vector3.new(4, 1.2, 4), Vector3.new(CASE_X, baseTop + 0.6, z), COLORS.white)
	pedestal:SetAttribute("Slot", k)
	local plaque = box("TrophyPlaque_" .. k, Vector3.new(0.3, 1.1, pitch - 0.6), Vector3.new(front - 0.15, GROUND + 0.9, z), COLORS.plaque)
	plaque:SetAttribute("Slot", k)
	sign(plaque, "", COLORS.gold, 50, "Name", 20)
end

return "Entrance built: " .. #folder:GetChildren() .. " parts"
