--!strict
-- Server bootstrap: starts each module in an explicit order and fails visibly.

local Actions = require(script.Parent.Actions)
local Analytics = require(script.Parent.Analytics)
local DevTools = require(script.Parent.DevTools)
local Match = require(script.Parent.Match)
local Offline = require(script.Parent.Offline)
local Pads = require(script.Parent.Pads)
local Plots = require(script.Parent.Plots)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Sync = require(script.Parent.Sync)

Remotes.init()
DevTools.start()
Session.init()
Pads.start()
Plots.init()
Match.start()

-- Whatever a player buys: tell their client, redraw their capsules and log the funnel.
Actions.onChange = function(session, what, _id)
	Sync.all(session)
	Plots.refresh(session)
	if what == "player" then
		Analytics.milestone(session, "first_purchase")
	elseif what == "store" then
		Analytics.milestone(session, "first_upgrade")
	elseif what == "stadium" then
		Analytics.milestone(session, "first_stadium_upgrade")
	end
end

Session.onLoaded(function(session)
	-- Time away becomes cash first, so the first sync already has it. The client shows the message.
	local earned, secondsAway = Offline.apply(session.data, os.time())
	if earned > 0 then
		Sync.offline(session.player, earned, secondsAway)
		Analytics.event(session, "offline_earnings")
	end
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
	end
end)

Remotes.on("UpgradeStadium", function(player: Player, ...: any)
	local tierSeen = select(1, ...)
	local session = Session.get(player)
	if session then
		Actions.upgradeStadium(session, tierSeen)
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
