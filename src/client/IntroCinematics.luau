--!strict
-- The two intro cinematics of a new player (the server sends a Notice, once per profile):
--   * "plotTour": the first time the plot is claimed, a 5 second tour of the building, the stadium
--     and the training area (three short shots, each with a one-word caption).
--   * "firstMatch": when the first player is bought, the camera shows the pitch until the first match
--     ends (the result and the payout are held for a moment), with a hard time limit.
--   * "unlock": a pad opened (shared/Unlocks): 4 seconds over the pad with its name and what it does.
--     They queue and wait until no reveal, card or other cinematic is on screen.
-- Both can be skipped with a tap or the Skip button, lock the controls while they play, end when the
-- character respawns and always give the camera back. Reduced motion: still shots, no drift.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CourtPlan = require(ReplicatedStorage.Shared.CourtPlan)
local Net = require(script.Parent.Net)
local Sounds = require(script.Parent.Sounds)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)
local Unlocks = require(ReplicatedStorage.Shared.Unlocks)

local player = Players.LocalPlayer

local SKIP_AFTER = 0.8 -- a tap right after the start is ignored (a leftover tap)
local BLEND_SECONDS = 1.2 -- the camera glides from where it was to the first match shot
local PLOT_WAIT_SECONDS = 4 -- how long the plot may take to appear on this client
-- The unlock cinematic: the camera glides in, then closes from far/high to near/low over the pad.
local UNLOCK_SECONDS = 4
local UNLOCK_BLEND = 0.8
local UNLOCK_FAR, UNLOCK_NEAR = 26, 16
local UNLOCK_HIGH, UNLOCK_LOW = 14, 8
local UNLOCK_CALM_SECONDS = 1 -- the screen must be free this long before an unlock plays
local UNLOCK_SIDES = 16 -- the directions around a pad tried for a clear view of it
local SEE_THROUGH = 0.5 -- parts at least this transparent (glass) do not block the camera
local BUSY_GUIS = { "Reveal", "Cases", "StadiumCinematic", "RewardCard" }

type Shot = {
	caption: string,
	seconds: number,
	from: Vector3, -- camera position at the start and at the end, in plot space (the gate is the origin)
	to: Vector3,
	lookFrom: Vector3, -- the point it looks at, at the start and at the end
	lookTo: Vector3,
}

-- Plot space: x to the right of the gate, y up, z towards the stadium. The building stands at
-- x 51..129 (its glass front faces the gate side), the training pads at x -78, the court at z 217..253.
local TOUR: { Shot } = {
	{
		caption = "YOUR BUILDING",
		seconds = 1.7,
		from = Vector3.new(-75, 26, 35),
		to = Vector3.new(-38, 28, 70),
		lookFrom = Vector3.new(51, 28, 90),
		lookTo = Vector3.new(51, 30, 95),
	},
	{
		caption = "YOUR STADIUM",
		seconds = 1.7,
		from = Vector3.new(-40, 28, 160),
		to = Vector3.new(0, 20, 195),
		lookFrom = Vector3.new(0, 2, 238),
		lookTo = Vector3.new(0, 2, 236),
	},
	{
		caption = "TRAINING",
		seconds = 1.6,
		from = Vector3.new(-30, 14, 50),
		to = Vector3.new(-42, 12, 72),
		lookFrom = Vector3.new(-78, 1, 85),
		lookTo = Vector3.new(-78, 1, 115),
	},
}

local IntroCinematics = {}

local token = 0
local cleanup: (() -> ())? = nil
local lastResultAt: number? = nil -- os.clock() of the newest result of the player's own match

local function ownGate(): BasePart?
	local deadline = os.clock() + PLOT_WAIT_SECONDS
	while os.clock() < deadline do
		local slot = player:GetAttribute("plotSlot")
		local plots = Workspace:FindFirstChild("Plots")
		local plot = if type(slot) == "number" and plots
			then plots:FindFirstChild("Plot_" .. slot)
			else nil
		local gate = plot and plot:FindFirstChild("Gate")
		if gate and gate:IsA("BasePart") then
			return gate
		end
		task.wait(0.1)
	end
	return nil
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

local function makeGui(onSkip: () -> (), low: boolean): (ScreenGui, TextLabel, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "IntroCinematic"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Low captions sit just above Skip, so the pad in the middle of the shot and its label stay clear.
	local titleY = if low then UDim2.new(0.5, 0, 1, -150) else UDim2.fromScale(0.5, 0.2)
	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = titleY
	title.Size = UDim2.fromOffset(560, 64)
	title.BackgroundTransparency = 1
	title.Font = Style.font
	title.TextSize = 46
	title.TextColor3 = Style.ui.gold
	title.Text = ""
	title.TextTransparency = 1
	title.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Style.ui.dark
	stroke.Transparency = 1
	stroke.Parent = title

	-- One line under the title on what the thing shown does (the unlock cinematics).
	local detail = Instance.new("TextLabel")
	detail.Name = "Detail"
	detail.AnchorPoint = Vector2.new(0.5, 0)
	detail.Position = titleY + UDim2.fromOffset(0, 36)
	detail.Size = UDim2.new(0.9, 0, 0, 32)
	detail.BackgroundTransparency = 1
	detail.Font = Style.font
	detail.TextSize = 24
	detail.TextWrapped = true
	detail.TextColor3 = Style.ui.text
	detail.Text = ""
	detail.TextTransparency = 1
	detail.Parent = gui
	local detailStroke = Instance.new("UIStroke")
	detailStroke.Thickness = 2
	detailStroke.Color = Style.ui.dark
	detailStroke.Transparency = 1
	detailStroke.Parent = detail

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(0.5, 1)
	skip.Position = UDim2.new(0.5, 0, 1, -24)
	skip.Size = UDim2.fromOffset(150, 40)
	skip.BackgroundColor3 = Style.ui.dark
	skip.BackgroundTransparency = 0.25
	skip.Font = Style.font
	skip.TextSize = 18
	skip.TextColor3 = Style.ui.text
	skip.Text = "Skip"
	skip.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = skip
	skip.Activated:Connect(onSkip)
	return gui, title, detail
end

-- Fades a label (and its outline) in, then out again after `seconds`.
local function fadeLabel(label: TextLabel, text: string, seconds: number, myToken: number)
	if token ~= myToken or not label:IsDescendantOf(game) then
		return
	end
	label.Text = text
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local fade = TweenInfo.new(0.25)
	TweenService:Create(label, fade, { TextTransparency = 0 }):Play()
	if stroke then
		TweenService:Create(stroke, fade, { Transparency = 0 }):Play()
	end
	task.delay(math.max(seconds - 0.25, 0.1), function()
		if token ~= myToken or not label:IsDescendantOf(game) then
			return
		end
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		end
	end)
end

type Caption = { at: number, text: string, seconds: number, detail: string? }

local function showCaption(title: TextLabel, detail: TextLabel, caption: Caption, myToken: number)
	fadeLabel(title, caption.text, caption.seconds, myToken)
	if caption.detail then
		fadeLabel(detail, caption.detail, caption.seconds, myToken)
	end
end

-- Runs one cinematic. `update(elapsed)` gives the camera for that moment and whether it is over;
-- `captions` are shown at their time; `maxSeconds` is the hard limit; `blend` glides in from the
-- camera the player had; `lowCaptions` puts the captions near the bottom instead of the top.
local function start(
	update: (number) -> (CFrame, boolean),
	captions: { Caption },
	maxSeconds: number,
	blend: number,
	lowCaptions: boolean?
)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	if cleanup then
		cleanup()
	end
	token += 1
	local myToken = token
	local startedAt = os.clock()
	local blendFrom = camera.CFrame
	local reduced = GuiService.ReducedMotionEnabled

	local connection: RBXScriptConnection? = nil
	local gui: ScreenGui? = nil
	local function finish()
		if token ~= myToken then
			return
		end
		cleanup = nil
		token += 1 -- stops every timer of this run
		if connection then
			connection:Disconnect()
		end
		if gui then
			gui:Destroy()
		end
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		setControls(true)
	end
	cleanup = finish

	local built, title, detail = makeGui(finish, lowCaptions == true)
	gui = built
	setControls(false)
	camera.CameraType = Enum.CameraType.Scriptable

	for _, caption in captions do
		task.delay(caption.at, showCaption, title, detail, caption, myToken)
	end

	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startedAt
		local target, done = update(elapsed)
		if blend > 0 and not reduced and elapsed < blend then
			local alpha = TweenService:GetValue(
				elapsed / blend,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			)
			camera.CFrame = blendFrom:Lerp(target, alpha)
		else
			camera.CFrame = target
		end
		if done or elapsed > maxSeconds then
			finish()
		end
	end)

	local tap: RBXScriptConnection
	tap = UserInputService.InputBegan:Connect(function(input)
		local pressed = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.Keyboard
		if pressed and os.clock() - startedAt > SKIP_AFTER then
			tap:Disconnect()
			finish()
		end
	end)
	task.delay(maxSeconds + 0.5, function()
		tap:Disconnect()
	end)
	player.CharacterAdded:Once(finish) -- a respawn ends it too
end

-- The 5 second tour: three shots one after the other, each drifting a little.
local function playTour()
	local gate = ownGate()
	if gate == nil then
		return
	end
	local reduced = GuiService.ReducedMotionEnabled
	local total = 0
	for _, shot in TOUR do
		total += shot.seconds
	end
	-- Scaled so the whole tour lasts Config.Intro.tourSeconds.
	local scale = Config.Intro.tourSeconds / total
	local function world(point: Vector3): Vector3
		return (gate.CFrame * CFrame.new(point.X, point.Y, point.Z)).Position
	end

	local captions: { Caption } = {}
	local at = 0
	for _, shot in TOUR do
		table.insert(captions, { at = at, text = shot.caption, seconds = shot.seconds * scale })
		at += shot.seconds * scale
	end

	start(function(elapsed: number): (CFrame, boolean)
		local remaining = elapsed
		for index, shot in TOUR do
			local length = shot.seconds * scale
			if remaining < length or index == #TOUR then
				local alpha = if reduced then 0 else math.clamp(remaining / length, 0, 1)
				local position = world(shot.from:Lerp(shot.to, alpha))
				local look = world(shot.lookFrom:Lerp(shot.lookTo, alpha))
				return CFrame.lookAt(position, look), elapsed >= Config.Intro.tourSeconds
			end
			remaining -= length
		end
		return CFrame.new(), true
	end, captions, Config.Intro.tourSeconds + 1, 0)
end

-- The first match: the camera behind the pitch with a slow drift, until the result of the player's
-- own match arrives (plus a short hold), or the time limit.
local function playFirstMatch()
	local gate = ownGate()
	if gate == nil then
		return
	end
	local reduced = GuiService.ReducedMotionEnabled
	local tierDef = Config.StadiumTiers[State.data.stadiumTier] or Config.StadiumTiers[1]
	local length, width = tierDef.courtLength, tierDef.courtWidth
	local center = CourtPlan.CENTER_Z
	local function world(x: number, y: number, z: number): Vector3
		return (gate.CFrame * CFrame.new(x, y - 1, z)).Position
	end
	lastResultAt = nil

	start(function(elapsed: number): (CFrame, boolean)
		local drift = if reduced then 0 else math.sin(elapsed * 0.35) * 14
		local position = world(drift, 15 + length * 0.25, center - width / 2 - length * 0.5)
		local look = world(0, 3, center + 2)
		local resultAt = lastResultAt
		local done = resultAt ~= nil and os.clock() - resultAt >= Config.Intro.firstMatchHoldSeconds
		return CFrame.lookAt(position, look), done
	end, {
		{ at = 0.6, text = "YOUR FIRST MATCH", seconds = 2.4 },
	}, Config.Intro.firstMatchMaxSeconds, BLEND_SECONDS)
end

-- Unlocks ---------------------------------------------------------------------------------------

-- Something else holds the screen: another cinematic or a camera takeover (the skill games and the
-- penalties use a scriptable camera), a reveal, the cases screen or a reward card being read.
local function busy(): boolean
	if cleanup ~= nil or not State.hasPlot() then
		return true
	end
	local camera = Workspace.CurrentCamera
	if camera == nil or camera.CameraType ~= Enum.CameraType.Custom then
		return true
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui == nil then
		return true
	end
	for _, name in BUSY_GUIS do
		local gui = playerGui:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") and gui.Enabled then
			for _, child in gui:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					return true
				end
			end
		end
	end
	return false
end

-- Where the unlock camera is `alpha` of the way through its move, on the `away` side of the pad.
local function unlockPosition(target: Vector3, away: Vector3, alpha: number): Vector3
	local distance = UNLOCK_FAR + (UNLOCK_NEAR - UNLOCK_FAR) * alpha
	local height = UNLOCK_HIGH + (UNLOCK_LOW - UNLOCK_HIGH) * alpha
	return target + away * distance + Vector3.new(0, height, 0)
end

-- Whether anything solid stands between two points (glass and other see-through parts and the
-- player's own character do not count).
local function blocked(from: Vector3, to: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: { Instance } = {}
	if player.Character then
		table.insert(ignored, player.Character)
	end
	for _ = 1, 8 do
		params.FilterDescendantsInstances = ignored
		local hit = Workspace:Raycast(from, to - from, params)
		if hit == nil then
			return false
		end
		if hit.Instance.Transparency < SEE_THROUGH then
			return true
		end
		table.insert(ignored, hit.Instance)
	end
	return false
end

-- The side of the pad the unlock camera comes from: the player's own side when the pad stays in
-- view the whole way in, otherwise the nearest side around the pad that keeps it in view (the
-- training pads stand between the gym's walls, which hid them from a player in the building).
local function unlockSide(target: Vector3, preferred: Vector3, look: Vector3): Vector3
	for step = 0, UNLOCK_SIDES / 2 do
		for _, sign in (if step == 0 or step == UNLOCK_SIDES / 2 then { 1 } else { 1, -1 }) do
			local angle = sign * step * 2 * math.pi / UNLOCK_SIDES
			local away = CFrame.Angles(0, angle, 0):VectorToWorldSpace(preferred)
			local clear = true
			for _, alpha in { 0, 0.5, 1 } do
				if blocked(look, unlockPosition(target, away, alpha)) then
					clear = false
					break
				end
			end
			if clear then
				return away
			end
		end
	end
	return preferred
end

-- The camera comes from the player's side of the pad (or the nearest side with a clear view of it),
-- lowers and closes in while the title and what the pad does are shown. It glides in from the
-- player's camera, or cuts straight to the shot when a wall stands in between.
local function playUnlock(unlock: Unlocks.Unlock, target: Vector3)
	pcall(function()
		player:RequestStreamAroundAsync(target, 2) -- the pad may not be streamed in yet
	end)
	local reduced = GuiService.ReducedMotionEnabled
	local camera = Workspace.CurrentCamera
	local from = if camera then camera.CFrame.Position else target + Vector3.new(0, 0, 30)
	local flat = Vector3.new(from.X - target.X, 0, from.Z - target.Z)
	local look = target + Vector3.new(0, 2, 0)
	local away =
		unlockSide(target, if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, 1), look)
	local blend = if blocked(from, unlockPosition(target, away, 0)) then 0 else UNLOCK_BLEND
	Sounds.play("unlock")
	start(function(elapsed: number): (CFrame, boolean)
		local alpha = if reduced then 1 else math.clamp(elapsed / UNLOCK_SECONDS, 0, 1)
		return CFrame.lookAt(unlockPosition(target, away, alpha), look), elapsed >= UNLOCK_SECONDS
	end, {
		{ at = 0.3, text = unlock.title, detail = unlock.detail, seconds = UNLOCK_SECONDS - 0.3 },
	}, UNLOCK_SECONDS + 1, blend, true)
end

-- Unlocks that arrive together play one after another, each once the screen is free.
local unlockQueue: { { unlock: Unlocks.Unlock, position: Vector3 } } = {}
local unlockRunning = false

local function runUnlockQueue()
	if unlockRunning then
		return
	end
	unlockRunning = true
	while #unlockQueue > 0 do
		-- Free for a moment first, so a cinematic never starts on the frame a reveal closes.
		local freeSince: number? = nil
		while true do
			if busy() then
				freeSince = nil
			elseif freeSince == nil then
				freeSince = os.clock()
			elseif os.clock() - freeSince >= UNLOCK_CALM_SECONDS then
				break
			end
			task.wait(0.25)
		end
		local nextUp = table.remove(unlockQueue, 1)
		if nextUp then
			playUnlock(nextUp.unlock, nextUp.position)
			while cleanup ~= nil do
				task.wait(0.1)
			end
		end
	end
	unlockRunning = false
end

function IntroCinematics.init()
	Net.on("Notice", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.kind == "plotTour" then
			task.spawn(playTour)
		elseif info.kind == "firstMatch" then
			task.spawn(playFirstMatch)
		elseif info.kind == "unlock" then
			local unlock = if type(info.id) == "string" then Unlocks.byId[info.id] else nil
			if unlock and typeof(info.position) == "Vector3" then
				table.insert(unlockQueue, { unlock = unlock, position = info.position })
				task.spawn(runUnlockQueue)
			end
		end
	end)
	Net.on("MatchResult", function(_plot: any, info: any)
		if type(info) == "table" and info.ownerUserId == player.UserId then
			lastResultAt = os.clock()
		end
	end)
end

return IntroCinematics
