--!strict
-- One in-memory session per player, backed by ProfileStore (docs/PLAN.md, Step 6).
-- ProfileStore owns the session lock, retries and the shutdown save. This module adds the
-- load rules (retry, then kick, never play on a blank profile), migration and reconcile,
-- validation before forced saves, and a save that waits until it is really stored.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileStore = require(script.Parent.vendor.ProfileStore)
local Config = require(ReplicatedStorage.Shared.Config)

export type Session = {
	player: Player,
	profile: any, -- the ProfileStore profile
	data: ProfileSchema.Profile, -- the same table as profile.Data
	loadedAt: number,
}

local KICK_LOAD_FAILED =
	"Couldn't load your save. Please rejoin in a minute. Your progress is safe."
local KICK_TAKEN = "Your save was opened on another server. Please rejoin."

local sessions: { [Player]: Session } = {}
local loadedCallbacks: { (session: Session) -> () } = {}
local store: any
local started = false

local Session = {}

local function startOne(player: Player): Session?
	local began = os.clock()
	local key = "Player_" .. player.UserId

	-- Retry quietly while the profile is locked by another server (a quick server hop), then
	-- give up. The lock is never stolen: that could erase progress from the other server.
	local profile = store:StartSessionAsync(key, {
		Cancel = function()
			return player.Parent ~= Players or os.clock() - began > Config.Data.loadTimeoutSeconds
		end,
	})
	if profile == nil then
		return nil
	end

	profile:AddUserId(player.UserId) -- lets Roblox data deletion requests find this profile

	local migrated, reason = ProfileSchema.migrate(profile.Data)
	if not migrated then
		warn(
			string.format(
				"[Session] %s (%d) cannot be loaded: %s",
				player.Name,
				player.UserId,
				reason or "?"
			)
		)
		profile:EndSession()
		return nil
	end
	profile:Reconcile()
	ProfileSchema.pruneReceipts(profile.Data, os.time())

	if player.Parent ~= Players then
		profile:EndSession()
		return nil
	end

	-- A save is never blocked here, but a bad profile is logged loudly so it gets noticed.
	profile.OnSave:Connect(function()
		local valid, problem = ProfileSchema.validate(profile.Data)
		if not valid then
			warn(
				string.format(
					"[Session] %s is saving an INVALID profile: %s",
					player.Name,
					problem or "?"
				)
			)
		end
	end)

	-- Another server took the profile: stop this player at once so two servers never change it.
	profile.OnSessionEnd:Connect(function()
		if sessions[player] ~= nil then
			sessions[player] = nil
			if player.Parent == Players then
				player:Kick(KICK_TAKEN)
			end
		end
	end)

	local session: Session = {
		player = player,
		profile = profile,
		data = profile.Data,
		loadedAt = os.clock(),
	}
	sessions[player] = session
	return session
end

local function onPlayerAdded(player: Player)
	local session = startOne(player)
	if session == nil then
		if player.Parent == Players then
			warn(
				string.format(
					"[Session] could not load %s (%d), kicking",
					player.Name,
					player.UserId
				)
			)
			player:Kick(KICK_LOAD_FAILED)
		end
		return
	end
	for _, callback in loadedCallbacks do
		task.spawn(callback, session)
	end
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	sessions[player] = nil
	session.data.lastSeen = os.time()
	session.profile:EndSession() -- saves one last time and releases the lock
end

-- Call once at startup, before any player has joined.
function Session.init()
	assert(not started, "Session.init called twice")
	started = true

	ProfileStore.SetConstant("AUTO_SAVE_PERIOD", Config.Data.autoSaveSeconds)

	local inStudio = RunService:IsStudio()
	local storeName = if inStudio then Config.Data.studioStoreName else Config.Data.storeName
	local real = ProfileStore.New(storeName, ProfileSchema.newProfile())
	-- Studio runs on the in-memory Mock store unless the real Studio store is asked for.
	store = if inStudio and not Config.Data.useRealStoreInStudio then real.Mock else real

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- The loaded session of a player, or nil while loading or after leaving.
function Session.get(player: Player): Session?
	return sessions[player]
end

function Session.all(): { Session }
	local list = {}
	for _, session in sessions do
		table.insert(list, session)
	end
	return list
end

-- Runs `callback` for every session that finishes loading from now on.
function Session.onLoaded(callback: (session: Session) -> ())
	table.insert(loadedCallbacks, callback)
end

-- Yields until the player's session is loaded. Returns nil on timeout or when they leave.
function Session.await(player: Player, timeoutSeconds: number): Session?
	local deadline = os.clock() + timeoutSeconds
	while sessions[player] == nil do
		if player.Parent ~= Players or os.clock() > deadline then
			return nil
		end
		task.wait(0.1)
	end
	return sessions[player]
end

-- Saves now in the background (ProfileStore also autosaves). False when the profile is
-- invalid or not active; an invalid profile is never force saved.
function Session.save(player: Player): boolean
	local session = sessions[player]
	if session == nil or not session.profile:IsActive() then
		return false
	end
	local valid, problem = ProfileSchema.validate(session.data)
	if not valid then
		warn(string.format("[Session] refusing to save %s: %s", player.Name, problem or "?"))
		return false
	end
	session.data.lastSeen = os.time()
	session.profile:Save()
	return true
end

-- Saves and yields until `isStored` is true for the last data that really reached the
-- DataStore, or the time runs out. Used for purchases: the receipt is confirmed to Roblox
-- only after this returns true, for example
--   Session.saveAndConfirm(player, function(saved) return saved.receipts[id] ~= nil end)
function Session.saveAndConfirm(
	player: Player,
	isStored: (saved: { [string]: any }) -> boolean,
	timeoutSeconds: number?
): boolean
	if not Session.save(player) then
		return false
	end
	local session = sessions[player]
	local deadline = os.clock() + (timeoutSeconds or Config.Data.saveConfirmSeconds)
	while os.clock() < deadline do
		if session == nil or not session.profile:IsActive() then
			-- The session ended: the last save on release may still have stored it.
			local last = session and session.profile.LastSavedData
			return type(last) == "table" and isStored(last)
		end
		local last = session.profile.LastSavedData
		if type(last) == "table" and isStored(last) then
			return true
		end
		task.wait(0.1)
	end
	return false
end

return Session
