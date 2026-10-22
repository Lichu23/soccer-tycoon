--!nocheck
local T = require("./framework")
local Config = T.load("shared/Config")
local Cosmetics = T.load("shared/Cosmetics")
local Grants = T.load("server/Grants")
local NewSeason = T.load("server/NewSeason")
local ProfileSchema = T.load("server/ProfileSchema")
local Roster = T.load("shared/Roster")
local ShopRules = T.load("server/ShopRules")

T.suite("cosmetics")

local function profile(tier)
	local data = ProfileSchema.newProfile()
	data.stadiumTier = tier
	return data
end

local function firstPremium(slot)
	for _, def in Cosmetics.styles(slot) do
		if def.robux then
			return def
		end
	end
end

T.test("every slot has free, cash and Robux styles, and each Robux one has a product", function()
	for _, slot in Config.CosmeticSlots do
		local free, cash, premium = 0, 0, 0
		for _, def in Cosmetics.styles(slot.id) do
			T.truthy(not (def.cash and def.robux), def.id .. " has two prices")
			if def.robux then
				premium += 1
				T.truthy(Config.Products["cosmetic_" .. def.id] ~= nil, def.id)
			elseif def.cash then
				cash += 1
				T.eq(Config.Products["cosmetic_" .. def.id], nil)
			else
				free += 1
			end
		end
		T.truthy(free >= 3, slot.id)
		T.truthy(cash >= 2, slot.id)
		T.truthy(premium >= 2, slot.id)
	end
end)

T.test("cash prices rise with the tier that opens the slot", function()
	local last = 0
	for _, slot in Config.CosmeticSlots do
		local cheapest = math.huge
		for _, def in Cosmetics.styles(slot.id) do
			if def.cash then
				cheapest = math.min(cheapest, def.cash)
			end
		end
		T.truthy(cheapest > last, slot.id)
		last = cheapest
	end
end)

T.test("a cash style is for sale once its tier is reached and the cash is there", function()
	local data = profile(1)
	data.cash = 1_000
	T.eq(select(2, Cosmetics.canBuyCash(data, "kit_red")), "cannotAfford")
	T.eq(select(2, Cosmetics.canBuyCash(data, "crest_ruby")), "tier")
	T.eq(select(2, Cosmetics.canBuyCash(data, "kit_blue")), "free")
	T.eq(select(2, Cosmetics.canBuyCash(data, "kit_gold")), "free") -- sold for Robux only
	T.eq(select(2, Cosmetics.canBuyCash(data, "nothing")), "unknown")
	data.cash = 2_000
	T.eq(Cosmetics.canBuyCash(data, "kit_red"), true)
	T.eq(select(2, Cosmetics.choose(data, "kit_red")), "locked")
	Cosmetics.grant(data, "kit_red")
	T.eq(select(2, Cosmetics.canBuyCash(data, "kit_red")), "owned")
	T.eq(Cosmetics.choose(data, "kit_red"), true)
	T.eq(select(2, Cosmetics.canBuy(data, "kit_red")), "free") -- never a Robux product
end)

T.test("a slot opens with its stadium tier", function()
	local data = profile(1)
	T.eq(Cosmetics.slotOpen(data, "kit"), true)
	T.eq(Cosmetics.slotOpen(data, "crest"), false)
	data.stadiumTier = 3
	T.eq(Cosmetics.slotOpen(data, "banners"), true)
	T.eq(Cosmetics.slotOpen(data, "floodlights"), false)
	T.eq(Cosmetics.slotOpen(data, "nothing"), false)
end)

T.test("a free style of an open slot can be chosen, a closed slot cannot", function()
	local data = profile(1)
	T.eq(Cosmetics.choose(data, "kit_green"), true)
	T.eq(data.cosmetics.chosen.kit, "kit_green")
	local ok, reason = Cosmetics.choose(data, "crest_star")
	T.eq(ok, false)
	T.eq(reason, "tier")
	T.eq(data.cosmetics.chosen.crest, nil)
	T.eq(select(2, Cosmetics.choose(data, "nothing")), "unknown")
end)

T.test("a premium style needs to be owned before it can be chosen", function()
	local data = profile(1)
	local def = firstPremium("kit")
	T.eq(select(2, Cosmetics.choose(data, def.id)), "locked")
	Cosmetics.grant(data, def.id)
	T.eq(Cosmetics.choose(data, def.id), true)
	T.eq(Cosmetics.chosen(data, "kit").id, def.id)
end)

T.test(
	"the default style is the first free one, and a bad saved choice falls back to it",
	function()
		local data = profile(1)
		T.eq(Cosmetics.chosen(data, "kit").id, "kit_blue")
		data.cosmetics.chosen.kit = firstPremium("kit").id -- chosen but never owned
		T.eq(Cosmetics.chosen(data, "kit").id, "kit_blue")
		data.cosmetics.chosen.kit = "crest_star" -- a style of another slot
		T.eq(Cosmetics.chosen(data, "kit").id, "kit_blue")
	end
)

T.test("premium styles are for sale only for tiers reached, once, never free ones", function()
	local data = profile(1)
	local crown = firstPremium("crest")
	T.eq(select(2, Cosmetics.canBuy(data, crown.id)), "tier")
	T.eq(select(2, Cosmetics.canBuy(data, "kit_blue")), "free")
	T.eq(select(2, Cosmetics.canBuy(data, "nothing")), "unknown")
	data.stadiumTier = 2
	T.eq(Cosmetics.canBuy(data, crown.id), true)
	Cosmetics.grant(data, crown.id)
	T.eq(select(2, Cosmetics.canBuy(data, crown.id)), "owned")
end)

T.test("granting a free style does nothing", function()
	local data = profile(1)
	Cosmetics.grant(data, "kit_blue")
	T.eq(next(data.cosmetics.owned), nil)
end)

T.test("a cosmetic offer has no waiting time, only its tier", function()
	local data = profile(1)
	local key = "cosmetic_" .. firstPremium("kit").id
	T.eq(ShopRules.canOffer(data, key), true) -- never bought anything
	local crest = "cosmetic_" .. firstPremium("crest").id
	T.eq(select(2, ShopRules.canOffer(data, crest)), "tier")
end)

T.test("a bought style is owned, put on, and a resent receipt grants nothing again", function()
	local data = profile(2)
	local def = firstPremium("crest")
	local product = Config.Products["cosmetic_" .. def.id]
	local result, granted = Grants.apply(data, product, "c1", 100, 0)
	T.eq(granted, true)
	T.eq(result.kind, "cosmetic")
	T.eq(data.cosmetics.owned[def.id], true)
	T.eq(data.cosmetics.chosen.crest, def.id)
	data.cosmetics.chosen.crest = "crest_star"
	local again, grantedAgain = Grants.apply(data, product, "c1", 200, 0)
	T.eq(grantedAgain, false)
	T.eq(again.cosmeticId, def.id)
	T.eq(data.cosmetics.chosen.crest, "crest_star") -- the replay does not put it on again
	T.eq(ProfileSchema.validate(data), true)
end)

T.test("a New Season keeps the owned and chosen styles", function()
	local data = profile(3)
	for _, player in Config.Players do
		if player.floor <= 3 then
			Roster.add(data, player.id)
		end
	end
	local def = firstPremium("kit")
	Cosmetics.grant(data, def.id)
	Cosmetics.choose(data, def.id)
	T.truthy(NewSeason.start(data, nil) ~= nil)
	T.eq(data.cosmetics.owned[def.id], true)
	T.eq(data.cosmetics.chosen.kit, def.id)
	-- Back at tier 1 the higher slots are closed again but nothing is lost.
	T.eq(Cosmetics.slotOpen(data, "banners"), false)
end)
