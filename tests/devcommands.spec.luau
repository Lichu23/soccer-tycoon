--!nocheck
local T = require("./framework")
local DevCommands = T.load("server/DevCommands")
local Roster = T.load("shared/Roster")
local Config = T.load("shared/Config")
local Validate = T.load("shared/Validate")
local RemoteSpec = T.load("shared/RemoteSpec")
local ProfileSchema = T.load("server/ProfileSchema")

T.suite("dev commands")

T.test("grantFloor gives every player of the floors up to n and starts the matches", function()
	local data = ProfileSchema.newProfile()
	T.eq(DevCommands.apply(data, "grantFloor", 1), true)
	T.eq(Roster.ownedCount(data), 10)
	T.eq(Roster.floorComplete(data, 1), true)
	T.eq(data.fieldStarted, true)
	DevCommands.apply(data, "grantFloor", 2)
	T.eq(Roster.ownedCount(data), 20)
	DevCommands.apply(data, "grantFloor", 3)
	T.eq(Roster.ownedCount(data), 30)
	T.eq(Roster.floorsComplete(data), 3)
end)

T.test("Legends are never granted", function()
	local data = ProfileSchema.newProfile()
	DevCommands.apply(data, "grantFloor", 4)
	T.eq(Roster.ownedCount(data), 30)
	T.eq(Roster.owns(data, "pele"), false)
end)

T.test("setCash sets the cash and clamps to the allowed range", function()
	local data = ProfileSchema.newProfile()
	DevCommands.apply(data, "setCash", 1_000_000)
	T.eq(data.cash, 1_000_000)
	DevCommands.apply(data, "setCash", 1e30)
	T.eq(data.cash, Config.MaxCash)
	DevCommands.apply(data, "setCash", -5)
	T.eq(data.cash, 0)
end)

T.test("resetProfile returns a new profile", function()
	local data = ProfileSchema.newProfile()
	DevCommands.apply(data, "grantFloor", 3)
	DevCommands.apply(data, "setCash", 999)
	data.stadiumTier = 4
	data.storeLevels.offline = 5
	data.flags.milestones.first_match = 1
	T.eq(DevCommands.apply(data, "resetProfile", 0), true)
	T.eq(Roster.ownedCount(data), 0)
	T.eq(data.cash, 15)
	T.eq(data.stadiumTier, 1)
	T.eq(data.storeLevels.offline, 0)
	T.eq(data.flags.milestones.first_match, nil)
	T.eq(data.fieldStarted, false)
	local ok = ProfileSchema.validate(data)
	T.eq(ok, true)
end)

T.test("resetDaily makes the case and the kicks ready again", function()
	local data = ProfileSchema.newProfile()
	data.daily = { caseClaimedAt = 99, penaltyBatchAt = 99, kicksUsed = 3, goals = 2 }
	data.boosts.penaltyBoostLeft = 300
	T.eq(DevCommands.apply(data, "resetDaily", 0), true)
	T.eq(data.daily.caseClaimedAt, 0)
	T.eq(data.daily.kicksUsed, 0)
	T.eq(data.daily.goals, 0)
	T.eq(data.boosts.penaltyBoostLeft, 0)
	local ok = ProfileSchema.validate(data)
	T.eq(ok, true)
end)

T.test(
	"quickStart owns floor 1, ends the level-up tutorial and skips the tour and the kick screen",
	function()
		local data = ProfileSchema.newProfile()
		T.eq(DevCommands.apply(data, "quickStart", 0), true)
		T.eq(Roster.floorComplete(data, 1), true)
		local levelled = 0
		for _, owned in data.players do
			if owned.level > 0 then
				levelled += 1
			end
		end
		T.eq(levelled, 1)
		T.eq(data.flags.hasClaimedPlot, true)
		T.eq(data.flags.tilesSeen.kick, true)
		local ok = ProfileSchema.validate(data)
		T.eq(ok, true)
	end
)

T.test("an unknown command does nothing", function()
	local data = ProfileSchema.newProfile()
	T.eq(DevCommands.apply(data, "explode", 1), false)
	T.eq(data.cash, 15)
end)

T.test("the remote only accepts the known commands and a sane number", function()
	local args = RemoteSpec.remotes.DevCommand.args
	T.eq((Validate.args(args, { "grantFloor", 2 }, 2)), true)
	T.eq((Validate.args(args, { "setCash", 1e12 }, 2)), true)
	T.eq((Validate.args(args, { "playIntro", 1 }, 2)), true)
	T.eq((Validate.args(args, { "explode", 1 }, 2)), false)
	T.eq((Validate.args(args, { "setCash", -1 }, 2)), false)
	T.eq((Validate.args(args, { "setCash", 0 / 0 }, 2)), false)
	T.eq((Validate.args(args, { "setCash", 1e16 }, 2)), false)
end)
