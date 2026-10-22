--!strict
-- The uploaded images for the HUD icons (docs/PLAN.md, Step 8, art). An empty id means no image yet,
-- and the icon shows its text label instead. To add one, upload a 256x256 PNG with transparent
-- background to the experience's account, copy the asset id and paste "rbxassetid://<id>" here.

local Icons = {}

-- The button names (case, kick, shop, locker, alerts) are full tiles: the picture is the whole
-- button. cash and tp are tiles too: the picture takes the place of the round badge of the money and TP
-- boxes (with no id there, the box shows a round badge with a letter).
-- trophy is the matching Season tile (not used by the New Season button yet). stadium is the tile
-- next to the match timer, over the stadium tier.
Icons.ids = {
	case = "rbxassetid://89821955704110",
	kick = "rbxassetid://130401600402467",
	shop = "rbxassetid://118445232324314",
	locker = "rbxassetid://98567241028930",
	alerts = "rbxassetid://80620190525696",
	cash = "rbxassetid://119841301152540",
	tp = "rbxassetid://123384829300834", -- "TP" lettering, drawn by tools/kits/make (icon_tp)
	trophy = "rbxassetid://78532583067328",
	stadium = "rbxassetid://108981510454492", -- the full tile (the stadium on its pink tile)
	stadium_picture = "rbxassetid://83668493928617", -- the same stadium without a tile, not used yet
	-- Priority 2 tiles: the Shop and Locker rows and the boost badge. The four store tiles
	-- (cash per match, match speed, hat-trick, offline) wait for a screen that lists the upgrades.
	boost = "rbxassetid://105120001433741",
	case_standard = "rbxassetid://94582616552217",
	case_elite = "rbxassetid://120989645259700",
	store_cash = "rbxassetid://74944480644094",
	store_speed = "rbxassetid://137959507635232",
	store_hattrick = "rbxassetid://122151226082113",
	store_offline = "rbxassetid://98470084289543",
	slot_kit = "rbxassetid://85241712062584",
	slot_crest = "rbxassetid://125907228919138",
	slot_banners = "rbxassetid://134767133460346",
	slot_lamps = "rbxassetid://111556608763634", -- the floodlight models
	slot_floodlights = "rbxassetid://135541995662083", -- the light colour (tools/art/light_icon.py)
	slot_scoreboard = "rbxassetid://128404299109983",
	slot_stadium = "rbxassetid://108981510454492", -- the same tile as the HUD stadium
} :: { [string]: string }

function Icons.id(name: string): string
	return Icons.ids[name] or ""
end

return Icons
