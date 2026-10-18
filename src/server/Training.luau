--!strict
-- The training ground rules (docs/PLAN.md, Steps 1, 3 and 4). Standing on the training pad earns
-- 10 TP per minute while the stamina lasts; the stamina refills while the player is away from the
-- pad (and while offline). A timing drill pays extra TP (up to the per-minute cap) for as long as
-- the player keeps hitting it. TP are whole numbers in the profile, so the fraction that has not
-- reached a whole point yet is carried in memory (lost on leaving, less than 1 TP). Pure and unit
-- tested; TrainingActions wires it to the pad and the remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(script.Parent.Economy)
local ProfileSchema = require(script.Parent.ProfileSchema)

type Profile = ProfileSchema.Profile

-- The part of a TP point not paid yet.
export type Carry = { fraction: number, drillLog: { { at: number, amount: number } } }

local Training = {}

function Training.newCarry(): Carry
	return { fraction = 0, drillLog = {} }
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
-- stamina left nothing is paid and nothing refills until the player steps away. Returns the whole
-- TP paid in this step.
function Training.step(data: Profile, carry: Carry, dt: number, training: boolean): number
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
	carry.fraction += Config.Training.idleTpPerMinute / 60 * used
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

-- The drill ----------------------------------------------------------------------------------

local WINDOW_SECONDS = 60

-- TP the drill may still pay now: the drill part of the per-minute cap (the maximum rate minus the
-- idle rate) minus what it paid in the last minute.
function Training.drillRoomLeft(carry: Carry, now: number): number
	local log = carry.drillLog
	while #log > 0 and now - log[1].at > WINDOW_SECONDS do
		table.remove(log, 1)
	end
	local paid = 0
	for _, entry in log do
		paid += entry.amount
	end
	local cap = Config.Training.drillTpPerMinuteMax - Config.Training.idleTpPerMinute
	return math.max(cap - paid, 0)
end

-- Pays the drill result of a press: "hit" is the base TP plus the bonus, "miss" the base TP only,
-- the others nothing. Only while the player is training with stamina left and under the rate cap.
-- Returns the TP paid (a fraction), which can be less than asked when the cap is reached.
function Training.drillPay(data: Profile, carry: Carry, outcome: string, now: number): number
	if data.staminaLeft <= 0 or (outcome ~= "hit" and outcome ~= "miss") then
		return 0
	end
	local wanted = Config.Training.drillBaseTp
	if outcome == "hit" then
		wanted += Config.Training.drillHitBonusTp
	end
	local paid = math.min(wanted, Training.drillRoomLeft(carry, now))
	if paid <= 0 then
		return 0
	end
	table.insert(carry.drillLog, { at = now, amount = paid })
	carry.fraction += paid
	payWhole(data, carry)
	return paid
end

return Training
