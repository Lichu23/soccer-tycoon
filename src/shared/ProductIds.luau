--!strict
-- The Developer Product id of every Robux product, by its key in Config.Products. Each one is
-- created by hand on the Creator Dashboard (Monetization → Developer Products) with the price that
-- Config shows on the button, and its id is pasted here. 0 means not created yet: Studio then
-- simulates the purchase, and a live server refuses it (and warns at start). A test checks that
-- every product has an entry here.

return {
	caseStandard = 3721865336,
	caseElite = 3721865519,

	legend_ronaldinho = 3721865656,
	legend_zidane = 3721865804,
	legend_ronaldo_nazario = 3721865893,
	legend_maradona = 3721865977,
	legend_pele = 3721866081,

	cash_small = 3721866211,
	cash_medium = 3721866264,
	cash_large = 3721866370,
	tp_small = 3721866479,
	tp_medium = 3721866669,
	tp_large = 3721866731,

	boost_cash = 3721866871,
	boost_tp = 3721866956,
	boost_both = 3721867030,

	cosmetic_kit_gold = 3721867596,
	cosmetic_kit_black = 3721867682,
	cosmetic_crest_crown = 3721867748,
	cosmetic_crest_flame = 3721867803,
	cosmetic_banners_gold = 3721867880,
	cosmetic_banners_neon = 3721867923,
	cosmetic_lamps_halo = 3721867988,
	cosmetic_lamps_gold = 3721868058,
	cosmetic_floodlights_aurora = 3721868164,
	cosmetic_floodlights_rose = 3721868344,
	cosmetic_scoreboard_gold = 3721868417,
	cosmetic_scoreboard_crystal = 3721868515,
	cosmetic_stadium_gold = 3721869833,
	cosmetic_stadium_midnight = 3721869929,
} :: { [string]: number }
