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

--- Configure the plugin and point the stubbed context at the folders above.
---@param linemodes table
---@param opts table?
local function setup(linemodes, opts)
	opts = opts or {}
	opts.linemodes = linemodes
	main.setup({}, opts)

	cx.active.current = CURRENT
	cx.active.parent = PARENT
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

test("setup: overriding one of Yazi's own linemode names is still allowed", function()
	-- Replacing the `size` linemode is a thing to want; replacing `redraw` is
	-- not, and the two live on the same table.
	setup { size = { { "size", width = 4 }, { "size", width = 4 } } }
	eq(draw("size", CURRENT.files[1]), "  1B   1B")
end)

test("setup: a name Yazi cannot hold is refused", function()
	local long = string.rep("x", 21)
	throws(function() main.setup({}, { linemodes = { [long] = { "size" } } }) end, "1 to 20 characters")
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

	local preview_row = stub.file { name = "p", in_current = false, in_preview = true, size = 1 }
	cx.active.preview = { folder = CURRENT }
	eq(draw_child(preview_row), "  1B")
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

test("theme: base colours are resolved on the event, not at setup", function()
	-- Until `app:theme` fires, `th.*` holds preset values only, so anything a
	-- plugin reads at setup time is the wrong colour.
	th.supaline = nil
	setup { detail = { { "size", width = 3 } } }
	eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "cyan", "the column's own default")

	th.supaline = { size = "#ff8800" }
	for _, fn in ipairs(stub.subs.theme) do
		fn()
	end
	eq(stub.first_style(Linemode.detail { _file = CURRENT.files[1] }).fg, "#ff8800")
end)

test("theme: a style table works as well as a colour string", function()
	th.supaline = { size = ui.Style():fg("#00ff00"):bold() }
	setup { detail = { { "size", width = 3 } } }
	for _, fn in ipairs(stub.subs.theme) do
		fn()
	end

	local style = stub.first_style(Linemode.detail { _file = CURRENT.files[1] })
	eq(style.fg, "#00ff00")
	eq(style.bold, true)
	th.supaline = nil
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
	eq(calls, 1, "three rows, one pass")
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
