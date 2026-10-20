--!strict
-- Who may be offered what in the shop (docs/PLAN.md, Step 3): the case rules (floors, no offers in
-- the first 30 minutes), the boost bank and the direct Legend. Pure on the profile, so it is unit
-- tested; Purchases uses it before a prompt and Sync publishes whether cases are open.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cases = require(ReplicatedStorage.Shared.Cases)
local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Legends = require(ReplicatedStorage.Shared.Legends)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Roster = require(ReplicatedStorage.Shared.Roster)

type Profile = ProfileSchema.Profile

local ShopRules = {}

-- Whether the shop shows cases yet: floor 2 started, and 30 minutes after the first purchase.
function ShopRules.casesOpen(data: Profile, now: number): boolean
	local first = data.flags.milestones["first_purchase"]
	return Config.Features.cases
		and Roster.floorsComplete(data) >= 1
		and first ~= nil
		and now - first >= Config.CaseRules.noOfferSeconds
end

-- Whether a product may be offered now: true, or false and the reason ("unknown", "off", "early",
-- "locked", "tier", "full", "owned").
function ShopRules.canOffer(data: Profile, key: string, now: number): (boolean, string?)
	local product = Config.Products[key]
	if product == nil then
		return false, "unknown"
	end
	if product.kind == "case" then
		if not Config.Features.cases then
			return false, "off"
		end
		if not ShopRules.casesOpen(data, now) then
			return false, "early"
		end
		if not Cases.unlocked(data, product.caseId or "") then
			return false, "locked"
		end
	elseif product.kind == "boost" then
		-- The bank has room for another pack (it never expires, and is capped at 60).
		if data.boosts.bankedMatches + Config.Boost.matchPackSize > Config.Boost.matchBankMax then
			return false, "full"
		end
	elseif product.kind == "cash" or product.kind == "tp" then
		-- Packs wait like everything paid: never in the first 30 minutes after the first purchase.
		local first = data.flags.milestones["first_purchase"]
		if first == nil or now - first < Config.CaseRules.noOfferSeconds then
			return false, "early"
		end
	elseif product.kind == "cosmetic" then
		-- Direct purchase of a visible style, only for tiers reached and never in the first 30 minutes.
		local first = data.flags.milestones["first_purchase"]
		if first == nil or now - first < Config.CaseRules.noOfferSeconds then
			return false, "early"
		end
		local ok, reason = Cosmetics.canBuy(data, product.cosmeticId or "")
		if not ok then
			return false, reason
		end
	elseif product.kind == "legend" then
		if not Legends.reached(data) then
			return false, "locked"
		end
		if Roster.owns(data, product.playerId or "") then
			return false, "owned"
		end
	end
	return true, nil
end

return ShopRules
