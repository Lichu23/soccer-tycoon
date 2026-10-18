--!nocheck
local T = require("./framework")
local NumberFormat = T.load("shared/NumberFormat")

T.suite("number format")

T.test("small amounts show as whole numbers", function()
	T.eq(NumberFormat.short(0), "0")
	T.eq(NumberFormat.short(5), "5")
	T.eq(NumberFormat.short(15), "15")
	T.eq(NumberFormat.short(999), "999")
end)

T.test("thousands, millions, billions and trillions", function()
	T.eq(NumberFormat.short(1_000), "1K")
	T.eq(NumberFormat.short(1_300), "1.3K")
	T.eq(NumberFormat.short(11_100), "11.1K")
	T.eq(NumberFormat.short(145_000), "145K")
	T.eq(NumberFormat.short(1_900_000), "1.9M")
	T.eq(NumberFormat.short(6_990_000_000), "6.99B")
	T.eq(NumberFormat.short(2_500_000_000_000), "2.5T")
	T.eq(NumberFormat.short(15_000_000_000_000), "15T")
end)

T.test("amounts that round up move to the next suffix", function()
	T.eq(NumberFormat.short(999.6), "1K")
	T.eq(NumberFormat.short(999_600), "1M")
	T.eq(NumberFormat.short(999_950_000), "1B")
end)

T.test("the largest cash value still reads well", function()
	T.eq(NumberFormat.short(9_000_000_000_000_000), "9Qa")
end)

T.test("bad input shows zero", function()
	T.eq(NumberFormat.short(-5), "0")
	T.eq(NumberFormat.short(0 / 0), "0")
end)

T.test("money adds a dollar sign", function()
	T.eq(NumberFormat.money(250), "$250")
	T.eq(NumberFormat.money(45_000_000), "$45M")
end)
