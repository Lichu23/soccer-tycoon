--!nocheck
local T = require("./framework")
local Formation = T.load("shared/Formation")

T.suite("formation")

local LENGTH, WIDTH = 60, 36

T.test("there is one spot for every player", function()
	for count = 1, 11 do
		T.eq(#Formation.spots(count, LENGTH, WIDTH, -1), count, "team of " .. count)
	end
end)

T.test("a team stays in its own half, inside the court", function()
	for count = 1, 11 do
		for _, spot in Formation.spots(count, LENGTH, WIDTH, -1) do
			T.truthy(spot.x < 0 and spot.x >= -LENGTH / 2, "our x for " .. count)
			T.truthy(math.abs(spot.z) <= WIDTH / 2, "our z for " .. count)
		end
		for _, spot in Formation.spots(count, LENGTH, WIDTH, 1) do
			T.truthy(spot.x > 0 and spot.x <= LENGTH / 2, "their x for " .. count)
		end
	end
end)

T.test("the opponents mirror our team", function()
	local ours = Formation.spots(4, LENGTH, WIDTH, -1)
	local theirs = Formation.spots(4, LENGTH, WIDTH, 1)
	for index, spot in ours do
		T.near(theirs[index].x, -spot.x)
		T.near(theirs[index].z, spot.z)
	end
end)

T.test("no two players share a spot", function()
	for count = 1, 11 do
		local seen = {}
		for _, spot in Formation.spots(count, LENGTH, WIDTH, -1) do
			local key = string.format("%.2f,%.2f", spot.x, spot.z)
			T.falsy(seen[key], "duplicate spot for " .. count)
			seen[key] = true
		end
	end
end)

T.test("counts outside 1 to 11 are clamped", function()
	T.eq(#Formation.spots(0, LENGTH, WIDTH, -1), 1)
	T.eq(#Formation.spots(40, LENGTH, WIDTH, -1), 11)
end)
