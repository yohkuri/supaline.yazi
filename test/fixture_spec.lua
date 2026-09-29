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
--- The key set is named in four places -- `test/fixture/keymap.toml`,
--- `test/fixture/banner.txt`, `test/MANUAL.md`, and `e2e.py`'s capture loops.
--- The banner's only reader is a person, so it is the one that can fall behind
--- with everything green. The keymap is the authority, and nothing here names a
--- key of its own.

---@type supaline.Main
local main = require(".main")

-- Read rather than copied: a copy kept here would be a configuration this spec
-- passes while the fixture drew from a different one.
local INIT = ROOT .. "/test/fixture/init.lua"
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

test("fixture: the configuration `e2e.py` draws is one `setup` takes", function()
	-- A file that is there and empty compiles, runs and refuses nothing, so the
	-- read has to prove it found a configuration first.
	local body = read(INIT)
	has(body, "supaline:setup", "supaline.column")

	-- Told apart from the refusal below, because the fix is different: this is
	-- Lua declining to compile the fixture at all.
	local chunk, why = load(body, "@test/fixture/init.lua")
	assert(chunk, "the fixture's `init.lua` does not compile: " .. tostring(why))

	-- A plugin reaches itself by name in Yazi's spelling, so the name is
	-- resolved here instead of the call being rewritten there.
	local before = package.preload["supaline"]
	package.preload["supaline"] = function() return main end
	local ok, err = pcall(chunk)
	package.preload["supaline"] = before
	package.loaded["supaline"] = nil

	assert(ok, "the fixture's own configuration was refused by `setup`:\n    " .. tostring(err))
end)

-- `e2e.py` is deliberately not compared against the key set. It presses `c 2`
-- and neither `c 1` nor `c 3`, because that key replaces `theme.toml` wholesale
-- and a run can afford one swap, so a check there would need a list of exempt
-- keys -- a fifth place naming the set.

--- Keys the banner offers that the keymap does not bind, and why each is not a
--- fault. An entry the banner no longer offers is refused, so this cannot
--- become a list of keys the banner stopped mentioning.
local NOT_BOUND = {
	["m s"] = "Yazi's own size linemode, which `m 0` is the baseline for",
}

--- Every key `test/fixture/keymap.toml` binds, spelled the way a reader
--- presses it.
---@return table<string, true> # the keys, as a set
---@return integer # `on` lines read
---@return integer # `[[mgr.prepend_keymap]]` blocks the file holds
local function bound_keys()
	local toml = read(KEYMAP)
	local keys, ons = {}, 0
	for line in toml:gmatch("[^\n]+") do
		local rhs = line:match("^on%s*=%s*(.*)$")
		if rhs then
			-- `on = "T"` and `on = [ "m", "0" ]` are one thing at two lengths, so
			-- the quoted parts are joined with the space every other file uses.
			local press = {}
			for k in rhs:gmatch('"([^"]*)"') do
				press[#press + 1] = k
			end
			keys[table.concat(press, " ")] = true
			ons = ons + 1
		end
	end
	return keys, ons, select(2, toml:gsub("%[%[mgr%.prepend_keymap%]%]", "%0"))
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

test("fixture: this spec reads every key the keymap binds", function()
	-- The guard the tests below inherit: each asks whether another file carries
	-- the keys found here, so an extraction that came back empty *here* would
	-- let all of them pass over nothing. Proved against the file's own shape
	-- rather than a count written here, which would go stale with the next key.
	local keys, ons, blocks = bound_keys()
	assert(ons > 0, "no `on` line in test/fixture/keymap.toml; this spec is reading nothing")
	eq(ons, blocks, "every keymap block has an `on` line this spec could read")

	local distinct = 0
	for _ in pairs(keys) do
		distinct = distinct + 1
	end
	eq(distinct, ons, "no two keymap blocks bind the same key")
end)

test("fixture: the manual banner offers every key the keymap binds, and no other", function()
	local keys, offered = bound_keys(), offered_keys()
	eq(missing_from(keys, offered), "", "bound by test/fixture/keymap.toml and not offered by test/fixture/banner.txt")

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

test("fixture: `MANUAL.md` spells every key the keymap binds", function()
	-- Fenced blocks first: they are screen captures, and a key that appears only
	-- inside one has been drawn rather than documented.
	local prose = read(MANUAL_MD):gsub("\n```.-\n```\n", "\n")
	local spans = {}
	for span in prose:gmatch("`([^`]*)`") do
		spans[span] = true
	end
	-- One direction only: `MANUAL.md` spells Yazi's own keys as well, because
	-- comparing the fixture against them is half of what it is for.
	eq(missing_from(bound_keys(), spans), "", "bound by test/fixture/keymap.toml and never spelled in test/MANUAL.md")
end)
