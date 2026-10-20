--!strict
-- What is printed on the back of a shirt. Pure, so it is unit tested.

local BackPrint = {}

-- Players whose shirt does not carry the words after their first name.
local SHIRT_NAMES: { [string]: string } = {
	["Son Heung-min"] = "SON",
	["Vinícius Jr"] = "VINICIUS JR",
}

-- Shirts are printed without accents, and string.upper leaves accented letters as they are.
local PLAIN_LETTERS: { [string]: string } = {
	["á"] = "A",
	["ã"] = "A",
	["é"] = "E",
	["í"] = "I",
	["ć"] = "C",
	["ú"] = "U",
	["ó"] = "O",
	["Á"] = "A",
	["É"] = "E",
	["Í"] = "I",
	["Ć"] = "C",
	["Ó"] = "O",
	["Ú"] = "U",
}

-- The surname: everything after the first word, in capitals ("Kevin De Bruyne" is "DE BRUYNE").
function BackPrint.surname(name: string): string
	local shirt = SHIRT_NAMES[name]
	if shirt then
		return shirt
	end
	local rest = string.match(name, "^%S+%s+(.+)$")
	local plain = string.gsub(rest or name, utf8.charpattern, function(char)
		return PLAIN_LETTERS[char]
	end)
	return string.upper(plain)
end

return BackPrint
