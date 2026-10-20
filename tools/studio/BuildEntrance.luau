-- Builds the two props outside the building door in ServerStorage.PlotTemplate.Entrance: the Robux
-- booth on the left of the door (ShopBooth) and the trophy case on the right (TrophyCase with five
-- empty TrophySlot_k pedestals and a name plaque each). Run through the Studio MCP (execute_luau,
-- Edit mode). Safe to run again: it rebuilds the folder. Plot space, like the rest of the template:
-- the building door is at x 50, z 90 and the path is x -20 to 20, so both props stand at x 40 facing
-- the path (-x). Seen from the door (looking +x) the left is -z and the right is +z.
-- The server fills the case (src/server/TrophyCase.luau); the client opens the shop from the booth
-- (src/client/ShopBooth.luau).

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
local BOOTH_Z, CASE_Z = 66, 114
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

-- The Robux booth: a counter with two posts and a roof, a sign on the roof edge.
local boothTop = GROUND + 4
local counter = box("ShopBooth", Vector3.new(4, 4, 12), Vector3.new(X, GROUND + 2, BOOTH_Z), COLORS.wood)
counter:SetAttribute("BoothKind", "robux")
box("BoothPostA", Vector3.new(0.8, 9, 0.8), Vector3.new(X + 1.4, GROUND + 4.5, BOOTH_Z - 5.6), COLORS.dark)
box("BoothPostB", Vector3.new(0.8, 9, 0.8), Vector3.new(X + 1.4, GROUND + 4.5, BOOTH_Z + 5.6), COLORS.dark)
box("BoothRoof", Vector3.new(6, 0.6, 14), Vector3.new(X, GROUND + 9.3, BOOTH_Z), COLORS.gold)
local boothSign = box("BoothSign", Vector3.new(0.4, 2.6, 11), Vector3.new(X - 2.9, GROUND + 7.6, BOOTH_Z), COLORS.plaque)
sign(boothSign, "ROBUX SHOP", COLORS.white, 40)
-- A small price board on the counter front.
local board = box("BoothBoard", Vector3.new(0.2, 2, 8), Vector3.new(X - 2.1, boothTop - 2, BOOTH_Z), COLORS.plaque)
sign(board, "Cases · Boosts", COLORS.gold, 40)

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
