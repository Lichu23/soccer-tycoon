--!nocheck
local T = require("./framework")
local ProfileSchema = T.load("server/ProfileSchema")
local Config = T.load("shared/Config")

T.suite("profile template")

T.test("a new profile starts with $15, tier 1 and nothing owned", function()
	local profile = ProfileSchema.newProfile()
	T.eq(profile.version, ProfileSchema.CURRENT_VERSION)
	T.eq(profile.cash, 15)
	T.eq(profile.tp, 0)
	T.eq(profile.stadiumTier, 1)
	T.eq(profile.season.number, 1)
	T.eq(profile.staminaLeft, Config.Training.staminaSeconds)
	T.eq(profile.fieldStarted, false)
	T.deepEq(profile.players, {})
	T.deepEq(profile.receipts, {})
end)

T.test("every call returns a separate copy", function()
	local a, b = ProfileSchema.newProfile(), ProfileSchema.newProfile()
	a.players.kane = { level = 1, stars = 0 }
	a.storeLevels.hatTrick = 3
	T.deepEq(b.players, {})
	T.eq(b.storeLevels.hatTrick, 0)
end)

T.test("a new profile passes validation", function()
	local ok, reason = ProfileSchema.validate(ProfileSchema.newProfile())
	T.eq(ok, true, tostring(reason))
end)

T.suite("profile validation")

local function mutated(change)
	local profile = ProfileSchema.newProfile()
	change(profile)
	return (ProfileSchema.validate(profile))
end

T.test("a realistic mid-game profile passes", function()
	local profile = ProfileSchema.newProfile()
	profile.cash = 1_250_000
	profile.tp = 340
	profile.stadiumTier = 3
	profile.storeLevels.matchSpeed = 2
	profile.players.rashford = { level = 5, stars = 0 }
	profile.players.kane = { level = 2, stars = 3 }
	profile.players.pele = { level = 25, stars = 5 }
	profile.season.number = 4
	profile.trials.ronaldinho = { ownAllFloors = true }
	profile.cosmetics.owned.kit_gold = true
	profile.cosmetics.chosen.kit = "kit_gold"
	profile.receipts["abc-123"] =
		{ at = 1_700_000_000, result = { kind = "case", playerId = "kane", isNew = true } }
	profile.pendingReveals = { { playerId = "kane", isNew = true } }
	profile.seenRarities.Common = true
	local ok, reason = ProfileSchema.validate(profile)
	T.eq(ok, true, tostring(reason))
end)

T.test("cash must be finite, not negative and not above the maximum", function()
	T.eq(
		mutated(function(p)
			p.cash = 0 / 0
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.cash = math.huge
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.cash = -1
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.cash = Config.MaxCash + 1
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.cash = Config.MaxCash
		end),
		true
	)
end)

T.test("stadium tier and store levels stay in range", function()
	T.eq(
		mutated(function(p)
			p.stadiumTier = 0
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.stadiumTier = 7
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.stadiumTier = 2.5
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.storeLevels.hatTrick = 4
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.storeLevels.hatTrick = 3
		end),
		true
	)
	T.eq(
		mutated(function(p)
			p.boosts.tpBoostLeft = -1
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.storeLevels.matchSpeed = 6
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.storeLevels.hatTrick = -1
		end),
		false
	)
end)

T.test("owned players must be known and within their level and star caps", function()
	T.eq(
		mutated(function(p)
			p.players.not_a_player = { level = 0, stars = 0 }
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.players.rashford = { level = 6, stars = 0 }
		end),
		false -- a Common caps at level 5
	)
	T.eq(
		mutated(function(p)
			p.players.rashford = { level = 5, stars = 6 }
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.players.pele = { level = 25, stars = 5 }
		end),
		true
	)
	T.eq(
		mutated(function(p)
			p.players.kane = { level = 1.5, stars = 0 }
		end),
		false
	)
end)

T.test("season, boosts and daily counters stay in range", function()
	T.eq(
		mutated(function(p)
			p.season.number = 0
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.boosts.bankedMatches = -5
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.boosts.stadiumBoostLeft = 0 / 0
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.daily.kicksUsed = 4
		end),
		false
	)
end)

T.test("values that cannot be stored are rejected", function()
	T.eq(
		mutated(function(p)
			p.flags.extra = function() end
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.cosmetics.chosen.kit = "\255\254"
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.trials.x = { [true] = 1 }
		end),
		false
	)
	T.eq(
		mutated(function(p)
			p.seenRarities.Common = 0 / 0
		end),
		false
	)
end)

T.test("the version must be current", function()
	T.eq(
		mutated(function(p)
			p.version = ProfileSchema.CURRENT_VERSION + 1
		end),
		false
	)
end)

T.suite("profile migration")

T.test("a brand-new profile table is stamped with the current version", function()
	local data = {}
	local ok = ProfileSchema.migrate(data)
	T.eq(ok, true)
	T.eq(data.version, ProfileSchema.CURRENT_VERSION)
end)

T.test("current data is left alone", function()
	local data = ProfileSchema.newProfile()
	T.eq((ProfileSchema.migrate(data)), true)
	T.eq(data.cash, 15)
end)

T.test("version 2 drops the removed cash upgrade and gets the bought boost timers", function()
	local data = ProfileSchema.newProfile()
	data.version = 2
	data.storeLevels.cashPerMatch = 4
	data.boosts.cashBoostLeft = nil
	data.boosts.tpBoostLeft = nil
	T.eq((ProfileSchema.migrate(data)), true)
	ProfileSchema.reconcile(data, ProfileSchema.newProfile())
	T.eq(data.version, ProfileSchema.CURRENT_VERSION)
	T.eq(data.storeLevels.cashPerMatch, nil)
	T.eq(data.boosts.cashBoostLeft, 0)
	T.eq(data.boosts.tpBoostLeft, 0)
	T.eq((ProfileSchema.validate(data)), true)
end)

T.test("version 4 drops the saved button taps and gets the Faster training level", function()
	local data = ProfileSchema.newProfile()
	data.version = 4
	data.flags.tilesSeen = { kick = true, shop = true }
	data.storeLevels.gymRate = nil
	T.eq((ProfileSchema.migrate(data)), true)
	ProfileSchema.reconcile(data, ProfileSchema.newProfile())
	T.eq(data.version, ProfileSchema.CURRENT_VERSION)
	T.eq(data.flags.tilesSeen, nil)
	T.eq(data.storeLevels.gymRate, 0)
	T.eq((ProfileSchema.validate(data)), true)
end)

T.test("version 5 counts what was already open as shown, and nothing more", function()
	local data = ProfileSchema.newProfile()
	data.version = 5
	data.flags.unlocksShown = nil
	for _, def in Config.Players do
		if def.floor == 1 then
			data.players[def.id] = { level = 1, stars = 0 }
		end
	end
	T.eq((ProfileSchema.migrate(data)), true)
	ProfileSchema.reconcile(data, ProfileSchema.newProfile())
	T.eq(data.flags.unlocksShown.floor2, true) -- floor 1 is complete
	T.eq(data.flags.unlocksShown.store_hatTrick, true)
	T.eq(data.flags.unlocksShown.floor3, nil) -- not open yet: it will get its cinematic
	T.eq(data.flags.unlocksShown.store_matchSpeed, nil) -- needs stadium tier 2
	T.eq((ProfileSchema.validate(data)), true)
end)

T.test("newer or invalid versions are refused", function()
	local ok, reason = ProfileSchema.migrate({ version = ProfileSchema.CURRENT_VERSION + 1 })
	T.eq(ok, false)
	T.truthy(reason and string.find(reason, "newer"))
	T.eq((ProfileSchema.migrate({ version = "1" })), false)
	T.eq((ProfileSchema.migrate({ version = 0 })), false)
	T.eq((ProfileSchema.migrate({ version = 1.5 })), false)
end)

T.test("migrations run in order up to the current version", function()
	local savedVersion = ProfileSchema.CURRENT_VERSION
	local calls = {}
	ProfileSchema.CURRENT_VERSION = savedVersion + 2
	ProfileSchema.migrations[savedVersion] = function(data)
		table.insert(calls, 1)
		data.renamed = data.old
		data.old = nil
	end
	ProfileSchema.migrations[savedVersion + 1] = function(_)
		table.insert(calls, 2)
	end

	local data = { version = savedVersion, old = "value" }
	local ok = ProfileSchema.migrate(data)

	ProfileSchema.CURRENT_VERSION = savedVersion
	ProfileSchema.migrations[savedVersion] = nil
	ProfileSchema.migrations[savedVersion + 1] = nil

	T.eq(ok, true)
	T.deepEq(calls, { 1, 2 })
	T.eq(data.version, savedVersion + 2)
	T.eq(data.renamed, "value")
	T.eq(data.old, nil)
end)

T.test("a missing migration step is an error, not a silent skip", function()
	local savedVersion = ProfileSchema.CURRENT_VERSION
	ProfileSchema.CURRENT_VERSION = savedVersion + 1
	local ok = ProfileSchema.migrate({ version = savedVersion })
	ProfileSchema.CURRENT_VERSION = savedVersion
	T.eq(ok, false)
end)

T.test("version 1 drops the round records of the gym, the streak records start at 0", function()
	local data = ProfileSchema.newProfile()
	data.version = 1
	data.gym =
		{ keepieBestHits = 31, keepieBestMedal = 3, dribbleBestPasses = 20, dribbleBestMedal = 1 }
	T.eq((ProfileSchema.migrate(data)), true)
	ProfileSchema.reconcile(data, ProfileSchema.newProfile())
	T.deepEq(data.gym, { keepieBestStreak = 0, freekickBestStreak = 0 })
	T.eq((ProfileSchema.validate(data)), true)
	-- A version 1 profile saved without a gym at all migrates too.
	local bare = { version = 1 }
	T.eq((ProfileSchema.migrate(bare)), true)
end)

T.suite("profile reconcile")

T.test("missing fields are filled and stored values are kept", function()
	local stored = { version = 1, cash = 999, flags = { firstHatTrickDone = true } }
	ProfileSchema.reconcile(stored, ProfileSchema.newProfile())
	T.eq(stored.cash, 999)
	T.eq(stored.flags.firstHatTrickDone, true)
	T.eq(stored.flags.notificationAsked, false) -- added later, filled in
	T.eq(stored.stadiumTier, 1)
	T.deepEq(stored.players, {})
end)

T.test("maps keyed by id are not touched", function()
	local stored = ProfileSchema.newProfile()
	stored.players.kane = { level = 2, stars = 1 }
	stored.trials.zidane = { a = true }
	ProfileSchema.reconcile(stored, ProfileSchema.newProfile())
	T.deepEq(stored.players, { kane = { level = 2, stars = 1 } })
	T.deepEq(stored.trials, { zidane = { a = true } })
end)

T.test("reconciled data does not share tables with the template", function()
	local template = ProfileSchema.newProfile()
	local stored = { version = 1 }
	ProfileSchema.reconcile(stored, template)
	stored.players.kane = { level = 1, stars = 0 }
	T.deepEq(template.players, {})
end)

T.test("an old save passes validation after migrate and reconcile", function()
	local stored = { version = 1, cash = 500, tp = 10 }
	T.eq((ProfileSchema.migrate(stored)), true)
	ProfileSchema.reconcile(stored, ProfileSchema.newProfile())
	T.eq((ProfileSchema.validate(stored)), true)
end)

T.suite("receipt pruning")

local DAY = 24 * 60 * 60
local NOW = 2_000_000_000

local function profileWithReceipts(ages: { number })
	local profile = ProfileSchema.newProfile()
	for index, age in ages do
		profile.receipts["id" .. index] = { at = NOW - age, result = { kind = "boost" } }
	end
	return profile
end

T.test("recent receipts are kept", function()
	local profile = profileWithReceipts({ 0, 5 * DAY, 29 * DAY })
	ProfileSchema.pruneReceipts(profile, NOW)
	T.truthy(profile.receipts.id1 and profile.receipts.id2 and profile.receipts.id3)
end)

T.test("a few old receipts are kept because the newest 100 always stay", function()
	local profile = profileWithReceipts({ 40 * DAY, 90 * DAY })
	ProfileSchema.pruneReceipts(profile, NOW)
	T.truthy(profile.receipts.id1 and profile.receipts.id2)
end)

T.test("old receipts beyond the newest 100 are dropped", function()
	local ages = {}
	for _ = 1, 100 do
		table.insert(ages, 60 * DAY)
	end
	table.insert(ages, 90 * DAY) -- id101, the oldest
	table.insert(ages, 1 * DAY) -- id102, recent: pushes one 60-day receipt out of the newest 100
	local profile = profileWithReceipts(ages)
	ProfileSchema.pruneReceipts(profile, NOW)
	T.eq(profile.receipts.id102 ~= nil, true) -- recent, kept
	T.eq(profile.receipts.id101, nil) -- 90 days old and outside the newest 100
	local count = 0
	for _ in profile.receipts do
		count += 1
	end
	T.eq(count, 100) -- exactly the newest 100 remain
end)

T.test("more than 100 recent receipts are all kept", function()
	local ages = {}
	for _ = 1, 150 do
		table.insert(ages, 2 * DAY)
	end
	local profile = profileWithReceipts(ages)
	ProfileSchema.pruneReceipts(profile, NOW)
	local count = 0
	for _ in profile.receipts do
		count += 1
	end
	T.eq(count, 150)
end)

T.test("a running boost with fractions of a second left is still a valid profile", function()
	local data = ProfileSchema.newProfile()
	data.boosts.stadiumBoostLeft = 123.456
	data.boosts.penaltyBoostLeft = 0.25
	T.eq(ProfileSchema.validate(data), true)
	data.boosts.stadiumBoostLeft = -1
	T.eq(ProfileSchema.validate(data), false)
end)

T.test("version 3 drops the offline upgrade and keeps at most the top hat-trick level", function()
	local data = ProfileSchema.newProfile() :: any
	data.version = 3
	data.storeLevels.offline = 4
	data.storeLevels.hatTrick = 5
	T.eq((ProfileSchema.migrate(data)), true)
	T.eq(data.version, ProfileSchema.CURRENT_VERSION)
	T.eq(data.storeLevels.offline, nil)
	T.eq(data.storeLevels.hatTrick, 3)
	T.eq((ProfileSchema.validate(data)), true)
end)
