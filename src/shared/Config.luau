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

export type CaseDef = {
	id: string,
	name: string,
	floorsComplete: number, -- floors completed to unlock it
	legendChance: number, -- the share of a pull that is a Legend (fixed, taken off the top)
	-- Shares of the rest: a player of the floors reached, of the next floor, of the floors further on.
	odds: { reached: number, nextFloor: number, further: number },
}

export type ProductDef = {
	key: string,
	kind: "case" | "boost" | "legend" | "cosmetic" | "cash" | "tp",
	robux: number, -- the price shown on the button (the real price is set on the dashboard)
	productId: number, -- the Developer Product id, 0 until it is created on the dashboard
	caseId: string?,
	playerId: string?,
	cosmeticId: string?,
	amount: number?, -- the cash or the training points a pack gives (fixed amounts)
}

export type CosmeticSlotDef = { id: string, name: string, tier: number }

export type CosmeticDef = {
	id: string,
	slot: string,
	name: string,
	color: { number }, -- r, g, b (0 to 255): the swatch and, for the kit, the shirt colour
	robux: number?, -- nil = a free style
}

export type TrialGoal = {
	id: string,
	kind: "ownFloors" | "trained" | "tier",
	target: number,
	level: number?, -- for "trained": the level each of the `target` players must reach
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

-- Reminders for players who opted in (docs/PLAN.md, Step 3, Notifications): the offline bank is full or
-- the free case is ready. At most one a day, and they stop when several in a row are ignored.
Config.Reminders = {
	minGapSeconds = 22 * 60 * 60, -- between two reminders to the same player (Roblox allows 1 a day)
	minAwaySeconds = 60 * 60, -- a free-case reminder never comes sooner than this after leaving
	stopAfterIgnored = 3, -- reminders in a row that were not followed by a return
	respondedWithinSeconds = 6 * 60 * 60, -- a return within this long after a reminder counts as an answer
	queueSeconds = 3 * 24 * 60 * 60, -- a reminder that was not sent in this long is dropped
	sweepSeconds = 60, -- how often a server looks for reminders that are due
	-- Notification string asset ids from the Creator Hub (Notifications). Empty until they are created;
	-- nothing is sent for a kind without one.
	messages = { bank = "", case = "" } :: { [string]: string },
}

Config.Stars = {
	bonusPerStar = 0.10,
	maxStars = 5,
}

Config.Training = {
	bonusPerLevel = 0.03,
	levelCostBase = 40, -- cost of level L = base x L x rarity cost factor
	idleTpPerMinute = 10,
	staminaSeconds = 300,
	staminaRefillSeconds = 300, -- time away to refill from empty
	-- Keepie-uppies (a skill station of the Training Gym): the ball is kicked up and comes back to the
	-- foot every `juggleBounceSeconds`; a tap within `juggleWindow` seconds either side of that moment
	-- is a clean touch and the combo grows, a tap outside it or a ball left to drop breaks the combo
	-- and the ball starts again after `juggleCooldownSeconds`. A round lasts `juggleRoundSeconds`; the
	-- medal comes from the touches of the round (`juggleMedals`: bronze, silver, gold). Each touch pays
	-- `juggleBaseTp` plus `juggleComboTp` per combo step up to `juggleComboMax`, at most
	-- `juggleTpPerMinuteMax` TP in any minute (the treadmill pays 10, so this one is clearly better).
	juggleBounceSeconds = 0.8,
	juggleWindow = 0.14,
	juggleCooldownSeconds = 0.8,
	juggleRoundSeconds = 30,
	juggleLeadSeconds = 2, -- "get ready": the first ball of a round leaves the foot this long after the round starts
	juggleIntroSeconds = 4, -- extra time before the first round after stepping on the mat, to read how to play
	juggleRoundPauseSeconds = 3, -- the result of a round shows this long before the next one starts
	juggleBaseTp = 0.35,
	juggleComboTp = 0.05,
	juggleComboMax = 10,
	juggleTpPerMinuteMax = 40,
	juggleMedals = { bronze = 12, silver = 22, gold = 30 },
	-- The dribble run (the other skill station): rows of cones reach the player every
	-- `dribbleRowSeconds` and block one lane (a wide row blocks two, with one way through); he moves
	-- one lane left or right to stay clear. A row passed clean pays like a touch of the keepie-uppies
	-- (the same TP and the same per-minute cap, only one station can be played at a time); a cone
	-- breaks the combo and the player gets up after `dribbleStumbleSeconds`, skipping the rows meanwhile.
	-- A move may be stamped up to `dribbleGraceSeconds` in the past (a slow connection), so a row is
	-- judged only that long after it arrives. The round and the medals work like the keepie-uppies.
	dribbleRowSeconds = 0.9,
	dribbleApproachSeconds = 1.8, -- how long a row is on screen before it reaches the player
	dribbleStumbleSeconds = 0.9,
	dribbleGraceSeconds = 0.2,
	dribbleLeadSeconds = 2,
	dribbleRoundSeconds = 30,
	dribbleRoundPauseSeconds = 3,
	dribbleMedals = { bronze = 14, silver = 22, gold = 29 },
}

-- The Robux cases (docs/PLAN.md, Step 3). Within a floor a cheaper player is likelier (each step up
-- the slot order is `slotDecay` as likely as the one before). Odds, the chance of a duplicate and
-- the star rule are shown before the purchase, from these same numbers.
Config.Cases = {
	standard = {
		id = "standard",
		name = "Standard Case",
		floorsComplete = 1,
		legendChance = 0.005,
		odds = { reached = 0.70, nextFloor = 0.25, further = 0.05 },
	},
	elite = {
		id = "elite",
		name = "Elite Case",
		floorsComplete = 2,
		legendChance = 0.02,
		odds = { reached = 0.40, nextFloor = 0.40, further = 0.20 },
	},
} :: { [string]: CaseDef }

Config.CaseRules = {
	slotDecay = 0.7,
	noOfferSeconds = 30 * 60, -- no case offer until this long after the first purchase
	duplicateCashMinutes = 5, -- a duplicate past the star cap pays this much income instead
}

-- Developer Products. `productId` stays 0 until the product exists on the dashboard (then the
-- server only simulates the purchase in Studio). Prices are placeholders to set in Step 8.
Config.Products = {
	caseStandard = {
		key = "caseStandard",
		kind = "case",
		robux = 49,
		productId = 0,
		caseId = "standard",
	},
	caseElite = { key = "caseElite", kind = "case", robux = 149, productId = 0, caseId = "elite" },
	matchBoost = { key = "matchBoost", kind = "boost", robux = 39, productId = 0 },
	legend_ronaldinho = {
		key = "legend_ronaldinho",
		kind = "legend",
		robux = 799,
		productId = 0,
		playerId = "ronaldinho",
	},
	legend_zidane = {
		key = "legend_zidane",
		kind = "legend",
		robux = 1199,
		productId = 0,
		playerId = "zidane",
	},
	legend_ronaldo_nazario = {
		key = "legend_ronaldo_nazario",
		kind = "legend",
		robux = 1799,
		productId = 0,
		playerId = "ronaldo_nazario",
	},
	legend_maradona = {
		key = "legend_maradona",
		kind = "legend",
		robux = 2499,
		productId = 0,
		playerId = "maradona",
	},
	legend_pele = {
		key = "legend_pele",
		kind = "legend",
		robux = 3499,
		productId = 0,
		playerId = "pele",
	},
	-- Cash and TP packs, bought on the Robux pads outside the building. Fixed amounts (the same for
	-- everyone); the Robux prices are placeholders like the rest.
	cash_small = { key = "cash_small", kind = "cash", robux = 25, productId = 0, amount = 10_000 },
	cash_medium = {
		key = "cash_medium",
		kind = "cash",
		robux = 99,
		productId = 0,
		amount = 100_000,
	},
	cash_large = {
		key = "cash_large",
		kind = "cash",
		robux = 349,
		productId = 0,
		amount = 1_000_000,
	},
	tp_small = { key = "tp_small", kind = "tp", robux = 25, productId = 0, amount = 500 },
	tp_medium = { key = "tp_medium", kind = "tp", robux = 99, productId = 0, amount = 2_500 },
	tp_large = { key = "tp_large", kind = "tp", robux = 349, productId = 0, amount = 10_000 },
} :: { [string]: ProductDef }

-- Team customization (docs/PLAN.md, Step 3): each stadium tier opens one slot with free styles and a
-- few premium ones. Premium styles are cosmetic only, kept across seasons and bought directly (no
-- random cosmetic crates). The first style of a slot is its default. Counts and prices are
-- provisional; the dashboard product ids are 0 until the products exist.
Config.CosmeticSlots = {
	{ id = "kit", name = "Kit", tier = 1 },
	{ id = "crest", name = "Crest", tier = 2 },
	{ id = "banners", name = "Banners", tier = 3 },
	{ id = "floodlights", name = "Floodlights", tier = 4 },
	{ id = "scoreboard", name = "Scoreboard", tier = 5 },
} :: { CosmeticSlotDef }

local function style(id: string, slot: string, name: string, color: { number }, robux: number?)
	return { id = id, slot = slot, name = name, color = color, robux = robux } :: CosmeticDef
end

Config.Cosmetics = {
	style("kit_blue", "kit", "Blue", { 60, 120, 230 }, nil),
	style("kit_white", "kit", "White", { 235, 235, 240 }, nil),
	style("kit_green", "kit", "Green", { 50, 170, 90 }, nil),
	style("kit_gold", "kit", "Gold", { 235, 190, 50 }, 99),
	style("kit_black", "kit", "Midnight", { 35, 38, 50 }, 99),
	style("crest_shield", "crest", "Shield", { 200, 205, 220 }, nil),
	style("crest_star", "crest", "Star", { 250, 210, 70 }, nil),
	style("crest_ball", "crest", "Ball", { 240, 240, 240 }, nil),
	style("crest_crown", "crest", "Crown", { 240, 180, 40 }, 79),
	style("crest_flame", "crest", "Flame", { 240, 100, 40 }, 79),
	style("banners_plain", "banners", "Plain", { 210, 215, 225 }, nil),
	style("banners_stripes", "banners", "Stripes", { 90, 150, 230 }, nil),
	style("banners_dots", "banners", "Dots", { 230, 120, 140 }, nil),
	style("banners_gold", "banners", "Gold set", { 235, 190, 50 }, 129),
	style("banners_neon", "banners", "Neon set", { 70, 240, 200 }, 129),
	style("floodlights_white", "floodlights", "White", { 255, 255, 250 }, nil),
	style("floodlights_warm", "floodlights", "Warm", { 255, 214, 150 }, nil),
	style("floodlights_cool", "floodlights", "Cool", { 170, 210, 255 }, nil),
	style("floodlights_aurora", "floodlights", "Aurora", { 120, 255, 190 }, 149),
	style("floodlights_rose", "floodlights", "Rose", { 255, 140, 190 }, 149),
	style("scoreboard_classic", "scoreboard", "Classic", { 40, 44, 60 }, nil),
	style("scoreboard_light", "scoreboard", "Light", { 225, 228, 238 }, nil),
	style("scoreboard_retro", "scoreboard", "Retro", { 70, 160, 80 }, nil),
	style("scoreboard_gold", "scoreboard", "Gold", { 235, 190, 50 }, 199),
	style("scoreboard_crystal", "scoreboard", "Crystal", { 150, 220, 250 }, 199),
} :: { CosmeticDef }

Config.CosmeticsById = {} :: { [string]: CosmeticDef }
for _, def in Config.Cosmetics do
	Config.CosmeticsById[def.id] = def
	local price = def.robux
	if price then
		Config.Products["cosmetic_" .. def.id] = {
			key = "cosmetic_" .. def.id,
			kind = "cosmetic",
			robux = price,
			productId = 0,
			cosmeticId = def.id,
		}
	end
end

Config.Season = {
	bonusPerSeason = 0.5, -- permanent multiplier: season 2 = x1.5, season 3 = x2.0
}

-- The Legend Trials (docs/PLAN.md, Step 1): goals that use only training, owned players and stadium
-- tiers, never stars. Each Legend also has its cash price. Provisional, tune in the simulation: the
-- first Legend asks for floors 1 to 3, three players at level 5 and tier 4, later ones ask for more.
-- `ownFloors`: every player of floors 1 to `target`; `trained`: `target` players at `level` or more;
-- `tier`: the stadium at tier `target`.
Config.LegendTrials = {
	ronaldinho = {
		{ id = "own", kind = "ownFloors", target = 3 },
		{ id = "train", kind = "trained", target = 3, level = 5 },
		{ id = "tier", kind = "tier", target = 4 },
	},
	zidane = {
		{ id = "own", kind = "ownFloors", target = 3 },
		{ id = "train", kind = "trained", target = 5, level = 5 },
		{ id = "tier", kind = "tier", target = 4 },
	},
	ronaldo_nazario = {
		{ id = "own", kind = "ownFloors", target = 3 },
		{ id = "train", kind = "trained", target = 5, level = 10 },
		{ id = "tier", kind = "tier", target = 5 },
	},
	maradona = {
		{ id = "own", kind = "ownFloors", target = 3 },
		{ id = "train", kind = "trained", target = 8, level = 10 },
		{ id = "tier", kind = "tier", target = 5 },
	},
	pele = {
		{ id = "own", kind = "ownFloors", target = 3 },
		{ id = "train", kind = "trained", target = 10, level = 15 },
		{ id = "tier", kind = "tier", target = 5 },
	},
} :: { [string]: { TrialGoal } }

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
-- The two intro cinematics (client): a 5 second tour when the plot is claimed for the first time, and
-- the camera on the pitch from the first player bought until the first match ends (skippable).
Config.Intro = {
	tourSeconds = 5,
	firstMatchMaxSeconds = 60, -- never longer than this, whatever happens
	firstMatchHoldSeconds = 1.5, -- after the result, so the victory and the payout are seen
}

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
