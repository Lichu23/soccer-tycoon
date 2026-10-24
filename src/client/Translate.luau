--!strict
-- Texts built in code from a template with `{1}` pieces, in the player's language, for the labels
-- Roblox's automatic translation does not swap: rich text (with <font> tags). The template is an
-- entry of the localization table (tools/localization); it is translated whole, then the pieces
-- go in. English until the translator has loaded; `onReady` redraws a label once it has.

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Translate = {}

local translator: Translator? = nil
local waiting: { () -> () } = {}

function Translate.init()
	task.spawn(function()
		local ok, result = pcall(function(): Translator
			return LocalizationService:GetTranslatorForPlayerAsync(Players.LocalPlayer)
		end)
		if not ok then
			-- (a place file that was never published has none: Studio playtests stay in English)
			if not RunService:IsStudio() then
				warn("[Translate] no translator:", result)
			end
			return
		end
		translator = result
		for _, callback in waiting do
			task.spawn(callback)
		end
		table.clear(waiting)
	end)
end

-- Runs `callback` once the translator has loaded (never when it already has).
function Translate.onReady(callback: () -> ())
	if translator == nil then
		table.insert(waiting, callback)
	end
end

-- `template` in the player's language with `{n}` replaced by the n-th of the pieces.
function Translate.format(template: string, ...: any): string
	local text = template
	local current = translator
	if current then
		local ok, result = pcall(current.Translate, current, game, template)
		if ok then
			text = result
		end
	end
	local pieces = table.pack(...)
	return (string.gsub(text, "{(%d+)}", function(index: string): string?
		local piece = pieces[tonumber(index) :: number]
		return if piece ~= nil then tostring(piece) else nil
	end))
end

return Translate
