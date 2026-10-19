--!strict
-- Test shortcuts for Studio playtests (docs/PLAN.md, Step 6): grant whole floors, set the cash,
-- reset the profile. Pure on the profile so it is unit tested. DevTools only wires it to a remote
-- while running in Studio, never in a published game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Roster = require(ReplicatedStorage.Shared.Roster)

local DevCommands = {}

DevCommands.commands = {
	"grantFloor",
	"setCash",
	"resetProfile",
	"simulateAway",
	"stadiumUp",
	"resetDaily",
	"grantTp",
	"offerWait",
}

-- Applies one command. Returns false for an unknown command.
--   grantFloor n: owns every cash-floor player of floors 1 to n (Legends are never granted)
--   setCash n:    sets the cash (clamped to the maximum)
--   grantTp n:    adds n training points
--   resetDaily:   the free case and the penalty kicks are ready again
--   offerWait:    the 30-minute wait before cases are offered has passed
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
	elseif command == "grantTp" then
		data.tp = math.min(data.tp + math.floor(amount), 1_000_000_000)
		return true
	elseif command == "resetDaily" then
		data.daily = { caseClaimedAt = 0, penaltyBatchAt = 0, kicksUsed = 0, goals = 0 }
		data.boosts.penaltyBoostLeft = 0
		return true
	elseif command == "offerWait" then
		data.flags.milestones["first_purchase"] = os.time() - Config.CaseRules.noOfferSeconds - 1
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
