---@diagnostic disable: inject-field, param-type-mismatch

--- `main.lua` through its real entry point: what `setup` registers, what it
--- refuses, how the columns are joined, and which panes a linemode reaches.
---
--- The rendering itself is stubbed, so this says nothing about how any of it
--- looks. `test/e2e.sh` is what answers that.

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
---@param linemodes table
---@param opts table?
local function setup(linemodes, opts)
	opts = opts or {}
	opts.linemodes = linemodes
	main.setup({}, opts)

	cx.active.current = CURRENT
	cx.active.parent = PARENT
	cx.active.preview = { folder = PREVIEW }
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
	Linemode.reflow = function() return "" end
	throws(function() main.setup({}, { linemodes = { reflow = { "size" } } }) end, "part of Yazi's `Linemode` component")
	Linemode.reflow = nil
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

test("setup: a linemode has to be a list of columns", function()
	throws(function() main.setup({}, { linemodes = { detail = "size" } }) end, "must be a list of columns")
end)

-- --- panes -----------------------------------------------------------------

local function panes_error(value)
	local ok, err = pcall(function() main.setup({}, { linemodes = { t = { "size", panes = value } } }) end)
	assert(not ok, "expected `panes` to be refused")
	return tostring(err)
end

test("panes: the default is the current pane alone", function()
	setup { detail = { "size" } }
	eq(#stub.children, 0, "no child is added when no linemode leaves the current pane")
	eq(draw_child(stub.file { name = "x", in_current = false }), "")
end)

test("panes: a list opts into the panes it names", function()
	setup { detail = { { "size", width = 3 }, panes = { "current", "parent" } } }
	eq(#stub.children, 1, "one child, added once")

	local outside = stub.file { name = "current", in_current = false, size = 1 }
	eq(draw_child(outside), "  1B", "the parent pane draws, with solo()'s leading space")
end)

test("panes: a pane left off the list stays bare", function()
	setup { detail = { { "size", width = 3 }, panes = { "current", "preview" } } }

	local parent_row = stub.file { name = "current", in_current = false, size = 1 }
	eq(draw_child(parent_row), "", "the parent pane was not asked for")

	eq(draw_child(PREVIEW.files[1]), "  1B", "the preview pane draws")
end)

test("panes: every preview row draws, not just the one Yazi flags", function()
	-- `in_preview` is true for the previewed folder's cursor row alone, so a
	-- pane test that reads it passes on the first row and leaves the rest of
	-- the pane bare -- and, under `panes = { parent }`, draws them instead.
	setup { detail = { { "size", width = 3 }, panes = { "current", "preview" } } }
	eq(draw_child(PREVIEW.files[2]), "  2B", "the second preview row")

	setup { detail = { { "size", width = 3 }, panes = { "current", "parent" } } }
	eq(draw_child(PREVIEW.files[2]), "", "and it is not mistaken for a parent row")
end)

test("setup: a second call replaces what the first installed", function()
	-- `Linemode:redraw()` calls every child it holds, so a second one draws
	-- the parent and preview panes twice over.
	setup { detail = { { "size", width = 3 }, panes = { "current", "parent" } } }
	eq(#stub.children, 1, "one child after the first setup")

	setup { detail = { { "size", width = 3 }, panes = { "current", "preview" } } }
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
		function() main.setup({}, { linemodes = { good = { "size" }, bad = { "size", panes = { "nope" } } } }) end,
		"`panes` takes a list"
	)

	eq(draw("good", CURRENT.files[1]), before, "the linemode still draws as it did")
	-- The `theme` handler rebuilds from the stored specs, so a rejected one
	-- left there would make every later theme event throw.
	stub.fire("theme")
	eq(draw("good", CURRENT.files[1]), before, "and a theme event still rebuilds it")
end)

test("panes: the current pane is never drawn twice", function()
	setup { detail = { { "size", width = 3 }, panes = { "current", "parent" } } }
	-- `solo()` has already drawn it, so the child has to stand down.
	eq(draw_child(CURRENT.files[1]), "")
end)

test("panes: a linemode that never asked for the current pane is bare there", function()
	-- The pane set used to be consulted only by the parent/preview child, so
	-- leaving `current` out of the list changed nothing at all.
	setup { detail = { { "size", width = 4 }, panes = { "parent" } } }
	eq(draw("detail", CURRENT.files[1]), "", "the current pane")
	eq(draw_child(stub.file { name = "current", in_current = false, size = 1 }), "   1B", "the parent pane")
end)

test("panes: everything but a list of pane names is refused", function()
	local wanted = "takes a list of"
	assert(panes_error("all"):find(wanted, 1, true), '"all" is no longer a value')
	assert(panes_error({ "all" }):find(wanted, 1, true), '"all" is no longer a value in a list')
	assert(panes_error("current"):find('write { "current" }', 1, true), "a bare string names the list to write")
	assert(panes_error({ current = true }):find("no list entries", 1, true), "a map draws nothing, so it is refused")
	assert(panes_error({}):find("no list entries", 1, true), "an empty list draws nothing")
	assert(panes_error("sidebar"):find("`sidebar`", 1, true), "an unknown pane name")
	assert(panes_error(3):find("got a number", 1, true), "a value of the wrong type")
end)

-- --- the theme -------------------------------------------------------------

test("theme: a base colour comes from the user's `[supaline]` section", function()
	-- Readable from the start on 26.9.1: the user's `theme.toml` is merged
	-- before any plugin code runs, so `setup` resolves the user's colour rather
	-- than the column's default.
	stub.th.supaline = { size = "#ff8800" }

	setup { detail = { { "size", width = 3 } } }
	eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#ff8800")

	-- Put it back: a colour left set here would reach every test after this one,
	-- and the failure would point at the wrong one.
	stub.th.supaline = nil
end)

test("theme: a reload replaces a colour already resolved", function()
	-- This is the half that still fails silently. `app:theme` re-reads
	-- `theme.toml` from disk mid-run, and a plugin that resolved its colours
	-- once at `setup` goes on drawing the old ones with nothing to say so --
	-- which is what `ps.sub("theme", build)` is for.
	--
	-- Changing the section *after* `setup` is what makes this test say that. A
	-- section that never changed would pass for a plugin that never subscribed.
	stub.th.supaline = { size = "#ff8800" }
	setup { detail = { { "size", width = 3 } } }
	eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#ff8800")

	stub.th.supaline = { size = "#00ccff" }
	stub.fire("theme")
	eq(
		stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg,
		"#00ccff",
		"the reloaded colour, not the one resolved at setup"
	)

	stub.th.supaline = nil
end)

test("theme: a style table works as well as a colour string", function()
	stub.th.supaline = { size = ui.Style():fg("#00ff00"):bold() }
	setup { detail = { { "size", width = 3 } } }
	stub.fire("theme")

	local style = stub.first_style(Linemode.detail { _file = CURRENT.files[1] })
	eq(style.fg, "#00ff00")
	eq(style.bold, true)
	stub.th.supaline = nil
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

	setup { detail = { "seen", panes = { "current", "parent" } } }
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
