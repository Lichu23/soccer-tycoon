--!strict
-- The stats in the Roblox player list: Cash, TP and the best keepie-uppies streak ("Best Juggle").
-- They mirror the player attributes the server already publishes (Economy and Sync), so they only
-- show the server's numbers. Cash and TP are short text ("$1.84K"), the streak a plain number.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local Leaderstats = {}

local function watch(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Parent = folder
	local tp = Instance.new("StringValue")
	tp.Name = "TP"
	tp.Parent = folder
	local juggle = Instance.new("IntValue")
	juggle.Name = "Best Juggle"
	juggle.Parent = folder

	local function refresh()
		local cashValue, tpValue = player:GetAttribute("cash"), player:GetAttribute("tp")
		local best = player:GetAttribute("keepieBestStreak")
		cash.Value = NumberFormat.money(if type(cashValue) == "number" then cashValue else 0)
		tp.Value = NumberFormat.short(if type(tpValue) == "number" then tpValue else 0)
		juggle.Value = if type(best) == "number" then best else 0
	end
	refresh()
	for _, name in { "cash", "tp", "keepieBestStreak" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	folder.Parent = player
end

function Leaderstats.start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return Leaderstats
