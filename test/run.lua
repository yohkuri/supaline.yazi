-- Unit test runner.
--
--   lua test/run.lua
--
-- Loads the stubs, then each spec in test/. Exits non-zero on failure.

local HERE = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local ROOT = HERE .. "../"

local stub = dofile(HERE .. "stub.lua")
stub.install()

local t = { stub = stub, failures = 0, total = 0 }

--- Load a plugin module, satisfying its `require(".name")` imports.
function t.module(name)
	local key = "." .. name
	if not package.loaded[key] then
		package.loaded[key] = dofile(ROOT .. name .. ".lua")
	end
	return package.loaded[key]
end

function t.group(name) print(name) end

function t.check(name, cond, detail)
	t.total = t.total + 1
	if cond then
		print(string.format("  ok   %s", name))
	else
		t.failures = t.failures + 1
		print(string.format("  FAIL %s   %s", name, tostring(detail)))
	end
end

-- Dependency order: column requires gradient, builtin and git require column.
t.module("gradient")
t.module("column")
t.module("builtin")
t.module("git")

for _, spec in ipairs { "gradient_spec", "column_spec", "git_spec" } do
	print("")
	print("# " .. spec)
	dofile(HERE .. spec .. ".lua")(t)
end

print("")
if t.failures == 0 then
	print(string.format("all %d checks passed", t.total))
else
	print(string.format("%d of %d checks FAILED", t.failures, t.total))
	os.exit(1)
end
