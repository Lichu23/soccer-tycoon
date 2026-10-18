--!strict
-- Client bootstrap: starts each module in an explicit order. The client only presents what the
-- server sends and never decides cash, purchases or progress.

local Arrow = require(script.Parent.Arrow)
local DevPanel = require(script.Parent.DevPanel)
local GateLabels = require(script.Parent.GateLabels)
local Hud = require(script.Parent.Hud)
local MatchView = require(script.Parent.MatchView)
local PadRing = require(script.Parent.PadRing)
local StadiumCinematic = require(script.Parent.StadiumCinematic)
local State = require(script.Parent.State)

State.init()
Hud.init()
PadRing.init()
MatchView.init()
Arrow.init()
GateLabels.init()
StadiumCinematic.init()
DevPanel.init()

print("soccer-tycoon client started")
