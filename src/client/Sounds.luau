--!strict
-- The sound effects (docs/PLAN.md, Step 8, audio). Like the HUD icons (client/Icons), the sounds are
-- files uploaded to Roblox: each upload gets an asset id, and the code only needs that number. An
-- empty id means no sound yet, and the effect stays silent. To add one: in Studio open View >
-- Toolbox > Marketplace > Audio (or upload your own file in Creator Hub), pick a short sound, copy its
-- asset id and paste "rbxassetid://<id>" below. Only sounds the experience may use will play.
-- Nothing is ever cut off: a sound that has to stop (a long one, or the screen closing) fades out.

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Sounds = {}

Sounds.ids = {
	kick = "rbxassetid://9119340059", -- the ball is struck
	goal = "rbxassetid://182006959", -- a goal: the crowd screams
	net = "rbxassetid://5568887127", -- the ball hits the net
	post = "rbxassetid://129307213411297", -- it goes wide and hits the post
	save = "rbxassetid://9114010169", -- the keeper saves it
	ambience = "rbxassetid://9119562311", -- the stadium around the penalty screen, looped
} :: { [string]: string }

-- How loud each effect is (0 to 1); a cheer is quieter than a short tap.
Sounds.volumes = {
	kick = 0.7,
	goal = 0.6,
	net = 0.7,
	post = 0.7,
	save = 0.6,
	ambience = 0.35,
} :: { [string]: number }

-- A long sound is cut after this many seconds, with a short fade (the crowd scream is 12 s long, the save 6 s).
Sounds.maxSeconds = {
	goal = 2,
	save = 2,
} :: { [string]: number }
local FADE_SECONDS = 0.6 -- the fade at the end of a sound that is cut short
local AMBIENCE_FADE_IN = 0.8

local templates: { [string]: Sound } = {}
local active: { [Sound]: boolean } = {} -- the effects playing now
local ambience: Sound? = nil

-- Ramps the volume of `sound` to `volume` over `seconds`, then calls `done`.
local function fade(sound: Sound, seconds: number, volume: number, done: (() -> ())?)
	local tween = TweenService:Create(sound, TweenInfo.new(seconds), { Volume = volume })
	if done then
		tween.Completed:Connect(done)
	end
	tween:Play()
end

-- A new sound made from the template of `name` (already downloaded), or from the id.
local function make(name: string): Sound?
	local id = Sounds.ids[name]
	if id == nil or id == "" then
		return nil
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
	return sound
end

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
	local sound = make(name)
	if sound == nil then
		return
	end
	active[sound] = true
	sound.Destroying:Connect(function()
		active[sound] = nil
	end)
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
	local limit = Sounds.maxSeconds[name]
	if limit then
		-- The fade is part of the limit, so the sound is silent after `limit` seconds in all.
		task.delay(math.max(limit - FADE_SECONDS, 0), function()
			if sound.Parent == nil then
				return
			end
			fade(sound, FADE_SECONDS, 0, function()
				sound:Destroy()
			end)
		end)
	end
end

-- The loop of the place around the screen fades in; it plays until stopAmbience.
function Sounds.startAmbience()
	if ambience ~= nil then
		return
	end
	local sound = make("ambience")
	if sound == nil then
		return
	end
	sound.Looped = true
	sound.Volume = 0
	sound:Play()
	ambience = sound
	fade(sound, AMBIENCE_FADE_IN, Sounds.volumes.ambience or 0.35, nil)
end

-- Fades the loop out over `seconds` and removes it.
function Sounds.stopAmbience(seconds: number)
	local sound = ambience
	if sound == nil then
		return
	end
	ambience = nil
	fade(sound, seconds, 0, function()
		sound:Destroy()
	end)
end

-- When a screen closes: every sound still playing fades out over `seconds`, none is cut off.
function Sounds.fadeOutAll(seconds: number)
	Sounds.stopAmbience(seconds)
	for sound in active do
		active[sound] = nil
		fade(sound, seconds, 0, function()
			sound:Destroy()
		end)
	end
end

return Sounds
