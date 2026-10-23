--!strict
-- The pads that open during play and get a short camera cinematic the moment they do: where the pad
-- is and what it is for. Each one plays once per profile (the server keeps flags.unlocksShown, so a New
-- Season that locks floors again does not replay them). The treadmill is left out: the level-up
-- tutorial already walks the player there. Pure, so it is unit tested.

local Config = require(script.Parent.Config)
local Progress = require(script.Parent.Progress)
local Roster = require(script.Parent.Roster)
local Types = require(script.Parent.Types)

type ProgressData = Types.ProgressData

export type Unlock = {
	id: string,
	padKind: string, -- the pad marker's Kind in the plot template
	padId: string, -- its PadId
	title: string,
	detail: string, -- one line on what the pad does
	unlocked: (data: ProgressData) -> boolean,
}

local Unlocks = {}

-- The pad of the first slot of a floor: where the camera looks when the floor opens.
local function firstPadOf(floor: number): string
	local best: Config.PlayerDef? = nil
	for _, def in Config.Players do
		if def.floor == floor and (best == nil or def.slot < best.slot) then
			best = def
		end
	end
	assert(best, "no player on floor " .. floor)
	return best.id
end

local function floorUnlock(floor: number, title: string, detail: string): Unlock
	local padId = firstPadOf(floor)
	return {
		id = "floor" .. floor,
		padKind = if floor == Config.LegendFloor then "legend" else "player",
		padId = padId,
		title = title,
		detail = detail,
		unlocked = function(data: ProgressData): boolean
			return Roster.floorUnlocked(data, floor)
		end,
	}
end

local function storeUnlock(id: Config.StoreUpgradeId, title: string, detail: string): Unlock
	return {
		id = "store_" .. id,
		padKind = "store",
		padId = id,
		title = title,
		detail = detail,
		unlocked = function(data: ProgressData): boolean
			return Progress.storeUnlocked(data, id)
		end,
	}
end

-- The skill games open once the first player has been levelled up (PadInfo says the same).
local function skillUnlock(id: string, padId: string, title: string, detail: string): Unlock
	return {
		id = id,
		padKind = "training",
		padId = padId,
		title = title,
		detail = detail,
		unlocked = function(data: ProgressData): boolean
			return Progress.trainingUnlocked(data) and Progress.firstLevelDone(data)
		end,
	}
end

-- In the order they play when several open at once.
Unlocks.LIST = {
	skillUnlock(
		"keepie",
		"trainingKeepie",
		"KEEPIE-UPPIES",
		"Tap in time to juggle the ball and earn TP."
	),
	skillUnlock(
		"breakaway",
		"trainingFreekick",
		"1V1 BREAKAWAY",
		"Dribble past the defender and score to earn TP."
	),
	{
		id = "stadium",
		padKind = "stadium",
		padId = "stadium",
		title = "STADIUM UPGRADE",
		detail = "Your field is full. Upgrade the stadium to field more players and earn more.",
		unlocked = function(data: ProgressData): boolean
			local tier = Config.StadiumTiers[data.stadiumTier]
			return Progress.nextTier(data) ~= nil
				and tier ~= nil
				and Roster.ownedCount(data) >= tier.field
		end,
	},
	storeUnlock("hatTrick", "HAT-TRICK CHANCE", "Buy it for more matches that pay double."),
	storeUnlock(
		"matchSpeed",
		"FASTER MATCHES",
		"Shorter matches, so your team gets paid more often."
	),
	storeUnlock(
		"gymRate",
		"FASTER TRAINING",
		"More TP a minute on the treadmill and the bench press."
	),
	floorUnlock(
		2,
		"FLOOR 2 IS OPEN",
		"New players to sign upstairs. Take the stairs or the FLOOR buttons."
	),
	floorUnlock(
		3,
		"FLOOR 3 IS OPEN",
		"New players to sign upstairs. Take the stairs or the FLOOR buttons."
	),
	floorUnlock(4, "LEGENDS FLOOR", "Reach each Legend's goals, then sign them with cash."),
} :: { Unlock }

Unlocks.byId = {} :: { [string]: Unlock }
for _, unlock in Unlocks.LIST do
	Unlocks.byId[unlock.id] = unlock
end

-- The unlocks that are open now but not shown yet, in LIST order.
function Unlocks.newlyOpen(data: ProgressData, shown: { [string]: boolean }): { Unlock }
	local found = {}
	for _, unlock in Unlocks.LIST do
		if not shown[unlock.id] and unlock.unlocked(data) then
			table.insert(found, unlock)
		end
	end
	return found
end

-- Marks every unlock that is already open as shown, for a profile that existed before the
-- cinematics: a returning player is not shown everything they unlocked long ago.
function Unlocks.seed(data: ProgressData, shown: { [string]: boolean })
	for _, unlock in Unlocks.LIST do
		if unlock.unlocked(data) then
			shown[unlock.id] = true
		end
	end
end

return Unlocks
