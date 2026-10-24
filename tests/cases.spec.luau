--!nocheck
local T = require("./framework")
local Cases = T.load("shared/Cases")
local Config = T.load("shared/Config")
local Daily = T.load("server/Daily")
local Grants = T.load("server/Grants")
local MatchLogic = T.load("server/MatchLogic")
local ProfileSchema = T.load("server/ProfileSchema")
local Roster = T.load("shared/Roster")
local ShopRules = T.load("server/ShopRules")

T.suite("cases and purchases")

local function ownFloors(data, floors)
	for _, def in Config.Players do
		if def.floor <= floors then
			Roster.add(data, def.id)
		end
	end
end

local function profile(floors)
	local data = ProfileSchema.newProfile()
	ownFloors(data, floors)
	return data
end

local function total(entries)
	local sum = 0
	for _, entry in entries do
		sum += entry.chance
	end
	return sum
end

local function chanceOf(entries, id)
	for _, entry in entries do
		if entry.id == id then
			return entry.chance
		end
	end
	return 0
end

T.test("a case unlocks with the floors: Standard at floor 1 done, Elite at floor 2 done", function()
	T.eq(Cases.unlocked(profile(0), "standard"), false)
	T.eq(Cases.unlocked(profile(1), "standard"), true)
	T.eq(Cases.unlocked(profile(1), "elite"), false)
	T.eq(Cases.unlocked(profile(2), "elite"), true)
	T.eq(Cases.unlocked(profile(3), "nothing"), false)
end)

T.test("the chances add up to 1 for every case and every stage of progress", function()
	for floors = 0, 3 do
		for caseId in Config.Cases do
			local entries = Cases.odds(profile(floors), caseId)
			T.near(total(entries), 1, 1e-9)
		end
	end
end)

T.test("the Legend chance is fixed: 0.5% Standard, 2% Elite", function()
	local standard, summary = Cases.odds(profile(1), "standard")
	T.near(summary.legend, 0.005, 1e-12)
	local sum = 0
	for _, def in Config.Players do
		if def.floor == Config.LegendFloor then
			sum += chanceOf(standard, def.id)
		end
	end
	T.near(sum, 0.005, 1e-9)
	local _, elite = Cases.odds(profile(2), "elite")
	T.near(elite.legend, 0.02, 1e-12)
end)

T.test("the shares follow the table when every bucket has a floor", function()
	-- Nothing owned: floor 1 is the open floor, floor 2 the next, floor 3 further on.
	local _, standard = Cases.odds(profile(0), "standard")
	-- Standard: half the pulls are boosts and 0.5% Legends, the rest is split by the table.
	T.near(standard.reached, 0.495 * 0.70, 1e-9)
	T.near(standard.nextFloor, 0.495 * 0.25, 1e-9)
	T.near(standard.further, 0.495 * 0.05, 1e-9)
	T.near(standard.boost, 0.5, 1e-12)
	local _, elite = Cases.odds(profile(0), "elite")
	T.near(elite.reached, 0.98 * 0.40, 1e-9)
	T.near(elite.further, 0.98 * 0.20, 1e-9)
	T.near(elite.boost, 0, 1e-12)
end)

T.test("Standard is half x2 boosts (half cash, half TP), Elite is players only", function()
	local entries = Cases.odds(profile(1), "standard")
	local boosts = 0
	for _, entry in entries do
		if Cases.isBoost(entry.id) then
			boosts += entry.chance
		end
	end
	T.near(boosts, 0.5, 1e-9)
	T.near(chanceOf(entries, "caseBoost15"), 0.5 * 0.3, 1e-9)
	T.near(chanceOf(entries, "caseBoost60"), 0.5 * 0.05, 1e-9)
	T.near(chanceOf(entries, "caseBoostTp15"), 0.5 * 0.3, 1e-9)
	T.near(chanceOf(entries, "caseBoostTp60"), 0.5 * 0.05, 1e-9)
	for _, entry in Cases.odds(profile(2), "elite") do
		T.eq(Cases.isBoost(entry.id), false, entry.id)
	end
end)

T.test(
	"a share with no floor in it goes to the others (floor 3 open has nothing further)",
	function()
		local entries, summary = Cases.odds(profile(2), "standard")
		T.near(summary.further, 0, 1e-12)
		T.near(summary.reached + summary.nextFloor, 0.495, 1e-9)
		T.near(total(entries), 1, 1e-9)
	end
)

T.test("within a floor each step up the slot order is 30% less likely", function()
	local entries = Cases.odds(profile(0), "standard")
	local floorOne = {}
	for _, def in Config.Players do
		if def.floor == 1 then
			table.insert(floorOne, def.id)
		end
	end
	for index = 2, #floorOne do
		T.near(
			chanceOf(entries, floorOne[index]) / chanceOf(entries, floorOne[index - 1]),
			0.7,
			1e-9
		)
	end
end)

T.test("the chance of a duplicate is the chance of the players already owned", function()
	local data = profile(1)
	local entries, summary = Cases.odds(data, "standard")
	local expected = 0
	for id in data.players do
		expected += chanceOf(entries, id)
	end
	T.near(summary.duplicate, expected, 1e-12)
	T.truthy(summary.duplicate > 0)
	local _, fresh = Cases.odds(profile(0), "standard")
	T.eq(fresh.duplicate, 0)
end)

T.test("seeded rolls land on the table's shares", function()
	local data = profile(1)
	local entries, summary = Cases.odds(data, "standard")
	-- A fixed-seed generator (the unit tests have no Random): the same rolls on every run.
	local seed = 12345
	local random = {
		NextNumber = function()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end,
	}
	local rolls = 40000
	local counts = { reached = 0, legend = 0, boost = 0 }
	local floorOf = {}
	for _, def in Config.Players do
		floorOf[def.id] = def.floor
	end
	for _ = 1, rolls do
		local id = Cases.pick(entries, random:NextNumber())
		if Cases.isBoost(id) then
			counts.boost += 1
		elseif floorOf[id] == Config.LegendFloor then
			counts.legend += 1
		elseif floorOf[id] <= 2 then
			counts.reached += 1
		end
	end
	T.near(counts.reached / rolls, summary.reached, 0.01)
	T.near(counts.legend / rolls, 0.005, 0.003)
	T.near(counts.boost / rolls, 0.5, 0.015)
end)

T.test("pick returns the first player at 0 and the last just below 1", function()
	local entries = Cases.odds(profile(0), "standard")
	T.eq(Cases.pick(entries, 0), entries[1].id)
	T.eq(Cases.pick(entries, 0.9999999999), entries[#entries].id)
end)

-- Offers --------------------------------------------------------------------------------------

T.test("cases are offered once floor 1 is done, with no waiting time", function()
	T.eq(select(2, ShopRules.canOffer(profile(0), "caseStandard")), "early")
	T.eq(ShopRules.canOffer(profile(1), "caseStandard"), true) -- never bought anything
end)

T.test("Elite needs floor 2 done, and an unknown product is refused", function()
	local data = profile(1)
	T.eq(select(2, ShopRules.canOffer(data, "caseElite")), "locked")
	T.eq(select(2, ShopRules.canOffer(data, "nothing")), "unknown")
	local more = profile(2)
	T.eq(ShopRules.canOffer(more, "caseElite"), true)
end)

T.test(
	"the Elite Case rolls only players not owned yet, the Standard Case can roll duplicates",
	function()
		local data = profile(2)
		local entries, summary = Cases.odds(data, "elite")
		T.near(total(entries), 1, 1e-9)
		T.eq(summary.duplicate, 0)
		for _, entry in entries do
			T.eq(data.players[entry.id], nil, entry.id)
		end
		T.near(summary.legend, 0.02, 1e-12)
		local _, standard = Cases.odds(data, "standard")
		T.truthy(standard.duplicate > 0)
	end
)

T.test(
	"an Elite Case with only Legends left rolls Legends, and with nothing left rolls duplicates",
	function()
		local data = profile(3)
		local entries, summary = Cases.odds(data, "elite")
		T.near(total(entries), 1, 1e-9)
		T.near(summary.legend, 1, 1e-9)
		T.eq(chanceOf(entries, "rashford"), 0)
		for _, def in Config.Players do
			Roster.add(data, def.id)
		end
		local all, full = Cases.odds(data, "elite")
		T.near(total(all), 1, 1e-9)
		T.near(full.duplicate, 1, 1e-9)
	end
)

T.test("the 30-match boost is no longer sold", function()
	T.eq(Config.Products.matchBoost, nil)
	T.eq(select(2, ShopRules.canOffer(profile(0), "matchBoost")), "unknown")
end)

T.test("a Legend is offered for Robux only once floor 2 is complete, and not when owned", function()
	local data = profile(1)
	T.eq(select(2, ShopRules.canOffer(data, "legend_ronaldinho")), "locked")
	local reached = profile(2)
	T.eq(ShopRules.canOffer(reached, "legend_ronaldinho"), true)
	Roster.add(reached, "ronaldinho")
	T.eq(select(2, ShopRules.canOffer(reached, "legend_ronaldinho")), "owned")
end)

T.test("Robux skips a Legend's cash price and his trials", function()
	local data = profile(2) -- floors 1 and 2 owned, nobody trained, stadium tier 1
	T.eq(ShopRules.canOffer(data, "legend_ronaldinho"), true)
	T.eq(ShopRules.canOffer(data, "legend_maradona"), true)
end)

T.test("the Robux Legends cost more the higher their slot", function()
	local last = 0
	for _, def in Config.Players do
		local product = Config.Products["legend_" .. def.id]
		if product then
			T.eq(product.robux > last, true)
			last = product.robux
		end
	end
end)

-- Granting ------------------------------------------------------------------------------------

T.test("a case gives the rolled player at once and records the receipt", function()
	local data = profile(0)
	local result, granted = Grants.apply(data, Config.Products.caseStandard, "p1", 100, 0)
	T.eq(granted, true)
	T.eq(result.kind, "case")
	T.eq(result.isNew, true)
	T.eq(Roster.owns(data, result.playerId), true)
	T.eq(data.receipts.p1.result.playerId, result.playerId)
	T.eq(#data.pendingReveals, 1)
end)

T.test("a Standard TP boost adds its time to the bought TP timer, not the cash one", function()
	local data = profile(1)
	-- Players take the first half of the roll, then the TP boosts (15, 30, 60 min) and the cash ones.
	local result = Grants.apply(data, Config.Products.caseStandard, "t1", 1, 0.74)
	T.eq(result.boostId, "caseBoostTp60")
	T.eq(data.boosts.tpBoostLeft, 3600)
	T.eq(data.boosts.cashBoostLeft, 0)
	T.eq(ProfileSchema.validate(data), true)
end)

T.test("a Standard boost adds its time to the bought cash timer, past the pads' cap", function()
	local data = profile(1)
	data.boosts.cashBoostLeft = Config.Boost.paidMaxSeconds
	local cash = data.cash
	local owned = Roster.ownedCount(data)
	local result = Grants.apply(data, Config.Products.caseStandard, "b1", 1, 0.9999)
	T.eq(result.kind, "case")
	T.eq(result.boostId, "caseBoost60")
	T.eq(result.playerId, nil)
	T.eq(data.boosts.cashBoostLeft, Config.Boost.paidMaxSeconds + 3600)
	T.eq(data.cash, cash)
	T.eq(Roster.ownedCount(data), owned)
	T.eq(#data.pendingReveals, 0)
	T.eq(ProfileSchema.validate(data), true)
	local _, again = Grants.apply(data, Config.Products.caseStandard, "b1", 2, 0.9999)
	T.eq(again, false)
	T.eq(data.boosts.cashBoostLeft, Config.Boost.paidMaxSeconds + 3600)
end)

T.test("a resent receipt grants nothing again and returns the same result", function()
	local data = profile(1)
	local first = Grants.apply(data, Config.Products.caseStandard, "same", 100, 0.5)
	local snapshot = {}
	for id, owned in data.players do
		snapshot[id] = owned.stars
	end
	local cash = data.cash
	local again, granted = Grants.apply(data, Config.Products.caseStandard, "same", 200, 0.01)
	T.eq(granted, false)
	T.eq(again.playerId, first.playerId)
	T.eq(data.cash, cash)
	for id, owned in data.players do
		T.eq(owned.stars, snapshot[id] or 0, id)
	end
end)

T.test("a duplicate adds a star, and past the cap it pays cash instead", function()
	local data = profile(1)
	local first = Grants.apply(data, Config.Products.caseStandard, "a", 1, 0)
	local id = first.playerId -- roll 0 lands on the first player, a duplicate once floor 1 is owned
	T.eq(first.isNew, false)
	T.eq(data.players[id].stars, 1)
	data.players[id].stars = Config.Stars.maxStars
	local cash = data.cash
	local maxed = Grants.apply(data, Config.Products.caseStandard, "b", 2, 0)
	T.eq(maxed.playerId, id)
	T.eq(data.players[id].stars, Config.Stars.maxStars)
	T.truthy(maxed.cash and maxed.cash > 0)
	T.eq(data.cash, cash + maxed.cash)
end)

T.test("a Legend bought with Robux is owned at once, and an owned one gets a star", function()
	local data = profile(3)
	local result = Grants.apply(data, Config.Products.legend_pele, "l1", 1, 0)
	T.eq(result.isNew, true)
	T.eq(Roster.owns(data, "pele"), true)
	local again = Grants.apply(data, Config.Products.legend_pele, "l2", 2, 0)
	T.eq(again.isNew, false)
	T.eq(data.players.pele.stars, 1)
end)

T.test(
	"a failed save leaves the receipt unconfirmed, and the retry grants nothing twice",
	function()
		local data = profile(1)
		local result, granted = Grants.process(
			data,
			Config.Products.caseStandard,
			"flaky",
			1,
			0.3,
			function()
				return false
			end
		)
		T.eq(result, nil) -- not confirmed: Roblox asks again
		T.eq(granted, true)
		T.truthy(data.receipts.flaky ~= nil) -- the grant is already in the profile
		local owned = Roster.ownedCount(data)
		local retried, grantedAgain = Grants.process(
			data,
			Config.Products.caseStandard,
			"flaky",
			2,
			0.9,
			function()
				return true
			end
		)
		T.truthy(retried ~= nil)
		T.eq(grantedAgain, false)
		T.eq(Roster.ownedCount(data), owned)
	end
)

T.test("every receipt-granting path keeps the profile valid", function()
	local data = profile(3)
	data.flags.milestones.first_purchase = 0
	for index, key in { "caseStandard", "caseElite", "cash_large", "boost_both", "legend_zidane" } do
		Grants.apply(data, Config.Products[key], "v" .. index, index, 0.37 * index % 1)
	end
	T.eq(ProfileSchema.validate(data), true)
end)

-- The boost bank in a match ---------------------------------------------------------------------

T.test("a banked match doubles one match and is used up", function()
	local data = profile(0)
	Roster.add(data, "rashford")
	data.fieldStarted = true
	data.flags.firstHatTrickDone = true
	local state = { matchesInRow = 0, matchesPlayed = 0 }
	local never = function()
		return 0.99
	end
	local plain = MatchLogic.resolve(data, state, MatchLogic.plan(data, state, never)).payout
	data.boosts.bankedMatches = 2
	local boosted = MatchLogic.resolve(data, state, MatchLogic.plan(data, state, never)).payout
	T.eq(boosted, plain * 2)
	MatchLogic.resolve(data, state, MatchLogic.plan(data, state, never))
	T.eq(data.boosts.bankedMatches, 0)
	T.eq(MatchLogic.resolve(data, state, MatchLogic.plan(data, state, never)).payout, plain)
end)

-- Cash and TP packs (the Robux pads) -------------------------------------------------------------

T.test(
	"a cash pack adds minutes of the player's income once, a resent receipt adds nothing",
	function()
		local data = profile(1)
		data.fieldStarted = true
		local cash, tp = data.cash, data.tp
		local expected = Daily.caseCash(data, 60)
		T.truthy(expected > 0)
		local result, granted = Grants.apply(data, Config.Products.cash_medium, "c1", 100, 0)
		T.eq(granted, true)
		T.eq(result.kind, "cash")
		T.eq(result.minutes, 60)
		T.eq(result.amount, expected)
		T.eq(data.cash, cash + expected)
		T.eq(data.tp, tp)
		local _, again = Grants.apply(data, Config.Products.cash_medium, "c1", 200, 0)
		T.eq(again, false)
		T.eq(data.cash, cash + expected)
	end
)

T.test("a cash pack is worth the same minutes at every stage of the climb", function()
	local early, late = profile(1), profile(3)
	T.near( -- the same ratio at both stages (whole dollars, so not to the last digit)
		Daily.caseCash(late, 15) / Daily.caseCash(early, 15),
		Daily.caseCash(late, 60) / Daily.caseCash(early, 60),
		0.5
	)
	T.truthy(Daily.caseCash(late, 15) > Daily.caseCash(early, 15) * 100)
end)

T.test("a TP pack adds its fixed amount to TP and leaves cash alone", function()
	local data = profile(0)
	local cash, tp = data.cash, data.tp
	local result = Grants.apply(data, Config.Products.tp_large, "t1", 100, 0)
	T.eq(result.kind, "tp")
	T.eq(result.amount, 10_000)
	T.eq(data.tp, tp + 10_000)
	T.eq(data.cash, cash)
end)

T.test("TP packs can be bought at any time, cash packs once someone is on the field", function()
	local data = profile(0)
	T.eq(ShopRules.canOffer(data, "tp_small"), true)
	T.eq(select(2, ShopRules.canOffer(data, "cash_small")), "early")
	Roster.add(data, "rashford")
	T.eq(ShopRules.canOffer(data, "cash_small"), true)
	T.eq(ShopRules.canOffer(data, "cash_large"), true)
end)

T.test("cash packs are 15 min, 1 hour and 4 hours of income; TP packs are fixed amounts", function()
	local cash = Config.Products
	T.deepEq(
		{ cash.cash_small.minutes, cash.cash_medium.minutes, cash.cash_large.minutes },
		{ 15, 60, 240 }
	)
	T.deepEq(
		{ cash.cash_small.robux, cash.cash_medium.robux, cash.cash_large.robux },
		{ 39, 129, 399 }
	)
	T.deepEq(
		{ cash.tp_small.amount, cash.tp_medium.amount, cash.tp_large.amount },
		{ 500, 2_500, 10_000 }
	)
	T.deepEq({ cash.tp_small.robux, cash.tp_medium.robux, cash.tp_large.robux }, { 39, 149, 499 })
end)
