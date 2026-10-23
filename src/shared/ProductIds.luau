--!strict
-- The Developer Product id of every Robux product, by its key in Config.Products. Each one is
-- created by hand on the Creator Dashboard (Monetization → Developer Products) with the price that
-- Config shows on the button, and its id is pasted here. 0 means not created yet: Studio then
-- simulates the purchase, and a live server refuses it (and warns at start). A test checks that
-- every product has an entry here.

return {
	caseStandard = 0,
	caseElite = 0,

	legend_ronaldinho = 0,
	legend_zidane = 0,
	legend_ronaldo_nazario = 0,
	legend_maradona = 0,
	legend_pele = 0,

	cash_small = 0,
	cash_medium = 0,
	cash_large = 0,
	tp_small = 0,
	tp_medium = 0,
	tp_large = 0,

	boost_cash = 0,
	boost_tp = 0,
	boost_both = 0,

	cosmetic_kit_gold = 0,
	cosmetic_kit_black = 0,
	cosmetic_crest_crown = 0,
	cosmetic_crest_flame = 0,
	cosmetic_banners_gold = 0,
	cosmetic_banners_neon = 0,
	cosmetic_lamps_halo = 0,
	cosmetic_lamps_gold = 0,
	cosmetic_floodlights_aurora = 0,
	cosmetic_floodlights_rose = 0,
	cosmetic_scoreboard_gold = 0,
	cosmetic_scoreboard_crystal = 0,
	cosmetic_stadium_gold = 0,
	cosmetic_stadium_midnight = 0,
} :: { [string]: number }
