--!strict
-- What the full-screen cinematic games share (docs/CINEMATICS.md): the 1v1 breakaway (FreekickUi),
-- the daily penalty kicks (PenaltyUi) and the keepie-uppies (KeepieUi). The takeover saves the
-- camera, turns off the controls and hides the other screens while the scene shows, then puts
-- everything back; the aim reticle and the power meter are built here so both kicking games draw
-- them the same way, and the red X walks the player off the spot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local WHITE = Color3.fromRGB(255, 255, 255)
local MISS = Color3.fromRGB(232, 142, 138) -- the screens' red for a miss
local POWER_WIDTH = 30
local MARKER_HEIGHT = 8 -- the power meter's moving indicator, wider than the meter
local MARKER_OVERHANG = 18
-- On a phone (a short screen) the meter is taller and wider, so its green zone is easy to read.
local PHONE_HEIGHT = 500 -- screens shorter than this are phones
local PHONE_POWER_WIDTH = 46
local PHONE_POWER_SHARE = 0.62 -- the share of the screen height the meter takes (0.42 elsewhere)
local PHONE_MARKER_HEIGHT = 12
local PHONE_MARKER_OVERHANG = 24

-- The other screens hidden while the stadium shows: the HUD and its dock, the menu buttons down the
-- left, the floor buttons, the guide and the pad hint.
local HIDDEN_GUIS = {
	"Hud",
	"Shop",
	"Locker",
	"Reminders",
	"Music",
	"Daily",
	"Season",
	"FloorSwitcher",
	"Objective",
	"PadHint",
	"BigChance",
}

local CinemaScreen = {}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function rounded(parent: Instance, radius: number)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
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

-- The character stands still while a scene shows: the default control scripts may be missing (no
-- PlayerModule), so the keys would still walk it off the spot and close the game. Returns a function
-- that puts its speed back.
local function freeze(humanoid: Humanoid): () -> ()
	local walkSpeed, jumpPower, jumpHeight, autoRotate =
		humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight, humanoid.AutoRotate
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero)
	return function()
		if humanoid.Parent then
			humanoid.WalkSpeed = walkSpeed
			humanoid.JumpPower = jumpPower
			humanoid.JumpHeight = jumpHeight
			humanoid.AutoRotate = autoRotate
		end
	end
end

local function ownHumanoid(): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

export type Takeover = {
	take: () -> (), -- the camera becomes ours, the controls go off, the other screens hide
	keep: () -> (), -- every frame: the default camera scripts and other screens can switch back
	give: () -> (), -- everything back as it was
}

-- `keep` is a screen of the list that stays on (the Locker room's own). It is skipped, never turned
-- off and on again every frame: that drops a touch in the middle of a tap, so on a phone none of its
-- buttons worked.
function CinemaScreen.takeover(keep: ScreenGui?): Takeover
	local playerGui = player:WaitForChild("PlayerGui")
	local savedCamera: { [string]: any } = {}
	local hiddenGuis: { [ScreenGui]: boolean } = {}
	local frozen: Humanoid? = nil
	local unfreeze: (() -> ())? = nil

	-- A respawn brings a new humanoid; it stands still too.
	local function holdStill()
		local humanoid = ownHumanoid()
		if humanoid == nil or humanoid == frozen then
			return
		end
		if unfreeze then
			unfreeze()
		end
		frozen = humanoid
		unfreeze = freeze(humanoid)
	end

	local function hideOthers()
		for _, name in HIDDEN_GUIS do
			local other = playerGui:FindFirstChild(name)
			if other and other:IsA("ScreenGui") and other ~= keep then
				if hiddenGuis[other] == nil then
					hiddenGuis[other] = other.Enabled
				end
				other.Enabled = false
			end
		end
	end

	return {
		take = function()
			local camera = Workspace.CurrentCamera
			savedCamera = {
				FieldOfView = camera.FieldOfView,
			}
			camera.CameraType = Enum.CameraType.Scriptable
			setControls(false)
			holdStill()
			hideOthers()
		end,
		keep = function()
			holdStill()
			hideOthers()
			Workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
		end,
		give = function()
			local camera = Workspace.CurrentCamera
			-- Always back to following the player: a takeover can start in the same tap that ends
			-- another cinematic (the first-match camera ends on any tap), and putting its Scriptable
			-- camera back would leave the view frozen where this one left it.
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = savedCamera.FieldOfView or 70
			local character = player.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			if humanoid then
				camera.CameraSubject = humanoid
			end
			for other, enabled in hiddenGuis do
				other.Enabled = enabled
			end
			table.clear(hiddenGuis)
			if unfreeze then
				unfreeze()
			end
			frozen, unfreeze = nil, nil
			setControls(true)
		end,
	}
end

export type Reticle = { frame: Frame, stroke: UIStroke, scale: UIScale }

-- The aim reticle: a gold ring with a cross and a dot, placed on the goal mouth by the caller.
function CinemaScreen.reticle(parent: Instance): Reticle
	local reticle = new("Frame", {
		Name = "Reticle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(48, 48),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
	}, parent)
	rounded(reticle, 1000)
	local stroke = new("UIStroke", { Color = Style.ui.gold, Thickness = 4 }, reticle)
	for _, bar in { { 0.5, 0.06, 1.5, 0 }, { 0.06, 0.5, 0, 1.5 } } do
		for _, sign in { -1, 1 } do
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(
					0.5 + sign * 0.5 * bar[3] * 0.5,
					0.5 + sign * 0.5 * bar[4] * 0.5
				),
				Size = UDim2.fromScale(bar[1], bar[2]),
				BackgroundColor3 = Style.ui.gold,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, reticle)
		end
	end
	local dot = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Style.ui.gold,
		ZIndex = 4,
	}, reticle)
	rounded(dot, 1000)
	return { frame = reticle, stroke = stroke, scale = new("UIScale", {}, reticle) }
end

export type PowerMeter = {
	box: Frame,
	marker: Frame,
	stroke: UIStroke,
	zone: Frame,
	edges: { Frame },
	low: number,
	high: number,
}

-- The power meter on the right: an indicator slides up and down it over the green zone from `low`
-- to `high` (`setPowerZone` moves the zone, `setPower` the indicator).
function CinemaScreen.powerMeter(parent: Instance, low: number, high: number): PowerMeter
	local box = new("Frame", {
		Name = "Power",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.5, 0),
		Size = UDim2.new(0, POWER_WIDTH, 0.42, 0),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
		Visible = false,
		ZIndex = 5,
	}, parent)
	rounded(box, 8)
	local stroke = new("UIStroke", { Color = Style.ui.gold, Thickness = 3 }, box)
	local zone = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1 - low),
		Size = UDim2.fromScale(1, high - low),
		BackgroundColor3 = Style.ui.good,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, box)
	local edges = {}
	for _, edge in { low, high } do
		table.insert(
			edges,
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 1 - edge),
				Size = UDim2.new(1, 10, 0, 3),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				ZIndex = 7,
			}, box)
		)
	end
	local marker = new("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, MARKER_OVERHANG, 0, MARKER_HEIGHT),
		BackgroundColor3 = WHITE,
		ZIndex = 8,
	}, box)
	rounded(marker, MARKER_HEIGHT // 2)
	new("UIStroke", { Color = Style.ui.panel, Thickness = 2 }, marker)
	local markerCorner = marker:FindFirstChildOfClass("UICorner") :: UICorner
	-- The size for the screen: bigger on a phone, and again when the screen turns or resizes.
	local camera = Workspace.CurrentCamera
	local function fit()
		local phone = camera.ViewportSize.Y < PHONE_HEIGHT
		box.Size = if phone
			then UDim2.new(0, PHONE_POWER_WIDTH, PHONE_POWER_SHARE, 0)
			else UDim2.new(0, POWER_WIDTH, 0.42, 0)
		local height = if phone then PHONE_MARKER_HEIGHT else MARKER_HEIGHT
		marker.Size =
			UDim2.new(1, if phone then PHONE_MARKER_OVERHANG else MARKER_OVERHANG, 0, height)
		markerCorner.CornerRadius = UDim.new(0, height // 2)
	end
	fit()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	local label = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.fromOffset(70, 16),
		BackgroundTransparency = 1,
		Font = Style.font,
		Text = "POWER",
		TextSize = 14,
		TextColor3 = WHITE,
		ZIndex = 5,
	}, box)
	new("UIStroke", {
		Color = Color3.fromRGB(0, 0, 0),
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, label)
	return {
		box = box,
		marker = marker,
		stroke = stroke,
		zone = zone,
		edges = edges,
		low = low,
		high = high,
	}
end

-- Moves the green zone of `meter` to run from `low` to `high`.
function CinemaScreen.setPowerZone(meter: PowerMeter, low: number, high: number)
	if meter.low == low and meter.high == high then
		return
	end
	meter.low, meter.high = low, high
	meter.zone.Position = UDim2.fromScale(0, 1 - low)
	meter.zone.Size = UDim2.fromScale(1, high - low)
	meter.edges[1].Position = UDim2.fromScale(0.5, 1 - low)
	meter.edges[2].Position = UDim2.fromScale(0.5, 1 - high)
end

-- The marker `name` (TrainingFreekick, TrainingKeepie) of the player's own plot, or nil.
local function ownSpot(name: string): BasePart?
	local slot = player:GetAttribute("plotSlot")
	local plots = Workspace:FindFirstChild("Plots")
	local plot = if type(slot) == "number" and plots
		then plots:FindFirstChild("Plot_" .. slot)
		else nil
	local spot = if plot then plot:FindFirstChild(name, true) else nil
	return if spot and spot:IsA("BasePart") then spot else nil
end

-- The red X's walk: off the spot `name`, `step` studs past its edge (any input of the player takes over).
function CinemaScreen.walkOff(name: string, step: number)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local spot = ownSpot(name)
	if humanoid == nil or root == nil or not root:IsA("BasePart") or spot == nil then
		return
	end
	local away = root.Position - spot.Position
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.5 then
		away = -spot.CFrame.LookVector
	end
	local reach = math.max(spot.Size.X, spot.Size.Z) / 2 + step
	humanoid:MoveTo(spot.Position + away.Unit * reach)
end

-- Puts the indicator of `meter` at `power`: white while it moves; once `stopped`, green on the
-- green zone and red off it.
function CinemaScreen.setPower(meter: PowerMeter, power: number, stopped: boolean)
	meter.marker.Position = UDim2.fromScale(0.5, 1 - power)
	meter.marker.BackgroundColor3 = if not stopped
		then WHITE
		elseif power >= meter.low and power <= meter.high then Style.ui.good
		else MISS
end

return CinemaScreen
