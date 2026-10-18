--!strict
-- Offline earnings (docs/PLAN.md, Steps 1 and 3). When a player joins, the time since their last
-- save becomes whole matches at the offline rate, capped at 4 hours. The time comes from the
-- server clock (os.time) saved in the profile, so changing the device date does nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(script.Parent.Economy)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Roster = require(ReplicatedStorage.Shared.Roster)

-- Shorter than this and the message would only be noise.
local MIN_SECONDS = 60

local Offline = {}

-- Cash earned while away, without changing anything. `now` is os.time().
function Offline.preview(data: ProfileSchema.Profile, now: number): (number, number)
	if not data.fieldStarted or data.lastSeen <= 0 then
		return 0, 0
	end
	local secondsAway = now - data.lastSeen
	if secondsAway < MIN_SECONDS then
		return 0, 0 -- also covers a negative gap (the clock went backwards)
	end
	local fieldIncomes = Roster.fieldIncomes(data)
	if #fieldIncomes == 0 then
		return 0, 0
	end
	local base = Formulas.basePayout({
		fieldIncomes = fieldIncomes,
		cashUpgradeLevel = data.storeLevels.cashPerMatch,
		season = data.season.number,
	})
	local earned = Formulas.offlineEarnings(
		secondsAway,
		Progress.matchSeconds(data),
		base,
		Progress.offlineRate(data)
	)
	return earned, secondsAway
end

-- Pays the offline earnings once and moves lastSeen to now, so rejoining cannot pay twice.
-- Returns the cash really added and the seconds away (0 when nothing was paid).
function Offline.apply(data: ProfileSchema.Profile, now: number): (number, number)
	local earned, secondsAway = Offline.preview(data, now)
	data.lastSeen = now
	if earned <= 0 then
		return 0, 0
	end
	return Economy.grant(data, earned), secondsAway
end

return Offline
