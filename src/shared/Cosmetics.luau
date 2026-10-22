--!strict
-- Team customization rules (docs/PLAN.md, Step 3): each stadium tier opens one slot, with free styles,
-- a few bought with cash and a few with Robux. The server checks every choice here, the Locker room draws from the same
-- answers. Pure on the profile, so it is unit tested.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

type Data = {
	cash: number,
	stadiumTier: number,
	cosmetics: { owned: { [string]: boolean }, chosen: { [string]: string } },
}

local Cosmetics = {}

local slotsById: { [string]: Config.CosmeticSlotDef } = {}
for _, slot in Config.CosmeticSlots do
	slotsById[slot.id] = slot
end

-- A slot is open once the stadium has reached its tier.
function Cosmetics.slotOpen(data: Data, slotId: string): boolean
	local slot = slotsById[slotId]
	return slot ~= nil and data.stadiumTier >= slot.tier
end

-- Every style of a slot, in the order of the config.
function Cosmetics.styles(slotId: string): { Config.CosmeticDef }
	local list: { Config.CosmeticDef } = {}
	for _, def in Config.Cosmetics do
		if def.slot == slotId then
			table.insert(list, def)
		end
	end
	return list
end

-- A style with neither a cash nor a Robux price.
function Cosmetics.isFree(def: Config.CosmeticDef): boolean
	return def.cash == nil and def.robux == nil
end

-- Free styles are always owned; the others once bought.
function Cosmetics.owns(data: Data, id: string): boolean
	local def = Config.CosmeticsById[id]
	if def == nil then
		return false
	end
	return Cosmetics.isFree(def) or data.cosmetics.owned[id] == true
end

-- The style a slot shows: the chosen one while it is still valid, else the slot's first free style.
function Cosmetics.chosen(data: Data, slotId: string): Config.CosmeticDef?
	local id = data.cosmetics.chosen[slotId]
	local def = if id then Config.CosmeticsById[id] else nil
	if def and def.slot == slotId and Cosmetics.owns(data, def.id) then
		return def
	end
	for _, option in Cosmetics.styles(slotId) do
		if Cosmetics.isFree(option) then
			return option
		end
	end
	return nil
end

-- Whether a style may be chosen: true, or false and the reason ("unknown", "tier", "locked").
function Cosmetics.canChoose(data: Data, id: string): (boolean, string?)
	local def = Config.CosmeticsById[id]
	if def == nil then
		return false, "unknown"
	end
	if not Cosmetics.slotOpen(data, def.slot) then
		return false, "tier"
	end
	if not Cosmetics.owns(data, id) then
		return false, "locked"
	end
	return true, nil
end

-- Whether a Robux style may be bought: true, or false and the reason ("unknown", "free", "tier",
-- "owned"). "free" also answers a style sold for cash.
function Cosmetics.canBuy(data: Data, id: string): (boolean, string?)
	local def = Config.CosmeticsById[id]
	if def == nil then
		return false, "unknown"
	end
	if def.robux == nil then
		return false, "free"
	end
	if not Cosmetics.slotOpen(data, def.slot) then
		return false, "tier"
	end
	if data.cosmetics.owned[id] == true then
		return false, "owned"
	end
	return true, nil
end

-- Whether a cash style may be bought: true, or false and the reason ("unknown", "free", "tier",
-- "owned", "cannotAfford"). "free" also answers a style sold for Robux.
function Cosmetics.canBuyCash(data: Data, id: string): (boolean, string?)
	local def = Config.CosmeticsById[id]
	if def == nil then
		return false, "unknown"
	end
	local price = def.cash
	if price == nil then
		return false, "free"
	end
	if not Cosmetics.slotOpen(data, def.slot) then
		return false, "tier"
	end
	if data.cosmetics.owned[id] == true then
		return false, "owned"
	end
	if data.cash < price then
		return false, "cannotAfford"
	end
	return true, nil
end

-- Picks a style for its slot. Returns true, or false and the reason.
function Cosmetics.choose(data: Data, id: string): (boolean, string?)
	local ok, reason = Cosmetics.canChoose(data, id)
	if not ok then
		return false, reason
	end
	local def = Config.CosmeticsById[id]
	data.cosmetics.chosen[def.slot] = id
	return true, nil
end

-- Records a bought style as owned (a resent receipt changes nothing).
function Cosmetics.grant(data: Data, id: string)
	local def = Config.CosmeticsById[id]
	if def and not Cosmetics.isFree(def) then
		data.cosmetics.owned[id] = true
	end
end

-- The tier that opened the most recent slot (the Locker room notes it), 0 when none.
function Cosmetics.slotForTier(tier: number): Config.CosmeticSlotDef?
	for _, slot in Config.CosmeticSlots do
		if slot.tier == tier then
			return slot
		end
	end
	return nil
end

return Cosmetics
