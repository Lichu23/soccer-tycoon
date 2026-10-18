--!strict
-- Client side of the remotes. Every wait is bounded, so a missing remote is an error and not a
-- silent hang (docs/PLAN.md, Step 5).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSpec = require(ReplicatedStorage.Shared.RemoteSpec)

local WAIT_SECONDS = 15

local cache: { [string]: RemoteEvent } = {}

local Net = {}

local function remote(name: string): RemoteEvent
	local cached = cache[name]
	if cached then
		return cached
	end
	assert(RemoteSpec.remotes[name], "unknown remote " .. name)
	local folder = ReplicatedStorage:WaitForChild("Remotes", WAIT_SECONDS)
	assert(folder, "the Remotes folder never arrived")
	local event = folder:WaitForChild(name, WAIT_SECONDS)
	assert(event and event:IsA("RemoteEvent"), "remote " .. name .. " never arrived")
	cache[name] = event
	return event
end

-- Listens to a server-to-client event.
function Net.on(name: string, handler: (...any) -> ()): RBXScriptConnection
	local def = RemoteSpec.remotes[name]
	assert(def and def.direction == "toClient", "not a server-to-client remote: " .. name)
	return remote(name).OnClientEvent:Connect(handler)
end

-- Sends a client-to-server request. The server validates and may ignore it.
function Net.fire(name: string, ...: any)
	local def = RemoteSpec.remotes[name]
	assert(def and def.direction == "toServer", "not a client-to-server remote: " .. name)
	remote(name):FireServer(...)
end

return Net
