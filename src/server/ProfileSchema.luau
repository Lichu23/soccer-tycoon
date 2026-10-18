--!strict
-- The shape of a saved profile and the rules around it (docs/PLAN.md, Step 6): the template,
-- migrations, reconcile, the checks that run before every save, and receipt pruning.
-- Pure, so it is unit tested. Only values that cannot be recomputed are stored.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Receipt = {
	at: number, -- os.time() when the purchase was granted
	result: { [string]: any }, -- what was granted, for example { kind = "case", playerId = "kane", isNew = true }
}

export type PendingReveal = {
	playerId: string,
	isNew: boolean,
}

export type Profile = {
	version: number,
	cash: number,
	tp: number,
	staminaLeft: number, -- seconds left in the current training session
	lastSeen: number, -- os.time(), for offline earnings
	stadiumTier: number,
	storeLevels: { cashPerMatch: number, matchSpeed: number, hatTrick: number, offline: number },
	fieldStarted: boolean,
	players: { [string]: { level: number, stars: number } }, -- owned only, Legends included
	season: { number: number },
	trials: { [string]: { [string]: boolean } }, -- Legend Trial goals, never unset
	cosmetics: { owned: { [string]: boolean }, chosen: { [string]: string } },
	daily: { caseClaimedAt: number, penaltyBatchAt: number, kicksUsed: number },
	boosts: { bankedMatches: number, stadiumBoostLeft: number },
	receipts: { [string]: Receipt },
	pendingReveals: { PendingReveal },
	seenRarities: { [string]: boolean },
	flags: {
		firstHatTrickDone: boolean,
		notificationAsked: boolean,
		hasClaimedPlot: boolean, -- a returning player gets a plot at once, without the claim ring
		milestones: { [string]: number }, -- first_purchase, first_match... -> os.time() when first reached
	},
}

local ProfileSchema = {}

ProfileSchema.CURRENT_VERSION = 1

-- Receipts are kept for 30 days or the newest 100, whichever keeps more (Step 6).
ProfileSchema.RECEIPT_KEEP_SECONDS = 30 * 24 * 60 * 60
ProfileSchema.RECEIPT_KEEP_COUNT = 100

-- A fresh profile for a new player. ProfileStore also uses this as its template.
function ProfileSchema.newProfile(): Profile
	return {
		version = ProfileSchema.CURRENT_VERSION,
		cash = Config.StartingCash,
		tp = 0,
		staminaLeft = Config.Training.staminaSeconds,
		lastSeen = 0,
		stadiumTier = 1,
		storeLevels = { cashPerMatch = 0, matchSpeed = 0, hatTrick = 0, offline = 0 },
		fieldStarted = false,
		players = {},
		season = { number = 1 },
		trials = {},
		cosmetics = { owned = {}, chosen = {} },
		daily = { caseClaimedAt = 0, penaltyBatchAt = 0, kicksUsed = 0 },
		boosts = { bankedMatches = 0, stadiumBoostLeft = 0 },
		receipts = {},
		pendingReveals = {},
		seenRarities = {},
		flags = {
			firstHatTrickDone = false,
			notificationAsked = false,
			hasClaimedPlot = false,
			milestones = {},
		},
	}
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

-- Fills only the missing keys from the template and never overwrites a stored value, so it
-- handles fields added after a profile was saved. Maps keyed by ids (players, trials,
-- receipts...) have empty templates, so their contents are left alone.
function ProfileSchema.reconcile(target: { [any]: any }, template: { [any]: any })
	for key, default in template do
		local current = target[key]
		if current == nil then
			target[key] = deepCopy(default)
		elseif type(current) == "table" and type(default) == "table" then
			ProfileSchema.reconcile(current, default)
		end
	end
end

-- migrations[n] upgrades data from version n to n + 1. Reconcile handles added fields, a
-- migration is for a changed meaning. Never rename or repurpose a field without one.
local migrations: { [number]: (data: { [string]: any }) -> () } = {}
ProfileSchema.migrations = migrations

-- Brings saved data up to the current version in place. Returns false and a reason when
-- the data is from a newer version (a downgrade must never overwrite it).
function ProfileSchema.migrate(data: { [string]: any }): (boolean, string?)
	local version = data.version
	if version == nil then
		-- Nothing saved yet (a brand-new profile): stamp the current version.
		data.version = ProfileSchema.CURRENT_VERSION
		return true, nil
	end
	if type(version) ~= "number" or version ~= math.floor(version) or version < 1 then
		return false, "invalid profile version"
	end
	if version > ProfileSchema.CURRENT_VERSION then
		return false,
			string.format(
				"profile version %d is newer than %d",
				version,
				ProfileSchema.CURRENT_VERSION
			)
	end
	while version < ProfileSchema.CURRENT_VERSION do
		local step = migrations[version]
		if not step then
			return false, string.format("no migration from version %d", version)
		end
		step(data)
		version += 1
		data.version = version
	end
	return true, nil
end

-- Checks ---------------------------------------------------------------------------------

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- One bad value makes the whole write fail, so walk everything: only finite numbers, valid
-- UTF-8 strings, booleans and tables with string or number keys may be stored.
local function checkTree(value: any, path: string, depth: number): string?
	if depth > 8 then
		return path .. ": nested too deep"
	end
	local kind = type(value)
	if kind == "number" then
		if not isFiniteNumber(value) then
			return path .. ": number is not finite"
		end
	elseif kind == "string" then
		if utf8.len(value) == nil then
			return path .. ": string is not valid UTF-8"
		end
	elseif kind == "boolean" then
		return nil
	elseif kind == "table" then
		for key, inner in value do
			if type(key) ~= "string" and type(key) ~= "number" then
				return path .. ": a key is not a string or number"
			end
			local problem = checkTree(inner, path .. "." .. tostring(key), depth + 1)
			if problem then
				return problem
			end
		end
	else
		return path .. ": a " .. kind .. " cannot be saved"
	end
	return nil
end

local function isCount(value: any, max: number?): boolean
	return isFiniteNumber(value)
		and value >= 0
		and value == math.floor(value)
		and (max == nil or value <= max)
end

-- Runs before every save. Returns true, or false and the first problem found.
function ProfileSchema.validate(profile: { [string]: any }): (boolean, string?)
	local problem = checkTree(profile, "profile", 0)
	if problem then
		return false, problem
	end

	if profile.version ~= ProfileSchema.CURRENT_VERSION then
		return false, "profile.version is not current"
	end
	if
		not (isFiniteNumber(profile.cash) and profile.cash >= 0 and profile.cash <= Config.MaxCash)
	then
		return false, "profile.cash is out of range"
	end
	if not isCount(profile.tp) then
		return false, "profile.tp is out of range"
	end
	if not isFiniteNumber(profile.staminaLeft) or profile.staminaLeft < 0 then
		return false, "profile.staminaLeft is out of range"
	end
	if not isCount(profile.stadiumTier, #Config.StadiumTiers) or profile.stadiumTier < 1 then
		return false, "profile.stadiumTier is out of range"
	end
	for id, def in Config.Store do
		local level = profile.storeLevels[id]
		if not isCount(level, #def.prices) then
			return false, "profile.storeLevels." .. id .. " is out of range"
		end
	end
	for playerId, owned in profile.players do
		local def = Config.PlayersById[playerId]
		if not def then
			return false, "profile.players has an unknown id: " .. tostring(playerId)
		end
		local cap = Config.Rarities[def.rarity].levelCap
		if not isCount(owned.level, cap) then
			return false, "profile.players." .. playerId .. ".level is out of range"
		end
		if not isCount(owned.stars, Config.Stars.maxStars) then
			return false, "profile.players." .. playerId .. ".stars is out of range"
		end
	end
	if not isCount(profile.season.number) or profile.season.number < 1 then
		return false, "profile.season.number is out of range"
	end
	if
		not isCount(profile.boosts.bankedMatches, 10_000)
		or not isCount(profile.boosts.stadiumBoostLeft)
	then
		return false, "profile.boosts is out of range"
	end
	if not isCount(profile.daily.kicksUsed, Config.Daily.penaltyKicks) then
		return false, "profile.daily.kicksUsed is out of range"
	end
	return true, nil
end

-- Receipts ---------------------------------------------------------------------------------

-- Drops receipts older than the keep window, but always keeps the newest ones.
function ProfileSchema.pruneReceipts(profile: { receipts: { [string]: Receipt } }, now: number)
	local entries: { { id: string, at: number } } = {}
	for id, receipt in profile.receipts do
		table.insert(entries, { id = id, at = receipt.at })
	end
	table.sort(entries, function(a, b)
		return a.at > b.at
	end)
	local cutoff = now - ProfileSchema.RECEIPT_KEEP_SECONDS
	for index, entry in entries do
		if index > ProfileSchema.RECEIPT_KEEP_COUNT and entry.at < cutoff then
			profile.receipts[entry.id] = nil
		end
	end
end

return ProfileSchema
