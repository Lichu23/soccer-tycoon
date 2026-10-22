--!strict
-- How a Locker room style shows on the pitch (docs/PLAN.md, Step 3). Each slot paints the parts of
-- CourtPlan it names: the crest badge over the gate, the advertising boards, the floodlight heads and
-- the scoreboard. The server paints the owner's choices for everyone (server/Stadium), and the
-- Locker room paints a style the player is looking at on their own screen only, then paints the
-- chosen one back. The kit is drawn on the players by the match (client/MatchView), not here.

local Config = require(script.Parent.Config)

local StadiumLook = {}

-- The parts each slot paints, by CourtPlan name.
StadiumLook.PARTS = {
	crest = { Crest = true },
	banners = { AdBoard = true },
	floodlights = { LightHead = true, LampHead = true },
	scoreboard = { Scoreboard = true },
} :: { [string]: { [string]: boolean } }

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

-- The colour of the `index`th part (from 1) of a slot in style `def`, and its text colour if it has one.
function StadiumLook.colors(def: Config.CosmeticDef, index: number): (Color3, Color3?)
	local pattern = def.pattern
	local body = if pattern and #pattern > 0
		then rgb(pattern[(index - 1) % #pattern + 1])
		else rgb(def.color)
	return body, if def.accent then rgb(def.accent) else nil
end

-- Paints the parts of `slotId` under `court` in style `def`. Parts are counted in the order of the
-- CourtPlan list (the server sets a "PlanIndex" on each), so a pattern alternates the same way on the
-- server and on every client.
function StadiumLook.paint(court: Instance, slotId: string, def: Config.CosmeticDef)
	local names = StadiumLook.PARTS[slotId]
	if names == nil then
		return
	end
	local parts: { BasePart } = {}
	for _, child in court:GetChildren() do
		if child:IsA("BasePart") and names[child.Name] then
			table.insert(parts, child)
		end
	end
	table.sort(parts, function(a, b)
		return (tonumber(a:GetAttribute("PlanIndex")) or 0)
			< (tonumber(b:GetAttribute("PlanIndex")) or 0)
	end)
	for index, part in parts do
		local body, text = StadiumLook.colors(def, index)
		part.Color = body
		local gui = part:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		if label and text then
			label.TextColor3 = text
		end
	end
end

return StadiumLook
