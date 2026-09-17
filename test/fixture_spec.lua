--- The fixture's own configuration, put through `setup` the way Yazi puts it.
---
--- `test/setup.sh` writes an `init.lua` into the scratch tree it builds, and
--- until this file nothing but a real Yazi read it. No spec loaded the
--- fixture's configuration, so nothing in the suite stood between a refusal
--- added to `setup` and `e2e.sh` failing minutes later, on a machine with tmux
--- on it.
---
--- What that was costing is **not measured**. Two refusals were planted to
--- catch the suite passing one the fixture trips, and the suite caught both of
--- them anyway: it tests its own boundaries directly, and nothing the fixture
--- writes is exotic enough to slip past that. So this closes a gap that was
--- argued rather than one that was seen open -- which is the honest version,
--- and still worth the file. The fixture is the one configuration here written
--- to be right rather than wrong, at a length no spec writes, and a refusal is
--- exactly the kind of change that turns a right configuration away.
---
--- What this does not do is draw. `e2e.sh` is still the only thing that says
--- the configuration produces the screen `test/MANUAL.md` describes; this says
--- only that `setup` takes it.

---@type supaline.Main
local main = require(".main")

local SETUP = ROOT .. "/test/setup.sh"

--- The Lua `setup.sh` writes to `config/init.lua`, read out of the heredoc it
--- writes it from.
---
--- Read rather than copied. A copy kept here would be a configuration this
--- spec passes while the fixture drew from a different one, which is the
--- failure the spec exists for wearing a disguise.
---@return string # the body of the heredoc
local function fixture_init()
	local f = assert(io.open(SETUP), "cannot open test/setup.sh")
	local sh = f:read("a")
	f:close()

	-- Asserted here rather than at each caller, and it is the guard rather than
	-- a formality: a `match` that answers nil -- because the heredoc was
	-- renamed, requoted, or moved to a file of its own -- would otherwise reach
	-- `load` as nil and be reported as whatever that does, which is not what
	-- went wrong.
	local body = sh:match("cat >\"%$DIR/config/init%.lua\" <<'EOF'\n(.-)\nEOF\n")
	return assert(body, "no `config/init.lua` heredoc in test/setup.sh; this spec is reading nothing")
end

test("fixture: the `init.lua` this spec reads is the one `setup.sh` writes", function()
	local body = fixture_init()

	-- The other half of the same guard. An extraction that stops early answers
	-- a prefix of the fixture, which compiles and runs and refuses nothing --
	-- a spec exiting 0 over a configuration it never saw, which is the one
	-- outcome this file was written to make impossible.
	assert(body:find("supaline:setup", 1, true), "the heredoc was found but carries no `setup` call")
	assert(body:find("supaline.column", 1, true), "the heredoc was found but registers no columns")
end)

test("fixture: the configuration `e2e.sh` draws is one `setup` takes", function()
	-- Told apart from the refusal below, because they are different faults with
	-- different fixes: this one is Lua declining to compile the fixture at all.
	local chunk, why = load(fixture_init(), "@config/init.lua")
	assert(chunk, "the fixture's `init.lua` does not compile: " .. tostring(why))

	-- Yazi's own spelling. A plugin reaches itself by name, and the fixture is
	-- written to be read by Yazi rather than by this, so the name is resolved
	-- here instead of the call being rewritten there.
	local before = package.preload["supaline"]
	package.preload["supaline"] = function() return main end

	local ok, err = pcall(chunk)

	package.preload["supaline"] = before
	package.loaded["supaline"] = nil

	-- Reported rather than re-raised, so the message names the fixture instead
	-- of arriving as a stack from somewhere under `setup`.
	assert(ok, "the fixture's own configuration was refused by `setup`:\n    " .. tostring(err))
end)
