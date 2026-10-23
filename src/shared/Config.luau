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

export type StoreUpgradeId = "matchSpeed" | "hatTrick" | "gymRate"

export type StoreUpgradeDef = {
	id: StoreUpgradeId,
	baseValue: number, -- value at level 0
	prices: { number }, -- prices[level] buys that level
	values: { number }, -- values[level] is the value at that level
	minTier: number?, -- stadium tier needed to unlock
	floorsComplete: number?, -- floors completed needed to unlock
	showLocked: boolean?, -- the pad stays visible (greyed) while locked, instead of hidden
}

export type StadiumTierDef = {
	tier: number,
	price: number,
	field: number, -- players on the field
	courtLength: number, -- the pitch of this tier, in studs
	courtWidth: number,
	cashMultiplier: number, -- every match pays this times the field income (it replaced the cash upgrade)
}

export type CaseDef = {
	id: string,
	name: string,
	floorsComplete: number, -- floors completed to unlock it
	legendChance: number, -- the share of a pull that is a Legend (fixed, taken off the top)
	-- The share of a pull that is a x2 cash or TP boost of Config.CaseBoosts instead of a player (also off
	-- the top). nil for a case of players only.
	boostChance: number?,
	-- Only players not owned yet (no duplicates) while any is left in the case; a floor with none left
	-- passes its share to the others.
	newOnly: boolean?,
	-- Shares of the rest: a player of the floors reached, of the next floor, of the floors further on.
	odds: { reached: number, nextFloor: number, further: number },
}

export type ProductDef = {
	key: string,
	kind: "case" | "legend" | "cosmetic" | "cash" | "tp" | "timedBoost",
	robux: number, -- the price shown on the button (the real price is set on the dashboard)
	productId: number, -- the Developer Product id, 0 until it is created on the dashboard
	caseId: string?,
	playerId: string?,
	cosmeticId: string?,
	amount: number?, -- the training points a TP pack gives (a fixed amount)
	minutes: number?, -- a cash pack: this many minutes of the player's normal income (Daily.caseCash)
	-- A timed boost: what it doubles. The cash part runs for Config.Boost.paidCashSeconds of online
	-- time, the TP part for Config.Boost.paidTpSeconds.
	boostsCash: boolean?,
	boostsTp: boolean?,
}

export type CosmeticSlotDef = { id: string, name: string, tier: number }

export type CosmeticDef = {
	id: string,
	slot: string,
	name: string,
	color: { number }, -- r, g, b (0 to 255): the swatch and, for the kit, the shirt colour
	-- The colours the stadium parts of the slot take in turn (banner boards), nil = all `color`.
	pattern: { { number } }?,
	accent: { number }?, -- the text on the part (scoreboard, banners), nil = the part's own
	brands: { string }?, -- the made-up sponsors the banner boards show in turn
	image: string?, -- the crest's picture (an uploaded decal, art in tools/art)
	model: string?, -- a floodlight model (CourtPlan.LAMPS)
	design: string?, -- a scoreboard design (shared/StadiumLook)
	cash: number?, -- a cash price; with neither price the style is free
	robux: number?,
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
	-- A banked boosted match doubles the match. Nothing sells banked matches any more (the 30-match
	-- product was dropped: x2 Cash gave three times the value for the same price); kept for old saves.
	matchMultiplier = 2,
	-- The x2 boosts bought on the Robux pads in the middle of floor 1: cash, TP, or both. Each
	-- purchase adds its time of online time to its timer, up to paidMaxSeconds. The TP boost lasts
	-- longer because it only pays while the stamina lasts (about half of the time).
	paidMultiplier = 2,
	paidCashSeconds = 10 * 60,
	paidTpSeconds = 20 * 60,
	paidMaxSeconds = 60 * 60,
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
	-- Each kick is played like the shot of the 1v1 breakaway (shared/Penalty): the reticle and the
	-- power meter of Config.Training, then a film of `penaltyFilmSeconds` (the run-up, the strike, the
	-- result). The next kick's reticle starts `penaltyLeadSeconds` after the film. The keeper always
	-- stands in the middle of the goal and reaches `penaltyKeeperReach` to either side (goal units at
	-- the sweet power; the posts are at 1), so only a kick placed towards a post beats him.
	penaltyLeadSeconds = 1.2,
	penaltyFilmSeconds = 5.2,
	penaltyKeeperReach = 0.5,
	-- The penalty's green zone: from the breakaway's weak power up to this (wider than the 1v1's).
	penaltyGoodHigh = 0.82,
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
	-- The share of normal income earned while away, the same for everyone (no upgrade).
	rate = 0.25,
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
	-- Players whose levels cost something else, level by level. The first player bought is the
	-- level-up tutorial (Arrow): his first level is quick to earn in the Training Gym.
	levelCostOverrides = {
		rashford = { 5, 10, 20, 40, 50 },
	} :: { [string]: { number } },
	idleTpPerMinute = 20,
	-- The level-up tutorial: until the first level ever, the treadmill pays `tutorialTpPerMinute`
	-- while the player has less than `tutorialTp` (the first level of the first player, see
	-- levelCostOverrides), holds them on the belt until then, and the other stations stay locked.
	tutorialTp = 5,
	tutorialTpPerMinute = 40,
	staminaSeconds = 300,
	staminaRefillSeconds = 300, -- time away to refill from empty
	-- Keepie-uppies (a skill station of the Training Gym), an endless streak: the ball is kicked up and
	-- comes back to the foot on a beat that starts at `juggleBounceSeconds` and gets
	-- `juggleBounceStep` shorter with every touch, down to `juggleBounceMin`. A tap within
	-- `juggleWindow` seconds either side of that moment is a clean touch and the streak grows; a tap
	-- outside it or a ball left to drop ends the streak. The result shows for `juggleOverSeconds`, then
	-- a new streak starts after `juggleLeadSeconds`. The longest streak is the personal best; the
	-- medals (`juggleMedals`: bronze, silver, gold) are streak milestones. Each touch pays by its
	-- place in the streak (`juggleTpTiers`: touches up to `upTo` pay `tp`; past the last tier
	-- `juggleTpFloor`), with no cap per minute: a new streak starts again at the top tier, and the
	-- stamina bar ends the session. The breakaway's goals are capped at
	-- `freekickTpPerMinuteMax` TP in any minute (the treadmill pays `idleTpPerMinute`).
	juggleBounceSeconds = 0.8,
	juggleBounceStep = 0.006,
	juggleBounceMin = 0.5,
	juggleWindow = 0.14,
	juggleLeadSeconds = 2, -- "get ready": the first ball of a streak leaves the foot this long after it starts
	juggleIntroSeconds = 4, -- extra time before the first streak after stepping on the mat, to read how to play
	juggleOverSeconds = 2.5, -- the result of a streak shows this long before the next one starts
	juggleTpTiers = {
		{ upTo = 40, tp = 1 }, -- 40 TP for the first 40 touches
		{ upTo = 110, tp = 0.5 },
		{ upTo = 210, tp = 0.3 },
		{ upTo = 340, tp = 0.2 },
	},
	juggleTpFloor = 0.1,
	freekickTpPerMinuteMax = 40,
	juggleMedals = { bronze = 10, silver = 25, gold = 50 },
	-- The 1v1 breakaway (the free-kick spot, the other skill station), an endless streak of goals. Each
	-- attack: the through-ball arrives (`freekickLeadSeconds`), then a skill move shows and waits
	-- `freekickMoveSeconds` for its key (less `freekickMoveStep` with every goal, down to
	-- `freekickMoveMin`), or the defender wins the ball. Then the aim reticle glides over the goal
	-- mouth (across in `freekickAimSeconds`, up in `freekickAimUpSeconds`) until a tap locks it, then
	-- the power meter fills by itself (empty to full in `freekickPowerSeconds`, then back) until a
	-- second tap shoots. An input may be stamped up to `freekickGraceSeconds` in the past (a slow
	-- connection). A beaten defender plays the dribble film (`freekickDribbleSeconds`) before the aim
	-- starts; after the shot the strike and the result play for `freekickFilmSeconds` (a lost dribble
	-- plays its own film for `freekickTackleSeconds`): a goal adds one to the streak and the next
	-- attack comes, anything else ends the streak and the result shows for `freekickOverSeconds`.
	-- The shot, in goal units: the posts are at x -1 and 1, the bar at height 1. The height at the goal
	-- is the reticle's, plus `freekickPowerLift` per unit of power above `freekickPowerSweet`. The
	-- keeper stands up to `freekickKeeperSpread` from the middle and reaches `freekickKeeperReach`,
	-- less for a hard shot and more with every goal of the streak (`freekickKeeperReachStep`, up to
	-- `freekickKeeperReachMax` more).
	freekickLeadSeconds = 1.2,
	freekickIntroSeconds = 1.5, -- extra time before the first attack after stepping on the spot, to get ready
	freekickMoveSeconds = 1.1,
	freekickMoveStep = 0.05,
	freekickMoveMin = 0.45,
	freekickAimSeconds = 1.5,
	freekickAimUpSeconds = 1.05,
	freekickAimRange = 1.25, -- the reticle glides from -this to +this (a little past the posts)
	freekickAimLow = 0.1, -- the reticle's lowest and highest height
	freekickAimHigh = 0.92,
	freekickPowerSeconds = 0.7,
	-- The meter starts to move this long after the aim is locked (a double tap does not shoot).
	freekickPowerDelay = 0.3,
	-- The meter fills faster with every goal of the streak: `freekickPowerStep` less, down to
	-- `freekickPowerMin`.
	freekickPowerStep = 0.02,
	freekickPowerMin = 0.5,
	-- The shot clock: from the start of the aim the player has `freekickShotSeconds` to lock the aim
	-- and shoot, `freekickShotStep` less with every goal of the streak down to `freekickShotMin`
	-- (reached on the 10th goal, the gold medal). The floor still leaves time for the reticle to reach
	-- a corner and the meter to fill once. When it runs out the keeper smothers a rushed shot.
	-- The practice attack has no clock.
	freekickShotSeconds = 6,
	freekickShotStep = 0.3,
	freekickShotMin = 3,
	freekickPowerSweet = 0.7,
	freekickPowerLift = 1.2,
	freekickWeakPower = 0.3, -- below this the shot rolls to the keeper
	-- The green zone of the meter: from `freekickGoodLow` up to `freekickGoodHigh` on the first
	-- attack, narrower with every goal (its bottom `freekickGoodLowStep` higher up to
	-- `freekickGoodLowMax`, its top `freekickGoodHighStep` lower down to `freekickGoodHighMin`). A
	-- free kick stopped under it rolls to the keeper, over it flies over the bar.
	freekickGoodLow = 0.42,
	freekickGoodHigh = 0.8,
	freekickGoodLowStep = 0.02,
	freekickGoodLowMax = 0.61,
	freekickGoodHighStep = 0.003,
	freekickGoodHighMin = 0.77,
	freekickGraceSeconds = 0.2,
	freekickDribbleSeconds = 2,
	freekickFilmSeconds = 4,
	freekickTackleSeconds = 3,
	freekickOverSeconds = 2.5,
	freekickBallRadius = 0.05,
	freekickKeeperSpread = 0.3,
	freekickKeeperReach = 0.42,
	freekickKeeperReachStep = 0.015,
	freekickKeeperReachMax = 0.15,
	freekickTopCorner = 0.4, -- a high shot is harder to reach: extra distance per unit of height over 0.6
	freekickBaseTp = 1.5,
	freekickStreakTp = 0.25,
	freekickStreakMax = 10,
	freekickMedals = { bronze = 3, silver = 6, gold = 10 },
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
		boostChance = 0.5,
		odds = { reached = 0.70, nextFloor = 0.25, further = 0.05 },
	},
	elite = {
		id = "elite",
		name = "Elite Case",
		floorsComplete = 2,
		legendChance = 0.02,
		newOnly = true,
		odds = { reached = 0.40, nextFloor = 0.40, further = 0.20 },
	},
} :: { [string]: CaseDef }

export type CaseBoost = {
	id: string,
	kind: "cash" | "tp", -- what it doubles: the match cash or the TP of the Training Gym
	label: string,
	detail: string,
	seconds: number, -- added to the paid x2 cash or TP timer (Boosts.addCaseBoost), never cut
	weight: number, -- the relative chance within the case's boost share
}

-- The boosts of a case that has a boostChance: half x2 TP, half x2 cash, all longer than the 10
-- minutes a Robux pad sells. The cash ones keep their first ids (saved receipts name them).
Config.CaseBoosts = {} :: { CaseBoost }
for _, kind in { "tp", "cash" } :: { "cash" | "tp" } do
	for _, step in
		{
			{ minutes = 15, weight = 30 },
			{ minutes = 30, weight = 15 },
			{ minutes = 60, weight = 5 },
		}
	do
		table.insert(Config.CaseBoosts, {
			id = (if kind == "cash" then "caseBoost" else "caseBoostTp") .. step.minutes,
			kind = kind,
			label = if kind == "cash" then "x2 Cash" else "x2 TP",
			detail = step.minutes .. " minutes",
			seconds = step.minutes * 60,
			weight = step.weight,
		})
	end
end

Config.CaseBoostsById = {} :: { [string]: CaseBoost }
for _, boost in Config.CaseBoosts do
	Config.CaseBoostsById[boost.id] = boost
end

Config.CaseRules = {
	slotDecay = 0.7,
	duplicateCashMinutes = 5, -- a duplicate past the star cap pays this much income instead
}

-- Developer Products. `productId` stays 0 until the product exists on the dashboard (then the
-- server only simulates the purchase in Studio). Prices follow one rate, about 3 to 4 Robux per
-- minute of play saved (the 10-minute x2 Cash boost for 39), measured in the pricing simulation
-- (docs/PLAN.md, Step 3, Robux prices).
Config.Products = {
	caseStandard = {
		key = "caseStandard",
		kind = "case",
		robux = 49,
		productId = 0,
		caseId = "standard",
	},
	caseElite = { key = "caseElite", kind = "case", robux = 79, productId = 0, caseId = "elite" },
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
	-- Cash and TP packs, bought on the Robux pads outside the building. A cash pack is minutes of the
	-- player's own normal income, so it is worth the same at every stage (a fixed amount was worth
	-- nothing after minute 17). TP packs are fixed amounts: the TP rate never grows.
	cash_small = { key = "cash_small", kind = "cash", robux = 39, productId = 0, minutes = 15 },
	cash_medium = { key = "cash_medium", kind = "cash", robux = 129, productId = 0, minutes = 60 },
	cash_large = { key = "cash_large", kind = "cash", robux = 399, productId = 0, minutes = 240 },
	tp_small = { key = "tp_small", kind = "tp", robux = 39, productId = 0, amount = 500 },
	tp_medium = { key = "tp_medium", kind = "tp", robux = 149, productId = 0, amount = 2_500 },
	tp_large = { key = "tp_large", kind = "tp", robux = 499, productId = 0, amount = 10_000 },
	-- The x2 boosts on the pads in the middle of floor 1 (10 minutes of cash, 20 of TP).
	boost_cash = {
		key = "boost_cash",
		kind = "timedBoost",
		robux = 39,
		productId = 0,
		boostsCash = true,
	},
	boost_tp = { key = "boost_tp", kind = "timedBoost", robux = 39, productId = 0, boostsTp = true },
	boost_both = {
		key = "boost_both",
		kind = "timedBoost",
		robux = 69,
		productId = 0,
		boostsCash = true,
		boostsTp = true,
	},
} :: { [string]: ProductDef }

-- Team customization (docs/PLAN.md, Step 3): each stadium tier opens one slot with free styles, a
-- few bought with cash and a few with Robux. Bought styles are cosmetic only, kept across seasons and
-- bought directly (no random cosmetic crates). The first style of a slot is its default. The two cash
-- prices of a slot are about 10 and 25 minutes of income near the end of the slot's tier (pricing
-- simulation). Counts are provisional; the dashboard product ids are 0 until the products exist.
Config.CosmeticSlots = {
	{ id = "kit", name = "Kit", tier = 1 },
	{ id = "crest", name = "Crest", tier = 2 },
	{ id = "banners", name = "Banners", tier = 3 },
	{ id = "lamps", name = "Floodlights", tier = 3 },
	{ id = "floodlights", name = "Light colour", tier = 4 },
	{ id = "scoreboard", name = "Scoreboard", tier = 5 },
	{ id = "stadium", name = "Stadium", tier = 6 },
} :: { CosmeticSlotDef }

type Look = {
	pattern: { { number } }?,
	accent: { number }?,
	brands: { string }?,
	image: string?,
	model: string?,
	design: string?,
}
type Price = { cash: number?, robux: number? }

local function style(
	id: string,
	slot: string,
	name: string,
	color: { number },
	price: Price?,
	look: Look?
): CosmeticDef
	return {
		id = id,
		slot = slot,
		name = name,
		color = color,
		pattern = look and look.pattern,
		accent = look and look.accent,
		brands = look and look.brands,
		image = look and look.image,
		model = look and look.model,
		design = look and look.design,
		cash = price and price.cash,
		robux = price and price.robux,
	}
end

local WHITE = { 240, 240, 240 }
local NAVY = { 32, 38, 56 }
local GOLD = { 255, 205, 60 }

Config.Cosmetics = {
	style("kit_blue", "kit", "Blue", { 60, 120, 230 }),
	style("kit_white", "kit", "White", { 235, 235, 240 }),
	style("kit_green", "kit", "Green", { 50, 170, 90 }),
	style("kit_red", "kit", "Red", { 220, 60, 60 }, { cash = 3_000 }),
	style("kit_purple", "kit", "Purple", { 150, 90, 220 }, { cash = 8_000 }),
	style("kit_gold", "kit", "Gold", { 235, 190, 50 }, { robux = 99 }),
	style("kit_black", "kit", "Midnight", { 35, 38, 50 }, { robux = 99 }),
	style("crest_shield", "crest", "Shield", { 205, 210, 225 }, nil, {
		image = "rbxassetid://119246926723352",
	}),
	style("crest_star", "crest", "Star", { 255, 210, 70 }, nil, {
		image = "rbxassetid://91284134429976",
	}),
	style("crest_ball", "crest", "Ball", { 60, 120, 230 }, nil, {
		image = "rbxassetid://109239234345017",
	}),
	style("crest_ruby", "crest", "Ruby", { 210, 50, 70 }, { cash = 300_000 }, {
		image = "rbxassetid://108259967301092",
	}),
	style("crest_emerald", "crest", "Emerald", { 40, 160, 95 }, { cash = 700_000 }, {
		image = "rbxassetid://84216287066856",
	}),
	style("crest_crown", "crest", "Crown", { 150, 90, 220 }, { robux = 79 }, {
		image = "rbxassetid://139431546168199",
	}),
	style("crest_flame", "crest", "Flame", { 240, 100, 40 }, { robux = 79 }, {
		image = "rbxassetid://120423274947356",
	}),
	-- Each banner set is a group of made-up sponsors (never real brands) in their colours. The
	-- first one keeps the sponsor colours the boards always had.
	style("banners_plain", "banners", "Sponsors", { 200, 50, 60 }, nil, {
		pattern = { { 200, 50, 60 }, { 30, 110, 200 }, { 240, 190, 50 }, { 40, 150, 90 } },
		brands = { "VOLTA", "FIZZUP", "ZOOMR", "PIXEL" },
		accent = WHITE,
	}),
	style("banners_stripes", "banners", "Kickz", { 90, 150, 230 }, nil, {
		pattern = { { 90, 150, 230 }, WHITE },
		brands = { "KICKZ", "KICKZ BOOTS" },
		accent = NAVY,
	}),
	style("banners_dots", "banners", "Fizz", { 230, 120, 140 }, nil, {
		pattern = { { 230, 120, 140 }, { 150, 90, 220 } },
		brands = { "FIZZUP", "fizz it up!" },
		accent = WHITE,
	}),
	style("banners_sunset", "banners", "Sunny", { 245, 140, 40 }, { cash = 6_000_000 }, {
		pattern = { { 245, 140, 40 }, { 235, 90, 130 }, { 150, 90, 220 } },
		brands = { "SUNNY JUICE", "GOALAZO", "SUNNY JUICE" },
		accent = WHITE,
	}),
	style("banners_ocean", "banners", "Wave", { 40, 150, 220 }, { cash = 15_000_000 }, {
		pattern = { { 40, 150, 220 }, { 60, 200, 200 }, { 30, 90, 180 } },
		brands = { "WAVE AIR", "BLUEBYTE", "WAVE AIR" },
		accent = WHITE,
	}),
	style("banners_gold", "banners", "Gold set", { 235, 190, 50 }, { robux = 129 }, {
		pattern = { { 235, 190, 50 }, NAVY },
		brands = { "GOLDEN BOOT", "TROPHY BANK" },
		accent = NAVY,
	}),
	style("banners_neon", "banners", "Neon set", { 70, 240, 200 }, { robux = 129 }, {
		pattern = { { 70, 240, 200 }, { 150, 90, 220 } },
		brands = { "NEON NOVA", "ZAPP" },
		accent = NAVY,
	}),
	-- The floodlight models, on the masts of every tier (shared/CourtPlan).
	style(
		"lamps_led",
		"lamps",
		"LED light",
		{ 32, 38, 56 },
		nil,
		{ model = "led", accent = { 255, 244, 214 } }
	),
	style(
		"lamps_twin",
		"lamps",
		"Twin panels",
		{ 32, 38, 56 },
		nil,
		{ model = "twin", accent = { 255, 244, 214 } }
	),
	style(
		"lamps_bank",
		"lamps",
		"Lamp bank",
		{ 82, 88, 100 },
		nil,
		{ model = "bank", accent = { 255, 244, 214 } }
	),
	style("lamps_tower", "lamps", "Tower", { 82, 88, 100 }, { cash = 8_000_000 }, {
		model = "tower",
		accent = { 255, 244, 214 },
	}),
	style("lamps_arena", "lamps", "Arena tower", { 82, 88, 100 }, { cash = 20_000_000 }, {
		model = "arena",
		accent = { 255, 244, 214 },
	}),
	style("lamps_halo", "lamps", "Halo", { 150, 90, 220 }, { robux = 149 }, {
		model = "halo",
		accent = { 255, 244, 214 },
	}),
	style("lamps_gold", "lamps", "Gold tower", { 235, 190, 50 }, { robux = 149 }, {
		model = "gold",
		accent = { 255, 244, 214 },
	}),
	-- The colour the floodlights glow (the lamp faces and the lamps under the roofs).
	style("floodlights_white", "floodlights", "White", { 255, 250, 235 }),
	style("floodlights_warm", "floodlights", "Sunny", { 255, 200, 90 }),
	style("floodlights_cool", "floodlights", "Sky blue", { 110, 190, 255 }),
	style("floodlights_gold", "floodlights", "Red", { 255, 80, 80 }, { cash = 120_000_000 }),
	style("floodlights_ice", "floodlights", "Green", { 90, 240, 120 }, { cash = 300_000_000 }),
	style("floodlights_aurora", "floodlights", "Aurora", { 80, 255, 210 }, { robux = 149 }),
	style("floodlights_rose", "floodlights", "Pink", { 255, 110, 200 }, { robux = 149 }),
	-- Each scoreboard is its own design (shared/StadiumLook) in its own colours.
	style("scoreboard_classic", "scoreboard", "Classic", { 40, 44, 60 }, nil, {
		design = "classic",
		accent = GOLD,
	}),
	style("scoreboard_light", "scoreboard", "Framed", { 225, 228, 238 }, nil, {
		design = "framed",
		accent = { 60, 120, 230 },
	}),
	style("scoreboard_retro", "scoreboard", "Retro", { 50, 120, 70 }, nil, {
		design = "retro",
		accent = WHITE,
	}),
	style("scoreboard_navy", "scoreboard", "Neon", NAVY, { cash = 800_000_000 }, {
		design = "neon",
		accent = { 120, 235, 140 },
	}),
	style("scoreboard_ruby", "scoreboard", "Derby", { 200, 50, 70 }, { cash = 2_000_000_000 }, {
		design = "split",
		pattern = { { 200, 50, 70 }, { 40, 110, 210 } },
		accent = WHITE,
	}),
	style("scoreboard_gold", "scoreboard", "Gold", { 235, 190, 50 }, { robux = 199 }, {
		design = "framed",
		accent = NAVY,
	}),
	style("scoreboard_crystal", "scoreboard", "Crystal", { 20, 30, 60 }, { robux = 199 }, {
		design = "neon",
		accent = { 120, 220, 255 },
	}),
	-- The outside of the roof arena: its roofs, pillars and stands.
	style("stadium_white", "stadium", "White", { 226, 229, 236 }),
	style("stadium_silver", "stadium", "Silver", { 170, 176, 190 }),
	style("stadium_sky", "stadium", "Sky", { 120, 180, 240 }),
	style("stadium_red", "stadium", "Red", { 210, 60, 70 }, { cash = 3_000_000_000 }),
	style("stadium_green", "stadium", "Green", { 60, 170, 100 }, { cash = 7_500_000_000 }),
	style("stadium_gold", "stadium", "Gold", { 235, 190, 50 }, { robux = 199 }),
	style("stadium_midnight", "stadium", "Midnight", { 40, 44, 70 }, { robux = 199 }),
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

-- The roof arena's name (tier 6), typed by the player: filtered by Roblox on the server before
-- anyone sees it, and paid for each time it changes (about 5 minutes of tier 6 income).
Config.StadiumName = {
	price = 1_500_000_000,
	minLength = 3,
	maxLength = 20,
}

Config.Season = {
	-- Permanent multiplier: season 2 = x1.5, season 3 = x2.0, up to season `fullBonusSeasons`
	-- (x5.5), then `lateBonusPerSeason` a season, so resetting again and again stops paying off.
	bonusPerSeason = 0.5,
	fullBonusSeasons = 10,
	lateBonusPerSeason = 0.1,
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
	-- Pelé asks for about 75K TP of training (it was 10 players at level 15, about 144K TP, which was
	-- three quarters of the whole game in the finish simulation).
	pele = {
		{ id = "own", kind = "ownFloors", target = 3 },
		{ id = "train", kind = "trained", target = 8, level = 12 },
		{ id = "tier", kind = "tier", target = 5 },
	},
} :: { [string]: { TrialGoal } }

Config.Store = {
	matchSpeed = {
		id = "matchSpeed",
		baseValue = 10, -- seconds
		prices = { 120, 2_000, 30_000, 500_000, 8_000_000 },
		values = { 9, 8, 7, 6, 5 },
		minTier = 2,
	},
	hatTrick = {
		id = "hatTrick",
		baseValue = 0.05, -- chance
		prices = { 2_000, 60_000, 1_500_000 },
		values = { 0.10, 0.20, 0.25 },
		floorsComplete = 1,
	},
	-- Faster training: the TP a minute of the treadmill and the bench press (the pad stands between
	-- them in the gym hall). It stays under the ~50 a minute of a juggler, so the skill games stay
	-- worth playing. Prices are a few minutes of income at the tier each level is meant for (2, 3, 5
	-- and 6); a New Season resets it like the other upgrades.
	gymRate = {
		id = "gymRate",
		baseValue = Config.Training.idleTpPerMinute,
		prices = { 5_000, 500_000, 50_000_000, 2_000_000_000 },
		values = { 25, 30, 35, 40 },
		minTier = 2,
		showLocked = true, -- it stands alone in the gym, so a Tier 1 player sees what is coming
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

-- Each tier also multiplies the match cash, in place of the removed "More cash per match" upgrade:
-- from tier 2 on, the values that upgrade had reached by about that point of the climb. Tier 1 is
-- x1.25, so the first stadium upgrade still comes at about 4:15 (tests/pacing). Tier 5 is a little
-- above tier 4 so its bigger field is worth buying (at x6.7 it added only 3%).
Config.StadiumTiers = {
	{ tier = 1, price = 0, field = 4, courtLength = 60, courtWidth = 36, cashMultiplier = 1.25 },
	{ tier = 2, price = 250, field = 5, courtLength = 70, courtWidth = 42, cashMultiplier = 2.7 },
	{
		tier = 3,
		price = 25_000,
		field = 6,
		courtLength = 84,
		courtWidth = 50,
		cashMultiplier = 5.1,
	},
	{
		tier = 4,
		price = 750_000,
		field = 8,
		courtLength = 100,
		courtWidth = 60,
		cashMultiplier = 6.7,
	},
	{
		tier = 5,
		price = 45_000_000,
		field = 11,
		courtLength = 120,
		courtWidth = 72,
		cashMultiplier = 7.3,
	},
	-- The roof arena: the same pitch and field under a retractable roof. Provisional, tune in the
	-- simulation (about 30 times tier 5, like the step from tier 4 to 5).
	{
		tier = 6,
		price = 1_500_000_000,
		field = 11,
		courtLength = 120,
		courtWidth = 72,
		cashMultiplier = 8,
	},
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
