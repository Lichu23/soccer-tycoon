--!strict
-- The belt of each plot's treadmill runs while its owner trains on it: the three chevrons on the belt
-- (Gym.Treadmill.BeltArrows, a SurfaceGui whose "up" points to the console) slide back, away from the
-- console, under the runner's feet, and fade out at the back and in again at the front. When nobody
-- trains they stand still at their places. Only a picture: the server's attributes say who trains.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SPEED = 0.7 -- belt lengths per second (about 5 studs a second on the 7 stud belt)
local SPAN = 0.9 -- the chevrons travel from 0.05 to 0.95 of the belt, one every SPAN / 3
local START = 0.05
local FADE = 0.12 -- the share of the belt at each end where a chevron fades
local REST = { 0.2, 0.5, 0.8 } -- where the chevrons stand when the belt is still

local TreadmillBelt = {}

-- The chevrons of a plot's treadmill, or nil.
local function chevronsOf(plot: Instance): { Frame }?
	local gym = plot:FindFirstChild("Gym")
	local treadmill = if gym then gym:FindFirstChild("Treadmill") else nil
	local arrows = if treadmill then treadmill:FindFirstChild("BeltArrows") else nil
	local gui = if arrows then arrows:FindFirstChild("Arrows") else nil
	if gui == nil then
		return nil
	end
	local chevrons = {}
	for index = 1, #REST do
		local chevron = gui:FindFirstChild("Chevron" .. index)
		if chevron == nil or not chevron:IsA("Frame") then
			return nil
		end
		chevrons[index] = chevron
	end
	return chevrons
end

local function place(chevron: Frame, y: number, transparency: number)
	chevron.Position = UDim2.fromScale(0.5, y)
	for _, bar in chevron:GetChildren() do
		if bar:IsA("Frame") then
			bar.BackgroundTransparency = transparency
		end
	end
end

local function runningOn(plot: Instance): boolean
	local owner = Players:GetPlayerByUserId(plot:GetAttribute("OwnerUserId") or 0)
	return owner ~= nil
		and owner:GetAttribute("training") == true
		and owner:GetAttribute("trainingStation") == "treadmill"
end

function TreadmillBelt.init()
	local moving: { [Instance]: true? } = {} -- the plots whose belt ran last frame
	local offset = 0

	RunService.Heartbeat:Connect(function(dt)
		local plots = Workspace:FindFirstChild("Plots")
		if plots == nil then
			return
		end
		offset = (offset + SPEED * dt) % SPAN
		for _, plot in plots:GetChildren() do
			local running = runningOn(plot)
			if not running and not moving[plot] then
				continue
			end
			local chevrons = chevronsOf(plot)
			if chevrons == nil then
				continue
			end
			for index, chevron in chevrons do
				if running then
					-- GUI y grows to the back of the belt, so adding the offset slides them back.
					local y = START + ((index - 1) * SPAN / #chevrons + offset) % SPAN
					local edge = math.min(y - START, START + SPAN - y)
					place(chevron, y, 1 - math.clamp(edge / FADE, 0, 1))
				else
					place(chevron, REST[index], 0)
				end
			end
			moving[plot] = if running then true else nil
		end
	end)
end

return TreadmillBelt
