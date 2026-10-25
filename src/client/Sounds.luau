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
	cash = "rbxassetid://79392333090964", -- the match is over: VICTORY and its cash
	cantAfford = "rbxassetid://91501650514390", -- standing on a pad without enough cash
	buy = "rbxassetid://130378474223829", -- cash spent on a pad: a player or a Store upgrade
	tick = "rbxassetid://9125478514", -- a card of the case roulette passes the marker
	purchase = "rbxassetid://9039637427", -- a Robux purchase is done (its card shows)
} :: { [string]: string }

-- The background music: the tracks play one after another, round and round (APM Music, free to use
-- in any experience). The player can turn it off with the MUSIC button (client/MusicUi).
Sounds.music = {
	"rbxassetid://9041954387", -- Nawlins Carnival Kids (b), 60 s
	"rbxassetid://9043849843", -- Brilliant Stars, 112 s
}

-- How loud each effect is (0 to 1); a cheer is quieter than a short tap.
Sounds.volumes = {
	kick = 0.7,
	goal = 0.6,
	net = 0.7,
	post = 0.7,
	save = 7, -- the file is very quiet (about 15 on the loudness scale, the others 100 to 340), so it is boosted
	ambience = 0.35,
	cash = 0.7,
	cantAfford = 0.4,
	buy = 0.6,
	tick = 0.35,
	purchase = 0.6,
} :: { [string]: number }
local MUSIC_VOLUME = 0.15
local MUSIC_FADE = 1.5
local DUCK_VOLUME = 0.3 -- the share of the music volume left while a sting or the penalty crowd plays

-- A long sound is cut after this many seconds, with a short fade (the crowd scream is 12 s long, the save 6 s).
Sounds.maxSeconds = {
	goal = 2,
	save = 2,
	purchase = 3,
} :: { [string]: number }
-- The stings that lower the music while they play, so they are heard over it.
local DUCKS = { purchase = true }
-- Sounds that never pile up: a new one quickly fades out the copy still playing (standing on pads
-- one after another).
local SINGLE = { cantAfford = true, buy = true, purchase = true }
local CUT_SECONDS = 0.15
-- Where in the file a sound starts, in seconds (the save sound has a quiet first second).
Sounds.startAt = {
	save = 1,
} :: { [string]: number }
local FADE_SECONDS = 0.6 -- the fade at the end of a sound that is cut short
local AMBIENCE_FADE_IN = 0.8

local templates: { [string]: Sound } = {}
local active: { [Sound]: boolean } = {} -- the effects playing now
local ambience: Sound? = nil
local music: Sound? = nil
local musicOn = true
local musicTrack = 0
local ducks = 0 -- how many stings (or the penalty crowd) hold the music down now
local latest: { [string]: Sound } = {} -- the last copy of each SINGLE sound

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
	if next(templates) ~= nil then
		return
	end
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

-- The volume the music should have now: off, held down under a sting, or full.
local function musicVolume(): number
	if not musicOn then
		return 0
	end
	return if ducks > 0 then MUSIC_VOLUME * DUCK_VOLUME else MUSIC_VOLUME
end

local function refreshMusic(seconds: number)
	local sound = music
	if sound then
		fade(sound, seconds, musicVolume(), nil)
	end
end

-- Holds the music down for `seconds`, then lets it back up (stings that overlap stack).
local function duck(seconds: number)
	ducks += 1
	refreshMusic(0.2)
	task.delay(seconds, function()
		ducks -= 1
		refreshMusic(0.6)
	end)
end

-- Plays `name` once, for this player only. Nothing happens while its id is empty.
function Sounds.play(name: string)
	local sound = make(name)
	if sound == nil then
		return
	end
	if SINGLE[name] then
		local previous = latest[name]
		if previous and previous.Parent ~= nil then
			active[previous] = nil
			fade(previous, CUT_SECONDS, 0, function()
				previous:Destroy()
			end)
		end
		latest[name] = sound
	end
	active[sound] = true
	sound.Destroying:Connect(function()
		active[sound] = nil
	end)
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	local startAt = Sounds.startAt[name]
	if startAt then
		sound.TimePosition = startAt
	end
	sound:Play()
	local limit = Sounds.maxSeconds[name]
	if DUCKS[name] then
		duck(limit or 3)
	end
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
	ducks += 1 -- the penalty crowd replaces the music until it stops
	refreshMusic(AMBIENCE_FADE_IN)
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
	ducks -= 1
	refreshMusic(seconds)
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

-- Starts the background music: each track fades in, plays to its end and the next one follows.
function Sounds.startMusic()
	if music ~= nil or #Sounds.music == 0 then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.Volume = 0
	sound.Parent = SoundService
	music = sound
	local function nextTrack()
		musicTrack = musicTrack % #Sounds.music + 1
		sound.SoundId = Sounds.music[musicTrack]
		sound.TimePosition = 0
		sound:Play()
		refreshMusic(MUSIC_FADE)
	end
	sound.Ended:Connect(nextTrack)
	nextTrack()
end

-- Turns the music on or off (it fades; the track keeps running silently, so it resumes in place).
function Sounds.setMusicOn(on: boolean)
	musicOn = on
	refreshMusic(0.4)
end

function Sounds.musicOn(): boolean
	return musicOn
end

return Sounds
