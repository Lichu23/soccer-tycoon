--!strict
-- The Studio-only test shortcuts. The handler is registered only while running in Studio, so in a
-- published game the DevCommand remote does nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Actions = require(script.Parent.Actions)
local Boosts = require(script.Parent.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local DevCommands = require(script.Parent.DevCommands)
local Offline = require(script.Parent.Offline)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Sync = require(script.Parent.Sync)

local DevTools = {}

function DevTools.start()
	if not RunService:IsStudio() then
		return
	end
	Remotes.on("DevCommand", function(player: Player, ...: any)
		local command, amount = select(1, ...)
		local session = Session.get(player)
		if session == nil then
			return
		end
		if command == "stadiumUp" then
			-- A free stadium upgrade (tier +1, with its boost) to try the cinematic.
			if session.data.stadiumTier < #Config.StadiumTiers then
				session.data.stadiumTier += 1
				Boosts.startStadium(session.data)
				Actions.onChange(session, "stadium", nil)
			end
		elseif command == "simulateAway" then
			-- Pretends the player was away for `amount` hours and pays it the way a join does.
			session.data.lastSeen = os.time() - math.floor(amount * 3600)
			local earned, secondsAway = Offline.apply(session.data, os.time())
			if earned > 0 then
				Sync.offline(player, earned, secondsAway)
			end
			Actions.onChange(session, "dev", nil)
			print(
				string.format(
					"[DevTools] %s: away %sh, earned %s",
					player.Name,
					tostring(amount),
					tostring(earned)
				)
			)
		elseif DevCommands.apply(session.data, command, amount) then
			session.runtime.nextMatchAt = 0
			Actions.onChange(session, "dev", nil)
			print(string.format("[DevTools] %s: %s %s", player.Name, command, tostring(amount)))
		end
	end)
end

return DevTools
