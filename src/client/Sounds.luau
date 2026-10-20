--!strict
-- The sound effects (docs/PLAN.md, Step 8, audio). Like the HUD icons (client/Icons), the sounds are
-- files uploaded to Roblox: each upload gets an asset id, and the code only needs that number. An
-- empty id means no sound yet, and the effect stays silent. To add one: in Studio open View >
-- Toolbox > Marketplace > Audio (or upload your own file in Creator Hub), pick a short sound, copy its
-- asset id and paste "rbxassetid://<id>" below. Only sounds the experience may use will play.

local SoundService = game:GetService("SoundService")

local Sounds = {}

Sounds.ids = {
	kick = "", -- the ball is struck
	goal = "", -- a goal: a cheer
	save = "", -- the keeper saves it
	miss = "", -- it goes wide: a groan
} :: { [string]: string }

-- How loud each effect is (0 to 1); a cheer is quieter than a short tap.
Sounds.volumes = {
	kick = 0.7,
	goal = 0.6,
	save = 0.6,
	miss = 0.5,
} :: { [string]: number }

-- Plays `name` once, for this player only. Nothing happens while its id is empty.
function Sounds.play(name: string)
	local id = Sounds.ids[name]
	if id == nil or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = Sounds.volumes[name] or 0.6
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end

return Sounds
