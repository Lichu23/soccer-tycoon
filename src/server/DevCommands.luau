--!strict
-- Test shortcuts for Studio playtests (docs/PLAN.md, Step 6): grant whole floors, set the cash,
-- reset the profile. Pure on the profile so it is unit tested. DevTools only wires it to a remote
-- while running in Studio, never in a published game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Roster = require(ReplicatedStorage.Shared.Roster)

local DevCommands = {}

DevCommands.commands = { "grantFloor", "setCash", "resetProfile", "simulateAway" }

-- Applies one command. Returns false for an unknown command.
--   grantFloor n: owns every cash-floor player of floors 1 to n (Legends are never granted)
--   setCash n:    sets the cash (clamped to the maximum)
--   resetProfile: back to a brand-new profile
function DevCommands.apply(data: ProfileSchema.Profile, command: string, amount: number): boolean
	if command == "grantFloor" then
		for _, def in Config.Players do
			if def.floor <= amount and def.floor <= Config.CashFloors then
				Roster.add(data, def.id)
			end
		end
		data.fieldStarted = true
		return true
	elseif command == "setCash" then
		data.cash = math.clamp(amount, 0, Config.MaxCash)
		return true
	elseif command == "resetProfile" then
		local fresh = ProfileSchema.newProfile()
		for key, value in fresh do
			(data :: any)[key] = value
		end
		return true
	end
	return false
end

return DevCommands
