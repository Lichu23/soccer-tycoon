--!strict
-- Turns the markers of a plot into pads: the status each one shows and what standing on it does
-- (docs/PLAN.md, Step 7: the template carries markers with a Kind and a PadId from Config).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Actions = require(script.Parent.Actions)
local Pads = require(script.Parent.Pads)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Session = require(script.Parent.Session)

local PadActions = {}

type Builder = (session: Session.Session, part: BasePart, padId: string) -> (() -> string, () -> ())

-- Each builder returns the status function and the completion function of a pad.
local builders: { [string]: Builder } = {
	player = function(session, _part, padId)
		return function()
			return Progress.playerStatus(session.data, padId)
		end, function()
			Actions.buyPlayer(session, padId)
		end
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
				local status, complete = build(session, part, padId)
				Pads.register({
					key = plot.Name .. ":" .. part.Name,
					part = part,
					kind = kind :: string,
					padId = padId,
					owner = session.player,
					repeatable = false,
					status = function()
						return status()
					end,
					complete = function()
						complete()
					end,
				})
			end
		end
	end
end

return PadActions
