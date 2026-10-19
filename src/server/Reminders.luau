--!strict
-- When a reminder is due (docs/PLAN.md, Step 3, Notifications). Pure on the profile, so it is unit
-- tested; ReminderService stores the plan and Notifier sends it. A player who opted in gets at most
-- one reminder after each visit: the offline bank full (the 4 hour cap) or the free case ready,
-- whichever comes first, never sooner than a day after the last one, and none at all once several
-- in a row were ignored. Only true, useful information, no guilt wording.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Daily = require(script.Parent.Daily)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Roster = require(ReplicatedStorage.Shared.Roster)

type Profile = ProfileSchema.Profile

export type Plan = { kind: string, dueAt: number }

local Reminders = {}

-- Several reminders in a row went unanswered: stop until the player turns them on again.
function Reminders.stopped(data: Profile): boolean
	return data.flags.reminderIgnored >= Config.Reminders.stopAfterIgnored
end

-- The reminder to send after this visit, or nil. `leftAt` is os.time() when the player left.
function Reminders.plan(data: Profile, leftAt: number): Plan?
	if not data.flags.notificationsOn or Reminders.stopped(data) then
		return nil
	end
	local best: Plan? = nil
	local function consider(kind: string, dueAt: number)
		if best == nil or dueAt < best.dueAt then
			best = { kind = kind, dueAt = dueAt }
		end
	end
	-- Offline earnings only grow while someone is on the field.
	if data.fieldStarted and #Roster.fieldIncomes(data) > 0 then
		consider("bank", leftAt + Config.Offline.capSeconds)
	end
	if Daily.unlocked(data) then
		consider(
			"case",
			math.max(Daily.caseReadyAt(data), leftAt + Config.Reminders.minAwaySeconds)
		)
	end
	local plan = best :: Plan?
	if plan == nil then
		return nil
	end
	-- At most one a day: never sooner than the minimum gap after the last one.
	local earliest = data.flags.reminderLastSentAt + Config.Reminders.minGapSeconds
	plan.dueAt = math.max(plan.dueAt, earliest)
	if plan.dueAt - leftAt > Config.Reminders.queueSeconds then
		return nil
	end
	return plan
end

-- The player is back. `sentAt` is when the last reminder was sent to them (nil when none was
-- waiting). Coming back soon after it counts as an answer; staying away counts as ignored.
function Reminders.onReturn(data: Profile, now: number, sentAt: number?)
	if sentAt == nil then
		return
	end
	data.flags.reminderLastSentAt = sentAt
	if now - sentAt <= Config.Reminders.respondedWithinSeconds then
		data.flags.reminderIgnored = 0
	else
		data.flags.reminderIgnored += 1
	end
end

return Reminders
