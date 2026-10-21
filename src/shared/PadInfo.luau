--!strict
-- The text a pad shows above it: the name on top, the price inside the ring, and a short note
-- under the ring (why it cannot be used, for example "Need $12 more"). Display only: the server
-- decides every purchase. Pure, so it is unit tested.

local Config = require(script.Parent.Config)
local Legends = require(script.Parent.Legends)
local NumberFormat = require(script.Parent.NumberFormat)
local Progress = require(script.Parent.Progress)
local Roster = require(script.Parent.Roster)
local Types = require(script.Parent.Types)

type ProgressData = Types.ProgressData

export type Line = { text: string, done: boolean }

export type Info = {
	title: string, -- above the ring
	price: string, -- inside the ring
	note: string, -- under the price, may be empty
	lines: { Line }?, -- extra rows under the price (the goals of a Legend)
	state: string, -- "ready", "cannotAfford", "locked", "owned", "maxed" or "info"
	icon: string?, -- the name of a picture shown above the text (client/Icons), for the Robux packs
}

local STORE_NAMES: { [string]: string } = {
	matchSpeed = "Faster matches",
	hatTrick = "Hat-trick chance",
	offline = "Offline earnings",
}

-- The stations of the Training Gym (the marker's PadId -> its name).
local TRAINING_NAMES: { [string]: string } = {
	trainingKeepie = "Keepie-uppies",
	trainingFreekick = "1v1 Breakaway",
	trainingTreadmill = "Treadmill",
	trainingBench = "Bench press",
}

local PadInfo = {}

-- Whether Config has a Store upgrade with this id (a pad id is just a string).
local function isStoreId(padId: string): boolean
	return (Config.Store :: any)[padId] ~= nil
end

local function missing(cost: number, cash: number): string
	return "Need " .. NumberFormat.money(cost - cash) .. " more"
end

-- The pad of an owned player once training is open: it levels the player up with TP.
function PadInfo.levelUp(data: ProgressData, def: Config.PlayerDef): Info
	local owned = data.players[def.id]
	local cap = Config.Rarities[def.rarity].levelCap
	local level = if owned then owned.level else 0
	local levelText = "Lv " .. level .. "/" .. cap
	local benched = table.find(Roster.field(data), def.id) == nil
	local status = Progress.levelStatus(data, def.id)
	local cost = Progress.levelCost(data, def.id)
	local bonus = "+" .. math.floor(Config.Training.bonusPerLevel * 100 + 0.5) .. "% income"
	-- Spending TP on a player who is not earning yet is allowed, but the pad says so first.
	local note = if benched then levelText .. " · on the bench" else levelText .. " · " .. bonus
	if status == "maxed" or cost == nil then
		return {
			title = def.name,
			price = "MAX",
			note = if benched then levelText .. " · on the bench" else levelText,
			state = "maxed",
		}
	elseif status == "cannotAfford" then
		local short = NumberFormat.short(cost - data.tp)
		return {
			title = def.name,
			price = NumberFormat.short(cost) .. " TP",
			note = levelText .. " · need " .. short .. " TP",
			state = status,
		}
	end
	return {
		title = def.name,
		price = NumberFormat.short(cost) .. " TP",
		note = note,
		state = status,
	}
end

function PadInfo.describe(kind: string, padId: string, data: ProgressData): Info
	if kind == "claim" then
		return { title = "Claim this plot", price = "FREE", note = "Stand here", state = "ready" }
	elseif kind == "player" then
		local def = Config.PlayersById[padId]
		if def == nil then
			return { title = "?", price = "", note = "", state = "locked" }
		end
		local status = Progress.playerStatus(data, padId)
		if status == "owned" then
			if not Progress.trainingUnlocked(data) then
				return { title = def.name, price = "OWNED", note = "", state = "owned" }
			end
			return PadInfo.levelUp(data, def)
		elseif status == "locked" then
			return {
				title = def.name,
				price = NumberFormat.money(def.price),
				note = "Finish floor " .. math.max(def.floor - 1, 1) .. " first",
				state = "locked",
			}
		elseif status == "cannotAfford" then
			return {
				title = def.name,
				price = NumberFormat.money(def.price),
				note = missing(def.price, data.cash),
				state = status,
			}
		end
		return { title = def.name, price = NumberFormat.money(def.price), note = "", state = status }
	elseif kind == "legend" then
		local def = Config.PlayersById[padId]
		if def == nil then
			return { title = "?", price = "", note = "", state = "locked" }
		end
		local status = Legends.status(data, padId)
		if status == "owned" then
			if not Progress.trainingUnlocked(data) then
				return { title = def.name, price = "OWNED", note = "", state = "owned" }
			end
			return PadInfo.levelUp(data, def)
		end
		local price = NumberFormat.money(def.price)
		local lines: { Line } = {}
		for _, goal in Legends.goals(data, padId) do
			table.insert(lines, { text = `{goal.text}  {goal.have}/{goal.need}`, done = goal.done })
		end
		local note = ""
		local state = status
		if status == "locked" then
			note = "Finish floor 3 first"
		elseif status == "goals" then
			state = "locked"
		elseif status == "cannotAfford" then
			note = missing(def.price, data.cash)
		end
		return { title = def.name, price = price, note = note, lines = lines, state = state }
	elseif kind == "store" then
		if not isStoreId(padId) then
			return { title = padId, price = "", note = "", state = "locked" }
		end
		local id: any = padId -- checked against Config above
		local title = STORE_NAMES[padId] or padId
		local status = Progress.storeStatus(data, id)
		local price = Progress.storePrice(data, id)
		if status == "locked" then
			return { title = title, price = "LOCKED", note = "Not unlocked yet", state = status }
		elseif status == "maxed" or price == nil then
			return { title = title, price = "MAX", note = "", state = "maxed" }
		elseif status == "cannotAfford" then
			return {
				title = title,
				price = NumberFormat.money(price),
				note = missing(price, data.cash),
				state = status,
			}
		end
		return { title = title, price = NumberFormat.money(price), note = "", state = status }
	elseif kind == "robux" then
		-- A cash or TP pack bought with Robux: the amount in the ring, the price under it. Whether it
		-- can be bought yet is the server's call (the first 30 minutes), it says so when stepped on.
		local product = Config.Products[padId]
		if product ~= nil and product.kind == "timedBoost" then
			-- An x2 boost: what it doubles and for how long in the ring, the price under it.
			local both = product.boostsCash and product.boostsTp
			local minutes = math.floor(Config.Boost.paidSeconds / 60)
			return {
				title = if both
					then "x2 Cash + TP"
					elseif product.boostsTp then "x2 TP"
					else "x2 Cash",
				price = minutes .. " MIN",
				note = product.robux .. " Robux",
				state = "ready",
				icon = if both then "boost" elseif product.boostsTp then "tp" else "cash",
			}
		end
		if product == nil or product.amount == nil then
			return { title = padId, price = "", note = "", state = "locked" }
		end
		local isCash = product.kind == "cash"
		return {
			title = if isCash then "Cash pack" else "TP pack",
			price = if isCash
				then "+" .. NumberFormat.money(product.amount)
				else "+" .. NumberFormat.short(product.amount) .. " TP",
			note = product.robux .. " Robux",
			state = "ready",
			icon = if isCash then "cash" else "tp",
		}
	elseif kind == "training" then
		local skill = padId == "trainingKeepie" or padId == "trainingFreekick"
		local title = TRAINING_NAMES[padId] or "Training"
		if not Progress.trainingUnlocked(data) then
			return {
				title = title,
				price = "",
				note = "Play your first match first",
				state = "locked",
			}
		end
		local note = if padId == "trainingFreekick"
			then "Dribble and score for TP"
			elseif skill then "Tap in time for TP"
			elseif padId == "trainingBench" then "Lie here: 10 TP per minute"
			else "Stand here: 10 TP per minute"
		return { title = title, price = "", note = note, state = "info" }
	elseif kind == "penalty" then
		-- Whether kicks are left today is the server's call (the client shows the wait time).
		if Roster.ownedCount(data) < 1 then
			return { title = "Penalty kicks", price = "", note = "", state = "locked" }
		end
		return { title = "Penalty kicks", price = "KICK", note = "", state = "ready" }
	elseif kind == "stadium" then
		local nextTier = Progress.nextTier(data)
		local status = Progress.stadiumStatus(data)
		if status == "maxed" or nextTier == nil then
			return { title = "Stadium", price = "MAX", note = "", state = "maxed" }
		elseif status == "cannotAfford" then
			return {
				title = "Stadium upgrade",
				price = NumberFormat.money(nextTier.price),
				note = missing(nextTier.price, data.cash),
				state = status,
			}
		end
		return {
			title = "Stadium upgrade",
			price = NumberFormat.money(nextTier.price),
			note = "",
			state = status,
		}
	end
	return { title = padId, price = "", note = "", state = "info" }
end

return PadInfo
