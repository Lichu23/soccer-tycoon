--!strict
-- The reminder opt-in (docs/PLAN.md, Step 3, Notifications). A HUD icon opens it once the player has
-- bought their first player; it never interrupts and the answer can be changed at any time. This
-- only records the choice; nothing is sent from here.

local Config = require(script.Parent.Config)

export type Data = { players: { [string]: any }, flags: { [string]: any } }

local Notifications = {}

-- The icon shows once the player owns someone (the first purchase is done).
function Notifications.unlocked(data: { players: { [string]: any } }): boolean
	return Config.Features.notifications and next(data.players) ~= nil
end

-- Records the answer. False while the feature is locked.
function Notifications.set(data: Data, on: boolean): boolean
	if not Notifications.unlocked(data) then
		return false
	end
	data.flags.notificationAsked = true
	data.flags.notificationsOn = on
	if on then
		data.flags.reminderIgnored = 0 -- turning it on again starts fresh
	end
	return true
end

return Notifications
