--!strict
-- Short money text for the HUD: 999, 1.2K, 11.1K, 145K, 1.9M, 6.99B, 15T.
-- Three significant digits at most, trailing zeros removed.

local NumberFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa" }

local function trim(text: string): string
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

-- Rounds to 3 significant digits and returns the text.
local function threeDigits(value: number): string
	if value >= 100 then
		return string.format("%.0f", value)
	elseif value >= 10 then
		return trim(string.format("%.1f", value))
	end
	return trim(string.format("%.2f", value))
end

function NumberFormat.short(amount: number): string
	if amount ~= amount or amount <= 0 then
		return "0"
	end
	local value = amount
	local index = 1
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	local text = threeDigits(value)
	-- Rounding can reach 1000 (999.6K -> 1000K): move up one suffix.
	if tonumber(text) :: number >= 1000 and index < #SUFFIXES then
		index += 1
		text = threeDigits(value / 1000)
	end
	return text .. SUFFIXES[index]
end

function NumberFormat.money(amount: number): string
	return "$" .. NumberFormat.short(amount)
end

-- A length of play from whole minutes: "15 min", "1 hour", "4 hours".
function NumberFormat.minutes(minutes: number): string
	if minutes >= 60 and minutes % 60 == 0 then
		local hours = minutes // 60
		return if hours == 1 then "1 hour" else `{hours} hours`
	end
	return `{minutes} min`
end

return NumberFormat
