--!strict
-- The global top 10 of the four plaza leaderboards (shared/Leaderboards). Only this server code
-- writes a score, read from the saved profile; a client never sends one. Each board is an
-- OrderedDataStore keyed "Player_<UserId>" that only ever goes up. The stored top 10 is read every
-- few minutes and joined with the live scores of the players here, then published as JSON on
-- ReplicatedStorage.Leaderboards (one attribute per board) for client/Scoreboards to draw.
-- Studio follows Session: without the real store it shows the players in this server only.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Config = require(ReplicatedStorage.Shared.Config)
local Boards = require(ReplicatedStorage.Shared.Leaderboards)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Safe = require(script.Parent.Safe)
local Session = require(script.Parent.Session)

type Entry = Boards.Entry

local PUBLISH_SECONDS = 10 -- the live scores of the players here show this fast
local READ_SECONDS = 120 -- the stored top 10 of each board
local WRITE_SECONDS = 180 -- a player's improved scores (and once more when they leave)
local SHUTDOWN_WAIT_SECONDS = 10
local KEY_PREFIX = "Player_"

local LeaderboardService = {}

local stores: { [string]: OrderedDataStore } = {}
local stored: { [string]: { Entry } } = {}
local written: { [Player]: { [string]: number } } = {}
local names: { [number]: string } = {}
local pendingWrites = 0
local folder: Folder
local started = false

-- The score of a profile on a board (whole numbers: OrderedDataStore keeps integers).
local function score(boardId: string, data: ProfileSchema.Profile): number
	if boardId == "Juggles" then
		return data.gym.keepieBestStreak
	elseif boardId == "Robux" then
		return data.stats.robuxSpent
	elseif boardId == "Money" then
		return math.floor(data.stats.cashEarned)
	elseif boardId == "Seasons" then
		return data.season.number
	end
	return 0
end

local function budget(kind: Enum.DataStoreRequestType): number
	local ok, value = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, kind)
	return if ok then value else 0
end

-- Stores the scores of a session that went up since the last write. Yields.
local function write(player: Player, scores: { [string]: number })
	local last = written[player]
	if last == nil then
		last = {}
		written[player] = last
	end
	local key = KEY_PREFIX .. player.UserId
	for boardId, value in scores do
		local store = stores[boardId]
		if not store or value <= 0 or value <= (last[boardId] or 0) then
			continue
		end
		if budget(Enum.DataStoreRequestType.SetIncrementSortedAsync) < 1 then
			return -- tried again on the next round
		end
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old: any): any
				if type(old) == "number" and old >= value then
					return nil -- never lower a stored score
				end
				return value
			end)
		end)
		if ok then
			last[boardId] = value
		else
			warn("[Leaderboards] write failed for " .. boardId .. ": " .. tostring(err))
		end
	end
end

local function scoresOf(session: Session.Session): { [string]: number }
	local scores = {}
	for _, board in Boards.boards do
		scores[board.id] = score(board.id, session.data)
	end
	return scores
end

-- Fills in the display names of stored entries from people who are not here. Yields.
local function resolveNames(entries: { Entry })
	local missing = {}
	for _, entry in entries do
		if names[entry.userId] == nil then
			table.insert(missing, entry.userId)
		end
	end
	if #missing > 0 then
		local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, missing)
		if ok and type(infos) == "table" then
			for _, info in infos do
				names[info.Id] = info.DisplayName
			end
		end
	end
	for _, entry in entries do
		entry.name = names[entry.userId] or ""
	end
end

-- Reads the stored top 10 of every board. Yields.
local function readAll()
	for boardId, store in stores do
		if budget(Enum.DataStoreRequestType.GetSortedAsync) < 1 then
			return
		end
		local ok, result = pcall(function()
			return store:GetSortedAsync(false, Boards.SIZE):GetCurrentPage()
		end)
		if not ok then
			warn("[Leaderboards] read failed for " .. boardId .. ": " .. tostring(result))
			continue
		end
		local entries: { Entry } = {}
		for _, item: any in result do
			local digits = string.match(item.key, "^" .. KEY_PREFIX .. "(%d+)$")
			local userId = if digits then tonumber(digits) else nil
			if userId and type(item.value) == "number" then
				table.insert(entries, { userId = userId, name = "", value = item.value })
			end
		end
		resolveNames(entries)
		stored[boardId] = entries
	end
end

local function publish()
	local sessions = Session.all()
	for _, board in Boards.boards do
		local live: { Entry } = {}
		for _, session in sessions do
			local player = session.player
			names[player.UserId] = player.DisplayName
			table.insert(live, {
				userId = player.UserId,
				name = player.DisplayName,
				value = score(board.id, session.data),
			})
		end
		local merged = Boards.merge(stored[board.id] or {}, live, Boards.SIZE)
		folder:SetAttribute(board.id, HttpService:JSONEncode(merged))
	end
end

local function writeAll()
	for _, session in Session.all() do
		write(session.player, scoresOf(session))
	end
end

function LeaderboardService.start()
	assert(not started, "LeaderboardService.start called twice")
	started = true

	folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder.Parent = ReplicatedStorage

	local useStore = not RunService:IsStudio() or Config.Data.useRealStoreInStudio
	if useStore then
		local suffix = if RunService:IsStudio() then "_Studio" else "_v1"
		for _, board in Boards.boards do
			stores[board.id] = DataStoreService:GetOrderedDataStore("LB_" .. board.id .. suffix)
		end
	end

	-- The scores are taken while the profile is still valid; the write runs on its own.
	Session.onLeaving(function(session)
		local player, scores = session.player, scoresOf(session)
		pendingWrites += 1
		task.spawn(function()
			write(player, scores)
			written[player] = nil
			pendingWrites -= 1
		end)
	end)
	game:BindToClose(function()
		local deadline = os.clock() + SHUTDOWN_WAIT_SECONDS
		while pendingWrites > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)

	task.spawn(function()
		local nextRead, nextWrite = 0, os.clock() + WRITE_SECONDS
		while true do
			local ok, err = Safe.call(function()
				local now = os.clock()
				if now >= nextWrite then
					nextWrite = now + WRITE_SECONDS
					writeAll()
				end
				if now >= nextRead then
					nextRead = now + READ_SECONDS
					readAll()
				end
				publish()
			end)
			if not ok then
				warn("[Leaderboards] update failed:", err)
			end
			task.wait(PUBLISH_SECONDS)
		end
	end)
end

return LeaderboardService
