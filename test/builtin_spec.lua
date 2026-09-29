--- `builtin.lua`: the formatters, and the fallbacks each column takes when the
--- value it wants is not there.

---@type supaline.ColumnCases
local cases = dofile(ROOT .. "/test/column_case.lua")
local registry = require(".column").new_registry()
local prepare = cases.compiler(registry)
local definitions = require(".builtin").definitions()
for name, def in pairs(definitions) do
	registry.register(name, def)
	if def.refresh then
		def.refresh()
	end
end

-- A `setup` that said nothing about scale, which is the only way a column
-- definition's own is what decides. A local rather than written at the call,
-- where a table constructor is checked for the fields its class requires.
local NO_SCALE = { band = {} }

--- A built-in column's spec, with `opts` written at the use site.
---@param name string
---@param opts table?
---@return table
local function spec_of(name, opts)
	local spec = { name }
	for k, v in pairs(opts or {}) do
		spec[k] = v
	end
	return spec
end

--- Render one built-in column for one file, returning plain text.
---@param name string
---@param file table
---@param opts table?
---@return string
local function render(name, file, opts) return text_of(cases.cell(prepare(spec_of(name, opts)), file)) end

-- --- size ------------------------------------------------------------------

test("size: human-readable, right-aligned in 7 cells", function()
	eq(render("size", stub.file { size = 0 }), "     0B")
	eq(render("size", stub.file { size = 900 }), "   900B")
	eq(render("size", stub.file { size = 819200 }), "   800K")
	eq(render("size", stub.file { size = 92160000 }), "  87.9M")
	-- `ya.readable_size` keeps the mantissa in (1, 1024] and strips a trailing
	-- ".0", so "1023.9K" is as wide as it gets.
	eq(#ya.readable_size(1023.9 * 1024), 7)
end)

test("size: a directory falls back to its entry count, or a dash", function()
	stub.listed = { files = { 1, 2, 3 } }
	eq(render("size", stub.file { name = "d", is_dir = true }), "      3")
	stub.listed = nil
	eq(render("size", stub.file { name = "d", is_dir = true }), "      -", "one Yazi has never listed")
end)

test("size: the scale is logarithmic unless something says otherwise", function()
	-- Stated on the definition, because a listing's sizes span orders of
	-- magnitude and a linear ratio puts everything below the largest file on
	-- the floor. The definition's is only what a column falls back to.
	eq(prepare("size", NO_SCALE).plan.scale, "log", "nobody said, so the definition's")
	eq(prepare("size").plan.scale, "linear", "a scale written in `setup` outranks it")
	eq(prepare({ "size", scale = "log" }).plan.scale, "log", "and the spec outranks that")
	eq(prepare("mtime", NO_SCALE).plan.scale, "linear", "a column that states none falls back to linear")
end)

-- --- times -----------------------------------------------------------------

local RECENT = os.time { year = os.date("*t").year, month = 3, day = 4, hour = 5, min = 6, sec = 0 }
local OLD = os.time { year = 2020, month = 12, day = 25, hour = 1, min = 2, sec = 0 }

test("mtime: time of day within the current year, the year itself before it", function()
	eq(render("mtime", stub.file { mtime = RECENT }), "03/04 05:06")
	eq(render("mtime", stub.file { mtime = OLD }), "12/25  2020")
end)

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

-- --- permissions -----------------------------------------------------------

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

--- The style each character of `permissions` is drawn in, `false` where one
--- carries none, with `th.status` set to `status` -- `STATUS` unless given --
--- and read through the column's `refresh`, which is what main.lua runs on
--- install and on `cd` and the only thing that reads the theme for it.
---@param file table
---@param opts table?
---@param status table?
---@return table[]
local function perm_styles(file, opts, status)
	local col = prepare(spec_of("permissions", opts))
	stub.th.status = status or STATUS
	col.plan.refresh()
	return stub.drawn_styles(cases.cell(col, file))
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

local DIR = "#000011 #000022 #000033 #000044 #000022 #000055 #000044 #000022 #000055 #000044"

test("permissions: every character takes its own style from the theme", function()
	-- Yazi's own mapping, measured against the status bar of a real 26.9.1 and
	-- written down in `.agents/skills/yazi-platform-traps/references/probes.md`:
	-- the character decides, not the position, so the leading `-` of a regular
	-- file is a `perm_sep` like any other bit that is off.
	eq(
		perm_fgs(stub.file { perm = "-rw-r--r--" }),
		"#000055 #000022 #000033 #000055 #000022 #000055 #000055 #000022 #000055 #000055"
	)
	eq(perm_fgs(stub.file { perm = "drwxr-xr-x" }), DIR)
	-- `s` and `t` are execute bits with another bit folded into them, and `l`
	-- is a type character like `d`.
	eq(perm_fgs(stub.file { perm = "lrwsr-xr-t" }), DIR)
	-- `S` and `T` never reached the screen. They are `perm_exec` on the source
	-- instead: `Status:perm()` in `yazi-plugin/preset/components/status.lua` at
	-- 26.9.1 holds `x`, `s`, `S`, `t` and `T` in one branch.
	eq(
		perm_fgs(stub.file { perm = "-rwSr-Sr-T" }),
		"#000055 #000022 #000033 #000044 #000022 #000055 #000044 #000022 #000055 #000044"
	)
	-- A socket's type character is an `s`, and keying on the character sends it
	-- where every other `s` goes -- as Yazi's status bar does.
	eq(
		perm_fgs(stub.file { perm = "srwxr-xr-x" }),
		"#000044 #000022 #000033 #000044 #000022 #000055 #000044 #000022 #000055 #000044"
	)
	-- `?` is a `perm_sep` beside `-`, nine at a time: a file Yazi could not
	-- stat, or a `reveal` of a path that is not there yet.
	eq(perm_fgs(stub.file { perm = "-?????????" }), ("#000055 "):rep(9) .. "#000055")
end)

test("permissions: a theme with no `[status]` at all still draws the text", function()
	local col = prepare("permissions")
	col.plan.refresh()
	eq(text_of(cases.cell(col, stub.file { perm = "drwxr-xr-x" })), "drwxr-xr-x")
end)

test("permissions: a colour written for the column takes the theme's place", function()
	-- Flat, for the whole cell: painting the characters over a colour the user
	-- wrote would leave it visible nowhere. `ctx.fg_written` is the question.
	local file = stub.file { perm = "drwxr-xr-x" }
	eq(perm_fgs(file, { style = "#00ccff" }), "#00ccff")
	eq(perm_fgs(file, { style = { fg = "#00ccff", bold = true } }), "#00ccff")
	-- `false` is a colour turned off, and the column steps aside for that too.
	eq(perm_fgs(file, { style = { fg = false } }), "-")

	stub.th.supaline = { permissions = "#00ccff" }
	eq(perm_fgs(file), "#00ccff", "and so does one the theme wrote")
end)

test("permissions: an attribute or a background reaches the characters, and their colours survive it", function()
	-- The one column that paints its own cell, so the rest of a style has to
	-- reach the characters some other way than through `ctx.style` alone.
	local file = stub.file { perm = "drwxr-xr-x" }
	local loud = { style = { bold = true, bg = "#1e1e2e" } }
	eq(perm_fgs(file, loud), DIR, "the colours are the theme's either way")
	for i, style in ipairs(perm_styles(file, loud)) do
		eq(assert(style, "character " .. i .. " lost its style").bold, true, "character " .. i)
		eq(style.bg, "#1e1e2e", "character " .. i)
	end

	-- And nothing is added when nobody asked.
	for i, style in ipairs(perm_styles(file)) do
		eq(rawget(assert(style), "bold"), nil, "character " .. i .. " gained an attribute nobody wrote")
	end

	-- From the theme as well: a weight with no colour keeps the ten colours.
	stub.th.supaline = { permissions = ui.Style():bold() }
	eq(perm_fgs(file), DIR)
	for i, style in ipairs(perm_styles(file)) do
		eq(assert(style).bold, true, "character " .. i)
	end
end)

test("permissions: a column's own keys beat the theme's, which is why they go over", function()
	-- The `[status]` styles are not a layer, they are what the column paints
	-- with. Under them, a flavor that writes `bold` on `perm_read` would take
	-- `style = { bold = false }` away from the user who wrote it.
	local file = stub.file { perm = "drwxr-xr-x" }
	-- Yazi's preset writes an `fg` and nothing else; a flavor that writes the
	-- rest is the only case in which the layering is visible at all.
	local loud = {
		perm_type = ui.Style():fg("#000011"):bold(),
		perm_read = ui.Style():fg("#000022"):bold():bg("#330000"),
		perm_write = ui.Style():fg("#000033"),
		perm_exec = ui.Style():fg("#000044"),
		perm_sep = ui.Style():fg("#000055"),
	}

	--- The style the `r` is drawn in, which is the character `loud` loads.
	---@param style table?
	---@return table
	local function read_style(style)
		return assert(perm_styles(file, { style = style }, loud)[2], "the `r` lost its style")
	end

	eq(read_style().bold, true, "untouched, so the theme arrived")
	eq(read_style().bg, "#330000")
	eq(read_style({ bold = false }).bold, false, "`false` reaches an attribute the theme turned on")
	eq(read_style({ bg = "#1e1e2e" }).bg, "#1e1e2e", "a background replaces the theme's")
	-- `false` on a colour does not reach it. `ui.Style` has a removal flag for
	-- every attribute and none for either colour, so `false` on a colour only
	-- drops what a nearer layer of supaline's own wrote, and a `[status]` style
	-- is not one of those layers.
	eq(read_style({ bg = false }).bg, "#330000")
	eq(read_style({ bold = false, bg = "#1e1e2e" }).fg, "#000022", "and the colours are still the theme's")
end)

test("permissions: `refresh` is what follows a theme that moved", function()
	local file = stub.file { perm = "drwxr-xr-x" }
	local col = prepare("permissions")

	stub.th.status = STATUS
	col.plan.refresh()
	eq(stub.drawn_styles(cases.cell(col, file))[1].fg, "#000011")

	-- The flavor arriving after `init.lua`, and a later `app:theme`, look the
	-- same from here: the section is different and the hook runs again.
	stub.th.status = { perm_type = ui.Style():fg("#ff00ff") }
	col.plan.refresh()
	eq(stub.drawn_styles(cases.cell(col, file))[1].fg, "#ff00ff")
end)

-- --- owner, user and group -------------------------------------------------

test("owner: user:group, truncated rather than allowed to push", function()
	-- Yazi sizes the file name against whatever the linemode takes, so a cell
	-- that overflowed would eat the name instead.
	eq(render("owner", stub.file { uid = 1, gid = 2 }), "user1:group2")
	eq(render("owner", stub.file { uid = 501, gid = 20 }), "user501:gro…")
end)

test("user and group: the halves of `owner`, drawn on their own", function()
	eq(render("user", stub.file { uid = 1, gid = 2 }), "user1   ")
	eq(render("group", stub.file { uid = 1, gid = 2 }), "group2  ")
end)

test("owner, user and group: a remote file keeps its numbers, a local one gets names", function()
	-- `ya.user_name` resolves against this machine, so a name is only right for
	-- a file that lives on it. A search result does, an SFTP one does not. Each
	-- of the three reads `is_virtual` for itself, so each is asserted.
	local function at(kind) return stub.file { uid = 501, gid = 20, url_kind = kind } end
	eq(render("owner", at("search")), "user501:gro…")
	eq(render("owner", at("sftp")), "501:20      ")
	eq(render("owner", at("mount")), "501:20      ")
	eq(render("user", at("sftp")), "501     ")
	eq(render("group", at("sftp")), "20      ")
	eq(render("user", at("search")), "user501 ")
end)

test("owner, user and group: blank on a build with no names", function()
	-- `cha.uid` is a `u32` on every platform, so on Windows every local file
	-- carries the 0 the Rust filled in, and a column keyed on the id would draw
	-- `0:0`. What is absent there is the pair of lookups, which are
	-- `#[cfg(unix)]` -- so taking them away is what a spec has instead of a
	-- Windows machine.
	ya.user_name = nil
	ya.group_name = nil
	eq(render("owner", stub.file {}), "            ")
	eq(render("user", stub.file {}), "        ")
	eq(render("group", stub.file {}), "        ")

	-- A remote file keeps its numbers here as well: they came off the server.
	eq(render("owner", stub.file { uid = 501, gid = 20, url_kind = "sftp" }), "501:20      ")
	eq(render("user", stub.file { uid = 501, gid = 20, url_kind = "sftp" }), "501     ")
end)

test("user and group: a lone column resolves one name, not two", function()
	-- `render` runs for every visible row on every frame, so a name looked up
	-- and dropped is paid for on each of them. Counted rather than timed.
	local users, groups = 0, 0
	local user, group = ya.user_name, ya.group_name
	ya.user_name = function(uid)
		users = users + 1
		return user(uid)
	end
	ya.group_name = function(gid)
		groups = groups + 1
		return group(gid)
	end
	local function counts(name)
		users, groups = 0, 0
		render(name, stub.file { uid = 1, gid = 2 })
		return users .. ":" .. groups
	end

	eq(counts("user"), "1:0")
	eq(counts("group"), "0:1")
	eq(counts("owner"), "1:1", "the pair wants both, and neither twice")
end)

test("count: directories only", function()
	stub.listed = { files = { 1, 2 } }
	eq(render("count", stub.file { name = "d", is_dir = true }), "    2")
	eq(render("count", stub.file { name = "f.txt" }), "     ")
end)

-- --- statistics ------------------------------------------------------------

test("stats: extremes skip the values that are not there", function()
	local size = assert(definitions["size"], "the `size` column is not registered")
	local st = assert(
		size.stats {
			stub.file { size = 100 },
			stub.file { size = nil }, -- an unevaluated directory
			stub.file { size = 0 }, -- an empty file must not drag the floor down
			stub.file { size = 5000 },
		},
		"a listing with two sizes in it has extremes"
	)
	eq(st.min, 100)
	eq(st.max, 5000)
	eq(size.stats { stub.file { size = nil } }, nil, "and a folder with nothing to measure has none")
end)

-- --- what none of them writes ----------------------------------------------

test("no built-in names a colour", function()
	-- Read off the registry rather than off a list written here, so a built-in
	-- added tomorrow is covered, and rather than off `builtin.lua`'s text, whose
	-- header quotes the spelling it warns against.
	local seen = 0
	for name, def in pairs(definitions) do
		seen = seen + 1
		eq(def.style, nil, name .. ": a built-in leaves its cell unstyled, so the flavor's colour reaches it")
	end
	assert(seen > 0, '`require(".builtin")` registered no columns')
end)
