--!nocheck
local T = require("./framework")
local Config = T.load("shared/Config")
local Notifications = T.load("shared/Notifications")
local ProfileSchema = T.load("server/ProfileSchema")
local Reminders = T.load("server/Reminders")
local Roster = T.load("shared/Roster")

T.suite("reminders")

local HOUR = 3600
local LEFT = 1_000_000

local function profile(opts)
	local data = ProfileSchema.newProfile()
	data.flags.notificationsOn = true
	if opts.field then
		Roster.add(data, "rashford")
		data.fieldStarted = true
	end
	data.stadiumTier = opts.tier or 1
	return data
end

T.test("nothing is planned unless the player turned reminders on", function()
	local data = profile({ field = true })
	data.flags.notificationsOn = false
	T.eq(Reminders.plan(data, LEFT), nil)
end)

T.test("the offline bank reminder comes when the 4 hour cap is reached", function()
	local data = profile({ field = true })
	data.daily.caseClaimedAt = LEFT -- the free case was just opened, so only the bank is left to remind about
	local plan = Reminders.plan(data, LEFT)
	T.eq(plan.kind, "bank")
	T.eq(plan.dueAt, LEFT + Config.Offline.capSeconds)
end)

T.test("no player on the field and no daily case means nothing to remind about", function()
	T.eq(Reminders.plan(profile({}), LEFT), nil)
end)

T.test("the free case reminder wins when it is ready before the bank is full", function()
	local data = profile({ field = true })
	data.daily.caseClaimedAt = LEFT - Config.Daily.cooldownSeconds + 2 * HOUR -- ready 2 hours after leaving
	local plan = Reminders.plan(data, LEFT)
	T.eq(plan.kind, "case")
	T.eq(plan.dueAt, LEFT + 2 * HOUR)
end)

T.test("a case that is already ready waits the minimum away time, not an instant ping", function()
	local data = profile({ field = true })
	local plan = Reminders.plan(data, LEFT)
	T.eq(plan.kind, "case")
	T.eq(plan.dueAt, LEFT + Config.Reminders.minAwaySeconds)
end)

T.test("at most one a day: a recent reminder pushes the next one back", function()
	local data = profile({ field = true })
	data.flags.reminderLastSentAt = LEFT - HOUR
	local plan = Reminders.plan(data, LEFT)
	T.eq(plan.dueAt, LEFT - HOUR + Config.Reminders.minGapSeconds)
end)

T.test("a reminder that would come too late to matter is dropped", function()
	local data = profile({ field = true })
	data.flags.reminderLastSentAt = LEFT + Config.Reminders.queueSeconds
	T.eq(Reminders.plan(data, LEFT), nil)
end)

T.test("a quick return answers the last reminder, a late one counts as ignored", function()
	local data = profile({ field = true })
	data.flags.reminderIgnored = 2
	Reminders.onReturn(data, LEFT + HOUR, LEFT)
	T.eq(data.flags.reminderIgnored, 0)
	T.eq(data.flags.reminderLastSentAt, LEFT)
	Reminders.onReturn(data, LEFT + 20 * HOUR, LEFT)
	T.eq(data.flags.reminderIgnored, 1)
	Reminders.onReturn(data, LEFT + 99 * HOUR, nil) -- nothing was sent: nothing changes
	T.eq(data.flags.reminderIgnored, 1)
end)

T.test("after several ignored reminders they stop until the player turns them on again", function()
	local data = profile({ field = true })
	for _ = 1, Config.Reminders.stopAfterIgnored do
		Reminders.onReturn(data, LEFT + 30 * HOUR, LEFT)
	end
	T.eq(Reminders.stopped(data), true)
	T.eq(Reminders.plan(data, LEFT), nil)
	Notifications.set(data, true)
	T.eq(Reminders.stopped(data), false)
	T.truthy(Reminders.plan(data, LEFT) ~= nil)
end)

T.test("the new flags keep the profile valid", function()
	local data = profile({ field = true })
	Reminders.onReturn(data, LEFT + 30 * HOUR, LEFT)
	T.eq(ProfileSchema.validate(data), true)
end)
