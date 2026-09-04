---@diagnostic disable: lowercase-global

--- Unit tests for the pure logic: layout, normalisation, the ratio contract,
--- the built-in formatters.
---
--- They stub the Yazi globals, so they say nothing about rendering, fetchers or
--- `ya.sync`. Run `test/e2e.sh` for those.
---
---     lua test/run.lua            every spec
---     lua test/run.lua column     the specs whose name contains "column"
---
--- Written for Lua 5.5, the version Yazi runs. Nothing else loads this plugin,
--- so nothing else has a claim on the tests either.

-- Yazi runs Lua 5.5 and nothing else ever loads this plugin, so a pass under
-- another interpreter proves nothing -- and says so quietly. The semantics
-- diverge exactly where this code lives: `%z` in a pattern means the NUL byte
-- on 5.1 and the letter `z` from 5.2 on, and `utf8` does not exist before 5.3.
if _VERSION ~= "Lua 5.5" then
	io.stderr:write(string.format("test/run.lua: needs Lua 5.5, the version Yazi runs; got %s\n", _VERSION))
	os.exit(2)
end

local ROOT = (arg[0]:match("^(.*)[/\\]test[/\\]run%.lua$")) or "."
local FILTER = arg[1]

local SPECS = {
	"truncate_spec",
	"auth_spec",
	"dds_spec",
	"module_spec",
	"column_spec",
	"builtin_spec",
	"main_spec",
}

local stub = dofile(ROOT .. "/test/stub.lua")

local passed, failures, current = 0, {}, "?"

--- Declare one test. A failure is recorded and the run carries on, so one
--- broken assertion does not hide the rest.
---@param name string
---@param fn function
function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failures[#failures + 1] = string.format("%s / %s\n    %s", current, name, tostring(err))
	end
end

---@param actual any
---@param expected any
---@param what string?
function eq(actual, expected, what)
	if actual ~= expected then
		error(string.format("%sexpected %q, got %q", what and what .. ": " or "", tostring(expected), tostring(actual)), 2)
	end
end

--- Assert that `fn` raises, and that the message mentions `pattern`.
---@param fn function
---@param pattern string
function throws(fn, pattern)
	local ok, err = pcall(fn)
	if ok then
		error("expected an error, got none", 2)
	elseif not tostring(err):find(pattern, 1, true) then
		error(string.format("expected an error mentioning %q, got %q", pattern, tostring(err)), 2)
	end
end

--- The plain text of anything a column rendered.
_G.text_of = stub.text_of
_G.stub = stub
_G.ROOT = ROOT

for _, name in ipairs(SPECS) do
	if not FILTER or name:find(FILTER, 1, true) then
		current = name
		-- A fresh registry per spec: the column registry is module state, and a
		-- spec that registers its own columns must not leak into the next.
		stub.install(ROOT)
		_G.text_of = stub.text_of
		_G.stub = stub
		local chunk, err = loadfile(ROOT .. "/test/" .. name .. ".lua")
		if not chunk then
			failures[#failures + 1] = string.format("%s\n    %s", name, tostring(err))
		else
			local ok, e = pcall(chunk)
			if not ok then
				failures[#failures + 1] = string.format("%s (while loading)\n    %s", name, tostring(e))
			end
		end
	end
end

print(string.format("%d passed, %d failed", passed, #failures))
for _, f in ipairs(failures) do
	print("\nFAIL " .. f)
end
os.exit(#failures == 0 and 0 or 1)
