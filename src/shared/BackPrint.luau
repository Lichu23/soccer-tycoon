--!strict
-- What is printed on the back of a shirt. Pure, so it is unit tested.

local BackPrint = {}

-- The surname: everything after the first word, in capitals ("Kevin De Bruyne" is "DE BRUYNE").
function BackPrint.surname(name: string): string
	local rest = string.match(name, "^%S+%s+(.+)$")
	return string.upper(rest or name)
end

return BackPrint
