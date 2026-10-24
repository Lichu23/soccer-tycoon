--!strict
-- Who may be offered what in the shop (docs/PLAN.md, Step 3): the case rules (floors), the boost
-- timers, the cash packs, the cosmetic tiers and the direct Legend (once floor 2 is complete). There is no
-- waiting time: everything a player has unlocked can be bought at any moment. Pure on the profile,
-- so it is unit tested; Purchases uses it before a prompt and Sync publishes whether cases are open.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Boosts = require(script.Parent.Boosts)
local Cases = require(ReplicatedStorage.Shared.Cases)
local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Roster = require(ReplicatedStorage.Shared.Roster)

type Profile = ProfileSchema.Profile

local ShopRules = {}

-- Whether the shop shows cases yet: floor 2 started.
function ShopRules.casesOpen(data: Profile): boolean
	return Config.Features.cases and Roster.floorsComplete(data) >= 1
end

-- Whether a product may be offered now: true, or false and the reason ("unknown", "off", "early"
-- (a case before floor 1 is done, a cash pack before the first player), "locked", "tier", "full",
-- "owned").
function ShopRules.canOffer(data: Profile, key: string): (boolean, string?)
	local product = Config.Products[key]
	if product == nil then
		return false, "unknown"
	end
	if product.kind == "case" then
		if not Config.Features.cases then
			return false, "off"
		end
		if not ShopRules.casesOpen(data) then
			return false, "early"
		end
		if not Cases.unlocked(data, product.caseId or "") then
			return false, "locked"
		end
	elseif product.kind == "cash" then
		-- A cash pack is minutes of income: with nobody on the field it would be worth nothing.
		if #Roster.field(data) == 0 then
			return false, "early"
		end
	elseif product.kind == "timedBoost" then
		-- A boost timer holds at most an hour.
		if not Boosts.canAddPaid(data, product.boostsCash == true, product.boostsTp == true) then
			return false, "full"
		end
	elseif product.kind == "cosmetic" then
		-- Direct purchase of a visible style, only for tiers reached.
		local ok, reason = Cosmetics.canBuy(data, product.cosmeticId or "")
		if not ok then
			return false, reason
		end
	elseif product.kind == "legend" then
		if Roster.floorsComplete(data) < Config.LegendRobuxFloors then
			return false, "locked"
		end
		if Roster.owns(data, product.playerId or "") then
			return false, "owned"
		end
		-- Robux skips both the cash price and the trials (owner decision 2026-10-24); the Legend
		-- prices are set for that (docs/PRICING.md).
	end
	return true, nil
end

return ShopRules
