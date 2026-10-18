--!strict
-- Builds every RemoteEvent from RemoteSpec and guards the server side: a rate limit, payload
-- validation and an optional cooldown run before any handler (docs/PLAN.md, Step 5).
-- A bad request is dropped with no effect and logged (the first few, then every 100th).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RateLimiter = require(script.Parent.RateLimiter)
local RemoteSpec = require(ReplicatedStorage.Shared.RemoteSpec)
local Validate = require(ReplicatedStorage.Shared.Validate)

-- The return values are ignored; the pack lets pcall's error message type-check.
type Handler = (player: Player, ...any) -> ...any

local BAD_REQUEST_COST = 3 -- tokens taken from the bucket for each rejected request
local LOG_FIRST = 5
local LOG_EVERY = 100

local events: { [string]: RemoteEvent } = {}
local buckets: { [string]: RateLimiter.Bucket } = {}
local cooldowns: { [string]: RateLimiter.Cooldown } = {}
local rejectCounts: { [string]: number } = {}
local started = false

local Remotes = {}

local function reject(player: Player, name: string, reason: string)
	local key = string.format("%d|%s", player.UserId, name)
	local count = (rejectCounts[key] or 0) + 1
	rejectCounts[key] = count
	if count <= LOG_FIRST or count % LOG_EVERY == 0 then
		warn(
			string.format(
				"[Remotes] rejected %s from %s (%d): %s (x%d)",
				name,
				player.Name,
				player.UserId,
				reason,
				count
			)
		)
	end
end

-- Creates the RemoteEvents. Call once, before any player joins.
function Remotes.init()
	assert(not started, "Remotes.init called twice")
	started = true

	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for name, def in RemoteSpec.remotes do
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
		events[name] = event
		if def.direction == "toServer" then
			buckets[name] = RateLimiter.bucket(def.ratePerSecond or 1, def.burst or 1, os.clock)
			if def.cooldownSeconds then
				cooldowns[name] = RateLimiter.cooldown(def.cooldownSeconds, os.clock)
			end
		end
	end
	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		for _, bucket in buckets do
			bucket:forget(player.UserId)
		end
		for _, cooldown in cooldowns do
			cooldown:forget(player.UserId)
		end
		for key in rejectCounts do
			if string.match(key, "^" .. player.UserId .. "|") then
				rejectCounts[key] = nil
			end
		end
	end)
end

-- Registers the one handler for a client-to-server remote.
function Remotes.on(name: string, handler: Handler)
	local def = RemoteSpec.remotes[name]
	assert(def and def.direction == "toServer", "unknown client-to-server remote: " .. name)
	local event = events[name]
	assert(event, "Remotes.init has not run")
	local bucket = buckets[name]
	assert(bucket, "no rate limit bucket for " .. name)

	event.OnServerEvent:Connect(function(player: Player, ...: any)
		local count = select("#", ...)
		local args = { ... }

		if not bucket:allow(player.UserId) then
			return
		end
		local ok, reason = Validate.args(def.args, args, count)
		if not ok then
			bucket:penalize(player.UserId, BAD_REQUEST_COST)
			reject(player, name, reason or "invalid payload")
			return
		end
		local cooldown = cooldowns[name]
		if cooldown and not cooldown:tryUse(player.UserId) then
			return
		end

		local success, err = pcall(handler, player, table.unpack(args, 1, count))
		if not success then
			warn(string.format("[Remotes] handler for %s failed: %s", name, tostring(err)))
		end
	end)
end

function Remotes.fireClient(name: string, player: Player, ...: any)
	local def = RemoteSpec.remotes[name]
	assert(def and def.direction == "toClient", "unknown server-to-client remote: " .. name)
	local event = events[name]
	assert(event, "Remotes.init has not run")
	event:FireClient(player, ...)
end

function Remotes.fireAllClients(name: string, ...: any)
	local def = RemoteSpec.remotes[name]
	assert(def and def.direction == "toClient", "unknown server-to-client remote: " .. name)
	local event = events[name]
	assert(event, "Remotes.init has not run")
	event:FireAllClients(...)
end

return Remotes
