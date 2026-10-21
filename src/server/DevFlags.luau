--!strict
-- Studio-only switches that make playtests faster. Outside Studio every switch is off, so a
-- published game always plays the full intros.
--
-- DevSkipIntros (a Workspace attribute, on unless set to false): no plot tour and no first-match
-- camera, the first stadium upgrade can be skipped like the later ones, and the keepie-uppies and
-- free kicks start without their "get ready" wait. The dev panel can still play the intros.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DevFlags = {}

function DevFlags.skipIntros(): boolean
	return RunService:IsStudio() and Workspace:GetAttribute("DevSkipIntros") ~= false
end

return DevFlags
