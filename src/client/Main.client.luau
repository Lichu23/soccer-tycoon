--!strict
-- Client bootstrap: starts each module in an explicit order. The client only presents what the
-- server sends and never decides cash, purchases or progress.

local Arrow = require(script.Parent.Arrow)
local Hud = require(script.Parent.Hud)
local MatchView = require(script.Parent.MatchView)
local PadRing = require(script.Parent.PadRing)
local State = require(script.Parent.State)

State.init()
Hud.init()
PadRing.init()
MatchView.init()
Arrow.init()

print("soccer-tycoon client started")
