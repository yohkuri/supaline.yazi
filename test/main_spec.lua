--- `main.lua` through its real entry point: what `setup` registers, what it
--- refuses, how the columns are joined, and which panes a linemode reaches.
---
--- The rendering itself is stubbed, so this says nothing about how any of it
--- looks. `test/e2e.sh` is what answers that.

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
	-- it. Yazi's preview always carries one, so leaving it out is the stub
	-- starting to drift.
	cx.active.preview = { folder = PREVIEW, skip = 0 }
	cx.active.pref.linemode = next(linemodes)
end

--- Draw one file through a registered linemode.
---@param name string
---@param file table
---@return string
local function draw(name, file) return text_of(Linemode[name] { _file = file }) end

--- Draw one file through the parent/preview child, if one was added.
---@param file table
---@return string
local function draw_child(file)
	if #stub.children == 0 then
		return ""
	end
	return text_of(stub.children[1].fn { _file = file })
end

-- --- registration ----------------------------------------------------------

test("setup: every linemode becomes a Linemode entry", function()
	setup { detail = { "size" }, wide = { "size", "mtime" } }
	eq(type(Linemode.detail), "function")
	eq(type(Linemode.wide), "function")
end)

test("setup: columns are joined by the separator", function()
	setup { detail = { { "size", width = 3 }, { "size", width = 3 } } }
	eq(draw("detail", CURRENT.files[1]), " 1B  1B")
end)

test("setup: the separator can be replaced per plugin and per linemode", function()
	setup({ detail = { { "size", width = 2 }, { "size", width = 2 } } }, { separator = "|" })
	eq(draw("detail", CURRENT.files[1]), "1B|1B")

	setup { detail = { { "size", width = 2 }, { "size", width = 2 }, separator = "::" } }
	eq(draw("detail", CURRENT.files[1]), "1B::1B")
end)

test("setup: `separator = false` drops the separator before a column", function()
	setup { detail = { { "size", width = 3 }, { "size", width = 3, separator = false } } }
	eq(draw("detail", CURRENT.files[1]), " 1B 1B")
end)

test("setup: a `separator` on a pane's first column is refused", function()
	-- `render` guards the separator with `i > 1`, so this one is drawn
	-- nowhere. Refused rather than ignored, and refused while `setup` runs
	-- rather than a session later.
	throws(
		function() main.setup({}, { linemodes = { t = { { "size", separator = "|" }, "size" } } }) end,
		"the first column of `current` on linemode `t`"
	)

	-- The pane, not the linemode, is what has a first column: this one is
	-- second in the current pane and first in the parent, and it is the
	-- parent the message names.
	throws(
		function()
			main.setup({}, {
				linemodes = {
					t = {
						current = { "size", { "size", separator = "|" } },
						parent = { { "size", separator = "|" } },
					},
				},
			})
		end,
		"the first column of `parent` on linemode `t`"
	)
end)

test("setup: `separator = false` on a pane's first column is accepted", function()
	-- It asks for nothing and gets nothing, which is the one spelling that
	-- agrees with what index 1 draws.
	setup { detail = { { "size", width = 3, separator = false }, { "size", width = 3 } } }
	eq(draw("detail", CURRENT.files[1]), " 1B  1B")
end)

test("setup: a registered column's own separator may head a linemode", function()
	-- The refusal is spec-only for this: a separator on a definition is read
	-- at every use of it, so refusing one here would stop a registered column
	-- being written first in any linemode -- one typo's cost paid by every
	-- reuse. What the column wrote is simply not drawn at index 1.
	main.column("septic", {
		separator = "|",
		width = 3,
		render = function() return "x" end,
	})
	setup { detail = { "septic", "septic" } }
	eq(draw("detail", CURRENT.files[1]), "  x|  x")
end)

--- A column that draws `text` and asks for no colour, so the only thing in a
--- row built out of these that can carry a style is the separator between
--- them.
---@param text string
---@return supaline.Render
local function plain(text)
	return function() return text end
end

--- The first style anywhere in a row, or nil if nothing in it carries one.
---@param name string
---@return table?
local function style_in(name) return stub.first_style(Linemode[name] { _file = CURRENT.files[1] }) end

test("setup: a separator can be drawn in a colour of its own", function()
	setup({ detail = { plain("a"), plain("b") } }, { separator = { " | ", style = { fg = "#585b70" } } })
	eq(draw("detail", CURRENT.files[1]), "a | b")
	eq(assert(style_in("detail"), "the separator came back unstyled").fg, "#585b70")
end)

test("setup: a nearer separator replaces a farther one whole, colour and all", function()
	-- The one rule the table form exists to keep: whichever level wrote a
	-- separator supplies both halves of it. A bare string at the nearer level
	-- therefore draws uncoloured rather than borrowing the colour above it,
	-- which is what a column's `style` does to a theme one level down.
	setup({
		detail = { plain("a"), { render = plain("b"), separator = "-" } },
	}, { separator = { " | ", style = { fg = "#585b70" } } })
	eq(draw("detail", CURRENT.files[1]), "a-b")
	eq(style_in("detail"), nil, "the nearer separator took the colour with it as well as the text")
end)

test("setup: a linemode's separator carries its style past the plugin-wide one", function()
	setup({
		detail = { plain("a"), plain("b"), separator = { "+", style = { fg = "#00ccff" } } },
	}, { separator = { " | ", style = { fg = "#585b70" } } })
	eq(draw("detail", CURRENT.files[1]), "a+b")
	eq(assert(style_in("detail"), "the separator came back unstyled").fg, "#00ccff")
end)

test("setup: a linemode with no columns draws nothing", function()
	setup { detail = {} }
	eq(draw("detail", CURRENT.files[1]), "")
end)

test("setup: a built-in column keeps its own default width", function()
	setup { detail = { "size" } }
	eq(draw("detail", CURRENT.files[1]), "     1B")
end)

-- --- what setup refuses ----------------------------------------------------

test("setup: an empty configuration is refused", function()
	throws(function() main.setup({}, {}) end, "`linemodes` is empty")
	throws(function() main.setup({}, { linemodes = {} }) end, "`linemodes` is empty")
end)

test("setup: a key `setup` itself does not take is refused", function()
	-- Nothing else refuses one. A key in a table constructor is past what the
	-- checker reads off `supaline.Opts`, and `setup` takes what it wants by
	-- name, so `scal = "log"` is a plugin-wide scale that is never applied and
	-- never mentioned again.
	local lm = { t = { "size" } }
	throws(function() main.setup({}, { linemodes = lm, scal = "log" }) end, "`scal`")
	throws(function() main.setup({}, { linemodes = lm, bnad = { from = 0.2, to = 0.9 } }) end, "`bnad`")
	throws(function() main.setup({}, { linemodes = lm, seperator = "|" }) end, "`seperator`")

	-- Both at once and sorted, so finding the second does not cost a second
	-- run.
	throws(function() main.setup({}, { linemodes = lm, scal = "log", bnad = { from = 0.2 } }) end, "`bnad`, `scal`")

	-- The two that are real mistakes rather than misspellings earn a hint.
	throws(function() main.setup({}, { linemodes = lm, linemode = lm }) end, "`linemodes` is the spelling")
	throws(function() main.setup({}, { linemodes = lm, columns = { "size" } }) end, "columns go inside a linemode")

	-- And the five it does take still go through.
	setup(
		{ t = { { "size", width = 3 } } },
		{ separator = "|", order = 1400, scale = "log", band = { fg = { from = 0.2, to = 0.9 } } }
	)
end)

test("setup: a `scale` it does not take is refused by `setup`'s own name", function()
	-- The test above refuses the key; this one refuses the value under a key
	-- spelled right. `scale = "LOG"` used to reach every column and scale none
	-- of them.
	--
	-- Refused here rather than left to `column.normalize`, which sees this
	-- value too. A message from there would name whichever column was
	-- normalised first, and send the reader to a column they wrote correctly --
	-- so what this pins is the `setup` in the message, not the refusal.
	local lm = { t = { "size" } }
	-- Bound once for the reason the column spec binds its own: a value that is
	-- wrong on purpose costs a suppression per spelling.
	---@diagnostic disable-next-line: assign-type-mismatch
	local shouted = { linemodes = lm, scale = "LOG" }
	throws(function() main.setup({}, shouted) end, "`scale` in `setup`")
	throws(function() main.setup({}, shouted) end, "must be `linear` or `log`")
	---@diagnostic disable-next-line: assign-type-mismatch
	throws(function() main.setup({}, { linemodes = lm, scale = "logarithmic" }) end, "got `logarithmic`")

	-- Both values it does take, and nothing written at all, which is the
	-- spelling that lets a column definition's own scale through.
	setup({ t = { "size" } }, { scale = "linear" })
	setup({ t = { "size" } }, { scale = "log" })
	setup({ t = { "size" } }, {})
end)

test("setup: names that are part of the Linemode component are refused", function()
	-- Yazi keeps the component's machinery on the same table the linemodes are
	-- looked up on. `linemodes.new` replaced the constructor and took every
	-- linemode down with it, not just its own.
	local before = Linemode.new
	for _, name in ipairs { "new", "redraw", "padding", "children_add", "children_remove", "_children", "_inc" } do
		throws(
			function() main.setup({}, { linemodes = { [name] = { "size" } } }) end,
			"part of Yazi's `Linemode` component"
		)
	end
	eq(Linemode.new, before, "the constructor survived")

	-- `solo()` returns early for these two, so they would silently do nothing.
	throws(function() main.setup({}, { linemodes = { none = { "size" } } }) end, "`Linemode` component")
	throws(function() main.setup({}, { linemodes = { solo = { "size" } } }) end, "`Linemode` component")
end)

test("setup: a member Yazi adds later is refused too", function()
	-- The guard asks `Linemode` what it holds rather than listing it. Yazi is on
	-- CalVer and adds to the component between releases; a hand-written denylist
	-- would let this through the moment it did.
	with(Linemode, "reflow", function() return "" end, function()
		throws(
			function() main.setup({}, { linemodes = { reflow = { "size" } } }) end,
			"part of Yazi's `Linemode` component"
		)
	end)
end)

test("setup: overriding one of Yazi's own linemode names is still allowed", function()
	-- Replacing the `size` linemode is a thing to want; replacing `redraw` is
	-- not, and the two live on the same table.
	setup { size = { { "size", width = 4 }, { "size", width = 4 } } }
	eq(draw("size", CURRENT.files[1]), "  1B   1B")
end)

test("setup: `.setup{...}` works as well as `:setup{...}`", function()
	-- The dot form lands the options in the state parameter, where reading them
	-- as the options says "`linemodes` is empty" -- naming the one thing the
	-- user got right.
	main.setup { linemodes = { dotted = { { "size", width = 3 } } } }
	cx.active.current = CURRENT
	cx.active.pref.linemode = "dotted"
	eq(draw("dotted", CURRENT.files[1]), " 1B")
end)

test("setup: a name Yazi cannot hold is refused", function()
	local long = string.rep("x", 21)
	throws(function() main.setup({}, { linemodes = { [long] = { "size" } } }) end, "1 to 20 characters")

	-- Yazi counts characters. This one is ten of them and thirty bytes, so a
	-- byte-length check would refuse a name Yazi is happy to hold.
	local cjk = "詳細表示モードの名前"
	setup { [cjk] = { { "size", width = 3 } } }
	eq(type(Linemode[cjk]), "function", "a CJK name well inside the limit is kept")

	-- ... and twenty-one characters is still too many, however few bytes.
	throws(function() main.setup({}, { linemodes = { [string.rep("あ", 21)] = { "size" } } }) end, "1 to 20 characters")
end)

test("setup: a separator that is neither a string nor a table is refused", function()
	-- The wrong value is the test; the checker refuses both of these where it
	-- runs, which is not over anyone's `init.lua`.
	---@diagnostic disable-next-line: assign-type-mismatch
	throws(function() main.setup({}, { linemodes = { t = { "size" } }, separator = 42 }) end, "`separator` in `setup`")

	-- `false` is the one this is really for. It reads like a column's
	-- `separator = false` and it is falsy, so it fell through to the
	-- plugin-wide separator: the linemode drew the separator it had asked to
	-- be rid of, and not until a row was drawn.
	---@diagnostic disable-next-line: assign-type-mismatch
	throws(function() main.setup({}, { linemodes = { t = { "size", separator = false } } }) end, "linemode `t`")

	-- And plugin-wide, which is the one the default could swallow: `setup`
	-- falls back to `DEFAULTS.separator` when nothing was written, and an `or`
	-- there would take `false` for nothing written and hand the user back the
	-- separator they wrote `false` to be rid of.
	---@diagnostic disable-next-line: assign-type-mismatch
	throws(function() main.setup({}, { linemodes = { t = { "size" } }, separator = false }) end, "`separator` in `setup`")

	-- The spelling the message names is taken.
	setup { detail = { { "size", width = 2 }, { "size", width = 2 }, separator = "" } }
	eq(draw("detail", CURRENT.files[1]), "1B1B", "an empty separator draws nothing between two columns")
end)

test("setup: a linemode has to be a table", function()
	-- A string where a list of columns goes -- the wrong value is the test,
	-- and the checker refuses it now that a spec has a class.
	---@diagnostic disable-next-line: assign-type-mismatch
	throws(function() main.setup({}, { linemodes = { detail = "size" } }) end, "`detail` is a string")
end)

-- --- panes -----------------------------------------------------------------

--- Assert that `setup` refuses `spec`, with a message mentioning `pattern`. A
--- whole spec rather than one value out of it, because a pane and a column sit
--- in the same table and half of what is refused is the two of them together.
---@param spec supaline.LinemodeSpec
---@param pattern string
local function refuses(spec, pattern)
	throws(function() main.setup({}, { linemodes = { t = spec } }) end, pattern)
end

test("panes: the default is the current pane alone", function()
	setup { detail = { "size" } }
	eq(#stub.children, 0, "no child is added when no linemode leaves the current pane")
	eq(draw_child(stub.file { name = "x", in_current = false }), "")
end)

test("panes: a pane key opts into the pane it names", function()
	local one = { { "size", width = 3 } }
	setup { detail = { current = one, parent = one } }
	eq(#stub.children, 1, "one child, added once")

	local outside = stub.file { name = "current", in_current = false, size = 1 }
	eq(draw_child(outside), "  1B", "the parent pane draws, with solo()'s leading space")
end)

test("panes: a pane left out stays bare", function()
	local one = { { "size", width = 3 } }
	setup { detail = { current = one, preview = one } }

	local parent_row = stub.file { name = "current", in_current = false, size = 1 }
	eq(draw_child(parent_row), "", "the parent pane was not asked for")

	eq(draw_child(PREVIEW.files[1]), "  1B", "the preview pane draws")
end)

test("panes: every preview row draws, not just the one Yazi flags", function()
	-- `in_preview` is true for the previewed folder's cursor row alone, so a
	-- pane test that reads it passes on the first row and leaves the rest of
	-- the pane bare -- and, under a `parent` key, draws them instead.
	setup { detail = { preview = { { "size", width = 3 } } } }
	eq(draw_child(PREVIEW.files[2]), "  2B", "the second preview row")

	setup { detail = { parent = { { "size", width = 3 } } } }
	eq(draw_child(PREVIEW.files[2]), "", "and it is not mistaken for a parent row")
end)

test("setup: a second call replaces what the first installed", function()
	-- `Linemode:redraw()` calls every child it holds, so a second one draws
	-- the parent and preview panes twice over.
	setup { detail = { parent = { { "size", width = 3 } } } }
	eq(#stub.children, 1, "one child after the first setup")

	setup { detail = { preview = { { "size", width = 3 } } } }
	eq(#stub.children, 1, "still one after the second")

	setup { detail = { "size" } }
	eq(#stub.children, 0, "and none once no linemode leaves the current pane")

	-- Subscribed at load, not in `setup`, so no number of calls can stack them.
	eq(#stub.subs.theme, 1, "the theme handler is subscribed once")
	eq(#stub.subs.rename, 1, "and so is each invalidation handler")
end)

test("setup: a linemode a later setup drops is unregistered", function()
	setup { alpha = { { "size", width = 3 } }, beta = { { "size", width = 3 } } }
	eq(type(Linemode.beta), "function")

	setup { alpha = { { "size", width = 3 } } }
	-- Not left registered and empty: Yazi draws an unregistered name as
	-- literal text, and a name that silently draws nothing hides the mistake.
	eq(Linemode.beta, nil, "the dropped name is off the component")
end)

test("setup: an override of Yazi's own linemode is handed back", function()
	local before = Linemode.size
	-- Pinned, not assumed: if an earlier test's `setup` failed to hand `size`
	-- back, this captures the damage as the baseline and the test below then
	-- passes for the wrong reason.
	eq(type(before), "function", "Yazi's own `size` is in place to begin with")

	setup { size = { { "size", width = 3 } } }
	assert(Linemode.size ~= before, "expected supaline to have taken `size` over")

	setup { detail = { "size" } }
	eq(Linemode.size, before, "Yazi's own is back once supaline stops claiming it")
end)

test("setup: a column may declare a refresh hook, built-in or not", function()
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

	-- A linemode that no longer uses the column stops paying for its hook.
	setup { detail = { "size" } }
	stub.fire("cd")
	eq(ran, 2, "a column no longer in service is not refreshed")
end)

test("setup: a refused configuration leaves the running one alone", function()
	setup { good = { { "size", width = 3 } } }
	local before = draw("good", CURRENT.files[1])

	throws(
		function() main.setup({}, { linemodes = { good = { "size" }, bad = { "size", parnet = { "mark" } } } }) end,
		"`parnet`"
	)

	eq(draw("good", CURRENT.files[1]), before, "the linemode still draws as it did")
	-- The `theme` handler rebuilds from the stored specs, so a rejected one
	-- left there would make every later theme event throw.
	stub.fire("theme")
	eq(draw("good", CURRENT.files[1]), before, "and a theme event still rebuilds it")
end)

test("panes: the current pane is never drawn twice", function()
	local one = { { "size", width = 3 } }
	setup { detail = { current = one, parent = one } }
	-- `solo()` has already drawn it, so the child has to stand down.
	eq(draw_child(CURRENT.files[1]), "")
end)

test("panes: a linemode that never asked for the current pane is bare there", function()
	-- A pane set consulted only by the parent/preview child would make leaving
	-- `current` out change nothing at all.
	setup { detail = { parent = { { "size", width = 4 } } } }
	eq(draw("detail", CURRENT.files[1]), "", "the current pane")
	eq(draw_child(stub.file { name = "current", in_current = false, size = 1 }), "   1B", "the parent pane")
end)

test("panes: a pane given anything but a list of columns is refused", function()
	-- The wrong value is the test, and the checker refuses it now that a pane
	-- is a declared field rather than an entry in a map.
	---@diagnostic disable-next-line: assign-type-mismatch
	refuses({ current = true }, "rather than a list of columns")
	-- An empty list is refused where the linemode's own is not: leaving the
	-- pane out says the same thing, and there is no second way to say it.
	refuses({ current = {} }, "empty list")
end)

test("panes: columns beside a pane key are refused", function()
	-- The list is what the current pane draws and so is a `current` key, so a
	-- linemode carrying both says the same thing twice -- and, once any pane is
	-- named, the list is what would have been drawn nowhere. A column the user
	-- wrote and cannot find is what this refuses rather than ships.
	-- A registered column on both sides, so a regression here is reported as
	-- the refusal that did not happen rather than as the name it tripped over
	-- on its way into `compile`.
	refuses({ "size", parent = { "mtime" } }, "drawn nowhere")

	-- Not `#spec`, which is 0 for a list that starts anywhere but index 1: a
	-- stray column would pass here and be dropped, where the very same column
	-- written at index 1 is refused.
	refuses({ [2] = "size", parent = { "mtime" } }, "drawn nowhere")
end)

test("panes: a key that is neither a pane nor an option is refused", function()
	-- Nothing else refuses one; `OPTIONS` in `main.lua` says why.
	refuses({ "size", parnet = { "mark" } }, "`parnet`")
	refuses({ "size", separatorr = "|" }, "`separatorr`")
	refuses({ "size", pane = { "parent" } }, "`pane`")

	-- Every one of them, in an order two runs agree on: a spec is walked with
	-- `pairs`, so naming whichever came up first would hide the second
	-- misspelling until the first was fixed.
	refuses({ "size", parnet = { "mark" }, preivew = { "mark" } }, "`parnet`, `preivew`")
end)

test("panes: an entry `ipairs` would not reach is refused", function()
	-- `compile` walks a column list with `ipairs`, so an entry it does not
	-- visit is not drawn and not complained about -- the same silence the keys
	-- of a linemode are refused for, one level down.
	---@diagnostic disable-next-line: assign-type-mismatch
	refuses({ current = { "size", separator = "|" } }, "an option goes on the linemode itself")
	---@diagnostic disable-next-line: assign-type-mismatch
	refuses({ current = { "size", parent = { "size" } } }, "`parent`")

	-- `ipairs` stops at the first missing index, so a list numbered around a
	-- gap draws the columns before it and drops the rest.
	refuses({ current = { [1] = "size", [3] = "mtime" } }, "`current` has a gap")
	refuses({ [1] = "size", [3] = "mtime" }, "this one has a gap")
end)

test("panes: each pane draws the columns written under it", function()
	setup {
		detail = {
			current = { { "size", width = 3 }, { "size", width = 4 } },
			parent = { { "size", width = 5 } },
		},
	}

	eq(draw("detail", CURRENT.files[1]), " 1B   1B", "the current pane draws the two columns it was given")

	local parent_row = stub.file { name = "current", in_current = false, size = 1 }
	eq(draw_child(parent_row), "    1B", "the parent pane draws the one it was given")
	eq(draw_child(PREVIEW.files[1]), "", "and the pane nobody named stays bare")
end)

test("panes: one list handed to two panes is compiled once", function()
	-- Sharing the compiled columns is what keeps a `refresh` to one run per
	-- `cd`; compiling the list once per pane would multiply it by the panes.
	local ran = 0
	main.column("ticking_panes", {
		width = 2,
		render = function(_, ctx) return "ok", ctx.style end,
		refresh = function() ran = ran + 1 end,
	})

	local both = { "ticking_panes" }
	setup { detail = { current = both, parent = both } }
	eq(ran, 1, "installed once, not once per pane")

	stub.fire("cd")
	eq(ran, 2, "and once per cd")

	-- Two lists that happen to hold the same column are two columns, because
	-- each pane can bind its own width and stats onto them.
	ran = 0
	setup { detail = { current = { "ticking_panes" }, parent = { "ticking_panes" } } }
	eq(ran, 2, "written twice, compiled twice")
end)

-- --- the theme -------------------------------------------------------------

--- Run `fn` with the user's `[supaline]` section set to `section`, and put the
--- stub's own back afterwards. A name for one field of `with`, which is where
--- the restore lives and says why it is protected rather than written as the
--- last line of a body.
---@param section table?
---@param fn function
local function with_theme(section, fn) with(stub.th, "supaline", section, fn) end

test("theme: a base colour comes from the user's `[supaline]` section", function()
	-- Readable from the start on 26.9.1: the user's `theme.toml` is merged
	-- before any plugin code runs, so `setup` resolves the user's colour rather
	-- than the column's default.
	with_theme({ size = "#ff8800" }, function()
		setup { detail = { { "size", width = 3 } } }
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#ff8800")
	end)
end)

test("theme: a reload replaces a colour already resolved", function()
	-- This is the half that still fails silently. `app:theme` re-reads
	-- `theme.toml` from disk mid-run, and a plugin that resolved its colours
	-- once at `setup` goes on drawing the old ones with nothing to say so --
	-- which is what `ps.sub("theme", build)` is for.
	--
	-- Changing the section *after* `setup` is what makes this test say that. A
	-- section that never changed would pass for a plugin that never subscribed.
	with_theme({ size = "#ff8800" }, function()
		setup { detail = { { "size", width = 3 } } }
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#ff8800")

		stub.th.supaline = { size = "#00ccff" }
		stub.fire("theme")
		eq(
			stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg,
			"#00ccff",
			"the reloaded colour, not the one resolved at setup"
		)
	end)
end)

test("theme: a column's `style` function is read again on a reload", function()
	-- The level test, not the key test. A column's `style` can be written in
	-- exactly one place, so one of these covers the feature -- which is the
	-- thing the plugin-wide separator got wrong by having a second level nobody
	-- checked.
	--
	-- Written as the flavor case because that is how it bites: a field only the
	-- flavor supplies is nil while `setup` runs and arrives a few milliseconds
	-- later with the `theme` event, so a frozen function is not a stale style,
	-- it is no style at all for the rest of the session.
	with_theme({}, function()
		setup { detail = { { "size", width = 3, style = function() return th.supaline.over end } } }
		eq(rawget(assert(style_in("detail")), "bold"), nil, "nothing to put over it yet")

		stub.th.supaline = { over = ui.Style():bold() }
		stub.fire("theme")
		eq(assert(style_in("detail")).bold, true, "the attribute the flavor brought with the event")
	end)
end)

test("theme: a linemode's separator style function is read again on a reload", function()
	-- The same repair a column's `style` gets and for the same reason: a spec is
	-- re-read on every build and never evaluated, so a style written as a value
	-- freezes whatever the theme held while `init.lua` ran. A function is
	-- called inside the build, where the flavor has landed and every `app:theme`
	-- after it runs again.
	--
	-- Changing the section *after* `setup` is what makes this test say that. A
	-- section that never changed would pass for a plugin that resolved the
	-- function once and kept the answer.
	with_theme({ sep = "#ff8800" }, function()
		setup {
			detail = { plain("a"), plain("b"), separator = { "|", style = function() return th.supaline.sep end } },
		}
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#ff8800")

		stub.th.supaline = { sep = "#00ccff" }
		stub.fire("theme")
		eq(
			stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg,
			"#00ccff",
			"the reloaded colour, not the one the function returned at setup"
		)
	end)
end)

test("theme: the plugin-wide separator's style function is read again too", function()
	-- The level the test above does not reach, and the one that was frozen.
	-- `setup` stores `cfg` once and hands that same table to every later
	-- build, so a separator read into a record there held whatever the
	-- function returned while `init.lua` ran and held it for the session.
	-- `compile` reads it instead, on the pass that draws, which is where the
	-- linemode's and the column's were already being read.
	--
	-- Written as the flavor case rather than as a second reload, because that
	-- is how it bites: a field only the flavor supplies is *nil* while `setup`
	-- runs and arrives with the `theme` event a few milliseconds later.
	-- Frozen, this separator is not merely a stale colour -- it is uncoloured
	-- for the rest of the session, with nothing anywhere to say so.
	with_theme({}, function()
		setup({ detail = { plain("a"), plain("b") } }, {
			separator = { "|", style = function() return th.supaline.sep end },
		})
		eq(style_in("detail"), nil, "nothing to draw it in yet, which the table form allows")

		stub.th.supaline = { sep = "#00ccff" }
		stub.fire("theme")
		eq(style_in("detail").fg, "#00ccff", "the colour the flavor brought with the event")
	end)
end)

test("theme: a style table works as well as a colour string", function()
	with_theme({ size = ui.Style():fg("#00ff00"):bold() }, function()
		setup { detail = { { "size", width = 3 } } }
		stub.fire("theme")

		-- Asserted rather than indexed straight: an unstyled cell here is a real
		-- failure, and "attempt to index a nil value" names the harness for it.
		local style = assert(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }), "the cell came back unstyled")
		-- In Yazi's own spelling: a table field arrives as the `Style` Yazi
		-- parsed and is read back through `raw()`, which uppercases a hex.
		eq(style.fg, "#00FF00")
		eq(style.bold, true)
	end)
end)

test("theme: a ramp in the `[supaline]` section colours the whole range", function()
	-- A theme cannot hold a list -- Yazi refuses the file outright -- so a ramp
	-- reaches a plugin as a string, and this is the path that says so end to
	-- end: the section is read, the endpoints are parsed, the folder pass finds
	-- the extremes, and the two files land on the two ends of the ramp.
	with_theme({ size = "#0b3d91 -> #7fd4ff" }, function()
		setup { detail = { { "size", width = 4 } } }

		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#0b3d91", "the smallest file")
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#7fd4ff", "the largest")
	end)
end)

test("theme: a reload rebuilds a ramp, not only a flat colour", function()
	-- The flat case is pinned above. A ramp is built once and indexed per row,
	-- so it is exactly the kind of derived value that would keep the old
	-- colours through an `app:theme` with nothing to say so.
	with_theme({ size = "#0b3d91 -> #7fd4ff" }, function()
		setup { detail = { { "size", width = 4 } } }
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#7fd4ff")

		stub.th.supaline = { size = "#111111 -> #00ccff" }
		stub.fire("theme")
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#00ccff", "the reloaded ramp")
	end)
end)

test("theme: one colour with `<->` is a gradient a theme can ask for", function()
	-- What a theme could not say before. A field holds one value, so a ramp
	-- had to be written with both of its ends in it; `<->` asks for the band
	-- around a single colour, which is the only other thing that fits.
	--
	-- Both ends are derived, neither is the colour written: the largest file
	-- draws the light end of the band around `#7fd4ff` and the smallest draws
	-- the dark one. `colour_spec.lua` pins where each lands and why.
	with_theme({ size = "#7fd4ff <->" }, function()
		setup({ detail = { { "size", width = 4 } } }, { band = { fg = { from = 0.35, to = 0.88 } } })
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#a8e1ff")
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#223f4d", "and the low end below it")
	end)
end)

test("theme: the `fg` band in `setup` is what a themed `<->` is drawn at", function()
	-- A theme field holds one value, so a band written there is a bare string
	-- and a bare string is the `fg` key: `fg` is the name it asks for, and the
	-- name is the whole of how the two files meet. A flavour writes the hue; a
	-- reader's `setup` writes the two lightnesses their own ground decides.
	with_theme({ size = "#0b3d91 <->" }, function()
		setup({ detail = { { "size", width = 4 } } }, { band = { fg = { from = 0.50, to = 0.70 } } })
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#649cff", "the high end")
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#155ace", "and the low one")
	end)
end)

test("theme: a band written backwards is what a light terminal asks for", function()
	-- `from` is what ratio 0 draws, so the pair carries its own direction and
	-- inverting it is writing it the other way round. Nothing else changes:
	-- the same two lightnesses, the same hue, the largest file now dark.
	with_theme({ size = "#0b3d91 <->" }, function()
		setup({ detail = { { "size", width = 4 } } }, { band = { fg = { from = 0.88, to = 0.35 } } })
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#08347f", "the largest file is dark")
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#c2d9ff", "and the smallest pale")
	end)
end)

test("theme: a band survives a theme reload", function()
	-- `build()` re-runs `compile(specs, cfg)`, so anything in `cfg` has to
	-- reach the rebuilt ramp as well as the first one. Bands read at setup and
	-- then dropped would leave the next `app:theme` with none defined, which
	-- turns a drawing column into a refusal for no reason on screen.
	with_theme({ size = "#0b3d91 <->" }, function()
		setup({ detail = { { "size", width = 4 } } }, { band = { fg = { from = 0.88, to = 0.35 } } })
		stub.fire("theme")
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#08347f")
	end)
end)

test("setup: a band that is not two lightnesses is refused, and changes nothing", function()
	setup { good = { { "size", width = 3 } } }
	local before = draw("good", CURRENT.files[1])

	throws(
		---@diagnostic disable-next-line: assign-type-mismatch
		function() main.setup({}, { linemodes = { good = { "size" } }, band = { fg = { from = 0.35 } } }) end,
		"`band` in `setup`: `fg`"
	)
	eq(draw("good", CURRENT.files[1]), before, "the linemode still draws as it did")
end)

test("setup: a `<->` with no band behind it is refused, and changes nothing", function()
	-- The front door, from the outside. A `setup` that defines no band and a
	-- spec that writes one is the first thing a reader does, and what they get
	-- is the message rather than a column drawn at a pair nobody chose.
	setup { good = { { "size", width = 3 } } }
	local before = draw("good", CURRENT.files[1])

	throws(
		function() main.setup({}, { linemodes = { good = { { "size", style = "#0b3d91 <->" } } } }) end,
		"nothing defines `fg`"
	)
	eq(draw("good", CURRENT.files[1]), before, "the linemode still draws as it did")
end)

test("setup: a band a spec names by hand is drawn at that band", function()
	-- The other half of the name: a string may ask for a band the key it was
	-- written under is not called, which is the only way one column differs
	-- from the next.
	setup({ detail = { { "size", width = 4, style = "#0b3d91 <-> dim" } } }, {
		band = { fg = { from = 0.35, to = 0.88 }, dim = { from = 0.50, to = 0.70 } },
	})
	eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#649cff", "`dim`, not `fg`")
end)

test("setup: a `style` function's band name is read on the pass that draws", function()
	-- A function is called once per build rather than once at setup, so that it
	-- sees the flavour. Every level that can hold one is pinned elsewhere; what
	-- this adds is that the name inside what it returned is resolved on that
	-- same pass, rather than the string being kept and read once.
	local asked = 0
	local style = function()
		asked = asked + 1
		return "#0b3d91 <-> dim"
	end
	setup({ detail = { { "size", width = 4, style = style } } }, { band = { dim = { from = 0.50, to = 0.70 } } })
	eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#649cff")
	stub.fire("theme")
	eq(asked, 2, "called again on the rebuild")
	eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#649cff", "and resolved again")
end)

test("theme: a colour in the spec replaces a themed gradient, and keeps the rest of the theme's", function()
	-- Each key goes to the nearest writer, so a spec's `fg` is a flat colour on
	-- every row where the theme had a gradient -- and a `bg` the theme wrote
	-- beside a colour is still there under the spec's.
	with_theme({ size = "#0b3d91 -> #7fd4ff" }, function()
		setup { detail = { { "size", width = 4, style = "#ff8800" } } }

		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#ff8800")
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#ff8800", "every row, flat")
	end)

	with_theme({ size = ui.Style():fg("#0b3d91"):bg("#101010") }, function()
		setup { detail = { { "size", width = 4, style = "#ff8800" } } }
		local style = assert(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }), "the cell came back unstyled")
		eq(style.fg, "#ff8800", "the spec's colour")
		eq(style.bg, "#101010", "over the theme's ground")
	end)
end)

test("theme: a ramp on a column with no extremes says which file to fix", function()
	-- `theme.toml` has no `stats` to give and no `style` key to move the colour
	-- to, so the spec-side advice would be advice nobody could take. The error
	-- has to name the theme, and offer the one move that file allows.
	with_theme({ owner = "#0b3d91 -> #7fd4ff" }, function()
		local err = select(2, pcall(setup, { detail = { "owner" } }))
		local text = tostring(err)
		assert(text:find("`[supaline] owner` field in your theme", 1, true), text)
		assert(text:find("Write a flat colour there instead", 1, true), text)
	end)
end)

test("theme: a reload the theme breaks keeps the old colours and says so", function()
	-- The messages above are written for the person editing `theme.toml`, and
	-- that person is not editing it during `setup` -- they edit it and press a
	-- key bound to `app:theme`. On that path `compile` runs from a `ps.sub`
	-- handler, where raising reaches nobody: without this the reload would
	-- change nothing and say nothing, which is what a plugin that ignored the
	-- event looks like.
	with_theme({ size = "#ff8800" }, function()
		setup { detail = { { "size", width = 3 } } }
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#ff8800")

		local was = #stub.notified
		stub.th.supaline = { size = "nosuchcolour" }
		stub.fire("theme")

		eq(
			stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg,
			"#ff8800",
			"the last theme that compiled keeps drawing"
		)
		eq(#stub.notified - was, 1, "and the refusal reaches the screen, not only the log")

		-- Cut back to the sentence the message was written as. `pcall` hands
		-- back what Lua and Yazi wrapped around it -- a source position here, a
		-- `runtime error:` and two tracebacks under a real Yazi -- and
		-- `ya.notify` draws every line of whatever it is given.
		local said = stub.notified[#stub.notified].content
		eq(
			said,
			"supaline: the `[supaline] size` field in your theme: `nosuchcolour` is not a colour Yazi "
				.. "accepts. Write `#rrggbb`, a name such as `cyan`, a 256-colour index as a string such "
				.. "as `129`, or `reset`",
			"the message, and nothing Lua or Yazi wrapped around it"
		)
	end)
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
	for _, file in ipairs(CURRENT.files) do
		draw("detail", file)
	end
	eq(calls, 1, "every row, one pass")
end)

test("stats: a ramp with no extremes to place a row against says so, once", function()
	-- The failure this reports draws: the ramp has nothing to normalise
	-- against, so `ctx.ratio` is nil for every row and each one takes the low
	-- end. A column in one colour where several were asked for, and until now
	-- nothing said a word about it.
	--
	-- Said rather than raised, because this is knowable only inside a render
	-- pass and an `error` from there takes the whole screen down -- worse than
	-- what it would be reporting. Measured on 26.9.1: `ya.notify` from a
	-- linemode render reaches the screen and the rows draw under it.
	main.column("wrong_stats", {
		width = 6,
		stats = function() return { count = 3 } end,
		style = "#0b3d91 -> #7fd4ff",
		render = function() return "x" end,
	})

	local was = #stub.notified
	setup { detail = { "wrong_stats" } }
	for _, file in ipairs(CURRENT.files) do
		draw("detail", file)
	end

	eq(#stub.notified - was, 1, "said once, not once per row")
	local said = stub.notified[#stub.notified].content
	eq(said:find("`wrong_stats`", 1, true) ~= nil, true, "and it names the column")
	eq(said:find("no `min` and `max`", 1, true) ~= nil, true, "and what came back wrong")

	-- And it kept drawing, which is the half that would be lost to an `error`.
	eq(draw("detail", CURRENT.files[1]), "     x")
end)

test("stats: a column that is not a ramp owes nobody extremes", function()
	-- `stats` is also how a column derives a width, or carries anything its own
	-- `render` reads off `ctx.stats`. A column using it that way and returning
	-- no `min` or `max` is doing nothing wrong, and a report pointed at it
	-- would be the check crying about correct code -- which is the way a check
	-- like this one usually goes wrong.
	main.column("widened", {
		width = function(stats) return stats and stats.widest or 4 end,
		stats = function() return { widest = 5 } end,
		render = function() return "x" end,
	})

	local was = #stub.notified
	setup { detail = { "widened" } }
	draw("detail", CURRENT.files[1])
	eq(#stub.notified - was, 0, "nothing said")

	-- Nor does a column with no `stats` at all, which is most of them.
	main.column("bare", { width = 3, render = function() return "x" end })
	setup { detail = { "bare" } }
	draw("detail", CURRENT.files[1])
	eq(#stub.notified - was, 0, "still nothing said")
end)

test("throwing: a `render` that throws is kept inside that column's cells", function()
	-- What this is standing in for cannot be reached from here, and is the
	-- reason the code under test exists. Measured on 26.9.1 in a real Yazi: an
	-- error raised under a linemode's render fails the whole `Root` component,
	-- so the file list, the header and the status bar all stop drawing, on
	-- every frame, with no message on screen and no log at all unless
	-- `YAZI_LOG` was set before Yazi started. Nothing in supaline raises this
	-- one -- it is the reader's own `render` -- which is why the containment
	-- cannot live beside the plugin's own refusals.
	main.column("fine", { width = 2, render = function() return "ok" end })
	main.column("thrower", {
		width = 3,
		render = function() error("a column of mine is broken") end,
	})

	local was = #stub.notified
	setup { detail = { "fine", "thrower" } }

	-- Every row, not just the first: the flag is what makes this a report
	-- rather than one notification per row per frame.
	for _, file in ipairs(CURRENT.files) do
		draw("detail", file)
	end
	eq(#stub.notified - was, 1, "said once, not once per row")

	local said = stub.notified[#stub.notified].content
	eq(said:find("`thrower`", 1, true) ~= nil, true, "and it names the column")
	eq(said:find("`render`", 1, true) ~= nil, true, "and which of the three threw")
	eq(said:find("a column of mine is broken", 1, true) ~= nil, true, "and what it said")

	-- The cells the column was given, filled rather than left blank, and the
	-- column beside it untouched. This is the assertion the whole change is
	-- for: the line still draws.
	eq(draw("detail", CURRENT.files[1]), "ok !!!")
end)

test("throwing: a `stats` that throws leaves the rest of the line drawing", function()
	main.column("bad_stats", {
		width = 6,
		stats = function() error("no stats for you") end,
		render = function() return "x" end,
	})

	local was = #stub.notified
	setup { detail = { "bad_stats" } }
	draw("detail", CURRENT.files[1])

	eq(#stub.notified - was, 1, "said once")
	local said = stub.notified[#stub.notified].content
	eq(said:find("`stats`", 1, true) ~= nil, true, "and it names the stage")

	-- `render` never asked for the stats, so the column draws exactly as it
	-- would have. What was lost is whatever `stats` was going to carry.
	eq(draw("detail", CURRENT.files[1]), "     x")
end)

test("throwing: a `width` function that throws draws unpadded rather than not at all", function()
	main.column("bad_width", {
		width = function() error("cannot size this") end,
		render = function() return "x" end,
	})

	local was = #stub.notified
	setup { detail = { "bad_width" } }
	-- The width pass runs on the first row drawn, not on `setup`: `setup`
	-- compiles the spec and nothing has a folder to measure against yet.
	local first = draw("detail", CURRENT.files[1])

	eq(#stub.notified - was, 1, "said once")
	local said = stub.notified[#stub.notified].content
	eq(said:find("`width`", 1, true) ~= nil, true, "and it names the stage")

	-- The documented fallback, and the honest one: there is no width the pass
	-- can stand behind and none is invented, so the cell is whatever `render`
	-- returned. A ragged row -- which is what a refused `width = 0` exists to
	-- prevent -- but a ragged row is readable and arrives with the message
	-- above, where the `error` this replaces left an empty terminal.
	eq(first, "x")
end)

test("width: a function returning no usable number is reported as itself", function()
	-- The other half of the test above, and the distinction is the point.
	-- Nothing throws here: the function returns, and what it returns is a
	-- width supaline will not take. `resolve_width` hands that back as a
	-- reason rather than raising it, so the reader is told their function
	-- returned `0` instead of being told it threw -- which is what a refusal
	-- raised into the same `pcall` the throws come out of would have said.
	main.column("zero_width", {
		width = function() return 0 end,
		render = function() return "x" end,
	})

	local was = #stub.notified
	setup { detail = { "zero_width" } }
	local first = draw("detail", CURRENT.files[1])

	eq(#stub.notified - was, 1, "said once")
	local said = stub.notified[#stub.notified].content
	eq(said:find("returned `0`", 1, true) ~= nil, true, "and it says what came back")
	eq(said:find("threw", 1, true), nil, "and does not call a return a throw")

	-- Same fallback as a throw, because the pass is left with the same
	-- nothing: unpadded, ragged and readable.
	eq(first, "x")
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
	draw("detail", CURRENT.files[1])
	eq(seen, 42, "the folder pass was skipped because nothing else consumed it")
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
	draw("detail", CURRENT.files[1])
	draw_child(stub.file { name = "current", in_current = false })

	eq(#seen, 2, "one pass per folder")
	eq(seen[1], #CURRENT.files)
	eq(seen[2], #PARENT.files, "the parent row was measured against the parent folder")
end)

test("stats: a folder revisited after a write is measured again", function()
	-- The cached pass is keyed by the linemode, the folder and its file count,
	-- so a write that leaves the count alone -- one file grown, one timestamp
	-- touched -- looks exactly like the visit before it. `cd` is the event that
	-- says the listing may have moved on, and without dropping the cache there
	-- the column keeps the width and the extremes of the first visit for as
	-- long as the session lasts: this drew "9…" in a real Yazi, a measured
	-- column two cells wide holding a six-cell size.
	local grown = 1
	local file = stub.file { name = "a.bin" }
	file.size = function() return grown end
	local folder = stub.folder("/elsewhere", { file })

	setup { detail = { { "size", width = "auto" } } }
	cx.active.current = folder
	eq(draw("detail", file), "1B")

	grown = 999999
	stub.fire("cd")
	eq(draw("detail", file), "976.6K", "the width and the value both follow the folder")
end)
