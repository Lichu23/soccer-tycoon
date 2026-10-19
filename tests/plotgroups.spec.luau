--!nocheck
local T = require("./framework")
local PlotGroups = T.load("shared/PlotGroups")

T.suite("private plot groups")

T.test("eight plots need 16 groups, all different and inside the engine limit", function()
	local names = PlotGroups.all(8)
	T.eq(#names, 16)
	local seen = {}
	for _, name in names do
		T.eq(seen[name], nil, name)
		seen[name] = true
	end
	T.truthy(#names < PlotGroups.MAX_GROUPS)
end)

T.test("an owner passes only their own fence", function()
	for index = 1, 8 do
		local owner = PlotGroups.owner(index)
		T.eq(PlotGroups.blocked(owner, index), false)
		T.eq(PlotGroups.blocked(owner, index % 8 + 1), true)
	end
end)

T.test("a visitor in the default group is stopped by every fence", function()
	for index = 1, 8 do
		T.eq(PlotGroups.blocked("Default", index), true)
	end
end)

T.test("the pair that must not collide is the owner and the fence of the same plot", function()
	local owner, fence = PlotGroups.passes(3)
	T.eq(owner, "Owner_3")
	T.eq(fence, "Fence_3")
end)

T.test("the gap is the space between the two front pieces", function()
	local centre, width = PlotGroups.gap(-20, 20)
	T.eq(centre, 0)
	T.eq(width, 40)
	local off, wide = PlotGroups.gap(-10, 30)
	T.eq(off, 10)
	T.eq(wide, 40)
	T.eq(PlotGroups.gap(5, 5), nil)
	T.eq(PlotGroups.gap(10, -10), nil)
end)
