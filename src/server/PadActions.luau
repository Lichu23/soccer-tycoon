--!strict
-- Turns the markers of a plot into pads: the status each one shows and what standing on it does
-- (docs/PLAN.md, Step 7: the template carries markers with a Kind and a PadId from Config).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Actions = require(script.Parent.Actions)
local Pads = require(script.Parent.Pads)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Roster = require(ReplicatedStorage.Shared.Roster)
local Session = require(script.Parent.Session)

local PadActions = {}

-- A builder returns the status and the completion function of a pad, and optionally a function
-- that says whether the pad keeps repeating while the player stays on it (level-up pads do).
type Builder = (
	session: Session.Session,
	part: BasePart,
	padId: string
) -> (() -> string, () -> (), (() -> boolean)?)

local builders: { [string]: Builder } = {
	-- Before a player is owned the pad buys him; afterwards it levels him up with TP, once for
	-- every second the player stays on it.
	player = function(session, _part, padId)
		local function owned(): boolean
			return Roster.owns(session.data, padId)
		end
		return function()
			if owned() then
				local status = Progress.levelStatus(session.data, padId)
				return if status == "ready" or status == "cannotAfford" then status else "owned"
			end
			return Progress.playerStatus(session.data, padId)
		end,
			function()
				if owned() then
					Actions.levelUp(session, padId, nil)
				else
					Actions.buyPlayer(session, padId)
				end
			end,
			owned
	end,
	-- Standing on the training pad is all it takes: TrainingActions watches the player's padKey.
	training = function(_session, _part, _padId)
		return function()
			return "info"
		end, function() end
	end,
	store = function(session, _part, padId)
		local id: any = padId -- the marker's PadId comes from Config
		return function()
			return Progress.storeStatus(session.data, id)
		end, function()
			Actions.buyStore(session, id, nil)
		end
	end,
	stadium = function(session, _part, _padId)
		return function()
			return Progress.stadiumStatus(session.data)
		end, function()
			Actions.upgradeStadium(session, nil)
		end
	end,
}

-- Registers the pads of a freshly placed plot for its owner.
function PadActions.registerPlot(session: Session.Session, plot: Model)
	local markers = plot:FindFirstChild("Markers")
	assert(markers, "plot has no Markers folder")
	for _, part in markers:GetChildren() do
		if part:IsA("BasePart") then
			local kind = part:GetAttribute("Kind")
			local padId = part:GetAttribute("PadId")
			local build = if type(kind) == "string" then builders[kind] else nil
			if build and type(padId) == "string" then
				local status, complete, repeats = build(session, part, padId)
				local pad: Pads.Pad = {
					key = plot.Name .. ":" .. part.Name,
					part = part,
					kind = kind :: string,
					padId = padId,
					owner = session.player,
					repeatable = false,
					status = status,
					complete = complete,
				}
				if repeats then
					-- The pad tracker asks for the status every tick, so this stays current.
					pad.status = function()
						pad.repeatable = repeats()
						return status()
					end
				end
				Pads.register(pad)
			end
		end
	end
end

return PadActions
