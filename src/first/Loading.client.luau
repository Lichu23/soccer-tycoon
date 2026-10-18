--!strict
-- The loading screen (docs/PLAN.md, Step 6). It covers the game until the server has loaded the
-- player's profile, so nobody acts on a stadium that is not there yet. It gives up waiting after
-- a while so a problem never leaves a black screen forever (a failed load kicks the player).

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local MAX_WAIT_SECONDS = 45

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = playerGui

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(20, 24, 35)
background.BorderSizePixel = 0
background.Parent = gui

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.Size = UDim2.fromOffset(420, 50)
label.BackgroundTransparency = 1
label.Text = "Loading your stadium..."
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.Font = Enum.Font.GothamBold
label.TextSize = 28
label.Parent = background

local started = os.clock()
while not game:IsLoaded() or player:GetAttribute("profileLoaded") ~= true do
	if os.clock() - started > MAX_WAIT_SECONDS then
		break
	end
	task.wait(0.1)
end

local info = TweenInfo.new(0.5)
TweenService:Create(background, info, { BackgroundTransparency = 1 }):Play()
TweenService:Create(label, info, { TextTransparency = 1 }):Play()
task.wait(0.6)
gui:Destroy()
