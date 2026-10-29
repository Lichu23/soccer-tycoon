--!strict
-- How far the safe area (CoreUISafeInsets) sits in from the left and right sides of the screen. On
-- phones with a notch or a camera hole it leaves a wide empty strip at each side, so the side columns
-- (the Dock buttons at the left, the HUD column at the right) move out by this much to sit near the
-- real edge. Their ScreenGuis need ClipToDeviceSafeArea off, or the moved part would be cut.

local Players = game:GetService("Players")

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

-- Calls `callback` now and whenever the strips change (the window resizes or the device turns).
function Edges.watch(callback: () -> ())
	ensure()
	table.insert(listeners, callback)
	callback()
end

return Edges
