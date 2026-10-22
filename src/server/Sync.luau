--!strict
-- Sends a player's state to their client (docs/PLAN.md, Step 5): single values travel as player
-- attributes (no remote), lists as one snapshot. The server never reads these back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Boosts = require(script.Parent.Boosts)
local Daily = require(script.Parent.Daily)
local Economy = require(script.Parent.Economy)
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local ShopRules = require(script.Parent.ShopRules)
local TileBadges = require(ReplicatedStorage.Shared.TileBadges)

local Sync = {}

-- Cash, training points, tier, the field flag and the boost end time.
function Sync.scalars(session: Session.Session)
	local player, data = session.player, session.data
	Economy.publish(player, data)
	player:SetAttribute("stadiumTier", data.stadiumTier)
	player:SetAttribute("stadiumName", session.runtime.stadiumName or "") -- filtered, safe to show
	player:SetAttribute("seasonNumber", data.season.number)
	player:SetAttribute("fieldStarted", data.fieldStarted)
	player:SetAttribute("notificationsOn", data.flags.notificationsOn)
	-- The "1" on the Case, Kick and Shop buttons: 0 = not tapped yet, 1 = tapped.
	for _, id in TileBadges.ids do
		player:SetAttribute("tile_" .. id, if TileBadges.seen(data, id) then 1 else 0)
	end
	-- The badge shows the multiplier of all running boosts and the time until the next one ends.
	local left = Boosts.nextEnd(data)
	player:SetAttribute("boostEndsAt", if left > 0 then Workspace:GetServerTimeNow() + left else 0)
	player:SetAttribute("boostMultiplier", Formulas.boostMultiplier(Boosts.active(data)))
	-- The x2 TP boost has its own badge.
	local tpLeft = data.boosts.tpBoostLeft
	player:SetAttribute(
		"tpBoostEndsAt",
		if tpLeft > 0 then Workspace:GetServerTimeNow() + tpLeft else 0
	)
	player:SetAttribute("trainingUnlocked", Progress.trainingUnlocked(data))
	player:SetAttribute("staminaMax", Config.Training.staminaSeconds)
	player:SetAttribute("keepieBestStreak", data.gym.keepieBestStreak)
	player:SetAttribute("freekickBestStreak", data.gym.freekickBestStreak)
	-- The shop: whether cases are on offer yet, the banked boost matches and this visit's total.
	player:SetAttribute("casesOpen", ShopRules.casesOpen(data))
	player:SetAttribute("bankedMatches", data.boosts.bankedMatches)
	player:SetAttribute("sessionCases", session.runtime.sessionCases)
	player:SetAttribute("sessionRobux", session.runtime.sessionRobux)
	-- The daily icons: when each one is ready (os.time(), 0 = now), and whether they exist yet.
	player:SetAttribute("dailyUnlocked", Daily.unlocked(data))
	player:SetAttribute("caseReadyAt", Daily.caseReadyAt(data))
	player:SetAttribute("penaltyReadyAt", Daily.penaltyReadyAt(data, os.time()))
	player:SetAttribute("penaltyKicksLeft", Daily.kicksLeft(data, os.time()))
end

-- The progress subset the HUD, the pads and the goal row need.
function Sync.snapshot(session: Session.Session)
	local data = session.data
	local players = {}
	for id, owned in data.players do
		players[id] = { level = owned.level, stars = owned.stars }
	end
	local trials = {}
	for legendId, goals in data.trials do
		trials[legendId] = table.clone(goals)
	end
	Remotes.fireClient("Snapshot", session.player, {
		cosmetics = {
			owned = table.clone(data.cosmetics.owned),
			chosen = table.clone(data.cosmetics.chosen),
		},
		trials = trials,
		cash = data.cash,
		tp = data.tp,
		stadiumTier = data.stadiumTier,
		storeLevels = {
			matchSpeed = data.storeLevels.matchSpeed,
			hatTrick = data.storeLevels.hatTrick,
			offline = data.storeLevels.offline,
		},
		fieldStarted = data.fieldStarted,
		players = players,
		flags = { milestones = { first_match = data.flags.milestones["first_match"] } },
	})
end

-- Tells the client how much it earned while away (the HUD shows it once).
function Sync.offline(player: Player, earned: number, secondsAway: number)
	player:SetAttribute("offlineSeconds", secondsAway)
	player:SetAttribute("offlineEarned", earned)
end

function Sync.all(session: Session.Session)
	Sync.scalars(session)
	Sync.snapshot(session)
end

return Sync
