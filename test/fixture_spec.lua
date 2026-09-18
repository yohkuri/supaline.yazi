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
---
--- The second half of the file is the same move made about the keys. The
--- fixture's key set is named in four places -- the keymap `setup.sh` writes,
--- `manual.sh`'s banner, `test/MANUAL.md`, and `e2e.sh`'s capture loops -- and
--- three of them are read by something. The banner's only reader is a person,
--- so it is the one that can fall behind without anything going red, and it
--- did: eight `c` keys were bound, sectioned and captured while the banner
--- offered six.

---@type supaline.Main
local main = require(".main")

local SETUP = ROOT .. "/test/setup.sh"
local MANUAL_SH = ROOT .. "/test/manual.sh"
local MANUAL_MD = ROOT .. "/test/MANUAL.md"

--- The whole of a file in the repository, by absolute path.
---@param path string
---@return string
local function read(path)
	local f = assert(io.open(path), "cannot open " .. path)
	local body = f:read("a")
	f:close()
	return body
end

--- The Lua `setup.sh` writes to `config/init.lua`, read out of the heredoc it
--- writes it from.
---
--- Read rather than copied. A copy kept here would be a configuration this
--- spec passes while the fixture drew from a different one, which is the
--- failure the spec exists for wearing a disguise.
---@return string # the body of the heredoc
local function fixture_init()
	local sh = read(SETUP)

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

-- `e2e.sh` names this key set too and is deliberately not compared against it.
-- It presses `c 2` and neither `c 1` nor `c 3`: that key replaces `theme.toml`
-- wholesale, and every capture taken before it was taken against the file the
-- run had been editing in place, so one swap is all a run can afford. "Every
-- bound key is pressed there" is false on purpose, and a check written around
-- it would have to carry a list of which keys are exempt. Such a list is a
-- fifth place naming the set, which is the thing this half of the file exists
-- not to become.

--- Keys the banner offers that the keymap does not bind, and why each is not a
--- fault.
---
--- Yazi's own, offered because half of what the fixture asks is "how does this
--- read against what Yazi does" -- `m 0` exists to be pressed against `m s`.
--- Nothing binds them because nothing has to.
---
--- An entry that is no longer offered is refused rather than ignored, so this
--- cannot silently become a list of keys the banner stopped mentioning.
local NOT_BOUND = {
	["m s"] = "Yazi's own size linemode, which `m 0` is the baseline for",
}

--- Every key `test/setup.sh` binds, spelled the way a reader presses it.
---@return table<string, true> # the keys, as a set
---@return integer # `on` lines read
---@return integer # `[[mgr.prepend_keymap]]` blocks the file holds
local function bound_keys()
	local sh = read(SETUP)
	local keys, ons = {}, 0

	for line in sh:gmatch("[^\n]+") do
		local rhs = line:match("^on%s*=%s*(.*)$")
		if rhs then
			-- `on = "T"` and `on = [ "m", "0" ]` are one thing said at two
			-- lengths, so the quoted parts are taken in order and joined with the
			-- space every other file here spells a key with.
			local press = {}
			for k in rhs:gmatch('"([^"]*)"') do
				press[#press + 1] = k
			end
			keys[table.concat(press, " ")] = true
			ons = ons + 1
		end
	end

	return keys, ons, select(2, sh:gsub("%[%[mgr%.prepend_keymap%]%]", "%0"))
end

--- Every key `manual.sh`'s banner **offers**, which is not every key it names.
---
--- An offer is a column: the key stands alone, with two or more spaces either
--- side of it and its description beside it. A mention runs on into the
--- sentence around it -- "press b u straight after", "g 6 breaks the left one"
--- -- with one space, so the banner can go on talking about a key without that
--- counting as a place to find it. That distinction is the whole check: a key
--- named in the prose and offered nowhere is exactly how `c b` and `c a` went
--- missing.
---@return table<string, true> # the keys, as a set
local function offered_keys()
	local banner = read(MANUAL_SH):match("cat <<'EOF'\n(.-)\nEOF\n")
	assert(banner, "no quoted banner heredoc in test/manual.sh; this spec is reading nothing")

	local keys = {}
	for line in banner:gmatch("[^\n]+") do
		-- Split on the runs of two or more spaces the banner's columns are made
		-- of. A marker rather than a pattern with alternation in it, which Lua
		-- patterns do not have.
		local fields = {}
		local marked = line:gsub("  +", "\1")
		for field in marked:gmatch("[^\1]+") do
			fields[#fields + 1] = field
		end

		-- Never the last field: a key with nothing beside it is not an offer of
		-- anything, and the last field is where a stray one-letter word lands.
		for i = 1, #fields - 1 do
			if fields[i]:match("^%a %w$") or fields[i]:match("^%a$") then
				keys[fields[i]] = true
			end
		end
	end

	return keys
end

--- The members of `set` that `other` has not got, sorted, as one string.
---@param set table<string, true>
---@param other table<string, true>
---@return string # empty when there are none
local function missing_from(set, other)
	local out = {}
	for k in pairs(set) do
		if not other[k] then
			out[#out + 1] = k
		end
	end
	table.sort(out)
	return table.concat(out, ", ")
end

test("fixture: this spec reads every key `setup.sh` binds", function()
	-- The guard the three tests below inherit, and the reason none of them
	-- needs one of its own. Each of those asks whether some other file carries
	-- the keys found here, so an extraction that came back empty *here* would
	-- let all three pass over nothing, while one that came back empty *there*
	-- fails loudly with every bound key named at once. Only the authority has
	-- to prove it was read.
	--
	-- Proved against the file's own shape rather than against a count written
	-- here, which would be a fifth place holding the size of the set and would
	-- go stale the first time a key is added.
	local keys, ons, blocks = bound_keys()
	assert(ons > 0, "no `on` line in test/setup.sh; this spec is reading nothing")
	eq(ons, blocks, "every keymap block has an `on` line this spec could read")

	local distinct = 0
	for _ in pairs(keys) do
		distinct = distinct + 1
	end
	eq(distinct, ons, "no two keymap blocks bind the same key")
end)

test("fixture: the manual banner offers every key the keymap binds", function()
	local missing = missing_from(bound_keys(), offered_keys())
	assert(
		missing == "",
		"bound by test/setup.sh and not offered by test/manual.sh's banner: "
			.. missing
			.. "\n    a key a reader cannot find is a case nobody reads"
	)
end)

test("fixture: the manual banner offers nothing the keymap leaves unbound", function()
	local keys = bound_keys()
	local offered = offered_keys()

	for key, why in pairs(NOT_BOUND) do
		assert(offered[key], string.format("`%s` is exempted as %s, and the banner no longer offers it", key, why))
		keys[key] = true
	end

	local extra = missing_from(offered, keys)
	assert(
		extra == "",
		"offered by test/manual.sh's banner and bound nowhere: "
			.. extra
			.. "\n    either bind it in test/setup.sh or say in `NOT_BOUND` whose key it is"
	)
end)

test("fixture: `MANUAL.md` spells every key the keymap binds", function()
	-- Fenced blocks first: they are screen captures, and a key that appears
	-- only inside one has been drawn rather than documented.
	local prose = read(MANUAL_MD):gsub("\n```.-\n```\n", "\n")

	local spans = {}
	for span in prose:gmatch("`([^`]*)`") do
		spans[span] = true
	end

	-- One direction only. A document naming a key nobody bound is a fault too,
	-- but this set cannot say so: `MANUAL.md` spells `m s`, `m b`, `c c` and
	-- `j` as well, because comparing the fixture against Yazi's own keys is
	-- half of what several of its sections are for.
	local missing = missing_from(bound_keys(), spans)
	assert(missing == "", "bound by test/setup.sh and never spelled in test/MANUAL.md: " .. missing)
end)
