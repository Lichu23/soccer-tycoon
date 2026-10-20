--!strict
-- The Robux booth outside the door of the player's own plot (template folder Entrance, part
-- ShopBooth). Walking up to it offers "Open shop"; the prompt opens the same screen as the SHOP
-- button. The booth only opens a screen: what is bought and charged is decided by the server.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ShopUi = require(script.Parent.ShopUi)

local player = Players.LocalPlayer

local ACTIVATION_DISTANCE = 14

local ShopBooth = {}

local function ownBooth(): BasePart?
	local plots = Workspace:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			local entrance = plot:FindFirstChild("Entrance")
			local booth = if entrance then entrance:FindFirstChild("ShopBooth") else nil
			return if booth and booth:IsA("BasePart") then booth else nil
		end
	end
	return nil
end

local function attach(booth: BasePart)
	if booth:FindFirstChild("ShopPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open shop"
	prompt.ObjectText = "Robux shop"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = booth
	prompt.Triggered:Connect(function()
		ShopUi.openFromWorld()
	end)
end

function ShopBooth.init()
	-- The plot appears after the player claims it, so look again until the booth is there.
	task.spawn(function()
		while true do
			local booth = ownBooth()
			if booth then
				attach(booth)
			end
			task.wait(1)
		end
	end)
end

return ShopBooth
