--!strict
-- Server bootstrap: starts each module in an explicit order and fails visibly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Actions = require(script.Parent.Actions)
local Analytics = require(script.Parent.Analytics)
local DailyActions = require(script.Parent.DailyActions)
local DevTools = require(script.Parent.DevTools)
local Match = require(script.Parent.Match)
local Config = require(ReplicatedStorage.Shared.Config)
local Legends = require(ReplicatedStorage.Shared.Legends)
local Offline = require(script.Parent.Offline)
local Pads = require(script.Parent.Pads)
local Plots = require(script.Parent.Plots)
local Remotes = require(script.Parent.Remotes)
local Purchases = require(script.Parent.Purchases)
local RevealActions = require(script.Parent.RevealActions)
local Session = require(script.Parent.Session)
local Stadium = require(script.Parent.Stadium)
local Training = require(script.Parent.Training)
local TrainingActions = require(script.Parent.TrainingActions)
local Sync = require(script.Parent.Sync)

Remotes.init()
DevTools.start()
Session.init()
Pads.start()
Plots.init()
Match.start()
DailyActions.start()
TrainingActions.start()
RevealActions.start()
Purchases.start()

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
		RevealActions.send(session, id)
		Analytics.milestone(session, "first_purchase")
	elseif what == "store" then
		Analytics.milestone(session, "first_upgrade")
	end
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

Session.onLoaded(function(session)
	-- Time away becomes cash first, so the first sync already has it. The client shows the message.
	local now = os.time()
	local lastSeen = session.data.lastSeen
	Training.refillAway(session.data, if lastSeen > 0 then now - lastSeen else 0)
	local earned, secondsAway = Offline.apply(session.data, now)
	if earned > 0 then
		Sync.offline(session.player, earned, secondsAway)
		Analytics.event(session, "offline_earnings")
	end
	Legends.record(session.data)
	Sync.all(session)
	session.player:SetAttribute("profileLoaded", true)
	Analytics.event(session, "joined")
	-- A returning player gets a plot at once, without the claim ring.
	if session.data.flags.hasClaimedPlot then
		Plots.assign(session, nil)
	end
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

Remotes.on("BuyStoreUpgrade", function(player: Player, ...: any)
	local id, levelSeen = select(1, ...)
	local session = Session.get(player)
	if session then
		Actions.buyStore(session, id, levelSeen)
	end
end)

print("soccer-tycoon server started")
