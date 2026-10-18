--!strict
-- What the two daily icons and the penalty pad show (docs/PLAN.md, Step 7): ready, waiting or not
-- unlocked yet, and the time left as plain text. Display only: the server judges every claim and
-- kick. Pure, so it is unit tested.

local DailyInfo = {}

-- "Ready in 3 h 20 min", "Ready in 45 min" or "Ready in under a minute".
function DailyInfo.waitText(seconds: number): string
	local minutes = math.ceil(math.max(seconds, 0) / 60)
	if minutes <= 1 then
		return "Ready in under a minute"
	end
	local hours = minutes // 60
	local rest = minutes % 60
	if hours == 0 then
		return "Ready in " .. rest .. " min"
	elseif rest == 0 then
		return "Ready in " .. hours .. " h"
	end
	return "Ready in " .. hours .. " h " .. rest .. " min"
end

-- "locked" before the icons open, "ready" when readyAt (server time) has passed, else "waiting".
function DailyInfo.status(unlocked: boolean, readyAt: number, now: number): string
	if not unlocked then
		return "locked"
	end
	return if now >= readyAt then "ready" else "waiting"
end

return DailyInfo
