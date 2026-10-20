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
local CASE_Z = 114
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
local function sign(part: BasePart, text: string, textColor: Color3, pixelsPerStud: number, name: string?)
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
	label.TextScaled = true
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
for _, child in markers:GetChildren() do
	if child.Name:match("^RobuxPad_") then
		child:Destroy()
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

-- The trophy case: a low base, five pedestals in a row inside a glass box, a name plaque in front of
-- each, a title board above.
local slots = 5
local pitch = 4.6
local width = slots * pitch + 1.4
local baseTop = GROUND + 1.6
box("CaseBase", Vector3.new(4, 1.6, width), Vector3.new(X, GROUND + 0.8, CASE_Z), COLORS.dark)
local glass = box("CaseGlass", Vector3.new(3.6, 6.4, width), Vector3.new(X, baseTop + 3.2, CASE_Z), COLORS.glass, Enum.Material.Glass)
glass.Transparency = 0.75
glass.CanCollide = false
box("CaseTop", Vector3.new(4, 0.6, width), Vector3.new(X, baseTop + 6.7, CASE_Z), COLORS.dark)
local title = box("CaseTitle", Vector3.new(0.4, 2.4, width - 2), Vector3.new(X - 2.1, baseTop + 8.2, CASE_Z), COLORS.plaque)
sign(title, "TROPHIES", COLORS.gold, 40)
for k = 1, slots do
	local z = CASE_Z + (k - (slots + 1) / 2) * pitch
	local pedestal = box("TrophySlot_" .. k, Vector3.new(2.6, 1.2, 2.6), Vector3.new(X, baseTop + 0.6, z), COLORS.white)
	pedestal:SetAttribute("Slot", k)
	local plaque = box("TrophyPlaque_" .. k, Vector3.new(0.3, 1.1, pitch - 0.6), Vector3.new(X - 2.1, GROUND + 0.9, z), COLORS.plaque)
	plaque:SetAttribute("Slot", k)
	sign(plaque, "", COLORS.gold, 50, "Name")
end

return "Entrance built: " .. #folder:GetChildren() .. " parts"
