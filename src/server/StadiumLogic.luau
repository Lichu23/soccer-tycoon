--!strict
-- What the client needs to play the stadium upgrade cinematic (docs/PLAN.md, Step 7). Pure, so
-- the rules are unit tested: the first upgrade a player ever buys cannot be skipped, later ones
-- can, and the text shows the field growing and the free boost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type UpgradeInfo = {
	tier: number,
	fieldFrom: number,
	fieldTo: number,
	canSkip: boolean,
	boostSeconds: number,
	boostMultiplier: number,
	seconds: number,
	maxSeconds: number,
}

local StadiumLogic = {}

function StadiumLogic.upgradeInfo(newTier: number, firstEver: boolean): UpgradeInfo
	local def = Config.StadiumTiers[newTier]
	local before = Config.StadiumTiers[newTier - 1]
	return {
		tier = newTier,
		fieldFrom = if before then before.field else def.field,
		fieldTo = def.field,
		canSkip = not firstEver,
		boostSeconds = Config.Boost.stadiumSeconds,
		boostMultiplier = Config.Boost.stadiumMultiplier,
		seconds = Config.Cinematic.seconds,
		maxSeconds = Config.Cinematic.maxSeconds,
	}
end

return StadiumLogic
