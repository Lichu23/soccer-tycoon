--!strict
-- Draws the match on the pitch (docs/PLAN.md, Step 7). The server has already decided the result and
-- the payout; the client only plays it with local figures, so nothing here is replicated and the
-- server never simulates a match. Greybox version: both teams jog around their half, and when the
-- result arrives the ball goes into the goal once for every goal and our team celebrates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Formation = require(ReplicatedStorage.Shared.Formation)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)
local Net = require(script.Parent.Net)
local Roster = require(ReplicatedStorage.Shared.Roster)
local State = require(script.Parent.State)

local player = Players.LocalPlayer
local random = Random.new()

local COURT_CENTER_Z = 64 -- the middle of every pitch, in plot space (docs/PLAN.md, Step 7)
local TORSO_HEIGHT = 0.7 + Mannequin.FEET_TO_TORSO - 1 -- in gate space (the gate is 1 stud up)
local RIVAL_KIT = Color3.fromRGB(215, 70, 70)
local SPEED = 5 -- studs per second while jogging
local FAR_AWAY = 240 -- studs from the camera: do not animate
local OTHER_PLOT_SECONDS = 40

type Runner = {
	model: Model,
	home: Vector3, -- court space: x along the length, z across, y unused
	position: Vector3,
	target: Vector3,
	nextTargetAt: number,
	facing: number, -- +1 looks towards +x, -1 towards -x
}

type Team = {
	plot: Model,
	gate: BasePart,
	key: string,
	runners: { Runner },
	length: number,
	width: number,
	celebrateUntil: number,
	lastUsed: number,
	ball: Part?,
}

local teams: { [Model]: Team } = {}
local folder: Folder

local MatchView = {}

local function gateCFrame(team: Team, x: number, z: number, lift: number): CFrame
	return team.gate.CFrame * CFrame.new(x, TORSO_HEIGHT + lift, COURT_CENTER_Z + z)
end

local function tierFor(count: number): Config.StadiumTierDef
	for _, def in Config.StadiumTiers do
		if def.field >= count then
			return def
		end
	end
	return Config.StadiumTiers[#Config.StadiumTiers]
end

local function opponentDef(index: number): Config.PlayerDef
	return {
		id = "rival" .. index,
		name = "",
		nationality = "",
		number = index,
		rarity = "Common",
		floor = 0,
		slot = 0,
		price = 0,
		income = 0,
	}
end

local function destroyTeam(team: Team)
	for _, runner in team.runners do
		runner.model:Destroy()
	end
	if team.ball then
		team.ball:Destroy()
	end
	teams[team.plot] = nil
end

local function placeRunner(team: Team, runner: Runner, now: number)
	local bob = 0
	if now < team.celebrateUntil and runner.facing == 1 then
		bob = math.abs(math.sin(now * 9)) * 2.2
	end
	local yaw = if runner.facing == 1 then -math.pi / 2 else math.pi / 2
	runner.model:PivotTo(
		gateCFrame(team, runner.position.X, runner.position.Z, bob) * CFrame.Angles(0, yaw, 0)
	)
end

-- Builds both teams for a plot: our field players and as many rival figures.
local function buildTeam(plot: Model, fieldIds: { string }, tier: Config.StadiumTierDef): Team?
	local gate = plot:FindFirstChild("Gate")
	if not gate or not gate:IsA("BasePart") then
		return nil
	end
	local count = #fieldIds
	local team: Team = {
		plot = plot,
		gate = gate,
		key = table.concat(fieldIds, ",") .. "|" .. tier.tier,
		runners = {},
		length = tier.courtLength,
		width = tier.courtWidth,
		celebrateUntil = 0,
		lastUsed = os.clock(),
		ball = nil,
	}
	local ours = Formation.spots(count, team.length, team.width, -1)
	local theirs = Formation.spots(count, team.length, team.width, 1)
	for index = 1, count do
		local def = Config.PlayersById[fieldIds[index]]
		if def then
			local mine = Mannequin.build(def, nil, false)
			mine.Parent = folder
			local home = Vector3.new(ours[index].x, 0, ours[index].z)
			table.insert(team.runners, {
				model = mine,
				home = home,
				position = home,
				target = home,
				nextTargetAt = 0,
				facing = 1,
			})
			local rival = Mannequin.build(opponentDef(index), RIVAL_KIT, false)
			rival.Parent = folder
			local rivalHome = Vector3.new(theirs[index].x, 0, theirs[index].z)
			table.insert(team.runners, {
				model = rival,
				home = rivalHome,
				position = rivalHome,
				target = rivalHome,
				nextTargetAt = 0,
				facing = -1,
			})
		end
	end
	teams[plot] = team
	for _, runner in team.runners do
		placeRunner(team, runner, 0)
	end
	return team
end

-- The team of a plot, rebuilt when the players on the field changed.
local function ensureTeam(plot: Model, fieldIds: { string }, tier: Config.StadiumTierDef): Team?
	local existing = teams[plot]
	local key = table.concat(fieldIds, ",") .. "|" .. tier.tier
	if existing and existing.key == key then
		existing.lastUsed = os.clock()
		return existing
	end
	if existing then
		destroyTeam(existing)
	end
	if #fieldIds == 0 then
		return nil
	end
	return buildTeam(plot, fieldIds, tier)
end

local function nearCamera(team: Team): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and (team.gate.Position - camera.CFrame.Position).Magnitude < FAR_AWAY
end

local function playResult(plot: Model, info: any)
	local fieldIds = info.fieldIds
	if type(fieldIds) ~= "table" or #fieldIds == 0 then
		return
	end
	local tierNumber = info.stadiumTier
	local tier = if type(tierNumber) == "number" and Config.StadiumTiers[tierNumber]
		then Config.StadiumTiers[tierNumber]
		else tierFor(#fieldIds)
	local team = ensureTeam(plot, fieldIds, tier)
	if team == nil or not nearCamera(team) then
		return
	end

	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1.6, 1.6, 1.6)
	ball.Color = Color3.fromRGB(250, 250, 250)
	ball.Material = Enum.Material.SmoothPlastic
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CFrame = gateCFrame(team, 0, 0, -1.2)
	ball.Parent = folder
	team.ball = ball

	task.spawn(function()
		local goalsFor = math.clamp(info.goalsFor or 1, 1, 6)
		local goalsAgainst = math.clamp(info.goalsAgainst or 0, 0, 6)
		-- Their goals come first, ours last, so the match ends on a win.
		local sequence = {}
		for _ = 1, goalsAgainst do
			table.insert(sequence, -1)
		end
		for _ = 1, goalsFor do
			table.insert(sequence, 1)
		end
		for _, side in sequence do
			if ball.Parent == nil then
				return
			end
			ball.CFrame = gateCFrame(team, 0, 0, -1.2)
			local goalMouth = gateCFrame(team, side * team.length / 2, 0, -1.2)
			local tween = TweenService:Create(
				ball,
				TweenInfo.new(0.45, Enum.EasingStyle.Quad),
				{ CFrame = goalMouth }
			)
			tween:Play()
			tween.Completed:Wait()
			task.wait(0.25)
		end
		team.celebrateUntil = os.clock() + 1.4
		task.wait(1.4)
		ball:Destroy()
		if team.ball == ball then
			team.ball = nil
		end
	end)
end

local function ownPlot(): Model?
	local slot = player:GetAttribute("plotSlot")
	local plots = Workspace:FindFirstChild("Plots")
	local plot = if type(slot) == "number" and plots
		then plots:FindFirstChild("Plot_" .. slot)
		else nil
	return if plot and plot:IsA("Model") then plot else nil
end

local function syncOwnTeam()
	local plot = ownPlot()
	if plot == nil then
		return
	end
	if State.data.fieldStarted then
		ensureTeam(plot, Roster.field(State.data), Config.StadiumTiers[State.data.stadiumTier])
	elseif teams[plot] then
		destroyTeam(teams[plot])
	end
end

function MatchView.init()
	folder = Instance.new("Folder")
	folder.Name = "ClientMatch"
	folder.Parent = Workspace

	Net.on("MatchResult", function(plot: any, info: any)
		if typeof(plot) ~= "Instance" or not plot:IsA("Model") or type(info) ~= "table" then
			return
		end
		playResult(plot, info)
	end)
	State.onChange(syncOwnTeam)

	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		for plot, team in teams do
			-- Other players' pitches are dropped when they have not been used for a while.
			local mine = plot == ownPlot()
			if plot.Parent == nil or (not mine and now - team.lastUsed > OTHER_PLOT_SECONDS) then
				destroyTeam(team)
			elseif nearCamera(team) then
				for _, runner in team.runners do
					if now >= runner.nextTargetAt then
						runner.nextTargetAt = now + 1 + random:NextNumber() * 1.5
						runner.target = runner.home
							+ Vector3.new(
								(random:NextNumber() - 0.5) * 8,
								0,
								(random:NextNumber() - 0.5) * 8
							)
					end
					local offset = runner.target - runner.position
					if offset.Magnitude > 0.2 then
						runner.position += offset.Unit * math.min(SPEED * dt, offset.Magnitude)
					end
					placeRunner(team, runner, now)
				end
			end
		end
	end)
	syncOwnTeam()
end

return MatchView
