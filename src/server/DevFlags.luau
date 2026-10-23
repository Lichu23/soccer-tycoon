--!strict
-- Studio-only switches that make playtests faster. Outside Studio every switch is off, so a
-- published game always plays the full intros.
--
-- DevSkipIntros (a Workspace attribute, off unless set to true): no plot tour and no first-match
-- camera, the first stadium upgrade can be skipped like the later ones, and the keepie-uppies and
-- free kicks start without their "get ready" wait. The dev panel can still play the intros. The
-- intros play by default; the dev panel's Quick start skips the opening without this switch.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DevFlags = {}

function DevFlags.skipIntros(): boolean
	return RunService:IsStudio() and Workspace:GetAttribute("DevSkipIntros") == true
end

return DevFlags
