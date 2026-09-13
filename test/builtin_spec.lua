---@diagnostic disable: inject-field

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

test("btime and atime read their own fields", function()
	eq(render("btime", stub.file { btime = OLD, mtime = RECENT }), "12/25  2020")
	eq(render("atime", stub.file { atime = OLD, mtime = RECENT }), "12/25  2020")
end)

-- --- the rest --------------------------------------------------------------

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
--- Returns the foreground of each character in order, so an assertion names
--- the string it expected rather than a list of styles.
---@param file table
---@param opts table?
---@param status table?
---@return string
local function perm_fgs(file, opts, status)
	local spec = { "permissions" }
	for k, v in pairs(opts or {}) do
		spec[k] = v
	end
	local col = column.normalize(spec, CFG)

	local out
	with(stub.th, "status", status == nil and STATUS or status, function()
		col.refresh()
		out = column.cell(col, file)
	end)

	-- Walked rather than read off `_parts` directly: `column.cell` puts what a
	-- render hands back through a `ui.Line` of its own, which Yazi answers with
	-- a new Line wrapping it, so the spans sit a level below the cell.
	local fgs = {}
	local function walk(x)
		if type(x) == "table" and x._parts then
			for _, part in ipairs(x._parts) do
				walk(part)
			end
			return
		end
		local style = stub.style_of(x)
		fgs[#fgs + 1] = style and style.fg or "-"
	end
	walk(out)
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
	-- wrote would leave it visible nowhere.
	eq(perm_fgs(stub.file { perm = "drwxr-xr-x" }, { base = "#00ccff" }), "#00ccff")

	with(
		stub.th,
		"supaline",
		{ permissions = "#00ccff" },
		function() eq(perm_fgs(stub.file { perm = "drwxr-xr-x" }), "#00ccff") end
	)
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
	local def = assert(column.get("size"), "the `size` column is not registered")
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
	local def = assert(column.get("size"), "the `size` column is not registered")
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
		eq(def.base, nil, name .. ": a built-in leaves its cell unstyled, so the flavor's colour reaches it")
		eq(def.ramp, nil, name .. ": a gradient is the user's to ask for, in the spec or in `[supaline]`")
	end
	-- A loop over an empty table passes, which is the one way this test could
	-- exit green over nothing at all.
	assert(seen > 0, '`require(".builtin")` registered no columns')
end)
