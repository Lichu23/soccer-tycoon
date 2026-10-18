--!strict
-- Connects the training ground to the world (docs/PLAN.md, Steps 4 and 7). A loop checks who stands
-- on the training pad (the pad system already publishes each player's padKey), runs the stamina
-- and the TP with Training, and publishes what the HUD shows. The drill sweeps on the server clock:
-- the client draws the bar from `drillStart`, the server judges each press on the same clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Drill = require(ReplicatedStorage.Shared.Drill)
local Economy = require(script.Parent.Economy)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(script.Parent.Remotes)
local Safe = require(script.Parent.Safe)
local Session = require(script.Parent.Session)
local Training = require(script.Parent.Training)

local TICK_SECONDS = 0.25

local carries: { [Player]: Training.Carry } = {}
local drills: { [Player]: Drill.State } = {}
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

-- The drill state as player attributes, so the client draws the same bar the server judges.
local function publishDrill(player: Player)
	local drill = drills[player]
	if drill then
		Drill.normalize(drill, Workspace:GetServerTimeNow())
	end
	player:SetAttribute("drillPhase", if drill then drill.phase else "off")
	player:SetAttribute("drillStart", if drill then drill.startedAt else 0)
	player:SetAttribute("drillCooldownUntil", if drill then drill.cooldownUntil else 0)
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

	-- The drill exists while the player stands on the pad. It starts stopped (a red bar) and the
	-- first press starts the marker.
	if standing and drills[player] == nil then
		drills[player] = Drill.new()
	elseif not standing then
		drills[player] = nil
	end
	publishDrill(player)
	player:SetAttribute("training", active)
	player:SetAttribute("staminaLeft", math.floor(data.staminaLeft * 10) / 10)
	if paid > 0 then
		Economy.publish(player, data)
	end
end

-- A press of the drill button, judged on the server clock (see Drill for the rules).
local function drillHit(player: Player)
	local session = Session.get(player)
	local drill = drills[player]
	if session == nil or drill == nil or not training[player] then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local outcome = Drill.press(drill, now)
	if outcome == "ignored" then
		return
	end
	local paid = 0
	local carry = carries[player]
	if carry then
		paid = Training.drillPay(session.data, carry, outcome, now)
		if paid > 0 then
			Economy.publish(player, session.data)
		end
	end
	publishDrill(player)
	Remotes.fireClient("Notice", player, {
		kind = "drillResult",
		outcome = outcome,
		paid = paid,
		capped = (outcome == "hit" or outcome == "miss") and paid <= 0,
	})
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
