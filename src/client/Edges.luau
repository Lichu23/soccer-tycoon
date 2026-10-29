--!strict
-- How far the safe area (CoreUISafeInsets) sits in from the left and right sides of the screen. On
-- phones it leaves a wide empty strip at each side (about 60 to 70 px), so the side columns (the
-- Dock buttons at the left, the HUD column at the right) move out over part of it. They keep
-- CLEARANCE px clear of the real edge: in landscape the iPhone Dynamic Island takes the first ~48 px
-- of one side, and either side can be the island side. Their ScreenGuis need ClipToDeviceSafeArea
-- off, or the moved part would be cut.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CLEARANCE = 44
-- The HUD column shrinks on short screens (phones), down to MIN_SCALE; full size from this height up.
local SCALE_REFERENCE_HEIGHT = 500
local MIN_SCALE = 0.75

local Edges = {}

local probes: { full: ScreenGui, safe: ScreenGui }? = nil
local listeners: { () -> () } = {}

local function probe(name: string, insets: Enum.ScreenInsets): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ScreenInsets = insets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local function ensure(): { full: ScreenGui, safe: ScreenGui }
	if probes then
		return probes
	end
	local made = {
		full = probe("EdgeProbeFull", Enum.ScreenInsets.None),
		safe = probe("EdgeProbeSafe", Enum.ScreenInsets.CoreUISafeInsets),
	}
	probes = made
	local function changed()
		for _, listener in listeners do
			listener()
		end
	end
	for _, gui in { made.full, made.safe } do
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(changed)
		gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(changed)
	end
	return made
end

-- The width of the strip between the screen edge and the safe area, at the left and at the right.
function Edges.insets(): (number, number)
	local made = ensure()
	local full, safe = made.full, made.safe
	local left = safe.AbsolutePosition.X - full.AbsolutePosition.X
	local right = (full.AbsolutePosition.X + full.AbsoluteSize.X) - (safe.AbsolutePosition.X + safe.AbsoluteSize.X)
	return math.max(left, 0), math.max(right, 0)
end

-- How far the side columns move out of the safe area, at the left and at the right: the strip,
-- less the clearance kept for the camera cutout.
function Edges.pull(): (number, number)
	local left, right = Edges.insets()
	return math.max(left - CLEARANCE, 0), math.max(right - CLEARANCE, 0)
end

-- The size of the HUD column on this screen: smaller on a phone, 1 on a tablet or desktop.
function Edges.hudScale(): number
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else SCALE_REFERENCE_HEIGHT
	return math.clamp(height / SCALE_REFERENCE_HEIGHT, MIN_SCALE, 1)
end

-- Calls `callback` now and whenever the screen or the strips change (the window resizes or the
-- device turns).
function Edges.watch(callback: () -> ())
	ensure()
	table.insert(listeners, callback)
	callback()
end

return Edges
