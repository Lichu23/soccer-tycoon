--!strict
-- pcall for functions that return nothing: the plain pcall type says such a call has no second
-- value, which the type checker rejects when the error message is read.

local Safe = {}

-- Returns true, or false and the error message.
function Safe.call(fn: (...any) -> ...any, ...: any): (boolean, any)
	local results = table.pack(pcall(fn, ...))
	return results[1] :: boolean, results[2]
end

return Safe
