--!strict
-- Every remote the game uses, in one place (docs/PLAN.md, Step 5). The server builds the
-- RemoteEvents from this list, validates every client payload against it and rate limits it.
-- Actions in the world (buying on a pad, claiming a plot) are server-timed pads and need no
-- remote.

local Config = require(script.Parent.Config)
local TileBadges = require(script.Parent.TileBadges)

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

-- The five aim targets of the daily penalty kick: the four corners of the goal and the middle.
RemoteSpec.aimZones = {
	"topLeft",
	"topRight",
	"bottomLeft",
	"bottomRight",
	"center",
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
	SetNotifications = {
		direction = "toServer",
		args = { { kind = "boolean" } },
		ratePerSecond = 1,
		burst = 2,
	},
	SeenTile = {
		direction = "toServer",
		args = { { kind = "enum", values = TileBadges.ids } },
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
	-- A tap at a skill station of the Training Gym (the keepie-uppies). The server judges it on its own
	-- clock; no argument.
	TrainingTap = {
		direction = "toServer",
		args = {},
		ratePerSecond = 6,
		burst = 6,
	},
	-- A tap on the bar of the free kicks (it sets the power, or the aim and kicks) and the server time
	-- the player's screen showed when he tapped (the server never trusts it more than a fraction of a
	-- second into the past).
	FreekickTap = {
		direction = "toServer",
		args = { { kind = "number", min = 0, max = 4_000_000_000 } },
		ratePerSecond = 6,
		burst = 6,
	},
	-- A tap on the ball of the free kicks: the contact point, each axis -1 to 1.
	FreekickContact = {
		direction = "toServer",
		args = {
			{ kind = "number", min = -1, max = 1 },
			{ kind = "number", min = -1, max = 1 },
		},
		ratePerSecond = 6,
		burst = 6,
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
				values = {
					"grantFloor",
					"setCash",
					"resetProfile",
					"simulateAway",
					"stadiumUp",
					"resetDaily",
					"grantTp",
					"revealRarity",
					"offerWait",
					"playIntro",
				},
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
	MatchStarted = { direction = "toClient", args = {} },
	MatchResult = { direction = "toClient", args = {} },
	Reveal = { direction = "toClient", args = {} },
	StadiumUpgraded = { direction = "toClient", args = {} },
	SeasonStarted = { direction = "toClient", args = {} },
	Notice = { direction = "toClient", args = {} },
} :: { [string]: RemoteDef }

return RemoteSpec
