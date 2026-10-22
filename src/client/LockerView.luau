--!strict
-- The stadium behind the Locker room (docs/PLAN.md, Step 3): while the room is open the camera looks at
-- the player's own pitch, framed on the slot being browsed (the kit on a few players at the centre
-- circle, the crest over the gate, the boards, the floodlights, the scoreboard). A style the player
-- taps is painted on their own screen only; leaving paints the chosen styles back. The server paints
-- the real choices for everyone (server/Stadium); nothing here is saved.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CinemaScreen = require(script.Parent.CinemaScreen)
local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local CourtPlan = require(ReplicatedStorage.Shared.CourtPlan)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)
local StadiumLook = require(ReplicatedStorage.Shared.StadiumLook)
local State = require(script.Parent.State)

local player = Players.LocalPlayer

local CAMERA_SPEED = 5 -- how fast the camera eases to a new shot (higher is faster)
local KIT_FIGURES = 5
local KIT_GAP = 3.2

local LockerView = {}

type Shot = { eye: Vector3, at: Vector3 }

local takeover: CinemaScreen.Takeover? = nil
local follow: RBXScriptConnection? = nil
local shot: Shot? = nil
local figures: Model? = nil
local painted: { [string]: boolean } = {} -- the slots painted with a preview

local function ownPlot(): Model?
	local slot = player:GetAttribute("plotSlot")
	local plots = Workspace:FindFirstChild("Plots")
	local plot = if type(slot) == "number" and plots
		then plots:FindFirstChild("Plot_" .. slot)
		else nil
	return if plot and plot:IsA("Model") then plot else nil
end

local function gateOf(plot: Model): BasePart?
	local gate = plot:FindFirstChild("Gate")
	return if gate and gate:IsA("BasePart") then gate else nil
end

-- The first part named `name` on the pitch (by its place in the plan), or nil.
local function firstPart(gate: BasePart, name: string): BasePart?
	local plot = gate.Parent
	local court = plot and plot:FindFirstChild("Court")
	local best: BasePart? = nil
	local bestIndex = math.huge
	if court then
		for _, child in court:GetChildren() do
			local index = tonumber(child:GetAttribute("PlanIndex"))
			if child:IsA("BasePart") and child.Name == name and index and index < bestIndex then
				best, bestIndex = child, index
			end
		end
	end
	return best
end

-- The camera shot of a slot. The crest, the scoreboard and the floodlights are framed on their real
-- parts (they move from tier to tier); the kit and the boards use plot space (CourtPlan) through the gate.
local function shotFor(gate: BasePart, slotId: string): Shot
	if slotId == "crest" or slotId == "scoreboard" then
		-- Both have their face on the part's front, so the camera stands in front of it.
		local part = firstPart(gate, if slotId == "crest" then "Crest" else "Scoreboard")
		if part then
			local distance = math.max(part.Size.X, part.Size.Y)
				* if slotId == "crest" then 5 else 1.4
			local front = part.CFrame.LookVector
			return {
				eye = part.Position + front * distance + Vector3.new(0, distance * 0.15, 0),
				-- The crest shot also takes in the sign under it.
				at = part.Position
					- Vector3.new(0, if slotId == "crest" then part.Size.Y * 0.6 else 0, 0),
			}
		end
	elseif slotId == "floodlights" then
		-- One mast, seen from high over the pitch (clear of the stands and roofs at every tier).
		local head = firstPart(gate, "LightHead")
		if head then
			local middle = (gate.CFrame * CFrame.new(0, CourtPlan.FLOOR, CourtPlan.CENTER_Z)).Position
			local out = Vector3.new(head.Position.X - middle.X, 0, head.Position.Z - middle.Z)
			return {
				eye = middle + out * 0.3 + Vector3.new(0, head.Position.Y - middle.Y + 14, 0),
				at = head.Position - Vector3.new(0, 6, 0),
			}
		end
	end
	local def = Config.StadiumTiers[State.data.stadiumTier] or Config.StadiumTiers[1]
	local length, width = def.courtLength, def.courtWidth
	local center = CourtPlan.CENTER_Z
	local near, far = center - width / 2, center + width / 2
	local floor = CourtPlan.FLOOR
	local eye, at
	if slotId == "kit" then
		eye, at = Vector3.new(0, floor + 7, center - 20), Vector3.new(0, floor + 3, center)
	elseif slotId == "banners" then
		-- Low inside the pitch, along the far boards (the near roofs of the big stadiums hide them).
		eye = Vector3.new(-length * 0.3, floor + 6, center - width * 0.1)
		at = Vector3.new(length * 0.1, floor + 1, far + 2)
	else
		-- The whole pitch from above the near side.
		eye = Vector3.new(-length * 0.15, floor + 14 + length * 0.2, near - length * 0.4)
		at = Vector3.new(0, floor, center)
	end
	local function world(v: Vector3): Vector3
		return (gate.CFrame * CFrame.new(v.X, v.Y - 1, v.Z)).Position
	end
	return { eye = world(eye), at = world(at) }
end

-- A few of the player's own team (or the first players of the game) at the centre circle, in `kit`.
local function showFigures(gate: BasePart, kit: Color3)
	if figures then
		figures:Destroy()
	end
	local ids: { string } = {}
	for id in State.data.players do
		if Config.PlayersById[id] then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	for _, def in Config.Players do
		if #ids >= KIT_FIGURES then
			break
		end
		if not table.find(ids, def.id) then
			table.insert(ids, def.id)
		end
	end
	local group = Instance.new("Model")
	group.Name = "LockerKit"
	local camera = shot and shot.eye or gate.Position
	for index = 1, math.min(KIT_FIGURES, #ids) do
		local figure = Mannequin.build(Config.PlayersById[ids[index]], kit, false)
		local x = (index - (KIT_FIGURES + 1) / 2) * KIT_GAP
		local feet = gate.CFrame * CFrame.new(x, CourtPlan.FLOOR - 1, CourtPlan.CENTER_Z)
		local torso = feet.Position + Vector3.new(0, Mannequin.FEET_TO_TORSO, 0)
		figure:PivotTo(CFrame.lookAt(torso, Vector3.new(camera.X, torso.Y, camera.Z)))
		figure.Parent = group
	end
	group.Parent = Workspace
	figures = group
end

local function hideFigures()
	if figures then
		figures:Destroy()
		figures = nil
	end
end

-- How far to turn the camera left so the subject sits in the middle of the screen space to the right
-- of the panel (`panelRight` is the panel's right edge in pixels), for this screen's shape.
local function sideTurn(camera: Camera, panelRight: number): number
	local size = camera.ViewportSize
	if size.X <= 0 or size.Y <= 0 then
		return 0
	end
	local middle = (math.clamp(panelRight / size.X, 0, 0.8) + 1) / 2 -- 0 to 1 across the screen
	local halfWidth = math.tan(math.rad(camera.FieldOfView / 2)) * size.X / size.Y
	return math.atan((middle * 2 - 1) * halfWidth)
end

-- Takes the camera and hides the other screens. The Locker room's own screen stays (`keepGui`), and
-- the shots are framed beside `panel`.
function LockerView.enter(keepGui: ScreenGui, panel: GuiObject)
	if takeover then
		return
	end
	local mine = CinemaScreen.takeover()
	takeover = mine
	mine.take()
	keepGui.Enabled = true
	local camera = Workspace.CurrentCamera
	local reduced = GuiService.ReducedMotionEnabled
	local first = true
	follow = RunService.RenderStepped:Connect(function(dt: number)
		-- Screens that show themselves again (the floor buttons) go back off; this one stays.
		mine.keep()
		keepGui.Enabled = true
		local target = shot
		if target == nil then
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable
		local panelRight = panel.AbsolutePosition.X + panel.AbsoluteSize.X
		local goal = CFrame.lookAt(target.eye, target.at)
			* CFrame.Angles(0, sideTurn(camera, panelRight), 0)
		if first or reduced then
			camera.CFrame = goal
			first = false
		else
			camera.CFrame = camera.CFrame:Lerp(goal, math.clamp(dt * CAMERA_SPEED, 0, 1))
		end
	end)
end

-- Frames `slotId` and, for the kit, shows the players in `kit` (nil = the chosen kit).
function LockerView.focus(slotId: string)
	local plot = ownPlot()
	local gate = plot and gateOf(plot)
	if gate == nil then
		return
	end
	shot = shotFor(gate, slotId)
	if slotId == "kit" then
		local chosen = Cosmetics.chosen(State.data, "kit")
		if chosen and figures == nil then
			showFigures(gate, Color3.fromRGB(chosen.color[1], chosen.color[2], chosen.color[3]))
		end
	else
		hideFigures()
	end
end

-- Paints style `def` of its slot on the player's own screen.
function LockerView.preview(def: Config.CosmeticDef)
	local plot = ownPlot()
	local gate = plot and gateOf(plot)
	if plot == nil or gate == nil then
		return
	end
	if def.slot == "kit" then
		showFigures(gate, Color3.fromRGB(def.color[1], def.color[2], def.color[3]))
		return
	end
	local court = plot:FindFirstChild("Court")
	if court then
		StadiumLook.paint(court, def.slot, def)
		painted[def.slot] = true
	end
end

-- Paints the chosen style back on every slot that showed a preview.
function LockerView.restore()
	local plot = ownPlot()
	local court = plot and plot:FindFirstChild("Court")
	for slotId in painted do
		local chosen = Cosmetics.chosen(State.data, slotId)
		if court and chosen then
			StadiumLook.paint(court, slotId, chosen)
		end
	end
	table.clear(painted)
	hideFigures() -- the next focus on the kit shows the chosen one again
end

-- Everything back as it was: the chosen styles, the camera, the controls and the other screens.
function LockerView.leave()
	LockerView.restore()
	hideFigures()
	shot = nil
	if follow then
		follow:Disconnect()
		follow = nil
	end
	if takeover then
		takeover.give()
		takeover = nil
	end
end

return LockerView
