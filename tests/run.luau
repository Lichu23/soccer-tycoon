--!nocheck
-- Runs every tests/*.spec.luau. Usage from the project root: lune run tests/run

local fs = require("@lune/fs")
local process = require("@lune/process")
local framework = require("./framework")

local specs = {}
for _, entry in fs.readDir("tests") do
	local name = string.match(entry, "^(.+)%.spec%.luau$")
	if name then
		table.insert(specs, name)
	end
end
table.sort(specs)

for _, name in specs do
	local ok, err = pcall(require, "./" .. name .. ".spec")
	if not ok then
		framework.suite(name)
		framework.test("load spec file", function()
			error(err, 0)
		end)
	end
end

local stats = framework.stats()
print(string.format("%d passed, %d failed (%d spec files)", stats.passed, stats.failed, #specs))
if stats.failed > 0 then
	for _, failure in stats.failures do
		print("  FAIL " .. failure)
	end
	process.exit(1)
end
