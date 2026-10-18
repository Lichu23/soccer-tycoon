--!strict
-- Connects the training ground to the world (docs/PLAN.md, Steps 4 and 7). A loop checks who stands
-- on the training pad (the pad system already publishes each player's padKey), runs the stamina
-- and the TP with Training, and publishes what the HUD shows. The drill sweeps on the server clock:
-- the client draws the bar from `drillStart`, the server judges each press on the same clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Economy = require(script.Parent.Economy)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(script.Parent.Remotes)
local Safe = require(script.Parent.Safe)
local Session = require(script.Parent.Session)
local Training = require(script.Parent.Training)

local TICK_SECONDS = 0.25

type Drill = { startedAt: number, lastRound: number }

local carries: { [Player]: Training.Carry } = {}
local drills: { [Player]: Drill } = {}
local training: { [Player]: boolean } = {} -- on the pad with stamina left, as of the last tick
local started = false

local TrainingActions = {}

local function onPad(session: Session.Session): boolean
	local plot = session.runtime.plot
	if plot == nil or not Progress.trainingUnlocked(session.data) then
		return false
	end
	return session.player:GetAttribute("padKey") == plot.Name .. ":Training"
end

local function step(session: Session.Session, dt: number)
	local player, data = session.player, session.data
	local carry = carries[player]
	if carry == nil then
		carry = Training.newCarry()
		carries[player] = carry
	end

	local standing = onPad(session)
	local paid = Training.step(data, carry, dt, standing)
	local active = standing and Training.hasStamina(data)
	training[player] = active

	-- The drill starts when the player steps onto the pad and ends when they leave it.
	if standing and drills[player] == nil then
		drills[player] = { startedAt = Workspace:GetServerTimeNow(), lastRound = -1 }
	elseif not standing then
		drills[player] = nil
	end

	local drill = drills[player]
	player:SetAttribute("drillStart", if drill then drill.startedAt else 0)
	player:SetAttribute("training", active)
	player:SetAttribute("staminaLeft", math.floor(data.staminaLeft * 10) / 10)
	if paid > 0 then
		Economy.publish(player, data)
	end
end

-- A press of the drill button: judged on the server clock, one press per round counts.
local function drillHit(player: Player)
	local session = Session.get(player)
	local drill = drills[player]
	if session == nil or drill == nil or not training[player] then
		return
	end
	local hit, round =
		Training.judgeHit(drill.startedAt, Workspace:GetServerTimeNow(), drill.lastRound)
	if hit == nil then
		return -- this round was already used
	end
	drill.lastRound = round
	local paid = 0
	if hit then
		local carry = carries[player]
		if carry then
			paid = Training.addDrillHit(session.data, carry)
		end
		if paid > 0 then
			Economy.publish(player, session.data)
		end
	end
	Remotes.fireClient("Notice", player, { kind = "drillResult", hit = hit, round = round })
end

-- Call once, after Remotes.init and Session.init.
function TrainingActions.start()
	assert(not started, "TrainingActions.start called twice")
	started = true
	Remotes.on("TrainingDrillHit", drillHit)
	Players.PlayerRemoving:Connect(function(player)
		carries[player] = nil
		drills[player] = nil
		training[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK_SECONDS)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, session in Session.all() do
				local ok, err = Safe.call(step, session, dt)
				if not ok then
					warn("[TrainingActions] step failed: " .. tostring(err))
				end
			end
		end
	end)
end

return TrainingActions
