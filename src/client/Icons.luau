--!strict
-- The uploaded images for the HUD icons (docs/PLAN.md, Step 8, art). An empty id means no image yet,
-- and the icon shows its text label instead. To add one, upload a 256x256 PNG with transparent
-- background to the experience's account, copy the asset id and paste "rbxassetid://<id>" here.

local Icons = {}

-- The button names (case, kick, shop, locker, alerts) are full tiles: the picture is the whole
-- button. cash and tp are tiles too: the picture takes the place of the round badge of the money and TP
-- boxes (with no id there, the box shows a round badge with a letter).
-- trophy is the matching Season tile (not used by the New Season button yet).
Icons.ids = {
	case = "rbxassetid://89821955704110",
	kick = "rbxassetid://130401600402467",
	shop = "rbxassetid://118445232324314",
	locker = "rbxassetid://98567241028930",
	alerts = "rbxassetid://80620190525696",
	cash = "rbxassetid://119841301152540",
	tp = "rbxassetid://118070040795011",
	trophy = "rbxassetid://78532583067328",
} :: { [string]: string }

function Icons.id(name: string): string
	return Icons.ids[name] or ""
end

return Icons
