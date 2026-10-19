--!strict
-- Sends one Roblox experience notification through Open Cloud (create user notification). It needs
-- three things set up outside the code: the notification strings (Config.Reminders.messages, made in
-- the Creator Hub), an API key with the user-notification permission saved as the HttpService secret
-- "ReminderApiKey", and HTTP requests enabled. Without them nothing is sent and the reason is
-- returned, so Studio and an unfinished setup are harmless. Roblox allows one a day per player and
-- sends only to players who opted in through its own prompt.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Notifier = {}

-- Returns true when Roblox accepted it, else false and why.
function Notifier.send(userId: number, kind: string): (boolean, string)
	local messageId = Config.Reminders.messages[kind]
	if messageId == nil or messageId == "" then
		return false, "no notification string for " .. kind
	end
	local gotKey, secret = pcall(function()
		return (HttpService :: any):GetSecret("ReminderApiKey")
	end)
	if not gotKey then
		return false, "no ReminderApiKey secret"
	end
	local body = HttpService:JSONEncode({
		source = { universe = "universes/" .. game.GameId },
		payload = { messageId = messageId, type = "MOMENT" },
	})
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = `https://apis.roblox.com/cloud/v2/users/{userId}/notifications`,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = secret },
			Body = body,
		})
	end)
	if not ok then
		return false, tostring(response)
	end
	if not response.Success then
		return false, `{response.StatusCode} {response.StatusMessage}`
	end
	return true, "sent"
end

return Notifier
