--!strict
-- Every remote the game uses, in one place (docs/PLAN.md, Step 5). The server builds the
-- RemoteEvents from this list, validates every client payload against it and rate limits it.
-- Actions in the world (buying on a pad, claiming a plot) are server-timed pads and need no
-- remote.

local Config = require(script.Parent.Config)

export type FieldSchema =
	{ kind: "number", min: number?, max: number?, integer: boolean? }
	| { kind: "string", maxLength: number }
	| { kind: "boolean" }
	| { kind: "enum", values: { string } }

export type RemoteDef = {
	direction: "toServer" | "toClient",
	args: { FieldSchema }, -- positional arguments after the player; a payload may not have extras
	ratePerSecond: number?, -- sustained requests per player (toServer only)
	burst: number?, -- extra requests allowed at once
	cooldownSeconds: number?, -- minimum time between accepted calls per player
}

local storeIds: { string } = {}
for id in Config.Store do
	table.insert(storeIds, id)
end
table.sort(storeIds)

local RemoteSpec = {}

-- Provisional aim zones for the daily penalty kick (Step 7 decides the final layout).
RemoteSpec.aimZones = {
	"topLeft",
	"topCenter",
	"topRight",
	"bottomLeft",
	"bottomCenter",
	"bottomRight",
} :: { string }

local ID_FIELD: FieldSchema = { kind = "string", maxLength = 40 }

RemoteSpec.remotes = {
	-- Client to server
	ClientReady = {
		direction = "toServer",
		args = {},
		ratePerSecond = 0.2,
		burst = 2,
	},
	UpgradeStadium = {
		direction = "toServer",
		-- The tier the client saw, so a double tap cannot buy two tiers.
		args = { { kind = "number", min = 1, max = #Config.StadiumTiers, integer = true } },
		ratePerSecond = 1,
		burst = 2,
	},
	BuyStoreUpgrade = {
		direction = "toServer",
		-- The upgrade id and the level the client saw.
		args = {
			{ kind = "enum", values = storeIds },
			{ kind = "number", min = 0, max = 20, integer = true },
		},
		ratePerSecond = 2,
		burst = 3,
	},
	ClaimDaily = {
		direction = "toServer",
		args = { { kind = "enum", values = { "case" } } },
		ratePerSecond = 0.5,
		burst = 2,
	},
	PenaltyKick = {
		direction = "toServer",
		args = { { kind = "enum", values = RemoteSpec.aimZones } },
		ratePerSecond = 1,
		burst = 2,
	},
	SetCosmetic = {
		direction = "toServer",
		-- The slot (kit, crest, ...) and an option id from Config.
		args = { { kind = "string", maxLength = 24 }, ID_FIELD },
		ratePerSecond = 2,
		burst = 4,
	},
	StartNewSeason = {
		direction = "toServer",
		-- The season number the client saw, so a double tap cannot reset twice.
		args = { { kind = "number", min = 1, max = 9999, integer = true } },
		ratePerSecond = 0.5,
		burst = 1,
	},
	TrainingDrillHit = {
		direction = "toServer",
		args = {},
		ratePerSecond = 5,
		burst = 5,
	},
	RequestPurchase = {
		direction = "toServer",
		-- A product key from Config. The server decides whether to show the Robux prompt.
		args = { ID_FIELD },
		ratePerSecond = 0.5,
		burst = 2,
	},
	-- Test shortcuts for Studio playtests (grant floors, set cash, reset). The server registers a
	-- handler only while running in Studio, so this does nothing in a published game.
	DevCommand = {
		direction = "toServer",
		args = {
			{
				kind = "enum",
				values = { "grantFloor", "setCash", "resetProfile", "simulateAway", "stadiumUp" },
			},
			{ kind = "number", min = 0, max = 1e15 },
		},
		ratePerSecond = 5,
		burst = 5,
	},
	AckReveal = {
		direction = "toServer",
		args = { ID_FIELD },
		ratePerSecond = 2,
		burst = 4,
	},

	-- Server to client
	Snapshot = { direction = "toClient", args = {} },
	Delta = { direction = "toClient", args = {} },
	MatchResult = { direction = "toClient", args = {} },
	Reveal = { direction = "toClient", args = {} },
	StadiumUpgraded = { direction = "toClient", args = {} },
	Notice = { direction = "toClient", args = {} },
} :: { [string]: RemoteDef }

return RemoteSpec
