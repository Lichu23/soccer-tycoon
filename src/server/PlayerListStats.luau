--!strict
-- The columns of the Roblox player list (Tab): the cash in hand, the season and the best
-- keepie-uppies streak. They copy the player attributes the server already publishes for the HUD
-- (Economy.publish, Sync.scalars, TrainingActions), so every change shows without new calls.
-- Display only: nothing reads these values back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local PlayerListStats = {}

local started = false

local function add(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	-- Text, so it reads like the HUD ($1.2M) instead of a long row of digits.
	local money = Instance.new("StringValue")
	money.Name = "Money"
	local seasons = Instance.new("IntValue")
	seasons.Name = "Seasons"
	local juggles = Instance.new("IntValue")
	juggles.Name = "Juggles"

	local function refresh()
		local cash = player:GetAttribute("cash")
		local season = player:GetAttribute("seasonNumber")
		local best = player:GetAttribute("keepieBestStreak")
		money.Value = NumberFormat.money(if type(cash) == "number" then cash else 0)
		seasons.Value = if type(season) == "number" then season else 0
		juggles.Value = if type(best) == "number" then best else 0
	end
	refresh()
	player:GetAttributeChangedSignal("cash"):Connect(refresh)
	player:GetAttributeChangedSignal("seasonNumber"):Connect(refresh)
	player:GetAttributeChangedSignal("keepieBestStreak"):Connect(refresh)

	money.Parent = folder
	seasons.Parent = folder
	juggles.Parent = folder
	folder.Parent = player
end

function PlayerListStats.start()
	assert(not started, "PlayerListStats.start called twice")
	started = true
	Players.PlayerAdded:Connect(add)
	for _, player in Players:GetPlayers() do
		add(player)
	end
end

return PlayerListStats
