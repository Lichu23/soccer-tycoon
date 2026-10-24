--!strict
-- Tells a client when one of its pads opens (shared/Unlocks), so it plays the short cinematic that
-- shows where the pad is and what it does. Each unlock goes out once per profile: it is marked in
-- flags.unlocksShown as it is sent. Without a plot there is nothing to point at, so nothing is sent or
-- marked until the player has one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Unlocks = require(ReplicatedStorage.Shared.Unlocks)

local UnlockNotices = {}

-- The world position of the plot's marker for a pad, or nil when the template has none.
local function markerPosition(plot: Instance, kind: string, padId: string): Vector3?
	local markers = plot:FindFirstChild("Markers")
	if markers == nil then
		return nil
	end
	for _, marker in markers:GetChildren() do
		if
			marker:IsA("BasePart")
			and marker:GetAttribute("Kind") == kind
			and marker:GetAttribute("PadId") == padId
		then
			return marker.Position
		end
	end
	return nil
end

-- Sends the unlocks that opened since the last check. Call after anything that changes progress.
function UnlockNotices.check(session: Session.Session)
	local plot = session.runtime.plot
	if plot == nil then
		return
	end
	local shown = session.data.flags.unlocksShown
	for _, unlock in Unlocks.newlyOpen(session.data, shown) do
		shown[unlock.id] = true
		local position = markerPosition(plot, unlock.padKind, unlock.padId)
		if position then
			Remotes.fireClient("Notice", session.player, {
				kind = "unlock",
				id = unlock.id,
				position = position,
			})
		end
	end
end

return UnlockNotices
