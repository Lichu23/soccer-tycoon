--!strict
-- What a Robux purchase gives (docs/PLAN.md, Steps 3 and 5), in one step on the profile with the
-- receipt recorded by its PurchaseId, so a resent receipt grants nothing a second time. Pure, so it
-- is unit tested; Purchases decides when to call it and confirms the receipt after the save.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Boosts = require(script.Parent.Boosts)
local Cases = require(ReplicatedStorage.Shared.Cases)
local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Daily = require(script.Parent.Daily)
local Economy = require(script.Parent.Economy)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Reveals = require(script.Parent.Reveals)

type Profile = ProfileSchema.Profile

local Grants = {}

-- Grants a product once for this PurchaseId and records the receipt in the profile. A resent
-- receipt grants nothing again and returns the saved result with `false`. `roll` is a number in
-- [0, 1) for the case pick. `robuxSpent` is what Roblox charged (the shown price when not given),
-- added to the leaderboard total. Returns (result, granted).
function Grants.apply(
	data: Profile,
	product: Config.ProductDef,
	purchaseId: string,
	now: number,
	roll: number,
	robuxSpent: number?
): ({ [string]: any }, boolean)
	local existing = data.receipts[purchaseId]
	if existing then
		return existing.result, false
	end

	local result: { [string]: any }
	if product.kind == "case" then
		local entries = Cases.odds(data, product.caseId or "")
		local id = Cases.pick(entries, roll)
		local boost = Config.CaseBoostsById[id]
		if boost then
			-- A x2 cash boost: its time adds to the bought cash timer.
			Boosts.addCaseBoost(data, boost.seconds)
			result =
				{ kind = "case", caseId = product.caseId, boostId = id, seconds = boost.seconds }
		else
			local before = data.players[id]
			local wasMaxed = before ~= nil and before.stars >= Config.Stars.maxStars
			Reveals.grant(data, id, true)
			result = {
				kind = "case",
				caseId = product.caseId,
				playerId = id,
				isNew = before == nil,
				stars = data.players[id].stars,
			}
			if wasMaxed then
				-- A duplicate past the star cap is never dead: it pays a few minutes of income.
				local cash = Daily.caseCash(data, Config.CaseRules.duplicateCashMinutes)
				Economy.grant(data, cash)
				result.cash = cash
			end
		end
	elseif product.kind == "boost" then
		-- Granted in full even when the bank has filled up since the prompt.
		data.boosts.bankedMatches += Config.Boost.matchPackSize
		result = { kind = "boost", matches = Config.Boost.matchPackSize }
	elseif product.kind == "timedBoost" then
		-- Granted in full even when the timer has filled up since the prompt (ShopRules checks before).
		local cash, tp = product.boostsCash == true, product.boostsTp == true
		Boosts.addPaid(data, cash, tp)
		result = { kind = "timedBoost", cash = cash, tp = tp, seconds = Config.Boost.paidSeconds }
	elseif product.kind == "cash" then
		result = { kind = "cash", amount = Economy.grant(data, product.amount or 0) }
	elseif product.kind == "tp" then
		result = { kind = "tp", amount = Economy.grantTp(data, product.amount or 0) }
	elseif product.kind == "cosmetic" then
		-- Owned for good (a New Season keeps it) and put on at once; a resent receipt never reaches here.
		local id = product.cosmeticId or ""
		Cosmetics.grant(data, id)
		Cosmetics.choose(data, id)
		result = { kind = "cosmetic", cosmeticId = id }
	else
		local id = product.playerId or ""
		local owned = data.players[id] ~= nil
		-- Already owned (bought with cash in between): the Robux are not wasted, it adds a star.
		Reveals.grant(data, id, owned)
		result = { kind = "legend", playerId = id, isNew = not owned }
	end
	local spent = robuxSpent or product.robux
	if type(spent) == "number" and spent > 0 and spent == math.floor(spent) then
		data.stats.robuxSpent += spent
	end
	data.receipts[purchaseId] = { at = now, result = result }
	return result, true
end

-- Grants and saves one purchase. `save` stores the profile and returns true once the receipt is in
-- the saved data. Returns the result and whether it was granted just now, or nil when the save
-- failed: the receipt then stays unconfirmed (Roblox asks again), and the retry finds the receipt in
-- the profile, grants nothing again and only tries the save again.
function Grants.process(
	data: Profile,
	product: Config.ProductDef,
	purchaseId: string,
	now: number,
	roll: number,
	save: () -> boolean,
	robuxSpent: number?
): ({ [string]: any }?, boolean)
	local result, granted = Grants.apply(data, product, purchaseId, now, roll, robuxSpent)
	if not save() then
		return nil, granted
	end
	return result, granted
end

return Grants
