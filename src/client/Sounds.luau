--!strict
-- The sound effects (docs/PLAN.md, Step 8, audio). Like the HUD icons (client/Icons), the sounds are
-- files uploaded to Roblox: each upload gets an asset id, and the code only needs that number. An
-- empty id means no sound yet, and the effect stays silent. To add one: in Studio open View >
-- Toolbox > Marketplace > Audio (or upload your own file in Creator Hub), pick a short sound, copy its
-- asset id and paste "rbxassetid://<id>" below. Only sounds the experience may use will play.

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Sounds = {}

Sounds.ids = {
	kick = "rbxassetid://9119340059", -- the ball is struck
	goal = "rbxassetid://182006959", -- a goal: the crowd screams
	net = "rbxassetid://5568887127", -- the ball hits the net
	post = "rbxassetid://129307213411297", -- it goes wide and hits the post
	save = "", -- the keeper saves it (no sound yet)
} :: { [string]: string }

-- How loud each effect is (0 to 1); a cheer is quieter than a short tap.
Sounds.volumes = {
	kick = 0.7,
	goal = 0.6,
	net = 0.7,
	post = 0.7,
	save = 0.6,
} :: { [string]: number }

-- A long sound is cut after this many seconds, with a short fade (the crowd scream is 12 s long).
Sounds.maxSeconds = {
	goal = 3.5,
} :: { [string]: number }
local FADE_SECONDS = 0.6

local templates: { [string]: Sound } = {}

-- Downloads every sound once at the start, so the first kick does not wait for the files: a sound
-- loaded only when it plays arrives a moment late. Each effect then plays a copy of its template.
function Sounds.preload()
	local folder = Instance.new("Folder")
	folder.Name = "SoundTemplates"
	folder.Parent = SoundService
	local list: { Instance } = {}
	for name, id in Sounds.ids do
		if id ~= "" then
			local template = Instance.new("Sound")
			template.Name = name
			template.SoundId = id
			template.Volume = Sounds.volumes[name] or 0.6
			template.Parent = folder
			templates[name] = template
			table.insert(list, template)
		end
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

-- Plays `name` once, for this player only. Nothing happens while its id is empty.
function Sounds.play(name: string)
	local id = Sounds.ids[name]
	if id == nil or id == "" then
		return
	end
	local template = templates[name]
	local sound: Sound
	if template then
		sound = template:Clone()
	else
		sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Volume = Sounds.volumes[name] or 0.6
	end
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
	local limit = Sounds.maxSeconds[name]
	if limit then
		task.delay(limit, function()
			if sound.Parent == nil then
				return
			end
			local fade = TweenService:Create(sound, TweenInfo.new(FADE_SECONDS), { Volume = 0 })
			fade.Completed:Connect(function()
				sound:Destroy()
			end)
			fade:Play()
		end)
	end
end

return Sounds
