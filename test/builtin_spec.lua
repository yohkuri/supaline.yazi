--- `builtin.lua`: the formatters, and the fallbacks each column takes when the
--- value it wants is not there.

local column = require(".column")
require(".builtin")

local CFG = { scale = "linear" }
-- A `setup` that said nothing about scale, which is the only way a column
-- definition's own is what decides. A local rather than a `{}` written at the
-- call: a table constructor passed straight as an argument is checked for the
-- fields its class requires, and this one is deliberately without them.
local NO_SCALE = {}

--- Run `fn` with `cx.active:history` answering `folder`, and put the stub's own
--- back afterwards.
---@param folder table?
---@param fn function
local function with_history(folder, fn)
	-- Yazi's parameters, for the reason `stub.lua` gives beside its own.
	with(cx.active, "history", function(_, _url) return folder end, fn)
end

--- Run `fn` on a build with no name lookups at all, and put them back
--- afterwards. `ya.user_name` and `ya.group_name` are `#[cfg(unix)]` in Yazi,
--- so on Windows they are not absent-and-nil but never created; taking them
--- away is what a spec has instead of a Windows machine.
---
--- Takes the two rather than assuming nil, so a spec that wants to watch the
--- lookups rather than remove them uses the same restore path. Nested rather
--- than swapped in one step, because `with` carries one field: either one left
--- reassigned reaches every test after this, and the inner call is what puts
--- the second back when the body raises.
---@param user function?
---@param group function?
---@param fn function
local function with_names(user, group, fn)
	with(ya, "user_name", user, function() with(ya, "group_name", group, fn) end)
end

--- The build with no lookups at all: Yazi's Windows one.
---@param fn function
local function without_names(fn) with_names(nil, nil, fn) end

--- Render one built-in column for one file, returning plain text.
---@param name string
---@param file table
---@param opts table?
---@return string
local function render(name, file, opts)
	local spec = { name }
	for k, v in pairs(opts or {}) do
		spec[k] = v
	end
	return text_of(column.cell(column.normalize(spec, CFG), file))
end

-- --- size ------------------------------------------------------------------

test("size: human-readable, right-aligned in 7 cells", function()
	eq(render("size", stub.file { size = 0 }), "     0B")
	eq(render("size", stub.file { size = 900 }), "   900B")
	eq(render("size", stub.file { size = 819200 }), "   800K")
	eq(render("size", stub.file { size = 92160000 }), "  87.9M")
end)

test("size: the widest readable size still fits the column", function()
	-- `ya.readable_size` keeps the mantissa in (1, 1024] and strips a trailing
	-- ".0", so "1023.9K" is as wide as it gets.
	eq(#ya.readable_size(1023.9 * 1024), 7)
end)

test("size: a directory falls back to its entry count", function()
	with_history(
		{ files = { 1, 2, 3 } },
		function() eq(render("size", stub.file { name = "d", is_dir = true }), "      3") end
	)
end)

test("size: a directory Yazi has never listed shows a dash", function()
	with_history(nil, function() eq(render("size", stub.file { name = "d", is_dir = true }), "      -") end)
end)

-- --- times -----------------------------------------------------------------

local THIS_YEAR = os.date("*t").year
local RECENT = os.time { year = THIS_YEAR, month = 3, day = 4, hour = 5, min = 6, sec = 0 }
local OLD = os.time { year = 2020, month = 12, day = 25, hour = 1, min = 2, sec = 0 }

test(
	"mtime: time of day within the current year",
	function() eq(render("mtime", stub.file { mtime = RECENT }), "03/04 05:06") end
)

test(
	"mtime: the year itself for anything older",
	function() eq(render("mtime", stub.file { mtime = OLD }), "12/25  2020") end
)

test(
	"mtime: both forms are the same width",
	function() eq(#render("mtime", stub.file { mtime = RECENT }), #render("mtime", stub.file { mtime = OLD })) end
)

test("mtime: a missing or zero time is blank", function()
	eq(render("mtime", stub.file {}), "           ")
	eq(render("mtime", stub.file { mtime = 0 }), "           ")
end)

test(
	"mtime: `format` takes an os.date format",
	function() eq(render("mtime", stub.file { mtime = OLD }, { format = "%Y-%m-%d", width = 10 }), "2020-12-25") end
)

test("mtime: `format` reserves no word of its own", function()
	-- `"smart"` was a second spelling of the preset here, which is what
	-- leaving `format` out asks for. Withdrawn, it is the literal `os.date`
	-- makes of any string carrying no `%`, the way `"hello"` is -- so what
	-- this pins is that the word went back to `os.date`. Put the branch back
	-- and this reads the preset's `12/25  2020` instead.
	eq(render("mtime", stub.file { mtime = OLD }, { format = "smart", width = 5 }), "smart")
end)

test("btime and atime read their own fields", function()
	eq(render("btime", stub.file { btime = OLD, mtime = RECENT }), "12/25  2020")
	eq(render("atime", stub.file { atime = OLD, mtime = RECENT }), "12/25  2020")
end)

-- --- the rest --------------------------------------------------------------

test("permissions: a string Yazi could not have produced is refused by the stub", function()
	-- The stub's half of this column, pinned here because nothing else would
	-- notice it going quiet: `perm_spans` falls back to `PERM_TYPE` for any
	-- character it does not know, so a made-up string renders, and a spec
	-- asserting on what came back passes while describing no file at all.
	throws(function() stub.file { perm = "nope" } end, "ten-character")
	throws(function() stub.file { perm = "drwxr-xr-" } end, "ten-character")
	throws(function() stub.file { perm = "?rwxr-xr-x" } end, "type character from `dlbcsp-`")
	-- The `?` of an unstat-able `Cha` is all nine or none: `ChaMode::permissions`
	-- returns on the dummy before it writes a single bit, so a string cannot
	-- carry them beside letters.
	throws(function() stub.file { perm = "drwxr-x???" } end, "nine `?`")
	-- And the letters are per position, so an execute bit's `s` is not a
	-- character that may turn up in a read slot.
	throws(function() stub.file { perm = "dswxr-xr-x" } end, "per position")

	-- Left out is the one thing that is not an error, and it is the platform
	-- rather than the file: `Cha:perm` is nil under `#[cfg(windows)]`.
	eq(stub.file({}).cha:perm(), nil)
	eq(stub.file({ perm = "-?????????" }).cha:perm(), "-?????????")
end)

test("permissions: left-aligned, blank when the platform has none", function()
	eq(render("permissions", stub.file { perm = "drwxr-xr-x" }), "drwxr-xr-x")
	eq(render("permissions", stub.file {}), "          ")
end)

-- The `[status]` styles a flavor writes, distinct enough that a character
-- drawn from the wrong one is named by the failure rather than just unequal.
local STATUS = {
	perm_type = ui.Style():fg("#000011"),
	perm_read = ui.Style():fg("#000022"),
	perm_write = ui.Style():fg("#000033"),
	perm_exec = ui.Style():fg("#000044"),
	perm_sep = ui.Style():fg("#000055"),
}

--- Render `permissions` with `th.status` set, through the column's `refresh`
--- hook -- which is what main.lua runs on install and on `cd`, and the only
--- thing that ever reads the theme for this column.
---
--- Returns the style each character is drawn in, in order, `false` where one
--- carries none, so that a caller can ask about any field of it. Drawn rather
--- than carried: what the column hands back beside the Line goes under the
--- characters' own styles, which is where a `bold` written for the column
--- reaches them.
---@param file table
---@param opts table?
---@return table[]
local function perm_styles(file, opts)
	local spec = { "permissions" }
	for k, v in pairs(opts or {}) do
		spec[k] = v
	end
	local col = column.normalize(spec, CFG)

	local out = with(stub.th, "status", STATUS, function()
		col.refresh()
		return column.cell(col, file)
	end)

	return stub.drawn_styles(out)
end

--- The foreground of each character in order, so an assertion names the string
--- it expected rather than a list of styles.
---@param file table
---@param opts table?
---@return string
local function perm_fgs(file, opts)
	local fgs = {}
	for _, style in ipairs(perm_styles(file, opts)) do
		-- `rawget`: a style carrying no colour answers `.fg` with the setter.
		fgs[#fgs + 1] = style and rawget(style, "fg") or "-"
	end
	return table.concat(fgs, " ")
end

test("permissions: every character takes its own style from the theme", function()
	-- Yazi's own mapping, measured against the status bar of a real 26.9.1 and
	-- written down in `.agents/skills/yazi-platform-traps/references/probes.md`:
	-- the character decides, not the position, so the leading `-` of a regular
	-- file is a `perm_sep` like any other bit that is off.
	eq(
		perm_fgs(stub.file { perm = "-rw-r--r--" }),
		"#000055 #000022 #000033 #000055 #000022 #000055 #000055 #000022 #000055 #000055"
	)
	eq(
		perm_fgs(stub.file { perm = "drwxr-xr-x" }),
		"#000011 #000022 #000033 #000044 #000022 #000055 #000044 #000022 #000055 #000044"
	)
	-- `s` and `t` are execute bits with another bit folded into them, and `l`
	-- is a type character like `d`.
	eq(
		perm_fgs(stub.file { perm = "lrwsr-xr-t" }),
		"#000011 #000022 #000033 #000044 #000022 #000055 #000044 #000022 #000055 #000044"
	)
	-- `S` and `T` -- a setuid, setgid or sticky bit with the execute bit off
	-- -- are the one part of the mapping the screen never produced. They are
	-- `perm_exec` on the source instead: `Status:perm()` in
	-- `yazi-plugin/preset/components/status.lua` at 26.9.1 holds `x`, `s`,
	-- `S`, `t` and `T` in one branch.
	eq(
		perm_fgs(stub.file { perm = "-rwSr-Sr-T" }),
		"#000055 #000022 #000033 #000044 #000022 #000055 #000044 #000022 #000055 #000044"
	)
	-- A socket's type character is an `s`, and keying on the character sends
	-- it where every other `s` goes. Pinned because it reads like a bug and is
	-- not one: Yazi's status bar draws it in `perm_exec` too, for the same
	-- reason, and `ChaMode::permissions` is where the `s` comes from.
	eq(
		perm_fgs(stub.file { perm = "srwxr-xr-x" }),
		"#000044 #000022 #000033 #000044 #000022 #000055 #000044 #000022 #000055 #000044"
	)
	-- `?` is a `perm_sep` beside `-`, and arrives nine at a time: `cha:perm()`
	-- on a file Yazi has no metadata for answers a type character and nine of
	-- them. Yazi builds one for a listed entry it cannot stat, and for a
	-- `reveal` of a path that is not there yet.
	eq(
		perm_fgs(stub.file { perm = "-?????????" }),
		"#000055 #000055 #000055 #000055 #000055 #000055 #000055 #000055 #000055 #000055"
	)
end)

test(
	"permissions: a theme with no `[status]` at all still draws the text",
	function()
		eq(text_of(column.cell(column.normalize({ "permissions" }, CFG), stub.file { perm = "drwxr-xr-x" })), "drwxr-xr-x")
	end
)

test("permissions: a colour written for the column takes the theme's place", function()
	-- Flat, for the whole cell: painting the characters over a colour the user
	-- wrote would leave it visible nowhere. `ctx.fg_written` is the question, so
	-- it is the `fg` that does it, from whichever file wrote one.
	local file = stub.file { perm = "drwxr-xr-x" }
	eq(perm_fgs(file, { style = "#00ccff" }), "#00ccff")
	eq(perm_fgs(file, { style = { fg = "#00ccff", bold = true } }), "#00ccff")

	with(stub.th, "supaline", { permissions = "#00ccff" }, function() eq(perm_fgs(file), "#00ccff") end)

	-- `false` is a colour turned off, and the column steps aside for that too:
	-- one span in no colour of its own, which is the row's.
	eq(perm_fgs(file, { style = { fg = false } }), "-")
end)

test("permissions: an attribute or a background reaches the characters, and their colours survive it", function()
	-- The one column in the plugin that paints its own cell, so the one place
	-- the rest of a style has to reach the characters some other way than
	-- through `ctx.style` alone. It does: `perm_spans` patches it over each
	-- character, and the colours survive because this path is reached only
	-- when no layer wrote an `fg`.
	local file = stub.file { perm = "drwxr-xr-x" }

	-- Held against the column drawn plain rather than against a second copy of
	-- the ten-colour literal the test above already pins. What this asserts is
	-- "untouched", and that is what it should be spelled as.
	eq(
		perm_fgs(file, { style = { bold = true, bg = "#1e1e2e" } }),
		perm_fgs(file),
		"the colours are the theme's either way"
	)
	for i, style in ipairs(perm_styles(file, { style = { bold = true, bg = "#1e1e2e" } })) do
		eq(assert(style, "character " .. i .. " lost its style").bold, true, "character " .. i)
		eq(style.bg, "#1e1e2e", "character " .. i)
	end

	-- From the theme as well: `[supaline] permissions = { bold = true }` is a
	-- weight with no colour, so the ten characters keep their own.
	with(stub.th, "supaline", { permissions = ui.Style():bold() }, function()
		eq(perm_fgs(file), "#000011 #000022 #000033 #000044 #000022 #000055 #000044 #000022 #000055 #000044")
		for i, style in ipairs(perm_styles(file)) do
			eq(assert(style).bold, true, "character " .. i)
		end
	end)

	-- And nothing is added when nobody asked, so the common path is the one it
	-- has always been.
	for i, style in ipairs(perm_styles(file)) do
		eq(rawget(assert(style), "bold"), nil, "character " .. i .. " gained an attribute nobody wrote")
	end
end)

--- The same five styles as `STATUS`, with a `bold` and a `bg` of their own on
--- the two a column is most likely to want to argue with. Yazi's preset writes
--- an `fg` and nothing else, and so does every flavor to hand -- but the theme
--- schema allows the rest, and a flavor that takes it up is the only case in
--- which the layering below is visible at all.
local LOUD = {
	perm_type = ui.Style():fg("#000011"):bold(),
	perm_read = ui.Style():fg("#000022"):bold():bg("#330000"),
	perm_write = ui.Style():fg("#000033"),
	perm_exec = ui.Style():fg("#000044"),
	perm_sep = ui.Style():fg("#000055"),
}

test("permissions: a column's own keys beat the theme's, which is why they go over", function()
	-- The rest of the plugin promises that the nearest layer to write a key
	-- wins, and here the `[status]` styles are not a layer at all -- they are
	-- what the column paints with. Under them, a flavor that writes `bold` on
	-- `perm_read` takes `style = { bold = false }` away from the user who wrote
	-- it, in the one column where a written key cannot be seen to have failed.
	local file = stub.file { perm = "drwxr-xr-x" }

	--- The style the `r` is drawn in, which is the character `LOUD` loads.
	---@param opts table?
	---@return table
	local function read_style(opts)
		local spec = { "permissions" }
		for k, v in pairs(opts or {}) do
			spec[k] = v
		end
		local col = column.normalize(spec, CFG)
		local out = with(stub.th, "status", LOUD, function()
			col.refresh()
			return column.cell(col, file)
		end)
		return assert(stub.drawn_styles(out)[2], "the `r` lost its style")
	end

	-- Untouched, so the failures below are about the column and not about the
	-- theme arriving wrong.
	eq(read_style().bold, true)
	eq(read_style().bg, "#330000")

	-- `false` is the attribute taken off, and it has to reach a character that
	-- the theme turned on -- that is the whole of what `false` is for.
	eq(read_style({ style = { bold = false } }).bold, false)
	-- A background written for the column replaces the theme's rather than
	-- sitting behind it where nothing would ever see it.
	eq(read_style({ style = { bg = "#1e1e2e" } }).bg, "#1e1e2e")

	-- And `false` on it does not, which is where the attribute and the colour
	-- part company. `ui.Style` has a removal flag for every attribute and none
	-- for either colour, so `false` on a colour is only ever "nothing written
	-- here": it drops what a nearer layer of supaline's own wrote, and has no
	-- way to reach a `[status]` style, which is not one of those layers.
	-- Pinned rather than left to be discovered, because the two `false`s read
	-- alike and do not behave alike.
	eq(read_style({ style = { bg = false } }).bg, "#330000")

	-- And the colours are still the theme's through all of it: the style going
	-- over carries no `fg`, because a layer that wrote one would have sent this
	-- column down the flat path instead.
	eq(read_style({ style = { bold = false, bg = "#1e1e2e" } }).fg, "#000022")
end)

test("permissions: `refresh` is what follows a theme that moved", function()
	local file = stub.file { perm = "drwxr-xr-x" }
	local col = column.normalize({ "permissions" }, CFG)

	-- The body reassigns the section, and what `with` puts back is what was
	-- there on the way in rather than what the body left.
	with(stub.th, "status", STATUS, function()
		col.refresh()
		eq(stub.first_style(column.cell(col, file)).fg, "#000011")

		-- The flavor arriving after `init.lua`, and a later `app:theme`, look
		-- the same from here: the section is different and the hook runs again.
		stub.th.status = { perm_type = ui.Style():fg("#ff00ff") }
		col.refresh()
		eq(stub.first_style(column.cell(col, file)).fg, "#ff00ff")
	end)
end)

test("owner: an id Yazi could not have produced is refused by the stub", function()
	-- The stub's half of the ownership columns, pinned here because nothing
	-- else would notice it going quiet. `Cha` carries both ids as `u32`, so a
	-- string or a negative number is a file Yazi cannot hand over -- and the
	-- lookups below stringify whatever they are given, so `uid = "root"` would
	-- have rendered `userroot` and passed.
	throws(function() stub.file { uid = "root" } end, "`uid` is a `u32`")
	throws(function() stub.file { gid = -1 } end, "`gid` is a `u32`")
	throws(function() stub.file { uid = 1.5 } end, "whole number")

	-- Left out is the one thing that is not an error: it is what Yazi fills in
	-- where the platform has no owner to name.
	eq(stub.file({}).cha.uid, 0)
	eq(stub.file({}).cha.gid, 0)
end)

test("owner: user:group", function() eq(render("owner", stub.file { uid = 1, gid = 2 }), "user1:group2") end)

test("owner, user and group: blank on a build with no names", function()
	-- Not "a file with no owner", which Yazi cannot hand out: `cha.uid` is a
	-- `u32` and arrives as a number on every platform, so on Windows every
	-- local file carries the 0 the Rust filled in. What is absent there is the
	-- pair of lookups, and that is the only thing worth asking -- a column
	-- keyed on the id would draw `0:0` for the whole listing. `permissions`
	-- goes blank on the same build, for the same kind of reason.
	without_names(function()
		eq(render("owner", stub.file {}), "            ")
		eq(render("user", stub.file {}), "        ")
		eq(render("group", stub.file {}), "        ")

		-- A remote file is the exception and keeps its numbers here as well.
		-- They came off the server, so a host that could not have named them
		-- anyway takes nothing away.
		eq(render("owner", stub.file { uid = 501, gid = 20, url_kind = "sftp" }), "501:20      ")
		eq(render("user", stub.file { uid = 501, gid = 20, url_kind = "sftp" }), "501     ")
	end)
end)

test("owner: a name longer than the column is truncated, not allowed to push", function()
	-- Yazi sizes the file name against whatever the linemode takes, so a cell
	-- that overflowed would eat the name instead.
	eq(render("owner", stub.file { uid = 501, gid = 20 }), "user501:gro…")
end)

test("owner: a remote file keeps its numbers, a local one gets names", function()
	-- `ya.user_name` resolves against this machine, so a name is only right
	-- for a file that lives on it. A search result does, an SFTP one does not.
	eq(render("owner", stub.file { uid = 501, gid = 20, url_kind = "search" }), "user501:gro…")
	eq(render("owner", stub.file { uid = 501, gid = 20, url_kind = "sftp" }), "501:20      ")
	eq(render("owner", stub.file { uid = 501, gid = 20, url_kind = "mount" }), "501:20      ")
end)

test("user and group: the halves of `owner`, drawn on their own", function()
	eq(render("user", stub.file { uid = 1, gid = 2 }), "user1   ")
	eq(render("group", stub.file { uid = 1, gid = 2 }), "group2  ")
end)

test("user and group: a remote file keeps its numbers here too", function()
	-- The same rule `owner` follows, and worth its own assertions: each of the
	-- three reads `is_virtual` for itself, so one of them could lose it and
	-- leave the other two green.
	eq(render("user", stub.file { uid = 501, gid = 20, url_kind = "sftp" }), "501     ")
	eq(render("group", stub.file { uid = 501, gid = 20, url_kind = "sftp" }), "20      ")
	eq(render("user", stub.file { uid = 501, gid = 20, url_kind = "search" }), "user501 ")
end)

test("user and group: a lone column resolves one name, not two", function()
	-- `render` runs for every visible row on every frame, so a name looked up
	-- and dropped is paid for on each of them. Counted rather than timed: the
	-- waste is a call that should not have happened, and a clock would have to
	-- be told how slow is too slow.
	local real = { ya.user_name, ya.group_name }
	local users, groups = 0, 0
	local counts = function(name)
		users, groups = 0, 0
		render(name, stub.file { uid = 1, gid = 2 })
		return users .. ":" .. groups
	end

	with_names(function(uid)
		users = users + 1
		return real[1](uid)
	end, function(gid)
		groups = groups + 1
		return real[2](gid)
	end, function()
		eq(counts("user"), "1:0")
		eq(counts("group"), "0:1")
		-- The pair still wants both, and neither of them twice.
		eq(counts("owner"), "1:1")
	end)
end)

test("count: directories only", function()
	with_history({ files = { 1, 2 } }, function()
		eq(render("count", stub.file { name = "d", is_dir = true }), "    2")
		eq(render("count", stub.file { name = "f.txt" }), "     ")
	end)
end)

-- --- statistics ------------------------------------------------------------

test("stats: extremes skip the values that are not there", function()
	-- Asserted rather than indexed straight. `get` returns nil for a column
	-- that was never registered and `stats` returns nil for a listing with
	-- nothing to measure, so each assert names which one went missing instead
	-- of failing as "attempt to index a nil value" two lines later.
	local def = assert(column._registry["size"], "the `size` column is not registered")
	local st = assert(
		def.stats {
			stub.file { size = 100 },
			stub.file { size = nil }, -- an unevaluated directory
			stub.file { size = 0 }, -- an empty file must not drag the floor down
			stub.file { size = 5000 },
		},
		"a listing with two sizes in it has extremes"
	)
	eq(st.min, 100)
	eq(st.max, 5000)
end)

test("stats: a folder with nothing to measure has no extremes", function()
	local def = assert(column._registry["size"], "the `size` column is not registered")
	eq(def.stats { stub.file { size = nil } }, nil)
end)

test("size: the scale is logarithmic unless something says otherwise", function()
	-- Stated on the definition, because a listing's sizes span orders of
	-- magnitude and a linear ratio puts everything below the largest file on
	-- the floor -- which is what eza's own size gradient does and how it looks.
	-- Nothing else here states one, so a timestamp still gets linear.
	--
	-- Three sources in order, and all three are asked: the definition's own is
	-- only what a column falls back to. `{}` is a `setup` that said nothing
	-- about scale, which is the only way to see the definition's.
	eq(column.normalize("size", NO_SCALE).scale, "log", "nobody said, so the definition's")
	eq(column.normalize("size", CFG).scale, "linear", "a scale written in `setup` outranks it")
	eq(column.normalize({ "size", scale = "log" }, CFG).scale, "log", "and the spec outranks that")
	eq(column.normalize("mtime", NO_SCALE).scale, "linear", "a column that states none falls back to linear")
end)

-- --- what none of them writes ----------------------------------------------

test("no built-in names a colour", function()
	-- The rule `builtin.lua`'s header states, read off the registry rather than
	-- off a list written here, so a built-in added tomorrow is covered by the
	-- same assertion without anyone remembering to extend one.
	--
	-- Over the registered definitions rather than over `builtin.lua`'s text,
	-- which a grep would have read cheaply and read wrong: the header paragraph
	-- stating this rule quotes the spelling it warns against, so the
	-- documentation is the first hit. The definitions are also the last word --
	-- `register` stores the table it was handed, so a field assigned to it
	-- afterwards is as live as one written inside the literal.
	local seen = 0
	for name, def in pairs(column._registry) do
		seen = seen + 1
		eq(def.style, nil, name .. ": a built-in leaves its cell unstyled, so the flavor's colour reaches it")
	end
	-- A loop over an empty table passes, which is the one way this test could
	-- exit green over nothing at all.
	assert(seen > 0, '`require(".builtin")` registered no columns')
end)
