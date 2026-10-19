--!strict
-- Client bootstrap: starts each module in an explicit order. The client only presents what the
-- server sends and never decides cash, purchases or progress.

local Arrow = require(script.Parent.Arrow)
local DailyUi = require(script.Parent.DailyUi)
local DevPanel = require(script.Parent.DevPanel)
local GateLabels = require(script.Parent.GateLabels)
local Hud = require(script.Parent.Hud)
local LegendPanels = require(script.Parent.LegendPanels)
local MatchView = require(script.Parent.MatchView)
local PadRing = require(script.Parent.PadRing)
local Reveal = require(script.Parent.Reveal)
local SeasonUi = require(script.Parent.SeasonUi)
local StadiumCinematic = require(script.Parent.StadiumCinematic)
local TrainingUi = require(script.Parent.TrainingUi)
local State = require(script.Parent.State)

State.init()
Hud.init()
PadRing.init()
MatchView.init()
Arrow.init()
GateLabels.init()
LegendPanels.init()
StadiumCinematic.init()
Reveal.init()
SeasonUi.init()
DailyUi.init()
TrainingUi.init()
DevPanel.init()

print("soccer-tycoon client started")
