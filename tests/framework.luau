--!nocheck
-- Minimal test framework and module loader for Lune (no Studio needed).
-- Modules under src/ keep their normal Roblox requires (script.Parent.X and
-- game:GetService("ReplicatedStorage").Shared.X); the loader below fakes just enough of
-- `script`, `game` and `require` to run the pure ones outside Studio.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Framework = {}

local SRC = "src"
local moduleCache: { [string]: any } = {}
local dirCache: { [string]: any } = {}

local stats = { passed = 0, failed = 0, failures = {} :: { string } }
local currentSuite = ""

-- Loader ---------------------------------------------------------------------------------

-- Lune's file functions yield, and a yield is not allowed inside the __index handlers
-- below, so every source file is read once up front.
local sources: { [string]: string } = {}
local directories: { [string]: boolean } = {}

local function scan(path: string)
	for _, entry in fs.readDir(path) do
		local fullPath = path .. "/" .. entry
		if fs.isDir(fullPath) then
			directories[fullPath] = true
			scan(fullPath)
		elseif string.match(entry, "%.luau$") then
			sources[fullPath] = fs.readFile(fullPath)
		end
	end
end

directories[SRC] = true
scan(SRC)

local loadModuleFile

local function dirNode(path: string): any
	local cached = dirCache[path]
	if cached then
		return cached
	end
	local node = {}
	dirCache[path] = node
	setmetatable(node, {
		__index = function(self, key)
			if key == "WaitForChild" or key == "FindFirstChild" then
				return function(_, name: string)
					return self[name]
				end
			elseif key == "Parent" then
				local parent = string.match(path, "^(.*)/[^/]+$")
				return if parent then dirNode(parent) else nil
			end
			local filePath = path .. "/" .. key .. ".luau"
			if sources[filePath] then
				return loadModuleFile(filePath)
			end
			local childDir = path .. "/" .. key
			if directories[childDir] then
				return dirNode(childDir)
			end
			return nil
		end,
	})
	return node
end

local gameMock = {
	GetService = function(_, name: string)
		if name == "ReplicatedStorage" then
			return { Shared = dirNode(SRC .. "/shared") }
		elseif name == "ServerScriptService" then
			return { Server = dirNode(SRC .. "/server") }
		end
		error("service not available in unit tests: " .. name)
	end,
}

function loadModuleFile(filePath: string): any
	local cached = moduleCache[filePath]
	if cached ~= nil then
		return cached
	end
	local parent = string.match(filePath, "^(.*)/[^/]+$") or "."
	local name = string.match(filePath, "([^/]+)%.luau$") or filePath
	local source = sources[filePath]
	if not source then
		error("module not found: " .. filePath, 0)
	end
	local chunk = luau.load(source, {
		debugName = filePath,
		environment = {
			script = { Parent = dirNode(parent), Name = name },
			game = gameMock,
			require = function(value)
				return value
			end,
		},
	})
	local value = chunk()
	moduleCache[filePath] = value
	return value
end

-- Load a module by its path under src/, for example Framework.load("shared/Config").
function Framework.load(relativePath: string): any
	return loadModuleFile(SRC .. "/" .. relativePath .. ".luau")
end

-- Tests ----------------------------------------------------------------------------------

function Framework.suite(name: string)
	currentSuite = name
end

function Framework.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		stats.passed += 1
	else
		stats.failed += 1
		table.insert(
			stats.failures,
			string.format("[%s] %s: %s", currentSuite, name, tostring(err))
		)
	end
end

local function describe(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

function Framework.eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(
			string.format(
				"%sexpected %s, got %s",
				if label then label .. ": " else "",
				describe(expected),
				describe(actual)
			),
			2
		)
	end
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function Framework.deepEq(actual: any, expected: any, label: string?)
	if not deepEqual(actual, expected) then
		error((if label then label .. ": " else "") .. "tables are not equal", 2)
	end
end

function Framework.near(actual: number, expected: number, epsilon: number?, label: string?)
	if math.abs(actual - expected) > (epsilon or 1e-9) then
		error(
			string.format(
				"%sexpected about %s, got %s",
				if label then label .. ": " else "",
				tostring(expected),
				tostring(actual)
			),
			2
		)
	end
end

function Framework.truthy(value: any, label: string?)
	if not value then
		error((if label then label .. ": " else "") .. "expected a truthy value", 2)
	end
end

function Framework.falsy(value: any, label: string?)
	if value then
		error((if label then label .. ": " else "") .. "expected a falsy value", 2)
	end
end

-- The function must raise an error. Returns the error message.
function Framework.throws(fn: () -> (), label: string?): string
	local ok, err = pcall(fn)
	if ok then
		error((if label then label .. ": " else "") .. "expected an error, none was raised", 2)
	end
	return tostring(err)
end

function Framework.stats()
	return stats
end

return Framework
