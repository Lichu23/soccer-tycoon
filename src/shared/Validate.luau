--!strict
-- Checks a remote payload against its schema. Pure, so it is unit tested.
-- Never trust the client: wrong types, NaN, infinity, fractions where integers are needed,
-- out-of-range values, unknown enum values and extra arguments are all rejected.

local RemoteSpec = require(script.Parent.RemoteSpec)

type FieldSchema = RemoteSpec.FieldSchema

local Validate = {}

local function checkField(schema: FieldSchema, value: any): string?
	if schema.kind == "number" then
		if type(value) ~= "number" then
			return "expected a number"
		end
		-- NaN is the only value that differs from itself; math.huge catches both infinities.
		if value ~= value or value == math.huge or value == -math.huge then
			return "number is not finite"
		end
		if schema.integer and value ~= math.floor(value) then
			return "expected an integer"
		end
		if schema.min and value < schema.min then
			return "number is below the minimum"
		end
		if schema.max and value > schema.max then
			return "number is above the maximum"
		end
	elseif schema.kind == "string" then
		if type(value) ~= "string" then
			return "expected a string"
		end
		local length = utf8.len(value)
		if length == nil then
			return "string is not valid UTF-8"
		end
		if length > schema.maxLength then
			return "string is too long"
		end
	elseif schema.kind == "boolean" then
		if type(value) ~= "boolean" then
			return "expected a boolean"
		end
	elseif schema.kind == "enum" then
		if type(value) ~= "string" or not table.find(schema.values, value) then
			return "value is not one of the allowed ids"
		end
	end
	return nil
end

-- `args` holds the payload, `count` its real length (nil arguments can sit in the middle).
-- Returns true, or false and the reason.
function Validate.args(schemas: { FieldSchema }, args: { any }, count: number): (boolean, string?)
	if count ~= #schemas then
		return false, string.format("expected %d arguments, got %d", #schemas, count)
	end
	for index, schema in schemas do
		local problem = checkField(schema, args[index])
		if problem then
			return false, string.format("argument %d: %s", index, problem)
		end
	end
	return true, nil
end

return Validate
