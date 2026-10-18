--!strict
-- The Studio-only test shortcuts. The handler is registered only while running in Studio, so in a
-- published game the DevCommand remote does nothing.

local RunService = game:GetService("RunService")

local Actions = require(script.Parent.Actions)
local DevCommands = require(script.Parent.DevCommands)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)

local DevTools = {}

function DevTools.start()
	if not RunService:IsStudio() then
		return
	end
	Remotes.on("DevCommand", function(player: Player, ...: any)
		local command, amount = select(1, ...)
		local session = Session.get(player)
		if session == nil then
			return
		end
		if command == "openStairs" then
			-- Opens every stair gate (or closes them again) without granting any player.
			session.runtime.devOpenGates = not session.runtime.devOpenGates
			Actions.onChange(session, "dev", nil)
			print(
				string.format(
					"[DevTools] %s: stairs open = %s",
					player.Name,
					tostring(session.runtime.devOpenGates)
				)
			)
		elseif DevCommands.apply(session.data, command, amount) then
			session.runtime.nextMatchAt = 0
			Actions.onChange(session, "dev", nil)
			print(string.format("[DevTools] %s: %s %s", player.Name, command, tostring(amount)))
		end
	end)
end

return DevTools
