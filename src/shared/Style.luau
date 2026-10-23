--!strict
-- Colours and text sizes used by the HUD and the pads (provisional, docs/PLAN.md Step 7). Rarity
-- colours also tint the capsule glass and the player kits.

local Style = {}

Style.rarityColors = {
	Common = Color3.fromRGB(205, 205, 210),
	Rare = Color3.fromRGB(70, 130, 220),
	VeryRare = Color3.fromRGB(150, 90, 220),
	Epic = Color3.fromRGB(240, 190, 50),
	Legend = Color3.fromRGB(240, 90, 90),
} :: { [string]: Color3 }

Style.rarityNames = {
	Common = "Common",
	Rare = "Rare",
	VeryRare = "Very Rare",
	Epic = "Epic",
	Legend = "Legend",
} :: { [string]: string }

Style.ui = {
	text = Color3.fromRGB(255, 255, 255),
	dark = Color3.fromRGB(20, 24, 35),
	panel = Color3.fromRGB(32, 38, 56),
	money = Color3.fromRGB(120, 235, 140),
	good = Color3.fromRGB(80, 220, 120),
	bad = Color3.fromRGB(255, 120, 120),
	idle = Color3.fromRGB(170, 175, 190),
	gold = Color3.fromRGB(255, 205, 60),
	bar = Color3.fromRGB(90, 170, 255),
	purple = Color3.fromRGB(150, 90, 220), -- the Very Rare colour, the Seasons leaderboard accent
}

Style.font = Enum.Font.GothamBold

return Style
