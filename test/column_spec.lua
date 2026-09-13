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

-- --- separators ------------------------------------------------------------

test("separator: a string is the whole of it, and costs no style", function()
	local sep = assert(column.separator("|", "`separator` in `setup`"))
	eq(sep.text, "|")
	-- Nil rather than an empty style: it is what keeps an uncoloured separator
	-- a bare string in the Line, and a `ui.Span` per row is what that saves.
	eq(sep.style, nil)
end)

test(
	"separator: nothing written is nothing to fall back from",
	function() eq(column.separator(nil, "`separator` in `setup`"), nil) end
)

test("separator: a table is the text and the colour it draws in", function()
	local sep = assert(column.separator({ "|", base = "cyan" }, "`separator` in `setup`"))
	eq(sep.text, "|")
	eq(assert(sep.style).fg, "cyan")
end)

test("separator: `base` takes everything a column's `base` takes", function()
	---@param base any
	---@return table the style that `base` came back as
	local function style(base) return assert(assert(column.separator({ "|", base = base }, "x")).style) end
	eq(style({ fg = "cyan", bold = true }).fg, "cyan", "a style table")
	eq(rawget(style { fg = "cyan", bold = true }, "bold"), true, "... attributes and all")
	eq(style(ui.Style():fg("red")).fg, "red", "a `ui.Style`")
	eq(style("129").fg, "129", "an index Yazi's own parser takes")
end)

test("separator: a `base` written as a function is called, never stored", function()
	-- The repair a column's `base` gets, for the reason `normalize` gives: a
	-- spec is re-read on every `theme` event and never evaluated again, so a
	-- colour borrowed from the theme has to be borrowed inside the build.
	local calls = 0
	local sep = assert(column.separator({
		"|",
		base = function()
			calls = calls + 1
			return "cyan"
		end,
	}, "`separator` in `setup`"))
	eq(calls, 1)
	eq(assert(sep.style).fg, "cyan")

	throws(function()
		column.separator({ "|", base = function() error("no `[status]` section") end }, "x")
	end, "the `base` function of x raised")
end)

test("separator: what is not one is refused by name", function()
	throws(function() column.separator(42, "`separator` in `setup`") end, "must be a string, or a table")
	-- The one worth its own sentence: `false` is a column's spelling for `sep`,
	-- and being falsy it used to fall through to the separator it was written
	-- to be rid of.
	throws(function() column.separator(false, "`separator` in `setup`") end, "a column's spelling for `sep`")
	throws(function() column.separator({ base = "cyan" }, "x") end, "first element is the text")
	throws(function() column.separator({ 42 }, "x") end, "has to be a string; got a number")
	throws(
		function() column.separator({ "|", bass = "cyan", colour = "x" }, "x") end,
		"`bass`, `colour` are not separator keys"
	)
	throws(function() column.separator({ "|", base = { fgg = "cyan" } }, "x") end, "the colour of x")
end)

test("normalize: a column's own `sep` takes the table form too", function()
	column.register("fixed", { width = 4, render = function() return "ab" end })
	-- Cast rather than asserted: `assert` narrows the nil away and leaves the
	-- `false` a column's `sep` can also be.
	local sep = column.normalize({ "fixed", sep = { "|", base = "cyan" } }, CFG).sep --[[@as supaline.Sep]]
	eq(sep.text, "|")
	eq(assert(sep.style).fg, "cyan")

	-- Refused nowhere until a row was drawn, and then as Yazi emptying the
	-- screen. The message names the column, because a linemode has as many
	-- `sep`s as it has columns.
	-- The wrong value is the test; the checker refuses it where it runs, which
	-- is not over anyone's `init.lua`.
	---@diagnostic disable-next-line: assign-type-mismatch
	throws(function() column.normalize({ "fixed", sep = 42 }, CFG) end, "`sep` on column `fixed`")
end)

-- --- spec shapes -----------------------------------------------------------

test("normalize: a registered column by name", function()
	column.register("fixed", { width = 4, render = function() return "ab" end })
	eq(cell("fixed"), "  ab")
end)

test("normalize: a name with its options overridden", function()
	column.register("fixed", { width = 4, align = "right", render = function() return "ab" end })
	eq(cell { "fixed", width = 5, align = "left" }, "ab   ")
end)

test("normalize: an option written on the definition survives, `false` and all", function()
	-- `sep` is the only option whose meaningful value is `false`, and the
	-- `opts[k] == nil and def[k] or opts[k]` idiom collapsed it to nil, so a
	-- definition that said `sep = false` still got a separator drawn.
	column.register("tight", { width = 3, sep = false, render = function() return "x" end })
	eq(column.normalize("tight", CFG).sep, false)
	eq(column.normalize({ "tight", sep = "|" }, CFG).sep.text, "|", "the use site still wins")
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
	-- The wrong value is the test. A spec carries a class now, so the checker
	-- refuses it as well, and the suppression sits on the line rather than at
	-- the top of the file: the blanket `param-type-mismatch` disable that used
	-- to be there was measured to cover this one site and nothing else.
	---@diagnostic disable-next-line: param-type-mismatch
	throws(function() column.normalize(42, CFG) end, "must be a name, a function, or a table")
	throws(function() column.normalize({}, CFG) end, "must be a name, a function, or a table")
end)

test("normalize: an unusable width is refused", function()
	throws(function()
		---@diagnostic disable-next-line: assign-type-mismatch
		column.normalize({ render = function() return "" end, width = "wide" }, CFG)
	end, 'must be a number, "auto", or a function')
end)

test("register: a column needs a render function", function()
	---@diagnostic disable-next-line: missing-fields
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
	local out = cell { render = function() return "octocat:wheel" end, width = 12 }
	eq(out, "octocat:whe…")
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

test("cell: a cluster is cut whole, and never over the width", function()
	-- Counting characters is what overran here. `❤️` is a one-cell character
	-- followed by a zero-cell one, and two cells on screen, so a cut that added
	-- them up handed back four cells for a column of three -- measured on Yazi
	-- 26.9.1, where `ui.truncate("❤️abc", { max = 3 })` is `❤️a…`. A cell one
	-- too wide is not a cosmetic problem: every column after it shifts.
	local heart = "\u{2764}\u{FE0F}abc"
	eq(cell { render = function() return heart end, width = 3, overflow = "clip" }, "\u{2764}\u{FE0F}a")
	eq(cell { render = function() return heart end, width = 3, overflow = "ellipsis" }, "\u{2764}\u{FE0F}…")
end)

test("cell: a joined emoji is cut at the cluster, not inside it", function()
	-- Yazi's own cut stops between the joiner and what it joined --
	-- `ui.truncate("👩‍💻abc", { max = 3 })` is `👩‍…` -- and drops the modifier
	-- from `👍🏽`. Both are one character as far as the screen is concerned, so
	-- the whole of one fits or none of it does.
	eq(
		cell { render = function() return "\u{1F469}\u{200D}\u{1F4BB}abc" end, width = 3, overflow = "clip" },
		"\u{1F469}\u{200D}\u{1F4BB}a"
	)
	eq(
		cell { render = function() return "\u{1F44D}\u{1F3FB}abc" end, width = 3, overflow = "clip" },
		"\u{1F44D}\u{1F3FB}a"
	)
	-- A flag is a pair of regional indicators and a third one starts a new
	-- flag, so the pair is the unit, not the run.
	eq(
		cell { render = function() return "\u{1F1EF}\u{1F1F5}\u{1F1EF}\u{1F1F5}" end, width = 3, overflow = "clip" },
		" \u{1F1EF}\u{1F1F5}"
	)
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

test("cell: a span drawn a second time is refused, the way Yazi refuses it", function()
	-- Yazi *moves* a span into the line it is put in, so a render that builds a
	-- list once and hands it back for every row raises on the second row and
	-- the pane stops drawing. Measured on 26.9.1 and reproduced by the stub
	-- deliberately: nothing else would tell the difference between caching the
	-- spans and caching the styles, and caching the spans is what a column
	-- drawing one character at a time invites.
	local kept = { ui.Span("a"), ui.Span("b") }
	local col = column.normalize({ render = function() return ui.Line(kept) end, width = 2 }, CFG)

	eq(text_of(column.cell(col, stub.file {})), "ab")
	throws(function() column.cell(col, stub.file {}) end, "already been put in a Line")
end)

test("cell: a whole Line drawn a second time is refused too", function()
	-- Not only the spans inside it. Measured on 26.9.1: `ui.Line(line)` takes
	-- the line the same way, so a render caching one finished Line raises on
	-- the second row exactly as a render caching its spans does -- and
	-- `column.cell` puts whatever comes back through `ui.Line`, so there is no
	-- shape of cached renderable that escapes it.
	local kept = ui.Line { ui.Span("a"), ui.Span("b") }
	local col = column.normalize({ render = function() return kept end, width = 2 }, CFG)

	eq(text_of(column.cell(col, stub.file {})), "ab")
	throws(function() column.cell(col, stub.file {}) end, "already been put in a Line")
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

test("cell: a renderable is truncated too, to the same width as a string", function()
	local col = column.normalize({ render = function() return ui.Line("abcdefgh") end, width = 4 }, CFG)
	eq(text_of(column.cell(col, stub.file {})), "abc…")

	-- `Line:truncate` drops the character that lands exactly on `max` to make
	-- room for the ellipsis, and goes on doing it when the ellipsis is empty:
	-- asked for four cells of these eight it returns three, where the same
	-- string cut as a string returns four. A column that hands back a
	-- renderable is not a narrower column, so `cell` asks for the cell back.
	local clipped =
		column.normalize({ render = function() return ui.Line("abcdefgh") end, width = 4, overflow = "clip" }, CFG)
	eq(text_of(column.cell(clipped, stub.file {})), "abcd")
end)

test("cell: a renderable Yazi thinks fits is cut anyway", function()
	-- The other half. `Line:truncate` counts characters, so it hands `❤️abc`
	-- back untouched for a column of four -- five cells on screen, and no
	-- `max` cuts it to exactly four. Coming back a cell short is fine, because
	-- short is padded; coming back long is what shifts the columns after it.
	for _, mode in ipairs { "ellipsis", "clip" } do
		local col = column.normalize(
			{ render = function() return ui.Line("\u{2764}\u{FE0F}abc") end, width = 4, overflow = mode },
			CFG
		)
		eq(stub.str_width(text_of(column.cell(col, stub.file {}))), 4, mode)
	end
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

-- --- the colour ------------------------------------------------------------

local BLUES = "#0b3d91 -> #7fd4ff"

--- A column carrying a colour, ready to be asked for styles.
---
--- `stats` is there because a ramp needs a column that can produce extremes:
--- `normalize` refuses one on a column that declares none. Returning nil from
--- it is a folder with nothing to measure, which is a state of its own.
---@param opts table
---@return supaline.Ctx
local function coloured(opts)
	opts.render = function() return "" end
	opts.stats = opts.stats or function() return nil end
	return column.normalize(opts, CFG).ctx
end

test("ramp: the endpoints sit at the ends of the range", function()
	local ctx = coloured { ramp = BLUES }
	eq(ctx.style(0).fg, "#0b3d91")
	eq(ctx.style(1).fg, "#7fd4ff")
	-- The bucket arithmetic, not just the ends: 64 steps put the halfway
	-- ratio on the 33rd, and `colour_spec.lua` pins what that colour is.
	eq(ctx.style(0.5).fg, "#4288c9")
end)

test(
	"ramp: a list and a string say the same thing",
	function() eq(coloured({ ramp = { "#0b3d91", "#7fd4ff" } }).style(0.5).fg, coloured({ ramp = BLUES }).style(0.5).fg) end
)

test("ramp: a row with no value draws the ramp's low end", function()
	-- Not the ground beneath it: that is where a theme's `bold` lives and it
	-- may carry no colour at all, which would leave an unevaluated directory
	-- in `size` the one uncoloured cell in the column.
	local ctx = coloured { ramp = BLUES }
	eq(ctx.style(nil).fg, "#0b3d91")
	eq(ctx.base.fg, "#0b3d91")
end)

test("ramp: a ratio off the end is clamped, not left unstyled", function()
	-- `ratio` clamps, but `style` is public and a column may hand it anything.
	-- An index past the end would return nil, and a nil style draws a cell with
	-- no colour -- which reads as a theme that failed to load.
	local ctx = coloured { ramp = BLUES }
	eq(ctx.style(-1).fg, "#0b3d91")
	eq(ctx.style(2).fg, "#7fd4ff")
end)

test("ramp: a NaN ratio is clamped too, where a comparison would let it past", function()
	-- NaN answers false to `< 1` and to `> n` alike, so a clamp written as two
	-- comparisons hands `ramp[nan]` back, which is nil -- and `cell` drops a nil
	-- style without a word. Not hypothetical: `ratio` produces one for any
	-- `scale = "log"` column whose extremes reach -1 or below, where `math.log`
	-- of a non-positive number is a NaN in `_lo`.
	local ctx = coloured { ramp = BLUES }
	eq(ctx.style(0 / 0).fg, "#0b3d91")

	local col = column.normalize({
		render = function() return "" end,
		stats = function() return { min = -10, max = 100 } end,
		scale = "log",
		ramp = BLUES,
	}, CFG)
	column.bind(col, { stats = { min = -10, max = 100 } })
	local r = col.ctx.ratio(5)
	assert(r ~= r, "a log scale over a negative minimum is where the NaN comes from")
	eq(col.ctx.style(r).fg, "#0b3d91", "and the cell is still coloured")
end)

test("ramp: `false` turns a colour off rather than being read as one", function()
	-- The spelling `sep` already uses, and the only way to drop a colour the
	-- definition or the theme would otherwise supply. Read as a value it would
	-- reach `stops` and come back as "must be a list of colours", which says
	-- nothing about what was actually asked for.
	column.register("hue3", {
		render = function() return "" end,
		stats = function() return nil end,
		base = "red",
		ramp = BLUES,
	})
	eq(column.normalize("hue3", CFG).ctx.base.fg, "#0b3d91", "the definition's ramp, without it")

	local ctx = column.normalize({ "hue3", base = false, ramp = false }, CFG).ctx
	eq(ctx.style(1), ctx.base, "no ramp left to index")
	-- `rawget`, because reading `.fg` off a style that has none hands back the
	-- setter rather than nil -- on a real Yazi as here, which is why nothing in
	-- this plugin ever reads a colour back out of a style.
	eq(rawget(ctx.base, "fg"), nil, "and no colour left either")
end)

test("ramp: the base is the ground it is patched onto", function()
	local ctx = coloured { base = ui.Style():fg("red"):bold(), ramp = BLUES }
	local style = ctx.style(1)
	eq(style.fg, "#7fd4ff", "the ramp decides the colour")
	eq(style.bold, true, "and everything else is kept")
end)

test("ramp: a column with no extremes to place a value between is refused", function()
	-- Without `stats` the ratio is nil for every row, so the ramp could only
	-- ever draw its low end. A gradient that silently is not one has nothing
	-- else to report it, so `normalize` does.
	throws(function()
		column.normalize({ render = function() return "" end, ramp = BLUES }, CFG)
	end, "has no `stats`")
end)

test("base: a style table is built into a style, and anything else is refused", function()
	-- The spelling `theme.toml` uses, taken here too, so a style moves between
	-- the two files unchanged. `colour_spec.lua` pins the keys; this is the
	-- spec's own path to them.
	local ctx = coloured { base = { fg = "#ff8800", bold = true } }
	eq(ctx.base.fg, "#ff8800")
	eq(ctx.base.bold, true)

	-- Still an allow-list: what is not a colour, a style table or a `ui.Style`
	-- survives `setup` and then empties the screen, because `Span:style` takes a
	-- Style or nil and a number reaches Yazi as neither.
	throws(function() coloured { base = 42 } end, "is a number")
end)

test("base: a function is called for its colour, and called again on the next build", function()
	-- The one way a spec can reach a colour the theme does not have yet. 26.9.1
	-- merges the flavor after `init.lua` has run, so `base = th.status.perm_read`
	-- captures Yazi's preset and keeps it: the stored spec is re-read on every
	-- `theme` event but never evaluated again. A function is evaluated again.
	local answer = "#112233"
	local spec = { base = function() return answer end }
	eq(coloured(spec).base.fg, "#112233")

	answer = "#445566"
	eq(coloured(spec).base.fg, "#445566", "the next build asks again")

	-- And a `ui.Style` comes back through it, which is what the field this was
	-- written for holds.
	local ctx = coloured { base = function() return ui.Style():fg("#778899"):bold() end }
	eq(ctx.base.fg, "#778899")
	eq(ctx.base.bold, true)
end)

test("base: a function that returns `false` drops the colour, as writing it does", function()
	-- `false` is the only way to turn off a colour the theme or the definition
	-- would otherwise supply, and handed to `colour.style` it would come back
	-- refused as a boolean. The spec has still said something, so the theme
	-- stays out of it.
	local ctx = coloured { base = function() return false end }
	eq(rawget(ctx.base, "fg"), nil)
	eq(ctx.source, "spec")
end)

test("base: `ui.Style` with the call forgotten is refused, not called", function()
	-- Measured on 26.9.1: `type(ui.Style)` is `table` and only `ui.Style()` is
	-- userdata. Now that a table is a style rather than a refusal, the bare name
	-- would be read as one -- `pairs` finds nothing on it, so it would come back
	-- an empty style, green and uncoloured. `colour.lua` tells the two apart by
	-- the `__call` a constructor carries, and the stub's `ui.Style` has one for
	-- the same reason Yazi's does.
	eq(type(ui.Style), "table")
	throws(function() coloured { base = ui.Style } end, "is the constructor")
end)

test("base: a function in the spec outranks the theme, the way a colour does", function()
	-- Which is also what tells `permissions` to stop colouring itself.
	column.register("hue4", { render = function() return "" end })
	with(stub.th, "supaline", { hue4 = "#00ccff" }, function()
		local col = column.normalize({ "hue4", base = function() return "#ff8800" end }, CFG)
		eq(col.ctx.base.fg, "#ff8800")
		eq(col.ctx.source, "spec")
	end)
end)

test("base: a function that fails is reported in terms of the file it was written in", function()
	-- Two ways to fail and one mechanism for both. A value `colour.style` would
	-- refuse is named for the function rather than for `base`, because the line
	-- holding the function is not the line to change -- and a definition may
	-- carry one, where the reader has no `base` of their own to look at.
	column.register("hue5", { render = function() return "" end, base = function() return 42 end })
	throws(function() column.normalize("hue5", CFG) end, "what the default `base` function of column `hue5` returned")

	-- The call raising is the likelier half: a flavor with no such section, a
	-- field that moved. Lua's own message for it carries no column at all.
	throws(function()
		column.normalize({ "hue5", base = function() return th.nosuch.field end }, CFG)
	end, "the `base` function of column `hue5` raised")
end)

test("colour: a value Yazi would refuse says which column it was", function()
	column.register("hue", { render = function() return "" end, base = "nosuchcolour" })
	throws(function() column.normalize("hue", CFG) end, "column `hue`")

	column.register("hue2", {
		render = function() return "" end,
		stats = function() return nil end,
		ramp = "cyan -> #7fd4ff",
	})
	throws(function() column.normalize("hue2", CFG) end, "column `hue2`")
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

test("width: a width function that returns no number is refused", function()
	-- Returning nil here left the column with no width at all: no padding, no
	-- truncation, and a cell free to push into the file name.
	local col = column.normalize({
		render = function() return "abcdefgh" end,
		name = "wonky",
		width = function() return nil end,
	}, CFG)
	throws(function() column.resolve_width(col, FILES, nil) end, "returned a nil; it must return a number")
end)

test('width: "auto" over an empty folder is zero', function()
	local col = column.normalize({ render = function() return "x" end, width = "auto" }, CFG)
	eq(column.resolve_width(col, {}, nil), 0)
end)
