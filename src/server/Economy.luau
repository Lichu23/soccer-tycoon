--!strict
-- The only place cash and training points change (docs/PLAN.md, Step 5). A spend checks and
-- takes the cash in one step with no yield, so two fast requests cannot both pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Wallet = { cash: number, tp: number }

local Economy = {}

local function validAmount(amount: any): boolean
	return type(amount) == "number" and amount == amount and amount >= 0 and amount < math.huge
end

function Economy.canAfford(data: Wallet, amount: number): boolean
	return validAmount(amount) and data.cash >= amount
end

-- Takes `amount` from the cash. False (and nothing changes) when it is invalid or too much.
function Economy.spend(data: Wallet, amount: number): boolean
	if not validAmount(amount) or data.cash < amount then
		return false
	end
	data.cash -= amount
	return true
end

-- Adds cash up to the maximum. Returns how much was really added.
function Economy.grant(data: Wallet, amount: number): number
	if not validAmount(amount) or amount == 0 then
		return 0
	end
	local before = data.cash
	data.cash = math.min(before + amount, Config.MaxCash)
	return data.cash - before
end

function Economy.grantTp(data: Wallet, amount: number): number
	if not validAmount(amount) or amount == 0 then
		return 0
	end
	local before = data.tp
	data.tp = before + amount
	return amount
end

-- Mirrors the wallet to player attributes so the HUD can read it without a remote.
function Economy.publish(player: Instance, data: Wallet)
	player:SetAttribute("cash", data.cash)
	player:SetAttribute("tp", data.tp)
end

return Economy
