--!nocheck
local T = require("./framework")
local Economy = T.load("server/Economy")
local Config = T.load("shared/Config")

T.suite("economy")

T.test("spending takes the cash, and exactly the balance is enough", function()
	local wallet = { cash = 100, tp = 0 }
	T.eq(Economy.spend(wallet, 30), true)
	T.eq(wallet.cash, 70)
	T.eq(Economy.spend(wallet, 70), true)
	T.eq(wallet.cash, 0)
end)

T.test("a spend that is too big changes nothing", function()
	local wallet = { cash = 10, tp = 0 }
	T.eq(Economy.spend(wallet, 11), false)
	T.eq(wallet.cash, 10)
end)

T.test("cash can never go negative", function()
	local wallet = { cash = 5, tp = 0 }
	T.eq(Economy.spend(wallet, 5), true)
	T.eq(Economy.spend(wallet, 1), false)
	T.eq(wallet.cash, 0)
end)

T.test("invalid amounts are refused", function()
	local wallet = { cash = 100, tp = 0 }
	T.eq(Economy.spend(wallet, -5), false)
	T.eq(Economy.spend(wallet, 0 / 0), false)
	T.eq(Economy.spend(wallet, math.huge), false)
	T.eq(Economy.spend(wallet, "5"), false)
	T.eq(wallet.cash, 100)
	T.eq(Economy.grant(wallet, -5), 0)
	T.eq(Economy.grant(wallet, 0 / 0), 0)
	T.eq(Economy.grant(wallet, math.huge), 0)
	T.eq(wallet.cash, 100)
end)

T.test("a free price of zero is allowed", function()
	local wallet = { cash = 0, tp = 0 }
	T.eq(Economy.spend(wallet, 0), true)
end)

T.test("two spends that together are too much cannot both pass", function()
	local wallet = { cash = 100, tp = 0 }
	local first = Economy.spend(wallet, 80)
	local second = Economy.spend(wallet, 80)
	T.eq(first, true)
	T.eq(second, false)
	T.eq(wallet.cash, 20)
end)

T.test("a grant adds cash and returns what was added", function()
	local wallet = { cash = 10, tp = 0 }
	T.eq(Economy.grant(wallet, 25), 25)
	T.eq(wallet.cash, 35)
end)

T.test("a grant stops at the maximum cash", function()
	local wallet = { cash = Config.MaxCash - 5, tp = 0 }
	T.eq(Economy.grant(wallet, 100), 5)
	T.eq(wallet.cash, Config.MaxCash)
	T.eq(Economy.grant(wallet, 100), 0)
end)

T.test("training points are granted separately", function()
	local wallet = { cash = 0, tp = 5 }
	T.eq(Economy.grantTp(wallet, 10), 10)
	T.eq(wallet.tp, 15)
	T.eq(Economy.grantTp(wallet, -1), 0)
end)

T.test("canAfford", function()
	local wallet = { cash = 50, tp = 0 }
	T.eq(Economy.canAfford(wallet, 50), true)
	T.eq(Economy.canAfford(wallet, 51), false)
	T.eq(Economy.canAfford(wallet, -1), false)
end)

T.test("publish mirrors the wallet to attributes", function()
	local attributes = {}
	local player = {
		SetAttribute = function(_, name, value)
			attributes[name] = value
		end,
	}
	Economy.publish(player, { cash = 42, tp = 7 })
	T.eq(attributes.cash, 42)
	T.eq(attributes.tp, 7)
end)
