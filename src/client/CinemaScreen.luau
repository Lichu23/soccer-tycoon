--!strict
-- What the full-screen cinematic games share (docs/CINEMATICS.md): the 1v1 breakaway (FreekickUi),
-- the daily penalty kicks (PenaltyUi) and the keepie-uppies (KeepieUi). The takeover saves the
-- camera, turns off the controls and hides the other screens while the scene shows, then puts
-- everything back; the aim reticle and the power meter are built here so both kicking games draw
-- them the same way, and the red X walks the player off the spot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local WHITE = Color3.fromRGB(255, 255, 255)
local POWER_WIDTH = 30

-- The other screens hidden while the stadium shows: the HUD and its dock, the menu buttons down the
-- left, the floor buttons, the guide and the pad hint.
local HIDDEN_GUIS = {
	"Hud",
	"Shop",
	"Locker",
	"Reminders",
	"Daily",
	"Season",
	"FloorSwitcher",
	"Objective",
	"PadHint",
}

local CinemaScreen = {}

-- The top of the power meter's green zone (its bottom is the weak power).
CinemaScreen.POWER_GOOD_MAX = Config.Training.freekickPowerSweet + 0.12

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

function CinemaScreen.takeover(): Takeover
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
			if other and other:IsA("ScreenGui") then
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
				CameraType = camera.CameraType,
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
			camera.CameraType = savedCamera.CameraType or Enum.CameraType.Custom
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

export type PowerMeter = { box: Frame, fill: Frame, stroke: UIStroke }

-- The power meter on the right: it fills from the bottom, with the green zone marked.
function CinemaScreen.powerMeter(parent: Instance): PowerMeter
	local weak = Config.Training.freekickWeakPower
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
	new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1 - weak),
		Size = UDim2.fromScale(1, CinemaScreen.POWER_GOOD_MAX - weak),
		BackgroundColor3 = Style.ui.good,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, box)
	for _, edge in { weak, CinemaScreen.POWER_GOOD_MAX } do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 1 - edge),
			Size = UDim2.new(1, 10, 0, 3),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 7,
		}, box)
	end
	local fill = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Style.ui.gold,
		ZIndex = 6,
	}, box)
	rounded(fill, 8)
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
	return { box = box, fill = fill, stroke = stroke }
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

-- The meter's fill colour for `power`: green inside the good zone, red outside it.
function CinemaScreen.powerGood(power: number): boolean
	return power >= Config.Training.freekickWeakPower and power <= CinemaScreen.POWER_GOOD_MAX
end

return CinemaScreen
