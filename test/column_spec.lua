---@diagnostic disable: param-type-mismatch

--- `column.lua`: spec normalisation, cell layout, the ratio contract, and the
--- two width shapes that are derived from the listing.

local column = require(".column")

local CFG = { scale = "linear" }

--- Normalise a spec and render one file through it, returning plain text.
---@param spec any
---@param file table?
---@return string
local function cell(spec, file)
	local col = column.normalize(spec, CFG)
	return text_of(column.cell(col, file or stub.file {}))
end

-- --- spec shapes -----------------------------------------------------------

test("normalize: a registered column by name", function()
	column.register("fixed", { width = 4, render = function() return "ab" end })
	eq(cell("fixed"), "  ab")
end)

test("normalize: a name with its options overridden", function()
	column.register("fixed", { width = 4, align = "right", render = function() return "ab" end })
	eq(cell { "fixed", width = 5, align = "left" }, "ab   ")
end)

test("normalize: a bare function", function()
	eq(cell(function() return "hi" end), "hi")
end)

test("normalize: an inline definition", function()
	eq(cell { render = function() return "x" end, width = 3, align = "left" }, "x  ")
end)

test("normalize: an unknown name is refused", function()
	throws(function() column.normalize("nope", CFG) end, "unknown column `nope`")
end)

test("normalize: a value that is not a spec is refused", function()
	throws(function() column.normalize(42, CFG) end, "must be a name, a function, or a table")
	throws(function() column.normalize({}, CFG) end, "must be a name, a function, or a table")
end)

test("normalize: an unusable width is refused", function()
	throws(function()
		column.normalize({ render = function() return "" end, width = "wide" }, CFG)
	end, 'must be a number, "auto", or a function')
end)

test("register: a column needs a render function", function()
	throws(function() column.register("bad", {}) end, "needs a `render` function")
	throws(function()
		column.register("", { render = function() end })
	end, "non-empty name")
end)

test("register: a column may not own asynchronous state", function()
	-- `ya.sync` blocks are matched by position between the two interpreters, so
	-- one registered from init.lua would never be replayed on the async side.
	throws(function()
		column.register("async", { render = function() return "" end, fetch = function() end })
	end, "cannot define `fetch`")
end)

-- --- layout ----------------------------------------------------------------

test("cell: pads to the column width, on the side the alignment asks for", function()
	eq(cell { render = function() return "ab" end, width = 5 }, "   ab")
	eq(cell { render = function() return "ab" end, width = 5, align = "left" }, "ab   ")
end)

test("cell: a nil render result is an empty cell", function()
	eq(cell { render = function() return nil end, width = 3 }, "   ")
end)

test("cell: no width means no padding", function()
	eq(cell { render = function() return "ab" end }, "ab")
end)

test("cell: an overflowing cell gets exactly one ellipsis", function()
	-- `ui.truncate` appends an ellipsis of its own; adding a second one was a
	-- real bug, and it was invisible because the width still came out right.
	local out = cell { render = function() return "yohkuri:wheel" end, width = 12 }
	eq(out, "yohkuri:whe…")
	eq(select(2, out:gsub("…", "")), 1, "ellipsis count")
end)

test("cell: a wide character at the edge is padded back to width", function()
	-- `ui.truncate` can only return 3 cells here, so `fit` has to measure the
	-- result again rather than trust it.
	local out = cell { render = function() return "你好，世界" end, width = 4 }
	eq(stub.str_width(out), 4)
	eq(out, " 你…")
end)

test("cell: clip cuts without an ellipsis", function()
	eq(cell { render = function() return "abcdefgh" end, width = 4, overflow = "clip" }, "abcd")
end)

test("cell: clip counts display cells, not bytes", function()
	-- The path that never ran in the real Yazi until it was tested: a wide
	-- character that does not fit is dropped whole, and the gap is padded.
	local out = cell { render = function() return "日本語abc" end, width = 5, overflow = "clip" }
	eq(out, " 日本")
	eq(stub.str_width(out), 5)
end)

test("cell: grow leaves an overflowing cell alone", function()
	eq(cell { render = function() return "abcdefgh" end, width = 4, overflow = "grow" }, "abcdefgh")
end)

test("cell: max_width caps the column", function()
	eq(cell { render = function() return "abcdefgh" end, width = 6, max_width = 4 }, "abc…")
end)

test("cell: a renderable comes back padded around, not inside", function()
	local out = cell { render = function() return ui.Line("ab") end, width = 5 }
	eq(text_of(out), "   ab")
end)

test("cell: a truncated renderable is padded back to width", function()
	-- `Line:truncate` returns at most `width`, exactly like `ui.truncate`: a
	-- wide character straddling the edge comes back a cell short. Left
	-- unpadded, every column after this one shifts.
	for _, mode in ipairs { "ellipsis", "clip" } do
		local col =
			column.normalize({ render = function() return ui.Line("你好，世界") end, width = 4, overflow = mode }, CFG)
		eq(stub.str_width(text_of(column.cell(col, stub.file {}))), 4, mode)
	end
end)

test("cell: a renderable is truncated too", function()
	local col = column.normalize({ render = function() return ui.Line("abcdefgh") end, width = 4 }, CFG)
	eq(text_of(column.cell(col, stub.file {})), "abc…")

	local clipped =
		column.normalize({ render = function() return ui.Line("abcdefgh") end, width = 4, overflow = "clip" }, CFG)
	eq(text_of(column.cell(clipped, stub.file {})), "abcd")
end)

-- --- the ratio contract ----------------------------------------------------

--- A column bound to one set of extremes, ready to be asked for ratios.
---@param stats table?
---@param scale string?
---@return table
local function bound(stats, scale)
	local col = column.normalize({ render = function() return "" end, scale = scale }, CFG)
	column.bind(col, { stats = stats })
	return col.ctx
end

test("ratio: linear normalisation between the extremes", function()
	local ctx = bound { min = 0, max = 10 }
	eq(ctx.ratio(0), 0)
	eq(ctx.ratio(5), 0.5)
	eq(ctx.ratio(10), 1)
end)

test("ratio: values outside the range are clamped", function()
	local ctx = bound { min = 10, max = 20 }
	eq(ctx.ratio(0), 0)
	eq(ctx.ratio(99), 1)
end)

test("ratio: a single-valued listing is all maximum", function() eq(bound({ min = 7, max = 7 }).ratio(7), 1) end)

test("ratio: nothing to normalise against gives nil", function()
	eq(bound(nil).ratio(5), nil)
	eq(bound({ min = 0, max = 10 }).ratio(nil), nil)
end)

test("ratio: the log scale lifts the small end", function()
	local lin = bound({ min = 1, max = 1000000 }, "linear")
	local log = bound({ min = 1, max = 1000000 }, "log")
	local small = 1000

	assert(lin.ratio(small) < 0.01, "linear pins 1000 to the floor")
	assert(log.ratio(small) > 0.4, "log gives it half the range")
	eq(log.ratio(1000000), 1)
end)

test("bind: rebinding swaps the extremes and the width", function()
	local col = column.normalize({ render = function() return "" end }, CFG)
	column.bind(col, { stats = { min = 0, max = 10 }, width = 6 })
	eq(col.ctx.width, 6)
	eq(col.ctx.ratio(5), 0.5)

	column.bind(col, { stats = { min = 0, max = 100 }, width = 3 })
	eq(col.ctx.width, 3)
	eq(col.ctx.ratio(5), 0.05)
end)

-- --- derived widths --------------------------------------------------------

local FILES = {
	stub.file { name = "a", size = 1 },
	stub.file { name = "b", size = 100000 },
	stub.file { name = "c", size = 1000 },
}

test("width: a stated number is used as is", function()
	local col = column.normalize({ render = function() return "" end, width = 4 }, CFG)
	eq(column.resolve_width(col, FILES, nil), 4)
	eq(col.needs_pass, false, "a stated width needs no pass over the folder")
end)

test("width: a stated width still takes the pass when stats are declared", function()
	-- Gating the folder pass on whoever consumes the result left a column whose
	-- `render` reads `ctx.stats` directly with nothing to read.
	local col = column.normalize({
		render = function() return "" end,
		width = 4,
		stats = function() return { min = 1, max = 2 } end,
	}, CFG)
	eq(col.needs_pass, true)
end)

test("width: a function is handed the folder's statistics", function()
	local col = column.normalize({
		render = function() return "" end,
		stats = function() return { min = 1, max = 100000 } end,
		width = function(st) return #ya.readable_size(st.max) end,
	}, CFG)
	eq(column.resolve_width(col, FILES, { min = 1, max = 100000 }), 5)
	eq(col.needs_pass, true)
end)

test('width: "auto" takes the widest rendered cell', function()
	local col = column.normalize({
		render = function(file) return ya.readable_size(file:size()) end,
		width = "auto",
	}, CFG)
	-- 1B / 97.7K / 1000B -> the widest is "1000B"
	eq(column.resolve_width(col, FILES, nil), 5)
	eq(col.needs_pass, true)
end)

test('width: max_width caps "auto"', function()
	local col = column.normalize({
		render = function(file) return ya.readable_size(file:size()) end,
		width = "auto",
		max_width = 3,
	}, CFG)
	eq(column.resolve_width(col, FILES, nil), 3)
end)

test('width: "auto" over an empty folder is zero', function()
	local col = column.normalize({ render = function() return "x" end, width = "auto" }, CFG)
	eq(column.resolve_width(col, {}, nil), 0)
end)
