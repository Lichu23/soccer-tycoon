--!strict
-- A soft click for every button of the screens (the Dock, the panels, their X). Not in the play
-- screens, whose taps have their own sounds (the kick, the shot), and not on a button marked with the
-- OwnSound attribute, whose action already makes a sound (a style put on in the Locker room).

local Players = game:GetService("Players")

local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer

-- The ScreenGuis of the 1v1, the keepie-uppies and the penalties.
local PLAY_SCREENS = { Freekick = true, Keepie = true, Penalty = true }

local ClickSounds = {}

local function screenOf(button: Instance): string?
	local gui = button:FindFirstAncestorWhichIsA("ScreenGui")
	return if gui then gui.Name else nil
end

local function watch(button: Instance)
	if not button:IsA("GuiButton") then
		return
	end
	local name = screenOf(button)
	if name and PLAY_SCREENS[name] then
		return
	end
	button.Activated:Connect(function()
		if button:GetAttribute("OwnSound") ~= true then
			Sounds.play("click")
		end
	end)
end

function ClickSounds.init()
	local playerGui = player:WaitForChild("PlayerGui")
	for _, item in playerGui:GetDescendants() do
		watch(item)
	end
	playerGui.DescendantAdded:Connect(watch)
end

return ClickSounds
