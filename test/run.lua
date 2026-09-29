---@diagnostic disable: lowercase-global

--- Unit tests for the pure logic: layout, normalisation, the ratio contract,
--- the built-in formatters.
---
--- They stub the Yazi globals, so they say nothing about rendering, fetchers or
--- `ya.sync`. Run `test/e2e.py` for those.
---
---     lua test/run.lua            every spec
---     lua test/run.lua column     the specs whose name contains "column"

-- Yazi runs Lua 5.5 and nothing else ever loads this plugin, so a pass under
-- another interpreter proves nothing -- and says so quietly. The semantics
-- diverge exactly where this code lives: `%z` in a pattern means the NUL byte
-- on 5.1 and the letter `z` from 5.2 on, and `utf8` does not exist before 5.3.
if _VERSION ~= "Lua 5.5" then
	io.stderr:write(
		string.format(
			"test/run.lua: needs Lua 5.5, the version Yazi runs; got %s\n"
				.. "  Any 5.5 does, and nothing here requires a version manager.\n",
			_VERSION
		)
	)
	os.exit(2)
end

local ROOT = (arg[0]:match("^(.*)[/\\]test[/\\]run%.lua$")) or "."
local FILTER = arg[1]

---@type supaline.Stub
local stub = dofile(ROOT .. "/test/stub.lua")

--- Every `test/*_spec.lua`, in name order. Found rather than listed, because a
--- spec left off a list never runs and the suite stays green without it.
---@return string[]
local function specs()
	-- Quoted whole for the shell, so no character in the checkout's path is
	-- one the shell reads.
	local dir = (ROOT .. "/test"):gsub("'", [['\'']])
	local pipe = assert(io.popen("ls '" .. dir .. "'"))
	local names = {}
	for file in pipe:read("a"):gmatch("[^\n]+") do
		names[#names + 1] = file:match("^(.+_spec)%.lua$")
	end
	pipe:close()
	assert(#names > 0, "found no spec under " .. ROOT .. "/test; is `ls` on PATH?")
	table.sort(names)
	return names
end

local passed, failures, current, declared = 0, {}, "?", 0

--- Declare one test. A failure is recorded and the run carries on, so one
--- broken assertion does not hide the rest.
---
--- Every test starts from the stubs' own `ui`, `th`, `ya` and `cx`, so a body
--- writes what it needs straight onto them and puts nothing back: a restore
--- written as a body's last line is skipped by the failure it would matter
--- for, and what it left set is then reported against the next test.
---@param name string
---@param fn function
function test(name, fn)
	declared = declared + 1
	stub.reset()
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

--- The first of `patterns` that `text` does not contain, as a failure message.
---@param text string
---@param patterns string[]
---@return string?
local function absent(text, patterns)
	for _, p in ipairs(patterns) do
		if not text:find(p, 1, true) then
			return string.format("expected %q in %q", p, text)
		end
	end
end

--- Assert that `text` contains every one of the strings, matched plainly.
---@param text string
---@param ... string
function has(text, ...)
	local why = absent(text, { ... })
	if why then
		error(why, 2)
	end
end

--- Assert that `text` contains none of the strings.
---@param text string
---@param ... string
function lacks(text, ...)
	for _, p in ipairs { ... } do
		if text:find(p, 1, true) then
			error(string.format("expected no %q in %q", p, text), 2)
		end
	end
end

--- Assert that `fn` raises with a message containing every one of the strings,
--- and hand the message back.
---@param fn function
---@param ... string
---@return string
function throws(fn, ...)
	local ok, err = pcall(fn)
	if ok then
		error("expected an error, got none", 2)
	end
	local msg = tostring(err)
	local why = absent(msg, { ... })
	if why then
		error(why, 2)
	end
	return msg
end

_G.ROOT = ROOT
_G.stub = stub
--- The plain text of anything a column rendered.
_G.text_of = stub.text_of

for _, name in ipairs(specs()) do
	if not FILTER or name:find(FILTER, 1, true) then
		current, declared = name, 0
		-- A fresh plugin per spec file, including its registry and
		-- subscriptions, so columns registered by one spec cannot reach the next.
		stub.install(ROOT)
		local chunk, err = loadfile(ROOT .. "/test/" .. name .. ".lua")
		if not chunk then
			failures[#failures + 1] = string.format("%s\n    %s", name, tostring(err))
		else
			local ok, e = pcall(chunk)
			if not ok then
				failures[#failures + 1] = string.format("%s (while loading)\n    %s", name, tostring(e))
			elseif declared == 0 then
				failures[#failures + 1] = string.format("%s\n    declares no test", name)
			end
		end
	end
end

print(string.format("%d passed, %d failed", passed, #failures))
for _, f in ipairs(failures) do
	print("\nFAIL " .. f)
end
os.exit(#failures == 0 and 0 or 1)
