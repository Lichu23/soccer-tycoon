--!strict
-- Server bootstrap: starts each module in an explicit order and fails visibly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Actions = require(script.Parent.Actions)
local Analytics = require(script.Parent.Analytics)
local BenchSeats = require(script.Parent.BenchSeats)
local BigChanceActions = require(script.Parent.BigChanceActions)
local DailyActions = require(script.Parent.DailyActions)
local DevTools = require(script.Parent.DevTools)
local LeaderboardService = require(script.Parent.LeaderboardService)
local Match = require(script.Parent.Match)
local Config = require(ReplicatedStorage.Shared.Config)
local Legends = require(ReplicatedStorage.Shared.Legends)
local Offline = require(script.Parent.Offline)
local Pads = require(script.Parent.Pads)
local PlayerListStats = require(script.Parent.PlayerListStats)
local Plots = require(script.Parent.Plots)
local ReminderService = require(script.Parent.ReminderService)
local Remotes = require(script.Parent.Remotes)
local Purchases = require(script.Parent.Purchases)
local RevealActions = require(script.Parent.RevealActions)
local Session = require(script.Parent.Session)
local Stadium = require(script.Parent.Stadium)
local StadiumName = require(script.Parent.StadiumName)
local Training = require(script.Parent.Training)
local TrainingActions = require(script.Parent.TrainingActions)
local UnlockNotices = require(script.Parent.UnlockNotices)
local Sync = require(script.Parent.Sync)

Remotes.init()
DevTools.start()
Session.init()
LeaderboardService.start()
PlayerListStats.start()
Pads.start()
Plots.init()
Match.start()
DailyActions.start()
BigChanceActions.start()
TrainingActions.start()
BenchSeats.start()
RevealActions.start()
Purchases.start()
ReminderService.start()

-- Whatever a player buys: tell their client, redraw their capsules and log the funnel.
Actions.onChange = function(session, what, id)
	Legends.record(session.data) -- Legend Trial goals are kept the moment they are reached
	Sync.all(session)
	if what == "stadium" then
		-- Before the refresh, so the refresh waits for the new pitch instead of building it at once.
		local first = Analytics.milestone(session, "first_stadium_upgrade")
		Stadium.upgraded(session, first)
	end
	Plots.refresh(session)
	if what == "case" then
		RevealActions.send(session, id) -- a case win: the reveal plays after the result is saved
	elseif what == "player" then
		-- The reveal plays first; the first match waits for it and brings its own camera (Match).
		RevealActions.send(session, id)
		Analytics.milestone(session, "first_purchase")
	elseif what == "level" and id then
		-- The client shows what the level gave (RewardCard).
		local owned = session.data.players[id]
		Analytics.milestone(session, "first_level") -- opens the other training stations for good
		if owned then
			Remotes.fireClient("Notice", session.player, {
				kind = "levelUp",
				playerId = id,
				level = owned.level,
				stars = owned.stars,
			})
		end
	elseif what == "store" then
		Analytics.milestone(session, "first_upgrade")
	end
	-- A pad that opened with this change gets its cinematic (the client waits for any reveal).
	UnlockNotices.check(session)
end

-- Everyone walks faster than the Roblox default (the plots are large).
local function setWalkSpeed(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = Config.Player.walkSpeed
	end
end
local function watchCharacters(player: Player)
	player.CharacterAdded:Connect(setWalkSpeed)
	if player.Character then
		task.spawn(setWalkSpeed, player.Character)
	end
end
Players.PlayerAdded:Connect(watchCharacters)
for _, player in Players:GetPlayers() do
	watchCharacters(player)
end

-- The time away refills the stamina and becomes cash when the plot is claimed (the client shows
-- the card then), counted up to the join: the wait in the plaza is not paid. Until then lastSeen
-- stays put (Session.awayHeld).
Plots.onClaimed = function(session)
	if not session.runtime.awayHeld then
		return
	end
	session.runtime.awayHeld = false
	local lastSeen = session.data.lastSeen
	Training.refillAway(session.data, if lastSeen > 0 then session.joinedAt - lastSeen else 0)
	local earned, secondsAway = Offline.apply(session.data, session.joinedAt)
	if earned > 0 then
		Sync.offline(session.player, earned, secondsAway)
		Analytics.event(session, "offline_earnings")
	end
end

Session.onLoaded(function(session)
	Legends.record(session.data)
	Sync.all(session)
	session.player:SetAttribute("profileLoaded", true)
	Analytics.event(session, "joined")
	-- Every player, returning ones too, picks a free plot by standing on its claim ring; their
	-- progress is rebuilt there. Only the first claim ever plays the tour.
end)

-- The client asks for its state once its listeners are ready (never sent before they exist).
Remotes.on("ClientReady", function(player: Player)
	local session = Session.await(player, 30)
	if session then
		Sync.all(session)
		RevealActions.send(session) -- reveals the player has not seen yet (a rejoin)
	end
end)

Remotes.on("UpgradeStadium", function(player: Player, ...: any)
	local tierSeen = select(1, ...)
	local session = Session.get(player)
	if session then
		Actions.upgradeStadium(session, tierSeen)
	end
end)

Remotes.on("StartNewSeason", function(player: Player, ...: any)
	local seasonSeen = select(1, ...)
	local session = Session.get(player)
	if session == nil then
		return
	end
	local result = Actions.startSeason(session, seasonSeen)
	if result then
		session.runtime.matchesInRow = 0
		session.runtime.nextMatchAt = 0
		Remotes.fireClient("SeasonStarted", player, result)
		Analytics.event(session, "new_season")
	end
end)

Remotes.on("SetCosmetic", function(player: Player, ...: any)
	local slot, id = select(1, ...)
	local session = Session.get(player)
	if session and type(slot) == "string" and type(id) == "string" then
		Actions.setCosmetic(session, slot, id)
	end
end)

Remotes.on("BuyCosmetic", function(player: Player, ...: any)
	local id = select(1, ...)
	local session = Session.get(player)
	if session == nil or type(id) ~= "string" then
		return
	end
	local ok, reason = Actions.buyCosmetic(session, id)
	if ok then
		Analytics.event(session, "cosmetic_cash")
	else
		-- The Locker room shows why (the same notice as a refused Robux purchase).
		Remotes.fireClient("Notice", player, { kind = "purchaseRefused", reason = reason })
	end
end)

Remotes.on("RenameStadium", function(player: Player, ...: any)
	local raw = select(1, ...)
	local session = Session.get(player)
	if session == nil or type(raw) ~= "string" then
		return
	end
	local text = StadiumName.clean(raw)
	local ok, reason = StadiumName.check(session.data, text)
	local filtered = if ok then StadiumName.filter(player, text) else nil
	session = Session.get(player) -- the filter yields; the player may have left
	if session == nil then
		return
	end
	if ok and filtered == nil then
		ok, reason = false, "unavailable"
	end
	if ok and filtered then
		session.runtime.stadiumName = filtered
		ok, reason = Actions.renameStadium(session, text, filtered)
		if not ok then
			session.runtime.stadiumName = nil
			Stadium.ensure(session) -- filters the saved name again
		end
	end
	if ok then
		Analytics.event(session, "stadium_renamed")
	else
		Remotes.fireClient("Notice", player, { kind = "renameRefused", reason = reason })
	end
end)

Remotes.on("SetNotifications", function(player: Player, ...: any)
	local on = select(1, ...)
	local session = Session.get(player)
	if session and type(on) == "boolean" then
		Actions.setNotifications(session, on)
	end
end)

Remotes.on("BuyStoreUpgrade", function(player: Player, ...: any)
	local id, levelSeen = select(1, ...)
	local session = Session.get(player)
	if session then
		Actions.buyStore(session, id, levelSeen)
	end
end)

print("soccer-tycoon server started")
