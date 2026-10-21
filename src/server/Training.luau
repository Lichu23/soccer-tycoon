--!strict
-- The training ground rules (docs/PLAN.md, Steps 1, 3 and 4). Standing on the training pad earns
-- 10 TP per minute while the stamina lasts; the stamina refills while the player is away from the
-- pad (and while offline). The keepie-uppies game pays extra TP (up to the per-minute cap) for as long
-- as the player keeps the ball up. TP are whole numbers in the profile, so the fraction that has not
-- reached a whole point yet is carried in memory (lost on leaving, less than 1 TP). Pure and unit
-- tested; TrainingActions wires it to the pad and the remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Boosts = require(script.Parent.Boosts)
local Economy = require(script.Parent.Economy)
local ProfileSchema = require(script.Parent.ProfileSchema)

type Profile = ProfileSchema.Profile

-- The part of a TP point not paid yet.
export type Carry = { fraction: number, payLog: { { at: number, amount: number } } }

local Training = {}

function Training.newCarry(): Carry
	return { fraction = 0, payLog = {} }
end

-- Stamina seconds restored per second spent away from the pad.
function Training.refillPerSecond(): number
	return Config.Training.staminaSeconds / Config.Training.staminaRefillSeconds
end

-- Whether the player could earn TP right now if they stood on the pad.
function Training.hasStamina(data: Profile): boolean
	return data.staminaLeft > 0
end

-- Pays the whole TP that the carried fraction has reached. Returns the whole TP paid.
local function payWhole(data: Profile, carry: Carry): number
	local whole = math.floor(carry.fraction + 1e-6) -- 0.25 s steps leave 9.9999 instead of 10
	if whole <= 0 then
		return 0
	end
	carry.fraction -= whole
	return Economy.grantTp(data, whole)
end

-- Moves the training forward by `dt` seconds. `training` is true while the player stands on the
-- pad with the training open. Standing still drains the stamina and pays the idle rate; with no
-- stamina left nothing is paid and nothing refills until the player steps away. On the active
-- station (`paysIdle` false) the stamina drains the same but nothing is paid here: only the game
-- pays. Returns the whole TP paid in this step.
function Training.step(
	data: Profile,
	carry: Carry,
	dt: number,
	training: boolean,
	paysIdle: boolean?
): number
	if dt <= 0 then
		return 0
	end
	if not training then
		data.staminaLeft = math.min(
			Config.Training.staminaSeconds,
			data.staminaLeft + dt * Training.refillPerSecond()
		)
		return 0
	end
	local used = math.min(dt, data.staminaLeft)
	if used <= 0 then
		return 0
	end
	data.staminaLeft -= used
	if paysIdle == false then
		return 0
	end
	carry.fraction += Config.Training.idleTpPerMinute / 60 * used * Boosts.tpMultiplier(data)
	return payWhole(data, carry)
end

-- Refills the stamina for the time the player was offline (TP are never earned offline).
function Training.refillAway(data: Profile, secondsAway: number)
	if secondsAway <= 0 then
		return
	end
	data.staminaLeft = math.min(
		Config.Training.staminaSeconds,
		data.staminaLeft + secondsAway * Training.refillPerSecond()
	)
end

-- The skill games (keepie-uppies, free kicks) ------------------------------------------------------------------------------

local WINDOW_SECONDS = 60

-- TP the skill games may still pay now (one cap for both, only one is played at a time): the per-minute cap minus what it paid in the last minute.
function Training.gameRoomLeft(carry: Carry, now: number): number
	local log = carry.payLog
	while #log > 0 and now - log[1].at > WINDOW_SECONDS do
		table.remove(log, 1)
	end
	local paid = 0
	for _, entry in log do
		paid += entry.amount
	end
	return math.max(Config.Training.juggleTpPerMinuteMax - paid, 0)
end

-- Pays `wanted` TP for a clean touch of the keepie-uppies or a goal of the free kicks (the game's
-- `tpFor` of the streak). Only while the player is training with stamina left and under the rate
-- cap (counted before the x2 TP boost, which doubles what is paid). Returns the TP paid (a
-- fraction), which can be less than asked when the cap is reached.
function Training.gamePay(data: Profile, carry: Carry, wanted: number, now: number): number
	if data.staminaLeft <= 0 or not (wanted > 0) then
		return 0
	end
	local paid = math.min(wanted, Training.gameRoomLeft(carry, now))
	if paid <= 0 then
		return 0
	end
	table.insert(carry.payLog, { at = now, amount = paid })
	paid *= Boosts.tpMultiplier(data)
	carry.fraction += paid
	payWhole(data, carry)
	return paid
end

return Training
