--!nocheck
local T = require("./framework")
local BackPrint = T.load("shared/BackPrint")

T.suite("back print")

T.test("the surname is everything after the first word, in capitals", function()
	T.eq(BackPrint.surname("Jack Grealish"), "GREALISH")
	T.eq(BackPrint.surname("Kevin De Bruyne"), "DE BRUYNE")
end)

T.test("a one word name is printed whole", function()
	T.eq(BackPrint.surname("Pele"), "PELE")
end)

T.test("a shirt that does not follow the rule has its real name", function()
	T.eq(BackPrint.surname("Son Heung-min"), "SON")
	T.eq(BackPrint.surname("Vinícius Jr"), "VINICIUS JR")
end)

T.test("accents are left off the print", function()
	T.eq(BackPrint.surname("João Félix"), "FELIX")
	T.eq(BackPrint.surname("Rafael Leão"), "LEAO")
	T.eq(BackPrint.surname("Luka Modrić"), "MODRIC")
	T.eq(BackPrint.surname("Lautaro Martínez"), "MARTINEZ")
	T.eq(BackPrint.surname("Kylian Mbappé"), "MBAPPE")
end)
