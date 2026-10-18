--!strict
-- The stadium upgrade cinematic (docs/PLAN.md, Step 7), about 6 seconds, only for the player who
-- bought it: controls lock, the camera moves over the court, the new pitch rises out of the ground
-- (the server builds it once the camera has arrived), and three short texts show what changed.
-- The first upgrade cannot be skipped, later ones can with a tap. It always ends by itself after a
-- time limit, so nobody is left stuck. Reduced motion: no camera shake and the new pitch just
-- appears. The server finishes the upgrade whatever happens here.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CourtPlan = require(ReplicatedStorage.Shared.CourtPlan)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local TRAVEL_SECONDS = 1.2
local SHAKE_START = 1.2
local SHAKE_SECONDS = 1.6
local SHAKE_SIZE = 0.45
local RISE_SECONDS = 1.1
local RISE_SPREAD = 0.7 -- the far parts start this much later than the middle ones
local SKIP_AFTER = 0.8 -- a skip tap is ignored right after the start (a leftover tap)

local StadiumCinematic = {}

local token = 0
local cleanup: (() -> ())? = nil

local function ownPlot(): Model?
	local slot = player:GetAttribute("plotSlot")
	local plots = Workspace:FindFirstChild("Plots")
	local plot = if type(slot) == "number" and plots
		then plots:FindFirstChild("Plot_" .. slot)
		else nil
	return if plot and plot:IsA("Model") then plot else nil
end

local function setControls(enabled: boolean)
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if module == nil then
		return
	end
	pcall(function()
		local controls = (require(module :: ModuleScript) :: any):GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

-- Lifts every part of a freshly built pitch out of the ground, the middle first.
local function rise(court: Instance, length: number, middle: Vector3)
	local reduced = GuiService.ReducedMotionEnabled
	if reduced then
		return
	end
	local info = TweenInfo.new(RISE_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for _, part in court:GetChildren() do
		if part:IsA("BasePart") then
			local final = part.CFrame
			local distance = (part.Position - middle).Magnitude
			part.CFrame = final - Vector3.new(0, part.Size.Y + 2, 0)
			local delay = math.clamp(distance / math.max(length, 1), 0, 1) * RISE_SPREAD
			task.delay(delay, function()
				if part.Parent then
					TweenService:Create(part, info, { CFrame = final }):Play()
				end
			end)
		end
	end
end

local function makeGui(): (ScreenGui, TextLabel, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "StadiumCinematic"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.2)
	title.Size = UDim2.fromOffset(640, 70)
	title.BackgroundTransparency = 1
	title.Font = Style.font
	title.TextSize = 54
	title.TextColor3 = Style.ui.gold
	title.Text = ""
	title.TextTransparency = 1
	title.Parent = gui
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 3
	titleStroke.Color = Style.ui.dark
	titleStroke.Transparency = 1
	titleStroke.Parent = title

	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -24)
	hint.Size = UDim2.fromOffset(300, 28)
	hint.BackgroundTransparency = 1
	hint.Font = Style.font
	hint.TextSize = 18
	hint.TextColor3 = Style.ui.text
	hint.Text = "Tap to skip"
	hint.Visible = false
	hint.Parent = gui
	local hintStroke = Instance.new("UIStroke")
	hintStroke.Thickness = 2
	hintStroke.Color = Style.ui.dark
	hintStroke.Parent = hint
	return gui, title, hint
end

local function showText(title: TextLabel, text: string, seconds: number, myToken: number)
	if token ~= myToken then
		return
	end
	title.Text = text
	local stroke = title:FindFirstChildOfClass("UIStroke")
	local fadeIn = TweenInfo.new(0.3)
	TweenService:Create(title, fadeIn, { TextTransparency = 0 }):Play()
	if stroke then
		TweenService:Create(stroke, fadeIn, { Transparency = 0 }):Play()
	end
	task.delay(seconds, function()
		if token ~= myToken or title.Parent == nil then
			return
		end
		local fadeOut = TweenInfo.new(0.3)
		TweenService:Create(title, fadeOut, { TextTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, fadeOut, { Transparency = 1 }):Play()
		end
	end)
end

local function play(info: any)
	local plot = ownPlot()
	local camera = Workspace.CurrentCamera
	local gate = plot and plot:FindFirstChild("Gate")
	if plot == nil or camera == nil or gate == nil or not gate:IsA("BasePart") then
		return
	end
	if cleanup then
		cleanup()
	end
	token += 1
	local myToken = token
	local startedAt = os.clock()
	local reduced = GuiService.ReducedMotionEnabled

	local tierDef = Config.StadiumTiers[info.tier] or Config.StadiumTiers[1]
	local length, width = tierDef.courtLength, tierDef.courtWidth
	local center = CourtPlan.CENTER_Z
	local function inPlot(x: number, y: number, z: number): Vector3
		return (gate.CFrame * CFrame.new(x, y - 1, z)).Position
	end
	local target = CFrame.lookAt(
		inPlot(0, 18 + length * 0.3, center - width / 2 - length * 0.55),
		inPlot(0, 4, center + 4)
	)

	local gui, title, hint = makeGui()
	hint.Visible = info.canSkip == true
	setControls(false)
	camera.CameraType = Enum.CameraType.Scriptable
	if reduced then
		camera.CFrame = target
	else
		TweenService:Create(
			camera,
			TweenInfo.new(TRAVEL_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ CFrame = target }
		):Play()
	end

	-- The new pitch is built by the server a moment later and rises out of the ground.
	local added = plot.ChildAdded:Connect(function(child)
		if child.Name == "Court" then
			rise(child, length, inPlot(0, 1, center))
		end
	end)

	-- Shake and dust while the pitch changes.
	local shake: RBXScriptConnection? = nil
	local dust: Part? = nil
	if not reduced then
		task.delay(SHAKE_START, function()
			if token ~= myToken then
				return
			end
			local shakeEnds = os.clock() + SHAKE_SECONDS
			shake = RunService.RenderStepped:Connect(function()
				if os.clock() > shakeEnds then
					return
				end
				local random = Random.new()
				camera.CFrame = target
					* CFrame.new(
						(random:NextNumber() - 0.5) * SHAKE_SIZE,
						(random:NextNumber() - 0.5) * SHAKE_SIZE,
						0
					)
			end)
			local puff = Instance.new("Part")
			puff.Anchored = true
			puff.CanCollide = false
			puff.CanQuery = false
			puff.CanTouch = false
			puff.Transparency = 1
			puff.Size = Vector3.new(length, 1, width)
			puff.Position = inPlot(0, 1, center)
			puff.Parent = Workspace
			local emitter = Instance.new("ParticleEmitter")
			emitter.Rate = 0
			emitter.Lifetime = NumberRange.new(1.2, 2)
			emitter.Speed = NumberRange.new(3, 8)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Size = NumberSequence.new(4, 9)
			emitter.Transparency = NumberSequence.new(0.5, 1)
			emitter.Color = ColorSequence.new(Color3.fromRGB(200, 190, 170))
			emitter.Shape = Enum.ParticleEmitterShape.Box
			emitter.Parent = puff
			emitter:Emit(60)
			dust = puff
			task.delay(2.5, function()
				puff:Destroy()
			end)
		end)
	end

	local function finish()
		if token ~= myToken then
			return
		end
		cleanup = nil
		token += 1 -- stops every timer of this run
		added:Disconnect()
		if shake then
			shake:Disconnect()
		end
		if dust then
			dust:Destroy()
		end
		gui:Destroy()
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		setControls(true)
	end
	cleanup = finish

	-- The texts: what happened, how the field grew, the free boost.
	local boostMinutes = math.floor((info.boostSeconds or Config.Boost.stadiumSeconds) / 60)
	task.delay(1.8, showText, title, "STADIUM UPGRADED", 1.3, myToken)
	task.delay(
		3.3,
		showText,
		title,
		"Field " .. info.fieldFrom .. " to " .. info.fieldTo,
		1.3,
		myToken
	)
	task.delay(
		4.8,
		showText,
		title,
		"x" .. (info.boostMultiplier or 2) .. " for " .. boostMinutes .. " minutes",
		1.2,
		myToken
	)

	-- It ends after its time, after the hard limit at the latest, or on a tap when it can be skipped.
	task.delay(info.seconds or Config.Cinematic.seconds, finish)
	task.delay(info.maxSeconds or Config.Cinematic.maxSeconds, finish)
	if info.canSkip == true then
		local connection: RBXScriptConnection
		connection = UserInputService.InputBegan:Connect(function(input)
			local tap = input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.Keyboard
			if tap and os.clock() - startedAt > SKIP_AFTER then
				connection:Disconnect()
				finish()
			end
		end)
		task.delay(info.maxSeconds or Config.Cinematic.maxSeconds, function()
			connection:Disconnect()
		end)
	end
	player.CharacterAdded:Once(finish) -- a respawn ends it too
end

function StadiumCinematic.init()
	Net.on("StadiumUpgraded", function(info: any)
		if type(info) == "table" and type(info.tier) == "number" then
			play(info)
		end
	end)
end

return StadiumCinematic
