--!nocheck
local T = require("./framework")
local ProfileSchema = T.load("server/ProfileSchema")
local TileBadges = T.load("shared/TileBadges")

T.suite("tile badges")

T.test("a new profile has every badge unseen, and tapping saves it for good", function()
	local data = ProfileSchema.newProfile()
	for _, id in TileBadges.ids do
		T.eq(TileBadges.seen(data, id), false)
	end
	T.eq(TileBadges.markSeen(data, "shop"), true)
	T.eq(TileBadges.seen(data, "shop"), true)
	T.eq(TileBadges.seen(data, "case"), false)
	T.eq(ProfileSchema.validate(data), true)
end)

T.test("an unknown button is refused and nothing is saved", function()
	local data = ProfileSchema.newProfile()
	T.eq(TileBadges.markSeen(data, "locker"), false)
	T.eq(next(data.flags.tilesSeen), nil)
end)

T.test("an old profile without the field gets it filled in", function()
	local stored = { version = 1, flags = { notificationAsked = true } }
	ProfileSchema.reconcile(stored, ProfileSchema.newProfile())
	T.eq(TileBadges.seen(stored, "kick"), false)
	T.eq(TileBadges.markSeen(stored, "kick"), true)
end)
