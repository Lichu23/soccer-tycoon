--!strict
-- The background music and its MUSIC button, the last of the row at the left edge (client/Dock). The
-- music starts with the game; a tap turns it off or on again. Turned off, the tile shows its muted
-- picture (the notes with a red slash). The choice lasts for this visit only.

local Players = game:GetService("Players")

local Dock = require(script.Parent.Dock)
local Icons = require(script.Parent.Icons)
local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer

local ACCENT = Color3.fromRGB(255, 140, 190)

local MusicUi = {}

function MusicUi.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Music"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 4
	gui.Parent = player:WaitForChild("PlayerGui")

	local tile = Dock.build(gui, "MusicIcon", 5, "MUSIC", ACCENT, "music")
	local function render()
		local on = Sounds.musicOn()
		local picture = tile.picture
		if picture then
			picture.Image = Icons.id(if on then "music" else "music_off")
		else
			tile.label.Text = if on then "MUSIC" else "MUTED"
		end
		Dock.paint(tile, "open")
	end
	tile.button.Activated:Connect(function()
		Sounds.setMusicOn(not Sounds.musicOn())
		render()
	end)
	render()

	Sounds.preload()
	Sounds.startMusic()
end

return MusicUi
