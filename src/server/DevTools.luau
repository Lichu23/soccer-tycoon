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
local Plots = require(script.Parent.Plots)
local Remotes = require(script.Parent.Remotes)
local Reveals = require(script.Parent.Reveals)
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
		elseif command == "revealRarity" then
			-- Grants the cheapest unowned player of rarity number `amount` (1 Common to 5 Legend) as
			-- a first of that rarity won from a case. With all of them owned it is a duplicate star.
			local rarity = Config.RarityOrder[math.floor(amount)]
			if rarity == nil then
				return
			end
			local target: string? = nil
			for _, def in Config.Players do
				if def.rarity == rarity then
					target = target or def.id
					if session.data.players[def.id] == nil then
						target = def.id
						break
					end
				end
			end
			if target then
				if session.data.players[target] == nil then
					session.data.seenRarities[rarity] = nil
				end
				Reveals.grant(session.data, target, true)
				session.data.fieldStarted = true
				session.runtime.nextMatchAt = 0
				Actions.onChange(session, "player", target)
			end
		elseif command == "quickStart" then
			-- Skips the opening: claims a plot (no tour), floor 1, the level-up tutorial done, the
			-- first match without its camera and the penalty screen that opens by itself.
			DevCommands.apply(session.data, "quickStart", 0)
			session.runtime.firstMatchShown = true
			session.runtime.nextMatchAt = 0
			Plots.assign(session, nil)
			Actions.onChange(session, "dev", nil)
			-- Stands the player just inside the gate, where the claim ring was.
			local plot = session.runtime.plot
			local gate = plot and plot:FindFirstChild("Gate")
			local character = player.Character
			if plot and gate and gate:IsA("BasePart") and character then
				local inward = plot:GetBoundingBox().Position - gate.Position
				inward = Vector3.new(inward.X, 0, inward.Z).Unit
				local spot = gate.Position + inward * 8 + Vector3.new(0, 3, 0)
				character:PivotTo(CFrame.lookAt(spot, spot + inward))
			end
			print(string.format("[DevTools] %s: quickStart", player.Name))
		elseif command == "playIntro" then
			-- Plays an intro cinematic again (1 the plot tour, 2 the first-match camera), also while
			-- DevSkipIntros is on. The client checks that the plot exists.
			local kind = if amount == 1 then "plotTour" elseif amount == 2 then "firstMatch" else nil
			if kind and session.runtime.plot then
				Remotes.fireClient("Notice", player, { kind = kind })
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
