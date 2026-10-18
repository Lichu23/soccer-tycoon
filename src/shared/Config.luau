--!strict
-- Every game number and every player lives here (docs/PLAN.md, Steps 1 and 3).
-- All values are placeholders from the economy draft: tune them here, not in code.
-- Shared code holds no secrets: the client may read all of this.

export type Rarity = "Common" | "Rare" | "VeryRare" | "Epic" | "Legend"

export type PlayerDef = {
	id: string,
	name: string,
	nationality: string,
	number: number, -- provisional shirt numbers, verify before launch
	rarity: Rarity,
	floor: number,
	slot: number, -- 1 to 35, orders price and income
	price: number,
	income: number, -- cash per match when on the field
}

export type RarityDef = {
	order: number,
	levelCap: number,
	costFactor: number, -- training level cost multiplier
}

export type StoreUpgradeId = "cashPerMatch" | "matchSpeed" | "hatTrick" | "offline"

export type StoreUpgradeDef = {
	id: StoreUpgradeId,
	baseValue: number, -- value at level 0
	prices: { number }, -- prices[level] buys that level
	values: { number }, -- values[level] is the value at that level
	minTier: number?, -- stadium tier needed to unlock
	floorsComplete: number?, -- floors completed needed to unlock
}

export type StadiumTierDef = {
	tier: number,
	price: number,
	field: number, -- players on the field
	courtLength: number, -- the pitch of this tier, in studs
	courtWidth: number,
}

local function player(
	id: string,
	name: string,
	nationality: string,
	number: number,
	rarity: Rarity,
	floor: number,
	slot: number,
	price: number,
	income: number
): PlayerDef
	return {
		id = id,
		name = name,
		nationality = nationality,
		number = number,
		rarity = rarity,
		floor = floor,
		slot = slot,
		price = price,
		income = income,
	}
end

-- Prices and incomes for slots 1 to 30 come from the Step 3 table.
-- Legend prices are from Step 3; Legend incomes are NOT in the plan: placeholders that
-- continue the floor 3 growth (about x1.6 per Legend). Tune them in the simulation.
local players: { PlayerDef } = {
	-- Floor 1
	player("rashford", "Marcus Rashford", "England", 10, "Common", 1, 1, 10, 3),
	player("grealish", "Jack Grealish", "England", 10, "Common", 1, 2, 30, 5),
	player("sterling", "Raheem Sterling", "England", 7, "Common", 1, 3, 70, 9),
	player("joao_felix", "João Félix", "Portugal", 11, "Common", 1, 4, 150, 16),
	player("son", "Son Heung-min", "South Korea", 7, "Rare", 1, 5, 308, 26),
	player("saka", "Bukayo Saka", "England", 7, "Rare", 1, 6, 630, 41),
	player("griezmann", "Antoine Griezmann", "France", 7, "Rare", 1, 7, 1_300, 66),
	player("pedri", "Pedri", "Spain", 8, "Rare", 1, 8, 2_700, 105),
	player("trent", "Trent Alexander-Arnold", "England", 66, "Rare", 1, 9, 5_400, 168),
	player("gavi", "Gavi", "Spain", 6, "Rare", 1, 10, 11_100, 268),
	-- Floor 2
	player("lautaro", "Lautaro Martínez", "Argentina", 10, "Rare", 2, 11, 21_200, 403),
	player("leao", "Rafael Leão", "Portugal", 10, "Rare", 2, 12, 40_200, 604),
	player("wirtz", "Florian Wirtz", "Germany", 10, "Rare", 2, 13, 76_400, 906),
	player("musiala", "Jamal Musiala", "Germany", 42, "Rare", 2, 14, 145_000, 1_400),
	player("lewandowski", "Robert Lewandowski", "Poland", 9, "VeryRare", 2, 15, 276_000, 2_000),
	player("benzema", "Karim Benzema", "France", 9, "VeryRare", 2, 16, 524_000, 3_100),
	player("modric", "Luka Modrić", "Croatia", 10, "VeryRare", 2, 17, 995_000, 4_600),
	player("kane", "Harry Kane", "England", 9, "VeryRare", 2, 18, 1_900_000, 6_900),
	player("de_bruyne", "Kevin De Bruyne", "Belgium", 7, "VeryRare", 2, 19, 3_600_000, 10_300),
	player("rodri", "Rodri", "Spain", 16, "VeryRare", 2, 20, 6_800_000, 15_500),
	-- Floor 3
	player("foden", "Phil Foden", "England", 47, "VeryRare", 3, 21, 13_700_000, 22_400),
	player("vinicius", "Vinícius Jr", "Brazil", 7, "VeryRare", 3, 22, 27_300_000, 32_500),
	player("bellingham", "Jude Bellingham", "England", 10, "VeryRare", 3, 23, 54_600_000, 47_200),
	player("yamal", "Lamine Yamal", "Spain", 19, "VeryRare", 3, 24, 109_000_000, 68_400),
	player("salah", "Mohamed Salah", "Egypt", 11, "Epic", 3, 25, 218_000_000, 99_200),
	player("neymar", "Neymar", "Brazil", 10, "Epic", 3, 26, 437_000_000, 144_000),
	player("haaland", "Erling Haaland", "Norway", 9, "Epic", 3, 27, 874_000_000, 209_000),
	player("mbappe", "Kylian Mbappé", "France", 10, "Epic", 3, 28, 1_750_000_000, 302_000),
	player("cristiano", "Cristiano Ronaldo", "Portugal", 7, "Epic", 3, 29, 3_490_000_000, 439_000),
	player("messi", "Lionel Messi", "Argentina", 10, "Epic", 3, 30, 6_990_000_000, 636_000),
	-- Floor 4: Legends (retired)
	player("ronaldinho", "Ronaldinho", "Brazil", 10, "Legend", 4, 31, 400_000_000_000, 1_000_000),
	player(
		"zidane",
		"Zinedine Zidane",
		"France",
		10,
		"Legend",
		4,
		32,
		1_000_000_000_000,
		1_600_000
	),
	player(
		"ronaldo_nazario",
		"Ronaldo Nazário",
		"Brazil",
		9,
		"Legend",
		4,
		33,
		2_500_000_000_000,
		2_600_000
	),
	player(
		"maradona",
		"Diego Maradona",
		"Argentina",
		10,
		"Legend",
		4,
		34,
		6_000_000_000_000,
		4_100_000
	),
	player("pele", "Pelé", "Brazil", 10, "Legend", 4, 35, 15_000_000_000_000, 6_600_000),
}

local playersById: { [string]: PlayerDef } = {}
for _, def in players do
	playersById[def.id] = def
end

local Config = {}

Config.Rarities = {
	Common = { order = 1, levelCap = 5, costFactor = 1 },
	Rare = { order = 2, levelCap = 10, costFactor = 2 },
	VeryRare = { order = 3, levelCap = 15, costFactor = 3 },
	Epic = { order = 4, levelCap = 20, costFactor = 4 },
	Legend = { order = 5, levelCap = 25, costFactor = 5 },
} :: { [Rarity]: RarityDef }

Config.RarityOrder = { "Common", "Rare", "VeryRare", "Epic", "Legend" } :: { Rarity }

Config.Players = players
Config.PlayersById = playersById

-- Floors 1 to 3 are the cash floors; floor 4 holds the Legends.
Config.CashFloors = 3
Config.LegendFloor = 4

Config.StartingCash = 15
-- Attributes and doubles are exact up to about 9e15, so cash is clamped just under that.
Config.MaxCash = 9_000_000_000_000_000

Config.Pad = {
	holdSeconds = 1, -- one value for every pad (purchase, level-up, stadium, claim)
}

-- The size of one plot (the plaza slots in tools/studio/BuildMap.luau are spaced for it).
Config.Plot = { width = 280, depth = 300 }

Config.Player = {
	walkSpeed = 32, -- studs per second (Roblox default is 16); every player gets it on spawn
}

Config.Match = {
	seconds = 10, -- base time between matches, before the match speed upgrade
	firstMatchSeconds = 5, -- the very first match is shorter (Step 2)
	hatTrickMultiplier = 2,
	-- The first hat-trick is scripted once (Step 2): it happens on this match of the session,
	-- about minute 4, unless a natural one already came. Afterwards the real odds apply.
	scriptedHatTrickMatch = 22,
	momentumPerMatch = 0.01,
	momentumCap = 0.25,
}

Config.Boost = {
	totalCap = 4, -- timed and banked boosts never multiply above this
	stadiumMultiplier = 2,
	stadiumSeconds = 300, -- counts only while online
	matchPackSize = 30,
	matchBankMax = 60,
	matchMultiplier = 2,
}

export type CaseReward = {
	id: string,
	kind: "cash" | "boost" | "tp",
	label: string,
	detail: string,
	weight: number,
	minutes: number?,
	seconds: number?,
	tp: number?,
}

Config.Daily = {
	cooldownSeconds = 20 * 60 * 60,
	penaltyKicks = 3,
	penaltyMultiplier = 1.5,
	-- Seconds of boost for the number of goals scored out of 3 kicks.
	penaltyBoostSeconds = { [0] = 0, [1] = 180, [2] = 300, [3] = 600 } :: { [number]: number },
	unlockTier = 2, -- the daily icons and the penalty pad open with the first stadium upgrade
	-- Chance that a kick goes wide or over before the keeper is even asked, by aim zone. Corners
	-- are riskier than the middle; the keeper then dives to a random zone.
	zoneMissChance = {
		topLeft = 0.2,
		topRight = 0.2,
		bottomLeft = 0.08,
		bottomRight = 0.08,
		center = 0.03,
	} :: { [string]: number },
	-- The free daily case: five small rewards (never players, never large amounts). `weight` is the
	-- relative chance. Cash is worth `minutes` of normal income, a boost is x2 for `seconds`, `tp`
	-- is a few training points. The roulette on screen spins through exactly these.
	caseRewards = {
		{
			id = "cashSmall",
			kind = "cash",
			label = "Cash",
			detail = "3 min of income",
			minutes = 3,
			weight = 35,
		},
		{
			id = "boostShort",
			kind = "boost",
			label = "x2 boost",
			detail = "3 minutes",
			seconds = 180,
			weight = 25,
		},
		{
			id = "tpSmall",
			kind = "tp",
			label = "Training points",
			detail = "+40 TP",
			tp = 40,
			weight = 20,
		},
		{
			id = "boostLong",
			kind = "boost",
			label = "x2 boost",
			detail = "8 minutes",
			seconds = 480,
			weight = 12,
		},
		{
			id = "cashBig",
			kind = "cash",
			label = "Big cash",
			detail = "8 min of income",
			minutes = 8,
			weight = 8,
		},
	} :: { CaseReward },
}

Config.Offline = {
	capSeconds = 4 * 60 * 60,
}

Config.Stars = {
	bonusPerStar = 0.10,
	maxStars = 5,
}

Config.Training = {
	bonusPerLevel = 0.03,
	levelCostBase = 40, -- cost of level L = base x L x rarity cost factor
	idleTpPerMinute = 10,
	drillTpPerMinuteMax = 15,
	staminaSeconds = 300,
	staminaRefillSeconds = 300, -- time away to refill from empty
	-- The timing drill: a marker sweeps across a bar once per round and one press per round counts.
	-- A press in the middle `drillWindow` (a fraction either side of the centre) pays the extra TP
	-- that lifts the idle rate to the drill maximum if every round is hit.
	drillRoundSeconds = 4,
	drillWindow = 0.15,
}

Config.Season = {
	bonusPerSeason = 0.5, -- permanent multiplier: season 2 = x1.5, season 3 = x2.0
}

Config.Store = {
	cashPerMatch = {
		id = "cashPerMatch",
		baseValue = 1,
		prices = { 15, 60, 240, 960, 3_800, 15_000, 61_000, 246_000 },
		values = { 1.5, 2.1, 2.7, 3.5, 4.3, 5.1, 5.9, 6.7 },
	},
	matchSpeed = {
		id = "matchSpeed",
		baseValue = 10, -- seconds
		prices = { 120, 2_000, 30_000, 500_000, 8_000_000 },
		values = { 9, 8, 7, 6, 5 },
		minTier = 2,
	},
	hatTrick = {
		id = "hatTrick",
		baseValue = 0.10, -- chance
		prices = { 300, 5_000, 80_000, 1_500_000, 25_000_000 },
		values = { 0.12, 0.14, 0.17, 0.21, 0.25 },
		floorsComplete = 1,
	},
	offline = {
		id = "offline",
		baseValue = 0.10, -- share of normal income
		prices = { 500, 10_000, 200_000, 4_000_000, 80_000_000 },
		values = { 0.15, 0.20, 0.25, 0.30, 0.35 },
		floorsComplete = 1,
	},
} :: { [StoreUpgradeId]: StoreUpgradeDef }

-- The upgrade cinematic (docs/PLAN.md, Step 7). The server builds the new pitch after
-- buildDelaySeconds, when the camera has arrived. The client unlocks by itself after maxSeconds.
Config.Cinematic = {
	seconds = 6.5,
	maxSeconds = 9,
	buildDelaySeconds = 1.8,
}

Config.StadiumTiers = {
	{ tier = 1, price = 0, field = 4, courtLength = 60, courtWidth = 36 },
	{ tier = 2, price = 250, field = 5, courtLength = 70, courtWidth = 42 },
	{ tier = 3, price = 25_000, field = 6, courtLength = 84, courtWidth = 50 },
	{ tier = 4, price = 750_000, field = 8, courtLength = 100, courtWidth = 60 },
	{ tier = 5, price = 45_000_000, field = 11, courtLength = 120, courtWidth = 72 },
} :: { StadiumTierDef }

-- Saving (Step 6). Studio uses ProfileStore's Mock store (memory only) unless useRealStoreInStudio
-- is set, and then it writes to studioStoreName, never to the live store.
Config.Data = {
	storeName = "PlayerData",
	studioStoreName = "PlayerData_Studio",
	useRealStoreInStudio = false,
	autoSaveSeconds = 60, -- ProfileStore's own default is 300
	loadTimeoutSeconds = 20, -- retry a locked profile this long, then kick (never steal the lock)
	saveConfirmSeconds = 10, -- how long a purchase waits for its save before giving up
}

-- Switch a feature off here to disable it without a full rework (Step 5).
Config.Features = {
	cases = true,
	trainingDrill = true,
	notifications = true,
}

return Config
