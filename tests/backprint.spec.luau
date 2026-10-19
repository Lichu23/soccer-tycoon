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
