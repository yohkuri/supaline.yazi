--- `main.lua` through its real entry point: what `setup` registers, what it
--- refuses, how the columns are joined, which panes a linemode reaches, and
--- what a session keeps across a theme event, a `cd` and a column that throws.
---
--- The rendering itself is stubbed, so this says nothing about how any of it
--- looks. `test/e2e.py` is what answers that.

local appearance = require(".appearance")
local config = require(".config")
local session = require(".session")
---@type supaline.Main
local main = require(".main")

local CURRENT = stub.folder("/current", {
	stub.file { name = "a.txt", size = 1 },
	stub.file { name = "b.bin", size = 4096 },
})
local PARENT = stub.folder("/", {
	stub.file { name = "current", is_dir = true, in_current = false },
})
-- The folder under the cursor, drawn in the preview pane. Two rows, because
-- Yazi flags only the first of them as `in_preview` and the second is what
-- catches a pane test that trusts the flag.
local PREVIEW = stub.folder("/current/nested", {
	stub.file { name = "p1.txt", in_current = false, size = 1 },
	stub.file { name = "p2.bin", in_current = false, size = 2 },
})

--- Configure the plugin and point the stubbed context at the folders above.
---@param linemodes table<string, supaline.LinemodeSpec>
---@param opts supaline.Opts?
local function setup(linemodes, opts)
	opts = opts or {}
	opts.linemodes = linemodes
	main.setup({}, opts)

	cx.active.current = CURRENT
	cx.active.parent = PARENT
	-- `skip` is how far the previewer has been scrolled, and nothing here reads
	-- it. Yazi's preview always carries one.
	cx.active.preview = { folder = PREVIEW, skip = 0 }
	cx.active.pref.linemode = next(linemodes)
end

--- Assert that `setup` refuses `opts`, with a message holding every pattern.
--- Typed `any`, because a wrong value is the point.
---@param opts any
---@param ... string
local function refuses(opts, ...)
	throws(function() main.setup({}, opts) end, ...)
end

--- The options for one linemode called `t`.
---@param spec any
---@return any
local function only(spec) return { linemodes = { t = spec } } end

--- Draw one file through a registered linemode, the first current row unless
--- told otherwise.
---@param name string
---@param file table?
---@return string
local function draw(name, file) return text_of(Linemode[name] { _file = file or CURRENT.files[1] }) end

--- Draw every current row, for a test counting what a whole frame calls.
---@param name string
local function draw_all(name)
	for _, file in ipairs(CURRENT.files) do
		draw(name, file)
	end
end

--- The style of each part `file` is drawn in, the first current row unless
--- told otherwise.
---@param name string
---@param file table?
---@return table[]
local function styles_of(name, file) return stub.drawn_styles(Linemode[name] { _file = file or CURRENT.files[1] }) end

--- Draw the first row of `folder`, with `folder` as the current one.
---@param name string
---@param folder supaline.Folder
---@return string
local function draw_in(name, folder)
	cx.active.current = folder
	return draw(name, folder.files[1])
end

--- A folder of one file of `size` bytes.
---@param path string
---@param size integer
---@return supaline.Folder
local function one_file(path, size) return stub.folder(path, { stub.file { name = "one", size = size } }) end

--- Draw one file through the parent/preview child, if one was added.
---@param file table
---@return string
local function draw_child(file)
	if #stub.children == 0 then
		return ""
	end
	return text_of(stub.children[1].fn { _file = file })
end

--- The first style anything in row `i` of the current folder is drawn in, or
--- nil if nothing in it carries one.
---@param name string
---@param i integer?
---@return table?
local function style_in(name, i)
	for _, style in ipairs(styles_of(name, CURRENT.files[i or 1])) do
		if style then
			return style
		end
	end
end

--- Assert that exactly `n` reports were made, each both halves -- `tell` gives
--- `ya.notify` the short sentence and `ya.err` the long one, which alone says
--- what the fault cost the rest of the line -- and return the last one's.
---@param n integer
---@return string said
---@return string logged
local function reported(n)
	eq(#stub.notified, n, "reports on screen")
	eq(#stub.logged, n, "reports in the log")
	local last = stub.notified[n]
	return last and last.content or "", n > 0 and tostring(stub.logged[n][1]) or ""
end

--- A column that draws `text` and asks for no colour, so the only thing in a
--- row built out of these that can carry a style is the separator.
---@param text string
---@return supaline.Render
local function plain(text)
	return function() return text end
end

-- --- registration ----------------------------------------------------------

test("setup: every linemode becomes a Linemode entry", function()
	setup { detail = { "size" }, wide = { "size", "mtime" } }
	eq(type(Linemode.detail), "function")
	eq(type(Linemode.wide), "function")
end)

test("setup: an empty linemode draws nothing, and a built-in keeps its own width", function()
	setup { detail = {} }
	eq(draw("detail"), "")
	setup { detail = { "size" } }
	eq(draw("detail"), "     1B")
end)

test("setup: columns are joined by the separator, replaced per plugin and per linemode", function()
	setup { detail = { { "size", width = 3 }, { "size", width = 3 } } }
	eq(draw("detail"), " 1B  1B")
	setup({ detail = { { "size", width = 2 }, { "size", width = 2 } } }, { separator = "|" })
	eq(draw("detail"), "1B|1B")
	setup { detail = { { "size", width = 2 }, { "size", width = 2 }, separator = "::" } }
	eq(draw("detail"), "1B::1B")
	setup { detail = { { "size", width = 2 }, { "size", width = 2 }, separator = "" } }
	eq(draw("detail"), "1B1B", "an empty separator draws nothing between two columns")
end)

test("setup: `separator = false` drops the separator before a column, first included", function()
	setup { detail = { { "size", width = 3 }, { "size", width = 3, separator = false } } }
	eq(draw("detail"), " 1B 1B")
	-- On the first column it asks for nothing and gets nothing, the one
	-- spelling that agrees with what index 1 draws.
	setup { detail = { { "size", width = 3, separator = false }, { "size", width = 3 } } }
	eq(draw("detail"), " 1B  1B")
end)

test("setup: a `separator` on a pane's first column is refused", function()
	-- Drawn nowhere, so refused while `setup` runs. The pane, not the linemode,
	-- is what has a first column.
	refuses(only { { "size", separator = "|" }, "size" }, "setup.linemodes.t[1].separator: is drawn by nobody")
	refuses(
		only { current = { "size", { "size", separator = "|" } }, parent = { { "size", separator = "|" } } },
		"setup.linemodes.t.parent[1].separator: is drawn by nobody"
	)
end)

test("setup: a registered column's own separator may head a linemode", function()
	-- A separator on a definition is read at every use of it, so refusing one
	-- would stop the column being written first anywhere. It is not drawn.
	main.column("septic", { separator = "|", width = 3, render = function() return "x" end })
	setup { detail = { "septic", "septic" } }
	eq(draw("detail"), "  x|  x")
end)

test("setup: a separator can be drawn in a colour of its own", function()
	setup({ detail = { plain("a"), plain("b") } }, { separator = { " | ", style = { fg = "#585b70" } } })
	eq(draw("detail"), "a | b")
	eq(assert(style_in("detail"), "the separator came back unstyled").fg, "#585b70")
end)

test("setup: a nearer separator replaces a farther one whole, colour and all", function()
	-- Whichever level wrote a separator supplies both halves of it, so a bare
	-- string at the nearer level draws uncoloured rather than borrowing.
	local wide = { separator = { " | ", style = { fg = "#585b70" } } }
	setup({ detail = { plain("a"), { render = plain("b"), separator = "-" } } }, wide)
	eq(draw("detail"), "a-b")
	eq(style_in("detail"), nil, "the nearer separator took the colour with it as well as the text")

	setup({ detail = { plain("a"), plain("b"), separator = { "+", style = { fg = "#00ccff" } } } }, wide)
	eq(draw("detail"), "a+b")
	eq(assert(style_in("detail")).fg, "#00ccff", "and a linemode's carries its own style past the plugin-wide one")
end)

test("setup: `.setup{...}` works as well as `:setup{...}`", function()
	-- The dot form lands the options in the state parameter, where reading them
	-- as the options says "`linemodes` is empty".
	main.setup { linemodes = { dotted = { { "size", width = 3 } } } }
	cx.active.current = CURRENT
	cx.active.pref.linemode = "dotted"
	eq(draw("dotted"), " 1B")
end)

test("setup: overriding one of Yazi's own linemode names is still allowed", function()
	-- Replacing `size` is a thing to want; replacing `redraw` is not, and the
	-- two live on the same table.
	setup { size = { { "size", width = 4 }, { "size", width = 4 } } }
	eq(draw("size"), "  1B   1B")
end)

test("setup: a name Yazi cannot hold is refused, counted in characters", function()
	refuses({ linemodes = { [string.rep("x", 21)] = { "size" } } }, "1 to 20 characters")
	-- Ten characters and thirty bytes, so a byte-length check would refuse it.
	local cjk = "詳細表示モードの名前"
	setup { [cjk] = { { "size", width = 3 } } }
	eq(type(Linemode[cjk]), "function", "a CJK name well inside the limit is kept")
	refuses({ linemodes = { [string.rep("あ", 21)] = { "size" } } }, "1 to 20 characters")
end)

-- --- what setup refuses ----------------------------------------------------

test("setup: a configuration with no linemodes, or not shaped as one, is refused", function()
	refuses({}, "setup.linemodes: names no linemode")
	refuses({ linemodes = {} }, "setup.linemodes: names no linemode")
	refuses({ linemodes = "detail" }, "setup.linemodes: must be a table")
	refuses({ linemodes = { detail = "size" } }, "setup.linemodes.detail: must be a table, got a string")
	-- Columns where the table of linemodes goes: the key is then a position,
	-- and a length rule would read as nonsense about a one-character name.
	refuses({ linemodes = { { "size", "mtime" } } }, "setup.linemodes: is a list", "linemodes = { detail = ")
end)

test("setup: what is not a table of options is refused as the options", function()
	-- Read as a table otherwise, and refused by Lua from inside supaline.
	local setup_any = main.setup --[[@as function]]
	throws(function() setup_any({}, "detail") end, "supaline: setup: must be handed a table of options", "got `detail`")
	throws(function() setup_any("detail") end, "supaline: setup: must be handed a table of options")
end)

test("setup: a refusal is raised as the one sentence it was written as", function()
	-- At level 0, so no position in a file of supaline's is put in front of
	-- the path into the reader's own configuration -- from `column` too.
	local ok, err = pcall(main.setup, {}, { linemodes = { t = { "size" } }, scale = "LOG" } --[[@as any]])
	eq(ok, false)
	eq(err, "supaline: setup.scale: must be `linear` or `log`, got `LOG`")

	local def = { render = function() return "" end, align = "centre" } ---@type any
	ok, err = pcall(main.column, "wonky", def)
	eq(ok, false)
	eq(err, 'supaline: column("wonky").align: must be `left` or `right`, got `centre`')
end)

test("setup: a key `setup` itself does not take is refused", function()
	-- A key in a table constructor is past what the checker reads, and `setup`
	-- takes what it wants by name, so `scal = "log"` would never be applied or
	-- mentioned again. All of them at once and sorted; the two that are real
	-- mistakes rather than misspellings earn a hint.
	local lm = { t = { "size" } }
	refuses({ linemodes = lm, scal = "log" }, "`scal`")
	refuses({ linemodes = lm, seperator = "|" }, "`seperator`")
	refuses({ linemodes = lm, scal = "log", bnad = { from = 0.2 } }, "`bnad`, `scal`")
	refuses({ linemodes = lm, linemode = lm }, "`linemodes` is the spelling")
	refuses({ linemodes = lm, columns = { "size" } }, "columns go inside a linemode")

	-- And the five it does take still go through.
	setup(
		{ t = { { "size", width = 3 } } },
		{ separator = "|", order = 1400, scale = "log", lightness = { fg = { from = 0.2, to = 0.9 } } }
	)
end)

test("setup: a value under `setup`'s own keys is refused by `setup`'s name", function()
	-- Refused as `setup`'s own rather than by whichever column first read it,
	-- which would send the reader to a column they wrote correctly.
	local lm = { t = { "size" } }
	refuses({ linemodes = lm, scale = "LOG" }, "setup.scale: ", "must be `linear` or `log`")
	refuses({ linemodes = lm, scale = "logarithmic" }, "got `logarithmic`")
	refuses({ linemodes = lm, separator = 42 }, "setup.separator: ")
	-- `false` reads like a column's `separator = false` and is falsy, so an `or`
	-- would take it for nothing written and hand back the default separator.
	refuses({ linemodes = lm, separator = false }, "setup.separator: ")
	refuses(only { "size", separator = false }, "setup.linemodes.t.separator: ")
	refuses({ linemodes = lm, lightness = { fg = { from = 0.35 } } }, "setup.lightness.fg.to: ")
	-- A column's own option is the column's to check, and `setup` says so.
	refuses(only { { "mtime", format = {} } }, "setup.linemodes.t[1].format: must be an `os.date` format")

	setup({ t = { "size" } }, { scale = "linear" })
	setup({ t = { "size" } }, { scale = "log" })
	setup({ t = { "size" } }, {})
end)

test("setup: `order` is a whole number, and is where the child sits", function()
	-- Handed to `Linemode:children_add`, which sorts by it, so anything else
	-- raises out of Yazi's own sort, naming nothing a reader wrote.
	local lm = { t = { parent = { "size" } } }
	refuses({ linemodes = lm, order = "late" }, "setup.order: must be a whole number")
	refuses({ linemodes = lm, order = 1.5 }, "got `1.5`")

	setup({ t = { parent = { "size" } } }, { order = 1500 })
	eq(stub.children[1].order, 1500)
	setup { t = { parent = { "size" } } }
	eq(stub.children[1].order, 1400, "and 1400 when nobody said")
end)

test("setup: names that are part of the Linemode component are refused", function()
	-- Yazi keeps the component's machinery on the table the linemodes are
	-- looked up on, and `linemodes.new` would replace the constructor. `solo()`
	-- returns early for `none` and `solo`, so those would silently do nothing.
	local before = Linemode.new
	for _, name in ipairs {
		"new",
		"redraw",
		"padding",
		"children_add",
		"children_remove",
		"_children",
		"_inc",
		"none",
		"solo",
	} do
		refuses({ linemodes = { [name] = { "size" } } }, "part of Yazi's `Linemode` component")
	end
	eq(Linemode.new, before, "the constructor survived")

	-- Asked of `Linemode` rather than listed, so a member a later Yazi adds is
	-- refused too.
	rawset(Linemode, "reflow", function() return "" end)
	local ok, err = pcall(main.setup, {}, { linemodes = { reflow = { "size" } } })
	rawset(Linemode, "reflow", nil)
	eq(ok, false)
	has(tostring(err), "part of Yazi's `Linemode` component")
end)

test("setup: a refused configuration leaves the running one alone", function()
	setup { good = { { "size", width = 3 } } }
	local before = draw("good")
	for _, case in ipairs {
		{ { linemodes = { good = { "size" }, bad = { "size", parnet = { "mark" } } } }, "`parnet`" },
		{ { linemodes = { good = { "size" } }, lightness = { fg = { from = 0.35 } } }, "setup.lightness.fg.to" },
		-- The front door: a `<->` with no range behind it is the refusal rather
		-- than a column drawn at a pair nobody chose.
		{ { linemodes = { good = { { "size", style = "#0b3d91 <->" } } } }, "nothing defines `fg`" },
	} do
		refuses(case[1], case[2])
		eq(draw("good"), before, "the linemode still draws as it did")
	end

	-- The `theme` handler rebuilds from what was kept, so a rejected spec left
	-- there would make every later theme event throw.
	stub.fire("theme")
	eq(draw("good"), before, "and a theme event still rebuilds it")
end)

-- --- panes -----------------------------------------------------------------

test("panes: the default is the current pane alone", function()
	setup { detail = { "size" } }
	eq(#stub.children, 0, "no child is added when no linemode leaves the current pane")
	eq(draw_child(stub.file { name = "x", in_current = false }), "")
end)

test("panes: a pane key opts into the pane it names, and one left out stays bare", function()
	local one = { { "size", width = 3 } }
	local parent_row = stub.file { name = "current", in_current = false, size = 1 }
	setup { detail = { current = one, parent = one } }
	eq(#stub.children, 1, "one child, added once")
	eq(draw_child(parent_row), "  1B", "the parent pane draws, with solo()'s leading space")
	eq(draw_child(CURRENT.files[1]), "", "and the current pane, which solo() drew, is not drawn twice")

	setup { detail = { current = one, preview = one } }
	eq(draw_child(parent_row), "", "the parent pane was not asked for")
	eq(draw_child(PREVIEW.files[1]), "  1B", "the preview pane draws")
end)

test("panes: every preview row draws, not just the one Yazi flags", function()
	-- `in_preview` is true for the previewed folder's cursor row alone.
	setup { detail = { preview = { { "size", width = 3 } } } }
	eq(draw_child(PREVIEW.files[2]), "  2B", "the second preview row")
	setup { detail = { parent = { { "size", width = 3 } } } }
	eq(draw_child(PREVIEW.files[2]), "", "and it is not mistaken for a parent row")
end)

test("panes: a linemode that never asked for the current pane is bare there", function()
	setup { detail = { parent = { { "size", width = 4 } } } }
	eq(draw("detail"), "", "the current pane")
	eq(draw_child(stub.file { name = "current", in_current = false, size = 1 }), "   1B", "the parent pane")
end)

test("panes: each pane draws the columns written under it", function()
	setup {
		detail = {
			current = { { "size", width = 3 }, { "size", width = 4 } },
			parent = { { "size", width = 5 } },
		},
	}
	eq(draw("detail"), " 1B   1B")
	eq(draw_child(stub.file { name = "current", in_current = false, size = 1 }), "    1B")
	eq(draw_child(PREVIEW.files[1]), "", "and the pane nobody named stays bare")
end)

test("panes: what a pane is refused for", function()
	-- A list of columns and pane keys sit in the same table, so half of what is
	-- refused is the two of them together.
	for _, case in ipairs {
		{ { current = true }, "setup.linemodes.t.current: must be a list of columns" },
		-- Leaving the pane out says the same thing, so there is no second way.
		{ { current = {} }, "empty list" },
		-- Once any pane is named, the list is what would be drawn nowhere --
		-- including a list that does not start at 1, which `#` calls empty.
		{ { "size", parent = { "mtime" } }, "drawn nowhere" },
		{ { [2] = "size", parent = { "mtime" } }, "drawn nowhere" },
		-- Every key that is neither a pane nor an option, sorted.
		{ { "size", separatorr = "|" }, "`separatorr`" },
		{ { "size", pane = { "parent" } }, "`pane`" },
		{ { "size", parnet = { "mark" }, preivew = { "mark" } }, "`parnet`, `preivew`" },
		-- `compile` walks a column list with `ipairs`, so an entry it would not
		-- visit is refused rather than dropped.
		{ { current = { "size", separator = "|" } }, "an option goes on the linemode itself" },
		{ { current = { "size", parent = { "size" } } }, "`parent`" },
		{ { current = { [1] = "size", [3] = "mtime" } }, "setup.linemodes.t.current: has a gap" },
		{ { [1] = "size", [3] = "mtime" }, "setup.linemodes.t: has a gap" },
	} do
		refuses(only(case[1]), case[2])
	end
end)

test("setup: a second call replaces what the first installed", function()
	-- `Linemode:redraw()` calls every child it holds, so a second one would draw
	-- the parent and preview panes twice over.
	setup { detail = { parent = { { "size", width = 3 } } } }
	eq(#stub.children, 1, "one child after the first setup")
	setup { detail = { preview = { { "size", width = 3 } } } }
	eq(#stub.children, 1, "still one after the second")
	setup { detail = { "size" } }
	eq(#stub.children, 0, "and none once no linemode leaves the current pane")

	-- Subscribed at load, not in `setup`, so no number of calls can stack them.
	-- Named rather than counted, since `hover` is published too, and subscribed
	-- in place of `rename` it would leave the listing's measurements stale.
	local kinds = {}
	for kind, handlers in pairs(stub.subs) do
		kinds[#kinds + 1] = kind
		eq(#handlers, 1, kind .. " is subscribed once")
	end
	table.sort(kinds)
	eq(table.concat(kinds, " "), "bulk-rename cd delete load move rename theme trash")
end)

test("setup: a linemode a later setup drops is unregistered, and Yazi's own handed back", function()
	-- Yazi draws an unregistered name as literal text, where a name left
	-- registered and empty hides the mistake.
	setup { alpha = { { "size", width = 3 } }, beta = { { "size", width = 3 } } }
	setup { alpha = { { "size", width = 3 } } }
	eq(Linemode.beta, nil, "the dropped name is off the component")

	local before = Linemode.size
	eq(type(before), "function", "Yazi's own `size` is in place to begin with")
	setup { size = { { "size", width = 3 } } }
	assert(Linemode.size ~= before, "expected supaline to have taken `size` over")
	setup { detail = { "size" } }
	eq(Linemode.size, before, "Yazi's own is back once supaline stops claiming it")
end)

test("setup: a column's refresh hook runs on install and on every cd, while in service", function()
	local ran = 0
	main.column("ticking", {
		width = 2,
		render = function(_, ctx) return "ok", ctx.style end,
		refresh = function() ran = ran + 1 end,
	})
	setup { detail = { "ticking" } }
	eq(ran, 1, "run once when the linemode is installed")
	stub.fire("cd")
	eq(ran, 2, "and again on every cd")
	setup { detail = { "size" } }
	stub.fire("cd")
	eq(ran, 2, "a column no longer in service is not refreshed")

	-- One list handed to two panes is compiled once, so its hook runs once;
	-- two lists holding the same column are two columns, since each pane binds
	-- its own width and stats.
	ran = 0
	local both = { "ticking" }
	setup { detail = { current = both, parent = both } }
	eq(ran, 1, "installed once, not once per pane")
	ran = 0
	setup { detail = { current = { "ticking" }, parent = { "ticking" } } }
	eq(ran, 2, "written twice, compiled twice")
end)

-- --- the theme -------------------------------------------------------------

test("theme: a reload re-reads every place a colour can be written", function()
	-- `app:theme` re-reads `theme.toml` mid-run, and the flavor lands with an
	-- unasked `theme` event after `init.lua`, so anything resolved once at
	-- `setup` goes stale with nothing to say so. A function is how a spec
	-- reaches the theme, and one called once is a value. Changing the section
	-- after `setup` is what makes each row say that, and each row's colour is
	-- under one key, so a function ignored has nowhere else to find it.
	local function themed() return th.supaline.x end
	for _, case in ipairs {
		{ "a colour the theme wrote", { detail = { { "size", width = 4 } } }, key = "size" },
		{
			"a ramp the theme wrote",
			{ detail = { { "size", width = 4 } } },
			nil,
			"#0b3d91 -> #ff8800",
			"#111111 -> #00ccff",
			key = "size",
		},
		{ "a column's `style` function", { detail = { { "size", width = 4, style = themed } } } },
		{ "a linemode's separator function", { detail = { plain("a"), plain("b"), separator = { "|", style = themed } } } },
		{
			"the plugin-wide separator function",
			{ detail = { plain("a"), plain("b") } },
			{ separator = { "|", style = themed } },
		},
	} do
		local what, before, after = case[1], case[4] or "#ff8800", case[5] or "#00ccff"
		local key = case.key or "x"
		stub.th.supaline = { [key] = before }
		setup(case[2], case[3])
		eq(assert(style_in("detail", 2), what).fg, "#ff8800", what)
		stub.th.supaline = { [key] = after }
		stub.fire("theme")
		eq(style_in("detail", 2).fg, "#00ccff", what .. ", after the reload")
	end
end)

test("theme: a separator function answering nothing draws uncoloured until the flavor lands", function()
	-- A field only the flavor supplies is nil while `setup` runs, and the table
	-- form allows no style at all, so the separator is drawn plain rather than
	-- in whatever style an unwritten slot happens to hold.
	stub.th.supaline = {}
	setup({ detail = { plain("a"), plain("b") } }, { separator = { "|", style = function() return th.supaline.x end } })
	eq(style_in("detail"), nil, "nothing to draw it in yet")
	stub.th.supaline = { x = "#00ccff" }
	stub.fire("theme")
	eq(assert(style_in("detail")).fg, "#00ccff", "the colour the flavor brought with the event")
end)

test("theme: a ramp in the `[supaline]` section colours the whole range", function()
	-- A theme cannot hold a list, so a ramp reaches a plugin as a string. End to
	-- end: the section is read, the endpoints parsed, the folder pass finds the
	-- extremes, and the two files land on the two ends.
	stub.th.supaline = { size = "#0b3d91 -> #7fd4ff" }
	setup { detail = { { "size", width = 4 } } }
	eq(style_in("detail", 1).fg, "#0b3d91", "the smallest file")
	eq(style_in("detail", 2).fg, "#7fd4ff", "the largest")
end)

test("theme: a themed `<->` is drawn at the `fg` range `setup` defines, through a reload", function()
	-- A theme field is a bare string and a bare string is the `fg` key, so the
	-- name is the whole of how the two files meet: a flavor writes the hue, a
	-- reader's `setup` the two lightnesses. A reload resolves the styles again,
	-- and has to find the ranges still there. Written backwards, the way a light
	-- terminal asks for it: `from` is what ratio 0 draws, so the pair carries
	-- its own direction and `setup` takes it as written.
	stub.th.supaline = { size = "#0b3d91 <->" }
	setup({ detail = { { "size", width = 4 } } }, { lightness = { fg = { from = 0.90, to = 0.40 } } })
	eq(style_in("detail", 2).fg, "#0c4098", "the largest file is dark")
	eq(style_in("detail", 1).fg, "#ccdfff", "and the smallest pale")
	stub.fire("theme")
	eq(style_in("detail", 2).fg, "#0c4098", "and again after a reload")
end)

test("setup: a `style` function's range name is read on the pass that draws", function()
	-- The name inside what a function returned is resolved on each build, not
	-- kept from the first.
	local asked = 0
	local style = function()
		asked = asked + 1
		return "#0b3d91 <-> dim"
	end
	setup({ detail = { { "size", width = 4, style = style } } }, { lightness = { dim = { from = 0.50, to = 0.70 } } })
	eq(style_in("detail", 2).fg, "#649cff", "`dim`, not `fg`")
	stub.fire("theme")
	eq(asked, 2, "called again on the rebuild")
	eq(style_in("detail", 2).fg, "#649cff", "and resolved again")
end)

test("theme: a reload the theme breaks keeps what drew, and says so", function()
	-- Raised from a `ps.sub` handler, the refusal would reach nobody and the
	-- reload would look like a plugin that ignored the event.
	local passes = 0
	main.column("kept", {
		width = 3,
		stats = function() passes = passes + 1 end,
		render = function(_, ctx) return "x", ctx.style end,
	})
	stub.th.supaline = { kept = "#ff8800" }
	setup { detail = { "kept" } }
	eq(style_in("detail").fg, "#ff8800")

	stub.th.supaline = { kept = "nosuchcolour" }
	stub.fire("theme")
	eq(style_in("detail").fg, "#ff8800", "the last theme that compiled keeps drawing")
	eq(passes, 1, "over the listing it had already measured")
	-- Cut back to the sentence the message was written as: `pcall` hands back
	-- what Lua and Yazi wrapped around it, and `ya.notify` draws every line.
	eq(
		reported(1),
		"supaline: theme [supaline].kept: `nosuchcolour` is not a colour Yazi "
			.. "accepts. Write `#rrggbb`, a name such as `cyan`, a 256-colour index as a string such "
			.. "as `129`, or `reset`"
	)

	stub.th.supaline = { kept = "#00ccff" }
	stub.fire("theme")
	eq(style_in("detail").fg, "#00ccff", "and the next theme that compiles is taken")
end)

-- --- the plan --------------------------------------------------------------

--- `opts` compiled the way `setup` compiles, against a registry holding one
--- column, `probe`, that draws its stats and its style.
local function compile(opts)
	local r = require(".column").new_registry()
	r.register("probe", { render = function(_, ctx) return tostring(ctx.stats), ctx.style end })
	return config.compile(opts, r, function() return false end)
end

test("plan: compiling neither reads a theme nor calls a style function", function()
	-- Both styles here are functions, which compiling keeps to call later, so
	-- `th` and `ui` can be taken away while it runs.
	local calls = 0
	local function counted(colour)
		return function()
			calls = calls + 1
			return colour
		end
	end
	local opts = {
		separator = { "|", style = counted("red") },
		linemodes = { detail = { { "probe", style = counted("blue") } } },
	}
	_G.th = nil
	_G.ui = nil
	local plan = compile(opts)
	stub.reset()
	eq(calls, 0)
	appearance.resolve(plan, {})
	eq(calls, 2, "resolving the appearance calls both")
end)

test("plan: a style written as a value is read once, at `setup`", function()
	-- Read rather than copied, so what a table reaches through `__index` is read
	-- as well, and nothing written to either afterwards reaches the plan.
	local inherited = { fg = "red" }
	local written = setmetatable({ bold = true }, { __index = inherited })
	local plan = compile { linemodes = { detail = { { "probe", style = written } } } }
	inherited.fg, written.bold = "blue", false
	local paint = appearance.resolve(plan, {})[plan.columns[1].slot]
	eq(paint.style:raw().fg, "Red")
	eq(paint.style:raw().bold, true)

	-- A `ui.Style` is read through `raw()`, the same way.
	local opaque = compile { linemodes = { detail = { { "probe", style = ui.Style():fg("green") } } } }
	eq(appearance.resolve(opaque, {})[opaque.columns[1].slot].style:raw().fg, "Green")
end)

test("plan: a theme reload cannot change what `setup` was handed", function()
	-- Everything a reader wrote is the plan's once `setup` returns: a reload
	-- re-reads the theme, not the tables. An option payload a column declares
	-- is borrowed rather than cloned, and only a new `setup` takes the rest.
	local definition = {
		width = 3,
		options = { "text", "state" },
		text = "old",
		state = { suffix = "" },
		style = { fg = "red" },
		render = function(_, ctx) return ctx.opts.text .. ctx.opts.state.suffix, ctx.style end,
	}
	main.column("snapshot", definition)
	local separator = { "|", style = { fg = "blue" } }
	local entry = { "snapshot", style = { bold = true } }
	local list = { entry, function() return "x" end }
	local opts = { separator = separator, linemodes = { snap = list } }
	main.setup(opts)
	local at = one_file("/snapshot", 1)
	eq(draw_in("snap", at), "old|x")

	definition.width, definition.text, definition.style.fg = 8, "new", "green"
	entry.style.bold, separator[1], separator.style.fg = false, "/", "yellow"
	list[2] = function() return "y" end
	opts.linemodes.extra = { "size" }
	stub.fire("theme")
	eq(draw_in("snap", at), "old|x")
	local parts = styles_of("snap", at.files[1])
	eq(parts[1].fg, "red")
	eq(parts[1].bold, true)
	eq(parts[2].fg, "blue")
	eq(Linemode.extra, nil)

	definition.state.suffix = "!"
	eq(draw_in("snap", at), "ol…|x", "the option payload is borrowed")
	definition.state.suffix = ""
	main.setup(opts)
	eq(draw_in("snap", at), "     new/y")
	eq(type(Linemode.extra), "function")
end)

test("plan: pane lists, mode separators and named ranges are owned by the plan", function()
	local lightness = { fg = { from = 0.35, to = 0.88 } }
	local sep = { ":", style = { fg = "cyan" } }
	---@type supaline.ColumnSpec[]
	local current = { { "size", style = "#0b3d91 <->" }, "mtime" }
	local spec = { current = current, separator = sep }
	main.setup { lightness = lightness, linemodes = { snap = spec } }
	local at = one_file("/ranges", 20)
	cx.active.current = at
	local before = styles_of("snap", at.files[1])

	lightness.fg.from, lightness.fg.to = 0.1, 0.2
	sep[1], sep.style.fg = "/", "red"
	spec.current = { "count" }
	current[1] = "permissions"
	stub.fire("theme")
	local after = styles_of("snap", at.files[1])
	eq(after[1].fg, before[1].fg)
	eq(after[2].fg, "cyan")
	has(draw_in("snap", at), ":")
end)

test("plan: re-registering a definition takes effect only on `setup`", function()
	main.column("replace", { render = function() return "old" end })
	local opts = { linemodes = { replace = { "replace" } } }
	main.setup(opts)
	main.column("replace", { render = function() return "new" end })
	stub.fire("theme")
	local at = one_file("/replace", 1)
	eq(draw_in("replace", at), "old")
	main.setup(opts)
	eq(draw_in("replace", at), "new")
end)

-- --- the per-folder pass ---------------------------------------------------

test("stats: the pass runs once per folder, not once per row", function()
	local calls = 0
	main.column("counted", {
		width = "auto",
		stats = function()
			calls = calls + 1
			return nil
		end,
		render = function() return "x" end,
	})
	setup { detail = { "counted" } }
	draw_all("detail")
	eq(calls, 1, "every row, one pass")
end)

test("rendering: what a frame does through wrappers does not grow with the folder", function()
	-- An `auto` column in every pane, so the per-file width pass runs as well
	-- as the per-row draw, and a computed one, whose once-per-folder read is
	-- what this allows.
	main.column("measured", { width = "auto", render = function(file) return file.name end })
	main.column("computed", { width = function() return 3 end, render = function() return "x" end })
	local cols = { "size", "measured", "computed" }

	--- `n` files, in the current pane or not.
	---@param n integer
	---@param current boolean
	---@return supaline.File[]
	local function files(n, current)
		local out = {}
		for i = 1, n do
			out[i] = stub.file { name = "f" .. i, size = i, in_current = current }
		end
		return out
	end

	--- The wrappers one first frame builds and calls, with `n` files in every
	--- pane.
	---@param n integer
	---@return integer
	local function crossings(n)
		setup { detail = { current = cols, parent = cols, preview = cols } }
		cx.active.current = stub.folder("/current", files(n, true))
		cx.active.parent = stub.folder("/", files(n, false))
		cx.active.preview = { folder = stub.folder("/current/nested", files(n, false)), skip = 0 }
		local before = stub.wrappers
		for _, file in ipairs(cx.active.current.files) do
			draw("detail", file)
		end
		for _, pane in ipairs { cx.active.parent, cx.active.preview.folder } do
			for _, file in ipairs(pane.files) do
				draw_child(file)
			end
		end
		return stub.wrappers - before
	end

	eq(
		crossings(4),
		crossings(2),
		"a module's function read or called through a wrapper per row or per file; take it off `__mod` at load,"
			.. " and see `session.lua` for what that costs a render"
	)
end)

test("stats: a column with a stated width still receives them", function()
	local seen = "not called"
	main.column("stated", {
		width = 6,
		stats = function() return { min = 1, max = 42 } end,
		render = function(_, ctx)
			seen = ctx.stats and ctx.stats.max or "nil"
			return ""
		end,
	})
	setup { detail = { "stated" } }
	draw("detail")
	eq(seen, 42)
end)

test("stats: each pane is measured against its own folder", function()
	local seen = {}
	main.column("seen", {
		width = "auto",
		stats = function(files)
			seen[#seen + 1] = #files
			return nil
		end,
		render = function() return "x" end,
	})
	local one = { "seen" }
	setup { detail = { current = one, parent = one } }
	draw("detail")
	draw_child(stub.file { name = "current", in_current = false })
	eq(#seen, 2, "one pass per folder")
	eq(seen[1], #CURRENT.files)
	eq(seen[2], #PARENT.files, "the parent row was measured against the parent folder")
end)

test("stats: a write that keeps the count is measured again on `load` and on `cd`", function()
	-- The cached pass is keyed by the linemode, the folder and its file count,
	-- so a write that leaves the count alone looks like the listing before it.
	-- `load` is Yazi saying the folder changed, and it has drawn the change by
	-- the time a handler runs, so the folder dropped asks for another frame or
	-- the stale one stays up. `cd` says the listing may have moved on.
	local written = { name = "a.bin", size = 1 }
	local here = stub.folder("/here", { stub.file(written) })
	setup { detail = { { "size", width = "auto" } } }
	eq(draw_in("detail", here), "1B")
	written.size = 999999
	stub.fire("load", { url = here.cwd })
	eq(stub.renders, 1, "a frame is asked for")
	eq(draw_in("detail", here), "976.6K", "the width and the value both follow the folder")
	written.size = 1
	stub.fire("cd")
	eq(draw_in("detail", here), "1B", "and follow it again after a `cd`")
end)

test("listing: `load` forgets the folder it names and no other", function()
	-- Yazi publishes it for every folder the cursor previews, so forgetting
	-- more would measure the current folder again on every step.
	local passes = {}
	main.column("counted", {
		width = 1,
		stats = function(files) passes[files[1]] = (passes[files[1]] or 0) + 1 end,
		render = function() return "x" end,
	})
	setup { detail = { "counted" } }
	local a, b = one_file("/a", 1), one_file("/b", 2)
	draw_in("detail", a)
	draw_in("detail", b)
	stub.fire("load", { url = a.cwd })
	draw_in("detail", a)
	draw_in("detail", b)
	eq(passes[a.files[1]], 2, "the folder named is measured again")
	eq(passes[b.files[1]], 1, "the other is not")
	eq(stub.renders, 1)
	stub.fire("load", { url = one_file("/never", 3).cwd })
	eq(stub.renders, 1, "a folder nothing prepared asks for no frame")
end)

test("listing: panes never share a context, and a cached folder keeps its own", function()
	-- A context handed to a column is the column's to keep, so the next pane
	-- or folder builds another rather than rebinding it.
	local seen, stats_calls, styles, refreshes = {}, 0, 0, 0
	local shared = {
		{
			stats = function(files)
				stats_calls = stats_calls + 1
				return { min = 1, max = files[1]:size() }
			end,
			width = function(stats) return stats.max end,
			refresh = function() refreshes = refreshes + 1 end,
			style = function()
				styles = styles + 1
				return "red"
			end,
			render = function(file, ctx)
				seen[file:size()] = ctx
				return "x", ctx.style
			end,
		},
	}
	main.setup { linemodes = { panes = { current = shared, parent = shared, preview = shared } } }
	local current, parent, preview = one_file("/p/current", 3), one_file("/p", 5), one_file("/p/current/preview", 7)
	parent.files[1].in_current, preview.files[1].in_current = false, false
	cx.active.current, cx.active.parent = current, parent
	cx.active.preview = { folder = preview, skip = 0 }
	cx.active.pref.linemode = "panes"
	for _ = 1, 3 do
		draw("panes", current.files[1])
		draw_child(parent.files[1])
		draw_child(preview.files[1])
	end
	eq(styles, 1)
	eq(refreshes, 1)
	eq(stats_calls, 3)
	eq(seen[3] == seen[5], false)
	eq(seen[5] == seen[7], false)
	for _, n in ipairs { 3, 5, 7 } do
		eq(seen[n].width, n)
		eq(seen[n].ratio(n), 1)
	end

	local saved = seen[3]
	draw("panes", current.files[1])
	eq(saved, seen[3], "rows in one cached folder share a context")
	stub.fire("cd")
	draw("panes", current.files[1])
	eq(refreshes, 2)
	eq(saved == seen[3], false)
	eq(saved.width, 3, "invalidating never changes a context already handed out")
end)

test("listing: a folder no pane holds is its own per mode and pane", function()
	local seen = {}
	local function entry(name, width)
		return {
			width = width,
			render = function(_, ctx)
				seen[name] = ctx
				return name
			end,
		}
	end
	local plan = compile { linemodes = { a = { parent = { entry("a", 2) } }, b = { parent = { entry("b", 4) } } } }
	local run = session.new(plan, {}, function() error("unexpected report") end)
	local file = stub.file {}
	eq(text_of(run.draw(plan.modes.a, "parent", file)), " a")
	eq(text_of(run.draw(plan.modes.b, "parent", file)), "   b")
	eq(seen.a == seen.b, false)
end)

test("listing: the ninth folder clears the eight-entry cache", function()
	local seen, passes = {}, 0
	main.setup {
		linemodes = {
			bounded = {
				{
					stats = function() passes = passes + 1 end,
					render = function(file, ctx)
						seen[file:size()] = ctx
						return "x"
					end,
				},
			},
		},
	}
	local first = one_file("/cache/1", 1)
	draw_in("bounded", first)
	local saved = seen[1]
	for i = 2, 8 do
		draw_in("bounded", one_file("/cache/" .. i, i))
	end
	draw_in("bounded", first)
	eq(seen[1], saved)
	eq(passes, 8)
	draw_in("bounded", one_file("/cache/9", 9))
	draw_in("bounded", first)
	eq(passes, 10)
	eq(seen[1] == saved, false)
end)

test("listing: a reload measures again, and leaves old contexts as they were", function()
	-- A `refresh` that reads the theme can change what `render` draws, so an
	-- `auto` width measured before the reload is stale after it.
	local text, passes, callbacks = "old", 0, 0
	local seen ---@type supaline.Ctx?
	main.setup {
		linemodes = {
			themed = {
				{
					width = "auto",
					stats = function() passes = passes + 1 end,
					refresh = function() text = th.supaline and th.supaline.text or "old" end,
					style = function()
						callbacks = callbacks + 1
						return "red"
					end,
					render = function(_, ctx)
						seen = ctx
						return text, ctx.style
					end,
				},
			},
		},
	}
	local at = one_file("/theme", 1)
	eq(draw_in("themed", at), "old")
	local old = assert(seen)
	for _ = 1, 10 do
		draw_in("themed", at)
		eq(seen, old)
	end
	eq(passes, 1)
	eq(callbacks, 1)

	stub.th.supaline = { text = "longer" }
	stub.fire("theme")
	eq(draw_in("themed", at), "longer")
	eq(assert(seen).width, 6)
	eq(old.width, 3)
	eq(passes, 2)
	eq(callbacks, 2)
end)

-- --- reports ---------------------------------------------------------------

test("stats: a ramp with no extremes to place a row against says so, once", function()
	-- Said rather than raised: this is knowable only inside a render pass, and
	-- an `error` from there takes the whole screen down. Measured on 26.9.1:
	-- `ya.notify` from a linemode render reaches the screen and the rows draw.
	main.column("wrong_stats", {
		width = 6,
		stats = function() return { count = 3 } end,
		style = "#0b3d91 -> #7fd4ff",
		render = function() return "x" end,
	})
	setup { detail = { "wrong_stats" } }
	draw_all("detail")
	has(reported(1), "`wrong_stats`", "no `min` and `max`")
	eq(draw("detail"), "     x", "and it kept drawing")
end)

test("stats: extremes that are not numbers are reported rather than raised", function()
	-- `listing.context` takes `math.log` of them from supaline's own folder
	-- pass, outside the `pcall` a column's functions go under.
	main.column("worded_stats", {
		width = 6,
		scale = "log",
		stats = function() return { min = "a", max = "z" } end,
		style = "#0b3d91 -> #7fd4ff",
		render = function() return "x" end,
	})
	setup { detail = { "worded_stats" } }
	eq(draw("detail"), "     x", "the row drew")
	has(reported(1), "`worded_stats`")
end)

test("stats: a column that is not a ramp, or has nothing to measure, owes nobody extremes", function()
	-- `stats` also derives a width or carries what `render` reads, and a report
	-- pointed at that would be the check crying about correct code. `nil` is a
	-- listing with no value to take extremes of, which is not a mistake either.
	main.column("widened", {
		width = function(stats) return stats and stats.widest or 4 end,
		stats = function() return { widest = 5 } end,
		render = function() return "x" end,
	})
	main.column("empty_stats", {
		width = 6,
		stats = function() return nil end,
		style = "#0b3d91 -> #7fd4ff",
		render = function() return "x" end,
	})
	main.column("bare", { width = 3, render = function() return "x" end })
	setup { detail = { "widened", "empty_stats", "bare" } }
	draw_all("detail")
	reported(0)
end)

test("throwing: a `render` that throws is kept inside that column's cells", function()
	-- Measured on 26.9.1: an error raised under a linemode's render fails the
	-- whole `Root` component, so the file list, the header and the status bar
	-- stop drawing on every frame, with nothing on screen or in the log. The
	-- reader's own `render` is the one that raises, which is why the
	-- containment cannot live beside the plugin's own refusals.
	main.column("fine", { width = 2, render = function() return "ok" end })
	main.column("thrower", { width = 3, render = function() error("a column of mine is broken") end })
	setup { detail = { "fine", "thrower" } }
	draw_all("detail")
	local said, logged = reported(1)
	has(said, "`thrower`", "`render`", "a column of mine is broken")
	-- The marker sentence belongs to `render` alone, the one stage that fills.
	has(logged, "filled with")
	eq(draw("detail"), "ok !!!", "the line still draws")
end)

test("throwing: a thrown value whose `__tostring` throws is reported, not raised again", function()
	-- The report turns what was thrown into text, and a value's `__tostring`
	-- is the column's own code; raised from there, it would reach the render
	-- the call that caught it was containing.
	local mute = setmetatable({}, { __tostring = function() error("cannot say") end })
	main.column("mute", { width = 3, render = function() error(mute) end })
	setup { detail = { "mute" } }
	draw_all("detail")
	has(reported(1), "`mute`", "`render`", "a table whose `__tostring` threw")
	eq(draw("detail"), "!!!", "the line still draws")
end)

test("throwing: a `stats` that throws leaves the rest of the line drawing", function()
	-- `render` never asked for the stats, so the column draws as it would have.
	main.column("bad_stats", {
		width = 6,
		stats = function() error("no stats for you") end,
		render = function() return "x" end,
	})
	setup { detail = { "bad_stats" } }
	draw("detail")
	has(reported(1), "`stats`")
	eq(draw("detail"), "     x")
end)

test("throwing: a ramp whose `stats` threw is told off once, not twice", function()
	-- A ramp asking whether what came back carried extremes would otherwise
	-- report "no `min` and `max`" about a function that never came back.
	main.column("thrown_ramp", {
		width = 6,
		stats = function() error("no stats for you") end,
		style = "#0b3d91 -> #7fd4ff",
		render = function() return "x" end,
	})
	setup { detail = { "thrown_ramp" } }
	draw("detail")
	local said, logged = reported(1)
	has(said, "threw")
	lacks(logged, "filled with")
end)

test("throwing: a `width` function that throws draws unpadded rather than not at all", function()
	-- The width pass runs on the first row drawn, when there is a folder to
	-- measure. No width is invented, so the cell is whatever `render` returned:
	-- ragged, readable, and arriving with a message saying so.
	main.column("bad_width", { width = function() error("cannot size this") end, render = function() return "x" end })
	setup { detail = { "bad_width" } }
	local first = draw("detail")
	local said, logged = reported(1)
	has(said, "`width`")
	-- Its own sentence rather than `render`'s: every cell is drawn, so a marker
	-- sends the reader looking for something only a `render` writes.
	lacks(logged, "filled with")
	has(logged, "unpadded")
	eq(first, "x")
end)

test('throwing: a `render` that throws under `width = "auto"` is named as a `render`', function()
	-- Measuring an `auto` column renders every file, so the throw comes out of
	-- the width pass -- but there is no `width` function to have thrown. One
	-- report for the column, measuring pass and rows together.
	main.column("fine", { width = 2, render = function() return "ok" end })
	main.column("auto_thrower", { width = "auto", render = function() error("a column of mine is broken") end })
	setup { detail = { "fine", "auto_thrower" } }
	draw_all("detail")
	local said = reported(1)
	has(said, "`auto_thrower`", "`render`", "a column of mine is broken")
	lacks(said, "`width`")
	eq(draw("detail"), "ok !", "no width to pad to, so one `!`")
end)

test("throwing: a `refresh` that throws is reported rather than propagated", function()
	-- From `moved` it runs inside a `ps.sub` handler, where a throw would stop
	-- the hooks queued after it with nothing on screen; from `install` it runs
	-- after `setup` has committed, where a throw would leave every linemode
	-- unregistered and drawn as literal text.
	local ran = 0
	main.column(
		"bad_refresh",
		{ width = 2, refresh = function() error("cannot refresh this") end, render = function() return "ok" end }
	)
	main.column(
		"good_refresh",
		{ width = 2, refresh = function() ran = ran + 1 end, render = function() return "ok" end }
	)
	-- The thrower first, so the hook that must go on running is the one after it.
	setup { detail = { "bad_refresh", "good_refresh" } }
	eq(ran, 1, "the hook queued after the throwing one still ran")
	eq(draw("detail"), "ok ok", "and the linemode reached `Linemode` and draws")

	local said, logged = reported(1)
	has(said, "`bad_refresh`", "`refresh`", "cannot refresh this")
	-- Read off the log, since the screen's half carries no cost sentence at any
	-- stage: what a failed refresh costs is a stale cache, not a marked cell.
	lacks(logged, "filled with")
	has(logged, "cached")

	stub.fire("cd")
	eq(ran, 2, "the working hook goes on running")
	reported(1)
end)

test("throwing: a theme reload does not re-arm a column's report, and `setup` does", function()
	-- Yazi fires `theme` unasked a few milliseconds after `init.lua`, so a gate
	-- a reload re-armed would report every fault twice at startup. A hook and a
	-- drawing stage, because they reach the one gate by different paths.
	main.column(
		"torn_hook",
		{ width = 2, refresh = function() error("cannot refresh this") end, render = function() return "ok" end }
	)
	main.column("torn_cell", { width = 2, render = function() error("cannot draw this") end })
	setup { detail = { "torn_hook", "torn_cell" } }
	draw("detail")
	reported(2)
	stub.fire("theme")
	draw("detail")
	reported(2)
	setup { detail = { "torn_hook", "torn_cell" } }
	draw("detail")
	reported(4)
end)

test("width: a function returning no usable number is reported as itself", function()
	-- Nothing throws: the function returns a width supaline will not take, and
	-- the reader is told what it returned rather than that it threw. Same
	-- fallback as a throw, because the pass is left with the same nothing.
	main.column("zero_width", { width = function() return 0 end, render = function() return "x" end })
	setup { detail = { "zero_width" } }
	local first = draw("detail")
	local said = reported(1)
	has(said, "returned `0`", "must return a whole number of cells")
	lacks(said, "threw")
	eq(first, "x")
end)

test("told: a column wrong in two kinds says both, once each", function()
	-- The gate is keyed by column and kind, and every other spec gives a column
	-- one fault. A ramp with no extremes and a width supaline will not take are
	-- two things about the same column, and one suppressing the other would
	-- leave the reader repairing one and finding the other unsaid.
	main.column("two_faults", {
		width = function() return 0 end,
		stats = function() return {} end,
		style = { fg = "#000080 -> #ff8800" },
		render = function(_, ctx) return "x", ctx.style_at(ctx.ratio(1)) end,
	})
	setup { detail = { "two_faults" } }
	draw_all("detail")
	reported(2)
	local kinds = {}
	for _, note in ipairs(stub.notified) do
		has(note.content, "`two_faults`")
		kinds[#kinds + 1] = note.content:find("no `min` and `max`", 1, true) and "extremes"
			or note.content:find("returned `0`", 1, true) and "width"
			or "?"
	end
	table.sort(kinds)
	eq(table.concat(kinds, " "), "extremes width")
end)

test("width: a `max_width` outlives the function that failed, as a cap", function()
	-- A cap is not a width: padding every cell to it would be a fixed width the
	-- reader never asked for, beside a message saying the column is unpadded.
	main.column("capped", {
		width = function() error("cannot size this") end,
		render = function(file) return file.name == "a.txt" and "x" or "abcdefgh" end,
	})
	setup { detail = { { "capped", max_width = 4 } } }
	eq(draw("detail"), "x", "unpadded, so a short cell stays short")
	eq(draw("detail", CURRENT.files[2]), "abc…", "and a long one is still cut at the cap")
end)
