--- The fixture's own configuration, put through `setup` the way Yazi puts it,
--- and the fixture's key set held together across the files that name it.
---
--- `test/fixture/init.lua` is the configuration `test/setup.py` copies into the
--- scratch tree. It is the one configuration here written to be right rather
--- than wrong, at a length no spec writes, and a refusal added to `setup` is
--- exactly the kind of change that turns a right configuration away -- which
--- would otherwise surface only in `e2e.py`, minutes later and outside CI.
---
--- What this does not do is draw. `e2e.py` is still the only thing that says
--- the configuration produces the screen `test/MANUAL.md` describes.
---
--- The key set is bound in two files -- `test/fixture/cases.toml`, a key per
--- folder, per case and per theme, and `test/fixture/keymap.toml`, the one
--- that is none of those -- and named again in two more, `test/fixture/banner.txt` and
--- `test/MANUAL.md`. `e2e.py` presses a case by what it is rather than by its
--- key. The banner's only reader is a person, so it is the one that can fall
--- behind with everything green. The two binding files are the authority, and
--- nothing here names a key of its own.

---@type supaline.Main
local main = require(".main")

-- Read rather than copied: a copy kept here would be a configuration this spec
-- passes while the fixture drew from a different one.
local INIT = ROOT .. "/test/fixture/init.lua"
local CASES = ROOT .. "/test/fixture/cases.toml"
local KEYMAP = ROOT .. "/test/fixture/keymap.toml"
local BANNER = ROOT .. "/test/fixture/banner.txt"
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

--- `init.lua` run the way Yazi runs it, with `supaline` resolved to this
--- checkout's plugin.
---@return boolean # whether it ran to the end
---@return any # what it raised, when it did not
---@return table? # the options it handed `setup`, when it got that far
local function configure()
	-- A file that is there and empty compiles, runs and refuses nothing, so the
	-- read has to prove it found a configuration first.
	local body = read(INIT)
	has(body, "supaline:setup", "supaline.column")

	-- Told apart from the refusal below, because the fix is different: this is
	-- Lua declining to compile the fixture at all.
	local chunk, why = load(body, "@test/fixture/init.lua")
	assert(chunk, "the fixture's `init.lua` does not compile: " .. tostring(why))

	-- A plugin reaches itself by name in Yazi's spelling, so the name is
	-- resolved here instead of the call being rewritten there. What it reaches
	-- is the plugin behind a table that keeps a copy of what `setup` is given,
	-- rather than the plugin with its `setup` swapped out for the length of a
	-- call.
	local given
	local seen = setmetatable({
		setup = function(st, opts)
			given = opts
			return main.setup(st, opts)
		end,
	}, { __index = main })
	local before = package.preload["supaline"]
	package.preload["supaline"] = function() return seen end
	-- The walk is the fixture's own plugin rather than supaline, and draws only
	-- in Yazi, so it is stood in for: a `setup` that takes the call and does
	-- nothing, which is the whole of what `init.lua` asks of it.
	local walk_before = package.preload["walk"]
	package.preload["walk"] = function()
		return { setup = function(_st) end }
	end
	local ok, err = pcall(chunk)
	package.preload["supaline"] = before
	package.preload["walk"] = walk_before
	package.loaded["supaline"] = nil
	package.loaded["walk"] = nil
	return ok, err, given
end

test("fixture: the configuration `e2e.py` draws is one `setup` takes", function()
	local ok, err = configure()
	assert(ok, "the fixture's own configuration was refused by `setup`:\n    " .. tostring(err))
end)

--- Every value `cases.toml` writes under `field`, one per line and spelled as
--- a string, as a set -- beside how many lines it was read from, and how many
--- blocks the file holds of the kinds that should each carry one.
---@param field string
---@param blocks string[] # the kinds of block that carry it: `case`, `folder`, `theme`
---@return table<string, true>
---@return integer # lines read
---@return integer # blocks of those kinds in the file
local function case_field(field, blocks)
	local toml = read(CASES)
	local found, lines = {}, 0
	for line in toml:gmatch("[^\n]+") do
		local value = line:match("^" .. field .. '%s*=%s*"([^"]*)"%s*$')
		if value then
			found[value] = true
			lines = lines + 1
		end
	end
	local count = 0
	for _, kind in ipairs(blocks) do
		count = count + select(2, toml:gsub("%[%[" .. kind .. "%]%]", "%0"))
	end
	return found, lines, count
end

-- `e2e.py` is deliberately not compared against the keys either file binds.
-- It presses every folder and case by what it is, `T`, and of the themes `alt`
-- alone, because a theme key replaces `theme.toml` wholesale and a run can
-- afford one swap, so a check there would need a list of exempt keys --
-- another place naming the set.

--- Keys the banner offers that the fixture does not bind, and why each is not a
--- fault. An entry the banner no longer offers is refused, so this cannot
--- become a list of keys the banner stopped mentioning.
local NOT_BOUND = {
	["m s"] = "Yazi's own size linemode, which `m 0` is the baseline for",
}

--- Every key the fixture binds, spelled the way a reader presses it: the ones
--- `test/fixture/keymap.toml` writes, and the ones `test/fixture/cases.toml`
--- gives a folder, a case or a theme.
---@return table<string, true> # the keys, as a set
---@return integer # lines a key was read from, across both files
---@return integer # blocks across both files that bind one
local function bound_keys()
	local toml = read(KEYMAP)
	local keys, lines = {}, 0
	for line in toml:gmatch("[^\n]+") do
		local rhs = line:match("^on%s*=%s*(.*)$")
		if rhs then
			-- `on = "T"` and `on = [ "c", "1" ]` are one thing at two lengths, so
			-- the quoted parts are joined with the space every other file uses.
			local press = {}
			for k in rhs:gmatch('"([^"]*)"') do
				press[#press + 1] = k
			end
			keys[table.concat(press, " ")] = true
			lines = lines + 1
		end
	end
	local blocks = select(2, toml:gsub("%[%[mgr%.prepend_keymap%]%]", "%0"))

	-- Spelled with the space already, which is why `cases.toml` writes a key
	-- as one string rather than as the list a keymap takes. A key bound twice,
	-- in either file or across the two, is one member of the set and two
	-- lines, which is how the test below finds it.
	local listed, there, blocks_there = case_field("key", { "case", "folder", "theme" })
	for key in pairs(listed) do
		keys[key] = true
	end
	return keys, lines + there, blocks + blocks_there
end

--- Every key the manual banner **offers**, which is not every key it names.
---
--- An offer is a column: the key stands alone, with two or more spaces either
--- side of it and its description beside it. A mention runs on into the
--- sentence around it with one space, so the banner can talk about a key
--- without that counting as a place to find it.
---@return table<string, true> # the keys, as a set
local function offered_keys()
	local banner = read(BANNER)
	assert(banner:find("%S"), "test/fixture/banner.txt is empty; this spec is reading nothing")

	local keys = {}
	for line in banner:gmatch("[^\n]+") do
		local fields = {}
		for field in line:gsub("  +", "\1"):gmatch("[^\1]+") do
			fields[#fields + 1] = field
		end
		-- Never the last field: a key with nothing beside it offers nothing, and
		-- the last field is where a stray one-letter word lands.
		for i = 1, #fields - 1 do
			if fields[i]:match("^%a %w$") or fields[i]:match("^%a$") then
				keys[fields[i]] = true
			end
		end
	end
	return keys
end

--- The keys of `set` that `other` has not got, sorted, as one string.
---@param set table<string, any>
---@param other table<string, any>
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

test("fixture: this spec reads every key the fixture binds", function()
	-- The guard the tests below inherit: each asks whether another file carries
	-- the keys found here, so an extraction that came back empty *here* would
	-- let all of them pass over nothing. Proved against the file's own shape
	-- rather than a count written here, which would go stale with the next key.
	local keys, lines, blocks = bound_keys()
	assert(lines > 0, "no key read from test/fixture/keymap.toml or cases.toml; this spec is reading nothing")
	eq(lines, blocks, "every block that binds a key has a line this spec could read it from")

	local distinct = 0
	for _ in pairs(keys) do
		distinct = distinct + 1
	end
	eq(distinct, lines, "no two blocks bind the same key")
end)

test("fixture: the manual banner offers every key the fixture binds, and no other", function()
	local keys, offered = bound_keys(), offered_keys()
	eq(missing_from(keys, offered), "", "bound by the fixture and not offered by test/fixture/banner.txt")

	for key, why in pairs(NOT_BOUND) do
		assert(offered[key], string.format("`%s` is exempted as %s, and the banner no longer offers it", key, why))
		keys[key] = true
	end
	eq(
		missing_from(offered, keys),
		"",
		"offered by test/fixture/banner.txt and bound nowhere; bind it, or say in `NOT_BOUND` whose key it is"
	)
end)

test("fixture: `MANUAL.md` spells every key the fixture binds", function()
	-- Fenced blocks first: they are screen captures, and a key that appears only
	-- inside one has been drawn rather than documented.
	local prose = read(MANUAL_MD):gsub("\n```.-\n```\n", "\n")
	local spans = {}
	for span in prose:gmatch("`([^`]*)`") do
		spans[span] = true
	end
	-- One direction only: `MANUAL.md` spells Yazi's own keys as well, because
	-- comparing the fixture against them is half of what it is for.
	eq(missing_from(bound_keys(), spans), "", "bound by the fixture and never spelled in test/MANUAL.md")
end)

test("fixture: every case names a linemode `init.lua` declares, and every one it declares is a case", function()
	-- Both directions, because each fails differently and quietly. A case whose
	-- linemode nobody declared is drawn by Yazi as its name in literal text,
	-- which `e2e.py` would find, minutes later and outside CI. A linemode no case
	-- names is configuration nothing can reach -- no key presses it and no run
	-- captures it -- and nothing at all would find that.
	local named, lines, blocks = case_field("linemode", { "case" })
	assert(lines > 0, "no `linemode` line in test/fixture/cases.toml; this spec is reading nothing")
	eq(lines, blocks, "every [[case]] in test/fixture/cases.toml has a `linemode` line this spec could read")

	local ok, err, opts = configure()
	assert(ok and opts and opts.linemodes, "the fixture's `init.lua` handed `setup` no linemodes: " .. tostring(err))
	local declared = opts.linemodes

	eq(missing_from(named, declared), "", "named by test/fixture/cases.toml and declared by no linemode in init.lua")
	eq(missing_from(declared, named), "", "declared in init.lua and named by no case in test/fixture/cases.toml")
end)
