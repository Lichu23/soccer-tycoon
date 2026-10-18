--!strict
-- The training ground rules (docs/PLAN.md, Steps 1, 3 and 4). Standing on the training pad earns
-- 10 TP per minute while the stamina lasts; the stamina refills while the player is away from the
-- pad (and while offline). A timing drill raises the rate towards 15 TP per minute for as long as
-- the player keeps hitting it. TP are whole numbers in the profile, so the fraction that has not
-- reached a whole point yet is carried in memory (lost on leaving, less than 1 TP). Pure and unit
-- tested; TrainingActions wires it to the pad and the remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Drill = require(ReplicatedStorage.Shared.Drill)
local Economy = require(script.Parent.Economy)
local ProfileSchema = require(script.Parent.ProfileSchema)

type Profile = ProfileSchema.Profile

-- The part of a TP point not paid yet.
export type Carry = { fraction: number }

local Training = {}

function Training.newCarry(): Carry
	return { fraction = 0 }
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

-- Extra TP one hit pays, so that a hit in every round lifts the rate from the idle rate to the
-- drill maximum.
function Training.drillBonusPerHit(): number
	local extraPerMinute = Config.Training.drillTpPerMinuteMax - Config.Training.idleTpPerMinute
	return extraPerMinute * Config.Training.drillRoundSeconds / 60
end

-- The marker and the judging are shared with the client (Drill), kept here for the callers.
Training.drillPosition = Drill.position
Training.judgeHit = Drill.judge

-- Pays a drill hit (as a fraction of TP), only while the player is training with stamina left.
-- Returns the whole TP paid.
function Training.addDrillHit(data: Profile, carry: Carry): number
	if data.staminaLeft <= 0 then
		return 0
	end
	carry.fraction += Training.drillBonusPerHit()
	return payWhole(data, carry)
end

return Training
