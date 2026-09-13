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

test("setup: `sep = false` drops the separator before a column", function()
	setup { detail = { { "size", width = 3 }, { "size", width = 3, sep = false } } }
	eq(draw("detail", CURRENT.files[1]), " 1B 1B")
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
	-- The dot form lands the options in the state parameter, and used to fail
	-- with "`linemodes` is empty" -- naming the one thing the user got right.
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
		render = function(_, ctx) return "ok", ctx.base end,
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
	-- The pane set used to be consulted only by the parent/preview child, so
	-- leaving `current` out changed nothing at all.
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
	-- stray column used to pass here and be dropped, and the very same column
	-- written at index 1 was refused.
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
		render = function(_, ctx) return "ok", ctx.base end,
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

test("theme: a style table works as well as a colour string", function()
	with_theme({ size = ui.Style():fg("#00ff00"):bold() }, function()
		setup { detail = { { "size", width = 3 } } }
		stub.fire("theme")

		-- Asserted rather than indexed straight: an unstyled cell here is a real
		-- failure, and "attempt to index a nil value" names the harness for it.
		local style = assert(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }), "the cell came back unstyled")
		eq(style.fg, "#00ff00")
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
		setup { detail = { { "size", width = 4 } } }
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#a8e1ff")
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#223f4d", "and the low end below it")
	end)
end)

test("theme: `band` in `setup` moves both ends of every band", function()
	-- The plugin-wide knob, and the reason it is plugin-wide: a band is a claim
	-- about what the terminal can show, and a terminal does not change between
	-- one column and the next.
	with_theme({ size = "#0b3d91 <->" }, function()
		setup({ detail = { { "size", width = 4 } } }, { band = { from = 0.50, to = 0.70 } })
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#649cff", "the high end")
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#155ace", "and the low one")
	end)
end)

test("theme: a band written backwards is what a light terminal asks for", function()
	-- `from` is what ratio 0 draws, so the pair carries its own direction and
	-- inverting it is writing it the other way round. Nothing else changes:
	-- the same two lightnesses, the same hue, the largest file now dark.
	with_theme({ size = "#0b3d91 <->" }, function()
		setup({ detail = { { "size", width = 4 } } }, { band = { from = 0.88, to = 0.35 } })
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#08347f", "the largest file is dark")
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#c2d9ff", "and the smallest pale")
	end)
end)

test("theme: a band survives a theme reload", function()
	-- `build()` re-runs `compile(specs, cfg)`, so anything in `cfg` has to
	-- reach the rebuilt ramp as well as the first one. A band read at setup and
	-- then dropped would go back to the default the next time `app:theme`
	-- fired, which is a colour changing under the user for no reason on screen.
	with_theme({ size = "#0b3d91 <->" }, function()
		setup({ detail = { { "size", width = 4 } } }, { band = { from = 0.88, to = 0.35 } })
		stub.fire("theme")
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#08347f")
	end)
end)

test("setup: a band that is not two lightnesses is refused, and changes nothing", function()
	setup { good = { { "size", width = 3 } } }
	local before = draw("good", CURRENT.files[1])

	throws(
		---@diagnostic disable-next-line: assign-type-mismatch
		function() main.setup({}, { linemodes = { good = { "size" } }, band = { from = 0.35 } }) end,
		"`band` in `setup`"
	)
	eq(draw("good", CURRENT.files[1]), before, "the linemode still draws as it did")
end)

test("theme: a colour in the spec replaces a themed ramp outright", function()
	-- One source decides the whole colour. Half of it from the spec and half
	-- from the theme would be a rule nobody could hold in their head, and it is
	-- the same rule as before: what the spec says wins.
	with_theme({ size = "#0b3d91 -> #7fd4ff" }, function()
		setup { detail = { { "size", width = 4, base = "#ff8800" } } }

		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#ff8800")
		eq(stub.first_style(Linemode.detail { _file = CURRENT.files[2] }).fg, "#ff8800", "every row, flat")
	end)
end)

test("theme: a ramp on a column with no extremes says which file to fix", function()
	-- `theme.toml` has no `stats` to give and no `base` field to move the colour
	-- to, so the spec-side advice would be advice nobody could take. The error
	-- has to name the theme, and offer the one move that file allows.
	with_theme({ owner = "#0b3d91 -> #7fd4ff" }, function()
		local err = select(2, pcall(setup, { detail = { "owner" } }))
		local text = tostring(err)
		assert(text:find("`[supaline] owner` colour in your theme", 1, true), text)
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
			"supaline: the `[supaline] size` colour in your theme: `nosuchcolour` is not a colour Yazi "
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
