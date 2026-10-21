--!nocheck
local T = require("./framework")
local Validate = T.load("shared/Validate")
local RemoteSpec = T.load("shared/RemoteSpec")
local Config = T.load("shared/Config")

T.suite("validate")

local function check(schemas, ...)
	return Validate.args(schemas, { ... }, select("#", ...))
end

local TIER = { { kind = "number", min = 1, max = 5, integer = true } }

T.test("a good payload passes", function()
	T.eq((check(TIER, 3)), true)
end)

T.test("numbers: wrong type, NaN, infinity, fraction and range are rejected", function()
	T.eq((check(TIER, "3")), false)
	T.eq((check(TIER, nil)), false)
	T.eq((check(TIER, 0 / 0)), false)
	T.eq((check(TIER, math.huge)), false)
	T.eq((check(TIER, -math.huge)), false)
	T.eq((check(TIER, 2.5)), false)
	T.eq((check(TIER, 0)), false)
	T.eq((check(TIER, 6)), false)
	T.eq((check(TIER, 1)), true)
	T.eq((check(TIER, 5)), true)
end)

T.test("strings: type, length and UTF-8", function()
	local schema = { { kind = "string", maxLength = 5 } }
	T.eq((check(schema, "abcde")), true)
	T.eq((check(schema, "abcdef")), false)
	T.eq((check(schema, 12)), false)
	T.eq((check(schema, "\255\254")), false) -- not valid UTF-8
	T.eq((check(schema, "João")), true) -- 4 characters, 5 bytes
end)

T.test("enums only accept the listed ids", function()
	local schema = { { kind = "enum", values = { "case" } } }
	T.eq((check(schema, "case")), true)
	T.eq((check(schema, "Case")), false)
	T.eq((check(schema, "other")), false)
	T.eq((check(schema, 1)), false)
end)

T.test("booleans", function()
	local schema = { { kind = "boolean" } }
	T.eq((check(schema, true)), true)
	T.eq((check(schema, "true")), false)
end)

T.test("the number of arguments must match exactly", function()
	T.eq((check({}, 1)), false) -- extra argument
	T.eq((check(TIER)), false) -- missing argument
	T.eq((check(TIER, 1, 2)), false)
	T.eq((check({})), true)
end)

T.test("a reason is returned for a rejected payload", function()
	local ok, reason = check(TIER, "x")
	T.eq(ok, false)
	T.truthy(reason and #reason > 0)
end)

T.test("a table or function is never a valid value", function()
	T.eq((check(TIER, {})), false)
	T.eq((check(TIER, function() end)), false)
end)

T.suite("remote spec")

local CLIENT_TO_SERVER = {
	"ClientReady",
	"UpgradeStadium",
	"BuyStoreUpgrade",
	"ClaimDaily",
	"PenaltyKick",
	"SetCosmetic",
	"SetNotifications",
	"StartNewSeason",
	"TrainingTap",
	"FreekickTap",
	"FreekickContact",
	"RequestPurchase",
	"AckReveal",
	"DevCommand",
}

T.test(
	"the client-to-server remotes (the eleven of Step 5, the three of the Training Gym) and the Studio-only DevCommand exist",
	function()
		local count = 0
		for name, def in RemoteSpec.remotes do
			if def.direction == "toServer" then
				count += 1
			end
		end
		T.eq(count, 15)
		for _, name in CLIENT_TO_SERVER do
			local def = RemoteSpec.remotes[name]
			T.truthy(def, name .. " is missing")
			T.eq(def.direction, "toServer", name)
		end
	end
)

T.test("every client-to-server remote has a rate limit and valid arguments", function()
	for name, def in RemoteSpec.remotes do
		if def.direction == "toServer" then
			T.truthy(def.ratePerSecond and def.ratePerSecond > 0, name .. " ratePerSecond")
			T.truthy(def.burst and def.burst >= 1, name .. " burst")
			for _, schema in def.args do
				T.truthy(
					schema.kind == "number"
						or schema.kind == "string"
						or schema.kind == "boolean"
						or schema.kind == "enum",
					name .. " schema kind"
				)
			end
		end
	end
end)

T.test("the store upgrade enum matches Config", function()
	local schema = RemoteSpec.remotes.BuyStoreUpgrade.args[1]
	T.eq(schema.kind, "enum")
	T.eq(#schema.values, 3)
	for id in Config.Store do
		T.truthy(table.find(schema.values, id), id .. " is in the enum")
	end
end)

T.test("the stadium upgrade accepts only real tiers", function()
	local args = RemoteSpec.remotes.UpgradeStadium.args
	T.eq((Validate.args(args, { 2 }, 1)), true)
	T.eq((Validate.args(args, { 6 }, 1)), false)
	T.eq((Validate.args(args, { 2.5 }, 1)), false)
end)

T.test("a forged payload for every remote is rejected", function()
	-- Each client-to-server remote refuses a table and a wrong argument count.
	for name, def in RemoteSpec.remotes do
		if def.direction == "toServer" then
			T.eq((Validate.args(def.args, { {}, {}, {}, {}, {} }, 5)), false, name .. " extra args")
			if #def.args > 0 then
				T.eq((Validate.args(def.args, { {} }, #def.args)), false, name .. " table arg")
			end
		end
	end
end)
