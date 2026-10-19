--!strict
-- Runs the reminders (docs/PLAN.md, Step 3, Notifications). A player who left gets their reminder
-- queued in a MemoryStore sorted map, keyed by user id and sorted by the time it is due. Any live server
-- looks for due ones once a minute and sends them with Notifier, so a reminder goes out as long as some
-- server of the game is running. Coming back cancels the queued one and settles whether the last
-- reminder was answered. Everything is wrapped in pcall: a failed store or send is logged once and
-- never touches gameplay. Not tested in Studio (the store is a mock there); the rules live in Reminders.

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Notifier = require(script.Parent.Notifier)
local Reminders = require(script.Parent.Reminders)
local Session = require(script.Parent.Session)

local SENT_KEEP_SECONDS = 30 * 24 * 60 * 60
local SWEEP_BATCH = 20

local queue: any
local sentMarks: any
local warned: { [string]: boolean } = {}
local started = false

local ReminderService = {}

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn("[Reminders] " .. message)
	end
end

local function guarded(label: string, fn: () -> any): any
	local ok, result = pcall(fn)
	if not ok then
		warnOnce(label, `{label} failed: {result}`)
		return nil
	end
	return result
end

-- The player is back: cancel what was queued and settle the last reminder.
local function onJoin(session: Session.Session)
	local key = tostring(session.player.UserId)
	local sentAt = guarded("read sent mark", function()
		return sentMarks:GetAsync(key)
	end)
	if Session.get(session.player) ~= session then
		return -- they left while the store answered
	end
	if type(sentAt) == "number" then
		Reminders.onReturn(session.data, os.time(), sentAt)
		guarded("clear sent mark", function()
			sentMarks:RemoveAsync(key)
			return nil
		end)
	end
	guarded("cancel queued reminder", function()
		queue:RemoveAsync(key)
		return nil
	end)
end

-- The player left: queue the reminder that is due after this visit, if any.
local function onLeaving(session: Session.Session)
	local plan = Reminders.plan(session.data, os.time())
	if plan == nil then
		return
	end
	local key = tostring(session.player.UserId)
	task.spawn(function()
		guarded("queue reminder", function()
			queue:SetAsync(key, { kind = plan.kind }, Config.Reminders.queueSeconds, plan.dueAt)
			return nil
		end)
	end)
end

-- Sends every reminder that is due now.
local function sweep()
	local now = os.time()
	local due = guarded("read due reminders", function()
		return queue:GetRangeAsync(
			Enum.SortDirection.Ascending,
			SWEEP_BATCH,
			nil,
			{ sortKey = now + 1 }
		)
	end)
	if due == nil then
		return
	end
	for _, item in due do
		local key, value = item.key, item.value
		-- Taken out first, so a second server that sweeps at the same time does not send it again.
		local taken = guarded("take reminder", function()
			queue:RemoveAsync(key)
			return true
		end)
		local userId = tonumber(key)
		if taken and userId and type(value) == "table" and type(value.kind) == "string" then
			local ok, why = Notifier.send(userId, value.kind)
			if ok then
				guarded("mark reminder sent", function()
					sentMarks:SetAsync(key, os.time(), SENT_KEEP_SECONDS)
					return nil
				end)
			else
				warnOnce("send " .. why, "not sent: " .. why)
			end
		end
	end
end

-- Call once at startup, after Session.init.
function ReminderService.start()
	assert(not started, "ReminderService.start called twice")
	started = true
	if not Config.Features.notifications then
		return
	end
	local ok = pcall(function()
		queue = MemoryStoreService:GetSortedMap("Reminders")
		sentMarks = MemoryStoreService:GetSortedMap("ReminderSent")
	end)
	if not ok then
		warnOnce("store", "MemoryStore is unavailable; reminders are off in this server")
		return
	end
	Session.onLoaded(function(session)
		task.spawn(onJoin, session)
	end)
	Session.onLeaving(onLeaving)
	task.spawn(function()
		while true do
			task.wait(Config.Reminders.sweepSeconds)
			sweep()
		end
	end)
end

return ReminderService
