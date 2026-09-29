--- `column.lua`: spec normalisation, cell layout, the ratio contract, and the
--- two width shapes that are derived from the listing.

local appearance = require(".appearance")
local column = require(".column")
local listing = require(".listing")
---@type supaline.ColumnCases
local cases = dofile(ROOT .. "/test/column_case.lua")
local registry = column.new_registry()
local register = registry.register
local prepare = cases.compiler(registry)

--- Normalise a spec and render one file through it, returning plain text.
---@param spec any
---@param file table?
---@return string
local function cell(spec, file) return text_of(cases.cell(prepare(spec), file)) end

--- Lay `s` out through an inline column written with `opts`.
---@param s string
---@param opts table
---@return string
local function laid(s, opts)
	opts.render = function() return s end
	return cell(opts)
end

--- Assert that every `{ spec, pattern, ... }` is refused by `through` --
--- `prepare` unless given -- with a message holding each pattern. Typed `any`
--- because a wrong value is the point, so the table of them needs no
--- suppression apiece.
---@param refusals any[]
---@param through fun(value: any)?
local function refused(refusals, through)
	through = through or prepare
	for _, case in ipairs(refusals) do
		throws(function() through(case[1]) end, table.unpack(case, 2))
	end
end

register("fixed", { width = 4, render = function() return "ab" end })
register("plain", { render = function() return "ab" end })

-- --- spec shapes -----------------------------------------------------------

test("normalize: a registered column by name, its options overridden at the use", function()
	eq(cell("fixed"), "  ab")
	eq(cell { "fixed", width = 5, align = "left" }, "ab   ")
end)

test("normalize: a bare function and an inline definition", function()
	eq(cell(function() return "hi" end), "hi")
	eq(cell { render = function() return "x" end, width = 3, align = "left" }, "x  ")
end)

test("normalize: a use site may override the definition's `render`", function()
	-- `render` is a column key like any other, and what tells a use from a
	-- definition is the name at `[1]`.
	register("over", { width = 6, align = "left", render = function() return "def" end })
	eq(cell { "over", render = function() return "spec" end }, "spec  ")
	eq(
		prepare({ "over", render = function() return "spec" end }).plan.name,
		"over",
		"and the name the theme is looked up under is still the definition's"
	)
end)

test("normalize: an option written on the definition survives, `false` and all", function()
	-- A separator is the only option whose meaningful value is `false`, which an
	-- `opts[k] == nil and def[k] or opts[k]` idiom would collapse to nil.
	register("tight", { width = 3, separator = false, render = function() return "x" end })
	eq(prepare("tight").plan.separator, false)
	eq(prepare({ "tight", separator = "|" }).plan.separator.text, "|", "the use site still wins")
end)

test("normalize: the two bare spellings are the tables they desugar to", function()
	-- Pinned field by field rather than against a cell, which would go on
	-- passing if a desugared spec picked up a different alignment.
	local fn = function() return "x" end
	for _, pair in ipairs { { "fixed", { "fixed" } }, { fn, { render = fn } } } do
		local bare, table_ = prepare(pair[1]), prepare(pair[2])
		for _, key in ipairs { "name", "align", "overflow", "scale" } do
			eq(bare.plan[key], table_.plan[key], "a bare spelling and its table disagree on `" .. key .. "`")
		end
	end
end)

test("normalize: one refusal per mistake, whichever spelling wrote it", function()
	local shape = "must be a name, a function, or a table with `render`"
	refused {
		{ "nope", "unknown column `nope`" },
		{ { "nope" }, "unknown column `nope`" },
		{ 42, shape },
		{ {}, shape },
		{ { x = 1 }, shape },
	}
end)

test("normalize: a key nobody claimed is refused by name", function()
	-- A misspelled key is drawn nowhere and mentioned nowhere, and a table
	-- constructor is past what the checker reads against a class. Every key is
	-- named, sorted, so the same mistake reports the same way twice running,
	-- and the message carries what to write instead.
	refused {
		{ { "fixed", max_widht = 2 }, "`max_widht` is not a column key", "`max_width`" },
		{ { "fixed", algin = 1, widht = 2 }, "`algin`, `widht` are not column keys" },
		{ { render = function() return "x" end, overflw = "clip" }, "`overflw` is not a column key" },
		-- A second element is a column written where no second column is read.
		{ { "fixed", "mtime" }, "`2` is not a column key" },
		-- A string there names a column and a function is refused below, so what
		-- reaches this is neither.
		{ { [1] = true, render = function() return "x" end }, "`1` is not a column key" },
	}
end)

test("normalize: a value the shared keys do not take is refused", function()
	-- A value nobody accepts would otherwise be accepted by being ignored:
	-- `align = "centre"` fell to the default and drew right-aligned. What was
	-- written comes back in the message, as written or by its type.
	refused {
		{ { "fixed", align = "centre" }, "spec.align: ", "must be `left` or `right`", "got `centre`" },
		{ { "fixed", overflow = "elipsis" }, "must be `ellipsis`, `clip` or `grow`" },
		{ { "fixed", scale = "LOG" }, "must be `linear` or `log`" },
		-- `scale`'s sources are merged with an `or` chain, which skips a `false`
		-- the way it skips a nil, so it has to be refused where it is read.
		{ { "fixed", scale = false }, "must be `linear` or `log`" },
		{ { "fixed", align = false }, "must be `left` or `right`" },
		{ { "fixed", align = 42 }, "got `42`" },
		{ { "fixed", align = {} }, "got a table" },
	}
end)

test("normalize: a key that is called rather than read must be a function", function()
	-- Each is knowable while `setup` runs. Taken on trust, `stats = 42` was
	-- reported at bind time as a function that threw, and `refresh = 42` raised
	-- out of `install` after `setup` had committed.
	refused {
		{ { "fixed", stats = 42 }, "spec.stats: ", "must be a function, got `42`" },
		{ { "fixed", refresh = 42 }, "spec.refresh: " },
		{ { "fixed", refresh = {} }, "got a table" },
		{ { "fixed", render = "nope" }, "spec.render: " },
		{ { render = 42 }, "spec.render: must be a function, got `42`" },
	}
	local untidy = { width = 4, refresh = 42, render = function() return "ab" end } ---@type any
	throws(function() register("untidy", untidy) end, 'column("untidy").refresh: ')
	local wrong = { render = 42 } ---@type any
	throws(function() register("bad", wrong) end, 'column("bad").render: must be a function, got `42`')
end)

test("normalize: a definition's own wrong value is refused as it is registered", function()
	-- A use reads the definition's value wherever it wrote none, so one that
	-- slipped through would reach every use of that column silently.
	local bent = { width = 4, align = "centre", render = function() return "ab" end } ---@type any
	throws(function() register("bent", bent) end, 'column("bent").align: must be `left` or `right`')
	throws(function() prepare("bent") end, "unknown column `bent`")
end)

test("normalize: a width that would draw nothing is refused", function()
	-- A width of 0 or less drew an empty cell on every row, which reads as a
	-- column that is not there. Not floored either: rounding is a guess about
	-- which of two whole numbers was meant.
	local whole = "must be a whole number of cells, 1 or more"
	refused {
		{ { "plain", width = 0 }, "spec.width: ", whole },
		{ { "plain", width = -3 }, "spec.width: ", whole },
		{ { "plain", max_width = 0 }, "spec.max_width: " },
		{ { "plain", max_width = -1 }, "got `-1`" },
		{ { "plain", width = 3.7 }, "got `3.7`" },
		{ { "plain", max_width = 2.5 }, "got `2.5`" },
		-- A string would otherwise reach `cap`, which compares it with a number.
		{ { "plain", max_width = "x" }, "spec.max_width: " },
		-- `math.tointeger("3")` answers 3 on 5.5.1, so the type is asked first.
		{ { "plain", max_width = "3" }, "spec.max_width: " },
		-- `width` takes two more shapes than `max_width`, and says so.
		{ { "plain", width = "3" }, 'must be a number of cells, "auto", or a function' },
	}
end)

test("normalize: a width it does take still goes through", function()
	eq(prepare({ "plain", width = 6 }).plan.width.value, 6)
	-- An integral float is not the mistake the refusal is about, so it is
	-- taken, and narrowed to an integer on the way past.
	eq(math.type(prepare({ "plain", width = 6.0 }).plan.width.value), "integer")
	eq(prepare({ "plain", max_width = 4.0 }).plan.max_width, 4)
	eq(prepare({ "plain", width = 9, max_width = 4 }).plan.width.value, 4, "and the cap applies to it")
end)

test("normalize: nothing written reaches the default, and every value taken passes", function()
	local col = prepare("plain")
	eq(col.plan.align, "right")
	eq(col.plan.overflow, "ellipsis")
	eq(col.plan.scale, "linear")

	for key, values in pairs {
		align = { "left", "right" },
		overflow = { "ellipsis", "clip", "grow" },
		scale = { "linear", "log" },
	} do
		for _, v in ipairs(values) do
			eq(prepare({ "plain", [key] = v }).plan[key], v)
		end
	end
end)

test("normalize: every key a column takes passes the sweep", function()
	-- Without this the sweep could quietly turn a real option into an error and
	-- every refusal above would still pass.
	local col = prepare {
		"fixed",
		align = "left",
		overflow = "clip",
		max_width = 6,
		separator = "|",
		stats = function() return {} end,
		refresh = function() end,
		style = { bold = true },
		width = 5,
		scale = "log",
	}
	eq(col.plan.align, "left")
	eq(col.plan.scale, "log")
end)

--- A column that declares an option, for the tests that write one at a use
--- site. `extra` goes on the definition, which is where a default lives.
---@param extra table?
local function timed(extra)
	local def = { width = 4, options = { "format" }, render = function() return "ab" end }
	for k, v in pairs(extra or {}) do
		def[k] = v
	end
	register("timed", def)
end

test("normalize: a column's own options are claimed, and only that column's", function()
	-- The definition declares them, which is what lets a misspelling of one be
	-- refused rather than ignored.
	timed()
	eq(prepare({ "timed", format = "%c" }).plan.name, "timed")
	refused {
		{ { "timed", fromat = "%c" }, "`fromat` is not a column key", "also takes `format`" },
		{ { "fixed", format = "%c" }, "`format` is not a column key" },
		{ { render = function() return "ab" end, options = { "pad" }, pda = 2 }, "`pda` is not a column key" },
	}
end)

test("normalize: `options` and `name` are the definition's to write", function()
	-- Both are read off the definition alone, so at a use site each is a key
	-- nobody reads.
	refused {
		{ { "fixed", options = { "pad" } }, "`options` goes on the definition" },
		{ { "fixed", name = "other" }, "read by nobody" },
	}

	-- The same two keys on the table that *is* the definition are its own.
	local col = prepare { name = "inline", options = { "pad" }, pad = 2, render = function() return "ab" end }
	eq(col.plan.name, "inline", "the name the theme is looked up under")
	eq(col.ctx.opts.pad, 2)
end)

test("normalize: `ctx.opts` holds the declared options and nothing else", function()
	-- Not the spec table: `opts.style` would be the one layer its use site
	-- wrote rather than the three merged, and `opts.width` the stated width.
	timed()
	local ctx = prepare({ "timed", format = "%c", width = 9, style = "cyan" }).ctx
	eq(ctx.opts.format, "%c")
	eq(ctx.opts.width, nil, "the effective width is `ctx.width`")
	eq(ctx.opts.style, nil, "and the merged style is `ctx.style`")
	eq(ctx.width, 9)
	eq(next(prepare("fixed").ctx.opts), nil, "a column that declared none gets a table rather than nil")
end)

test("normalize: a definition may default an option it declares", function()
	timed { options = { "format", "pad" }, format = "%F", pad = false }
	eq(prepare("timed").ctx.opts.format, "%F", "the definition's, with no spec over it")
	eq(prepare({ "timed", format = "%c" }).ctx.opts.format, "%c", "and the use site still wins")
	-- An explicit nil test, so a declared option whose value is `false` stays.
	eq(prepare("timed").ctx.opts.pad, false)
	eq(prepare({ "timed", pad = true }).ctx.opts.pad, true)
end)

test("normalize: a `render` at `[1]` is refused, and says where it goes", function()
	-- A reasonable thing to write, so the refusal carries the spelling that
	-- works.
	refused {
		{ { function() return "ab" end, width = 6 }, "goes under `render`, not at `[1]`", "`{ render = fn, width = 6 }`" },
	}
end)

-- --- register --------------------------------------------------------------

test("register: registries are explicit and share no column", function()
	local a, b = column.new_registry(), column.new_registry()
	local first, second = function() return "a" end, function() return "b" end
	a.register("mine", { render = first })
	b.register("mine", { render = second })
	eq(cases.compiler(a)("mine").plan.render, first)
	eq(cases.compiler(b)("mine").plan.render, second)
	throws(function() prepare("mine") end, "unknown column `mine`")
end)

test("register: a column needs a render function and a name", function()
	---@diagnostic disable-next-line: missing-fields
	throws(function() register("bad", {}) end, "needs a `render` function")
	throws(function()
		register("", { render = function() end })
	end, "`` cannot be a column name")
end)

test("register: a definition is swept the same way, and `options` is checked", function()
	-- Worse than a spec's, because it is read again for every spec naming it.
	local x = function() return "x" end
	throws(function() register("bad", { render = x, algin = "left" }) end, "`algin` is not a column key")
	refused({
		{ "format", 'column("odd").options: must be the list of names' },
		{ {}, "got an empty list" },
		{ { 42 }, "a list holding a number" },
		-- Declaring one changes nothing and reads as though the column took it.
		{ { "width" }, "which every column takes" },
		-- `ipairs` stops at the first gap and `#` cannot see one, so a name past
		-- it would be declared and read by nothing.
		{ { [1] = "a", [3] = "b" }, "a table with a gap in it" },
		{ { "a", extra = "b" }, "or with keys of its own" },
		-- supaline answers for `fetch` itself, and declaring it would walk past
		-- the one place that says why.
		{ { "fetch" }, "`fetch`, which supaline answers for itself" },
	}, function(options) register("odd", { render = x, options = options }) end)

	-- An inline definition never reaches `register`, and is checked all the same.
	refused {
		{ { render = x, options = "format" }, "spec.options: must be the list of names this column reads off `ctx.opts`" },
		{ { render = x, options = { "width" } }, "which every column takes" },
		{ { render = x, options = { "fetch" } }, "which supaline answers for itself" },
	}

	-- A list with neither fault is what a column declares.
	register("padded", { options = { "pad", "trim" }, render = x })
	eq(prepare({ "padded", pad = 2, trim = true }).ctx.opts.trim, true)
end)

test("register: `register` names the column, so `name` beside it is not read", function()
	-- `[1]` is where a *spec* names a column, so the hint says so.
	throws(function()
		register("real", { render = function() return "x" end, name = "alias" })
	end, "read by nobody")
	throws(function() prepare("alias") end, "unknown column `alias`")
	local entry = { "alias", render = function() return "x" end } ---@type any
	throws(function() register("regd", entry) end, "`1` is not a column key", "where a spec names the column it uses")
end)

test("register: a name a theme field cannot hold is refused", function()
	-- Yazi's rule, measured on 26.9.1: a custom section's field name is 1-20
	-- characters of lowercase letters, digits and `_`, and anything else is a
	-- TOML parse error that discards the whole of `theme.toml`. Its message
	-- says "snake-case" and its parser does not mean it, so the leading
	-- character is free.
	local r = function() return "" end
	for _, name in ipairs { "my-col", "MyCol", "UPPER", "my col", "my.col", ("a"):rep(21) } do
		throws(function() register(name, { render = r }) end, "cannot be a column name")
	end
	for _, name in ipairs { "_x", "x_", "2x", "a", ("a"):rep(20) } do
		register(name, { render = r })
		eq(prepare(name).plan.name, name)
	end

	-- A definition written inline names itself under `name`, and reaches
	-- `th.supaline[name]` the way a registered one does, so the rule reaches it.
	for _, name in ipairs { "my-col", "MyCol", ("a"):rep(21) } do
		throws(function() prepare { render = r, name = name } end, "cannot be a column name")
	end
	eq(type(prepare { render = r }), "table", "an inline definition need not name itself")
	stub.th.supaline = { my_col = ui.Style():fg("#ff0000") }
	eq(prepare({ render = r, name = "my_col" }).ctx.style.fg, "#FF0000")
end)

test("register: a column may not own asynchronous state", function()
	-- `ya.sync` blocks are matched by position between the two interpreters,
	-- so one registered from init.lua would never be replayed on the async
	-- side. Refused by the key sweep, which reaches an inline definition too.
	throws(function()
		register("async", { render = function() return "" end, fetch = function() end })
	end, "has to be built into supaline itself")
	refused { { { render = function() return "x" end, fetch = function() end }, "has to be built into supaline itself" } }
end)

-- --- separators ------------------------------------------------------------

--- The separator a column carries for `value`, with its style resolved the way
--- a build resolves it. A column's own separator is the one of the three
--- places nothing else reads before a row does.
---@param value any
---@return { text: string, style: unknown? }
local function separator(value)
	local sep = prepare({ "fixed", separator = value }).plan.separator --[[@as supaline.Sep]]
	return { text = sep.text, style = listing.sep_style(sep.slot and appearance.slot(sep.slot, {})) }
end

test("separator: a string is the text and no style", function()
	eq(separator("|").text, "|")
	eq(separator("|").style, nil, "nobody wrote one, so `render` has no Span to build")
	eq(separator("").text, "", "an empty separator draws nothing and is not a mistake")
end)

test("separator: the table form carries a style, and means the string without one", function()
	local one = separator { " | ", style = { fg = "#585b70" } }
	eq(one.text, " | ")
	eq(one.style.fg, "#585b70")
	-- Left out, the style is not taken from the level above: two spellings that
	-- differ only in what they inherit is what this shape was chosen to avoid.
	eq(separator({ " | " }).style, nil)
end)

test("separator: a style written as a function is called, and named when it raises", function()
	-- Called at `setup` and on every `theme` event; that it is called again is
	-- `main_spec.lua`'s to say. A raise reaches the user as `retheme`'s
	-- notification, where a message with no location says nothing.
	eq(separator({ "|", style = function() return "#ff8800" end }).style.fg, "#ff8800")
	throws(function()
		separator { "|", style = function() return th.nosuch.field end }
	end, "spec.separator.style(): raised: ")
end)

test("separator: what a separator is refused for", function()
	-- A column's own goes through no other check. Every key nobody claimed is
	-- named, sorted, the way every other table a user writes is refused.
	refused({
		{ 42, "spec.separator: must be a string or a table" },
		{ { style = { fg = "cyan" } }, "spec.separator[1]: must be the text to draw", "got nothing" },
		{ { 42, style = { fg = "cyan" } }, "got a number" },
		{ { "|", styel = 1, colour = 2 }, "`colour`, `styel`" },
		{ { "", style = { fg = "cyan" } }, 'spec.separator.style: colours `""`' },
		-- `false` turns off a colour a theme or a definition would supply, and a
		-- separator has neither behind it.
		{ { "|", style = false }, "nothing here to turn off" },
	}, separator)
end)

-- --- layout ----------------------------------------------------------------

test("cell: pads to the column width, on the side the alignment asks for", function()
	eq(laid("ab", { width = 5 }), "   ab")
	eq(laid("ab", { width = 5, align = "left" }), "ab   ")
	eq(cell { render = function() return nil end, width = 3 }, "   ", "a nil render result is an empty cell")
	eq(laid("ab", {}), "ab", "no width means no padding")
end)

test("cell: an overflowing cell gets exactly one ellipsis", function()
	-- `ui.truncate` appends an ellipsis of its own, and a second one leaves the
	-- width right, so the count is asserted rather than left to it.
	local out = laid("octocat:wheel", { width = 12 })
	eq(out, "octocat:whe…")
	eq(select(2, out:gsub("…", "")), 1, "ellipsis count")
end)

test("cell: a wide character at the edge is padded back to width", function()
	-- `ui.truncate` can only return 3 cells here, so `fit` measures again.
	eq(laid("你好，世界", { width = 4 }), " 你…")
	-- And clip drops a wide character that does not fit whole.
	eq(laid("日本語abc", { width = 5, overflow = "clip" }), " 日本")
end)

test("cell: clip, grow and max_width", function()
	eq(laid("abcdefgh", { width = 4, overflow = "clip" }), "abcd")
	eq(laid("abcdefgh", { width = 4, overflow = "grow" }), "abcdefgh")
	eq(laid("abcdefgh", { width = 6, max_width = 4 }), "abc…")
end)

test("cell: a cluster is cut whole, and never over the width", function()
	-- `❤️` is a one-cell character followed by a zero-cell one, and two cells on
	-- screen, so a cut that added them up handed back four cells for a column
	-- of three. A joined emoji and a skin tone are one character to the screen
	-- too, and a flag is a pair of regional indicators, so the pair is the unit.
	local function clip3(s) return laid(s, { width = 3, overflow = "clip" }) end
	eq(clip3("\u{2764}\u{FE0F}abc"), "\u{2764}\u{FE0F}a")
	eq(laid("\u{2764}\u{FE0F}abc", { width = 3 }), "\u{2764}\u{FE0F}…")
	eq(clip3("\u{1F469}\u{200D}\u{1F4BB}abc"), "\u{1F469}\u{200D}\u{1F4BB}a")
	eq(clip3("\u{1F44D}\u{1F3FB}abc"), "\u{1F44D}\u{1F3FB}a")
	eq(clip3("\u{1F1EF}\u{1F1F5}\u{1F1EF}\u{1F1F5}"), " \u{1F1EF}\u{1F1F5}")
end)

test("cell: a renderable comes back padded around, not inside", function()
	eq(cell { render = function() return ui.Line("ab") end, width = 5 }, "   ab")
end)

test("cell: a span or a Line drawn a second time is refused, the way Yazi refuses it", function()
	-- Yazi *moves* a span into the line it is put in, so a render that caches
	-- its spans -- or a finished Line, since `layout.cell` puts whatever comes
	-- back through `ui.Line` -- raises on the second row and the pane stops
	-- drawing.
	local spans = { ui.Span("a"), ui.Span("b") }
	local line = ui.Line { ui.Span("a"), ui.Span("b") }
	for _, render in ipairs { function() return ui.Line(spans) end, function() return line end } do
		local col = prepare { render = render, width = 2 }
		eq(text_of(cases.cell(col)), "ab")
		throws(function() cases.cell(col) end, "already been put in a Line")
	end
end)

test("cell: a renderable is cut to the width a string would be", function()
	-- `Line:truncate` comes back a cell short under a wide character, drops a
	-- character for an empty ellipsis, and hands `❤️abc` back whole for a
	-- column of four. Short is padded; long shifts every column after it.
	for _, mode in ipairs { "ellipsis", "clip" } do
		for _, s in ipairs { "你好，世界", "\u{2764}\u{FE0F}abc" } do
			local out = cell { render = function() return ui.Line(s) end, width = 4, overflow = mode }
			eq(stub.str_width(out), 4, mode .. " " .. s)
		end
	end
	eq(cell { render = function() return ui.Line("abcdefgh") end, width = 4 }, "abc…")
	eq(cell { render = function() return ui.Line("abcdefgh") end, width = 4, overflow = "clip" }, "abcd")
end)

test("cell: a renderable's padding is inside the column's style", function()
	-- The string path pads and then styles, so a background covers the whole
	-- cell. Both alignments, because the pad is built on either side.
	for _, align in ipairs { "left", "right" } do
		local col = prepare {
			render = function(_, ctx) return ui.Line("ab"), ctx.style end,
			width = 5,
			align = align,
			style = { bg = "#112233" },
		}
		local parts = stub.drawn_styles(cases.cell(col))
		eq(#parts, 2, align .. ": the text and the pad")
		for i, style in ipairs(parts) do
			eq(style and style.bg, "#112233", string.format("%s-aligned, part %d", align, i))
		end
	end
end)

-- --- the ratio contract ----------------------------------------------------

--- A column bound to one set of extremes, ready to be asked for ratios.
---@param stats table?
---@param scale string?
---@return table
local function bound(stats, scale)
	local col = prepare { render = function() return "" end, scale = scale }
	cases.bind(col, stats)
	return col.ctx
end

test("ratio: linear normalisation between the extremes, clamped", function()
	local ctx = bound { min = 0, max = 10 }
	eq(ctx.ratio(0), 0)
	eq(ctx.ratio(5), 0.5)
	eq(ctx.ratio(10), 1)
	eq(bound({ min = 10, max = 20 }).ratio(0), 0)
	eq(bound({ min = 10, max = 20 }).ratio(99), 1)
	eq(bound({ min = 7, max = 7 }).ratio(7), 1, "a single-valued listing is all maximum")
end)

test("ratio: nothing to normalise against gives nil", function()
	eq(bound(nil).ratio(5), nil)
	eq(bound({ min = 0, max = 10 }).ratio(nil), nil)
end)

test("ratio: the log scale lifts the small end", function()
	local lin = bound({ min = 1, max = 1000000 }, "linear")
	local log = bound({ min = 1, max = 1000000 }, "log")
	assert(lin.ratio(1000) < 0.01, "linear pins 1000 to the floor")
	assert(log.ratio(1000) > 0.4, "log gives it half the range")
	eq(log.ratio(1000000), 1)
end)

test("ratio: rebinding swaps the extremes", function()
	local col = prepare { render = function() return "" end }
	cases.bind(col, { min = 0, max = 10 })
	eq(col.ctx.ratio(5), 0.5)
	cases.bind(col, { min = 0, max = 100 })
	eq(col.ctx.ratio(5), 0.05)
end)

-- --- the colour ------------------------------------------------------------

local BLUES = "#0b3d91 -> #7fd4ff"

--- A column carrying a colour, ready to be asked for styles. `stats` is there
--- because a ramp is refused on a column with no extremes; one returning nil
--- is a folder with nothing to measure.
---@param opts table
---@return supaline.Ctx
local function coloured(opts)
	opts.render = function() return "" end
	opts.stats = opts.stats or function() return nil end
	return prepare(opts).ctx
end

test("style: a gradient's endpoints sit at the ends of the range", function()
	local ctx = coloured { style = BLUES }
	eq(ctx.style_at(0).fg, "#0b3d91")
	eq(ctx.style_at(1).fg, "#7fd4ff")
	eq(ctx.style_at(0.5).fg, "#4288c9", "64 steps put the halfway ratio on the 33rd")
	-- A row with no value draws the low end rather than the ground, which may
	-- carry no colour at all.
	eq(ctx.style_at(nil).fg, "#0b3d91")
	eq(ctx.style.fg, "#0b3d91")
end)

test("style: a gradient under `bg` reaches the cell as one under `fg` does", function()
	local ctx = coloured { style = { bg = BLUES, fg = "#ffffff" } }
	eq(ctx.style_at(0).bg, "#0b3d91")
	eq(ctx.style_at(1).bg, "#7fd4ff")
	eq(ctx.style_at(1).fg, "#ffffff", "and the flat `fg` is kept on every step")
end)

test("style: a ratio off the end is clamped, NaN included", function()
	-- `style_at` is public and a column may hand it anything, and a nil style
	-- draws a cell with no colour. NaN answers false to every comparison, and
	-- `ratio` produces one for a log column whose extremes reach -1 or below.
	local ctx = coloured { style = BLUES }
	eq(ctx.style_at(-1).fg, "#0b3d91")
	eq(ctx.style_at(2).fg, "#7fd4ff")
	eq(ctx.style_at(0 / 0).fg, "#0b3d91")

	local col = prepare {
		render = function() return "" end,
		stats = function() return { min = -10, max = 100 } end,
		scale = "log",
		style = BLUES,
	}
	cases.bind(col, { min = -10, max = 100 })
	local r = col.ctx.ratio(5)
	assert(r ~= r, "a log scale over a negative minimum is where the NaN comes from")
	eq(col.ctx.style_at(r).fg, "#0b3d91", "and the cell is still coloured")
end)

test("style: `false` turns the style off, whatever the layers beneath say", function()
	register(
		"hue3",
		{ render = function() return "" end, stats = function() return nil end, style = { fg = BLUES, bold = true } }
	)
	eq(prepare("hue3").ctx.style.fg, "#0b3d91", "the definition's gradient, without it")

	local ctx = prepare({ "hue3", style = false }).ctx
	eq(ctx.style_at(1), ctx.style, "no gradient left to index")
	-- `rawget`: reading `.fg` off a style with none hands back the setter.
	eq(rawget(ctx.style, "fg"), nil, "and no colour left either")
	eq(rawget(ctx.style, "bold"), nil, "nor the attribute")
	eq(ctx.fg_written, true, "and a colour is on record as having been written")
end)

test("style: one key can be turned off on its own, and the rest is kept", function()
	register("hue3b", { render = function() return "" end, style = { fg = "red", bg = "blue", bold = true } })
	local ctx = prepare({ "hue3b", style = { fg = false } }).ctx
	eq(rawget(ctx.style, "fg"), nil, "the colour is gone")
	eq(ctx.style.bg, "blue", "and the rest of the definition's is kept")
	eq(ctx.style.bold, true)
	eq(ctx.fg_written, true)
	eq(rawget(prepare({ "hue3b", style = { bold = false } }).ctx.style, "bold"), false, "an attribute off is a removal")
	eq(prepare("hue3b").ctx.fg_written, true, "the definition's colour is a colour written")
end)

test("style: a column with no extremes to place a value between is refused", function()
	-- Without `stats` the ratio is nil for every row, so the gradient could only
	-- draw its low end. The refusal names the writer, since a theme's gradient
	-- reaches a spec that wrote nothing, and offers what that writer can do.
	refused {
		{
			{ render = function() return "" end, style = BLUES },
			"spec.style: `fg` is a gradient, but this column has no `stats`",
			"Give the column a `stats` function, or write a flat colour",
		},
		{
			{ render = function() return "" end, style = { bg = BLUES } },
			"`bg` is a gradient, but this column has no `stats`",
		},
	}
	register("hue2b", { render = function() return "" end })
	stub.th.supaline = { hue2b = BLUES }
	throws(
		function() prepare("hue2b") end,
		"theme [supaline].hue2b: `fg` is a gradient",
		"Write a flat colour there instead"
	)
end)

test("style: a function is called for its style, and called again on the next build", function()
	-- The one way a spec can reach a colour the theme does not have yet: the
	-- flavor lands after `init.lua` has run, so a value captured there is
	-- Yazi's preset. A function is evaluated again.
	local answer = "#112233"
	local spec = { style = function() return answer end }
	eq(coloured(spec).style.fg, "#112233")
	answer = "#445566"
	eq(coloured(spec).style.fg, "#445566", "the next build asks again")

	local ctx = coloured { style = function() return ui.Style():fg("#778899"):bold() end }
	eq(ctx.style.fg, "#778899")
	eq(ctx.style.bold, true)

	-- Nil is how a function says "nothing"; `false` turns the style off.
	eq(coloured({ style = function() return nil end }).fg_written, false)
	local off = coloured { style = function() return false end }
	eq(rawget(off.style, "fg"), nil)
	eq(off.fg_written, true, "`false` is a colour written, not a colour unwritten")
end)

test("style: an inline column is one writer, read once and read as the definition", function()
	-- `{ render = fn, style = ... }` plays both parts, and read as both it ran a
	-- `style` function twice per build and beat the theme.
	local calls, answers = 0, { { bg = "#112233" }, { fg = "#445566" } }
	local ctx = prepare({
		render = function() return "" end,
		name = "inline1",
		style = function()
			calls = calls + 1
			return answers[calls] or answers[#answers]
		end,
	}).ctx
	eq(calls, 1, "once per column per build")
	eq(rawget(ctx.style, "fg"), nil, "and the style is the one answer, not two merged")

	stub.th.supaline = { inline2 = "red", inline3 = "red" }
	eq(
		prepare({ render = function() return "" end, name = "inline2", style = "cyan" }).ctx.style.fg,
		"red",
		"the theme is nearer than a definition"
	)

	-- A use of a column defined elsewhere still writes the spec's layer.
	register("inline3", { render = function() return "" end })
	eq(prepare({ "inline3", style = "cyan" }).ctx.style.fg, "cyan", "the spec is nearer")
	local off = prepare({ "inline3", style = false }).ctx
	eq(rawget(off.style, "fg"), nil, "and a spec's `false` still reaches the layer it turns off")
end)

test("style: each key comes from the nearest of definition, theme and spec", function()
	-- A themed table field is planted as the `ui.Style` Yazi hands a plugin.
	register("hue4", { render = function() return "" end, style = { bg = "#101010", italic = true } })
	stub.th.supaline = { hue4 = ui.Style():fg("#00ccff"):bold(), att2 = ui.Style():bold() }
	local ctx = prepare({ "hue4", style = function() return "#ff8800" end }).ctx
	eq(ctx.style.fg, "#ff8800", "the spec's colour")
	eq(ctx.style.bold, true, "the theme's bold")
	eq(ctx.style.bg, "#101010", "the definition's ground")
	eq(ctx.style.italic, true)
	eq(ctx.fg_written, true, "which is also what tells `permissions` to stop colouring itself")
	eq(prepare("hue4").ctx.fg_written, true, "and with no spec, the theme wrote one")

	-- A theme may say `{ bold = true }` and keep the colour.
	register("att2", { render = function() return "" end })
	local weight = prepare("att2").ctx
	eq(weight.style.bold, true)
	eq(weight.fg_written, false, "nobody wrote a colour, so a column that paints its own goes on doing so")
end)

test("style: an empty string in the theme is nothing written, and only there", function()
	-- A field cleared rather than deleted, in a file someone else's flavor also
	-- writes. Everywhere else `""` is a colour Yazi does not accept, and a spec
	-- that wants no colour has `false`.
	register("blank", { render = function() return "" end, style = { fg = "cyan", bold = true } })
	stub.th.supaline = { blank = "" }
	local ctx = prepare("blank").ctx
	eq(ctx.style.fg, "cyan", "the definition's colour survives it")
	eq(ctx.style.bold, true)
	eq(ctx.fg_written, true)
	throws(function() prepare { "blank", style = "" } end, "is not a colour Yazi accepts")
end)

test("style: a value that fails says which column and which writer", function()
	-- A value from a function is named for the function, because the line
	-- holding the function is the line to change; and every layer is read, so
	-- a definition's that raises is refused whatever the spec wrote over it.
	local r = function() return "" end
	local forty_two = { render = r, style = function() return 42 end } ---@type any
	register("hue5", forty_two)
	throws(function() prepare("hue5") end, 'column("hue5").style(): must be a colour string')
	register("hue5b", { render = r })
	throws(function()
		prepare { "hue5b", style = function() return th.nosuch.field end }
	end, "spec.style(): raised: ")

	register("hue", { render = r, style = "nosuchcolour" })
	throws(function() prepare("hue") end, 'column("hue").style: `nosuchcolour` is not a colour')
	-- Named by its place along the ramp, which a path alone could not say.
	register("hue2", { render = r, stats = function() return nil end, style = "cyan -> #7fd4ff" })
	throws(function() prepare("hue2") end, 'column("hue2").style, stop 1: `cyan` cannot be a gradient endpoint')
	refused {
		{ { "hue5b", style = { fgg = "cyan" } }, "spec.style: `fgg` is not a style key" },
		{ { "hue5b", style = 42 }, "spec.style: must be a colour string" },
	}
end)

-- --- derived widths --------------------------------------------------------

local FILES = {
	stub.file { name = "a", size = 1 },
	stub.file { name = "b", size = 100000 },
	stub.file { name = "c", size = 1000 },
}

test("width: a stated number is used as is, and calls nothing to decide it", function()
	local col = prepare { render = function() return "" end, width = 4 }
	eq(col.ctx.width, 4)
	eq(listing.pass(col.plan), nil)
end)

test("width: a function is handed the folder's statistics", function()
	local col = prepare {
		render = function() return "" end,
		stats = function() return { min = 1, max = 100000 } end,
		width = function(st) return #ya.readable_size(st.max) end,
	}
	eq(cases.width(col, FILES, { min = 1, max = 100000 }), 5)
	eq(listing.pass(col.plan), "width", "a throw from it is reported as the `width` function's")
end)

test('width: "auto" takes the widest rendered cell, capped by max_width', function()
	local sizes = function(file) return ya.readable_size(file:size()) end
	local col = prepare { render = sizes, width = "auto" }
	eq(cases.width(col, FILES, nil), 5, "1B / 97.7K / 1000B")
	eq(listing.pass(col.plan), "render", "measuring calls `render`, and a throw there is reported as its")
	eq(cases.width(prepare { render = sizes, width = "auto", max_width = 3 }, FILES, nil), 3)
	-- Zero rather than refused: a measured width of no cells is the right answer
	-- to a folder with nothing to measure, where a stated 0 is a claim.
	eq(cases.width(prepare { render = sizes, width = "auto" }, {}, nil), 0)
end)

test("width: a width function that returns no usable number is refused", function()
	-- Returned rather than raised: the only caller runs this under `pcall`, and
	-- a refusal raised into that wrapper would come back out looking exactly
	-- like the reader's function throwing. So the width comes back nil with
	-- what was returned beside it, for `report.lua` to word.
	---@param w any
	local function returning(w)
		return prepare { render = function() return "abcdefgh" end, name = "wonky", width = function() return w end }
	end
	-- Held to what a stated `width` is held to, and not floored either.
	for _, case in ipairs { { nil, "a nil" }, { 0, "`0`" }, { -3, "`-3`" }, { 2.5, "`2.5`" } } do
		local got, refused_as = cases.width(returning(case[1]), FILES, nil)
		eq(got, nil, "a width nobody can use came back as a width")
		eq(refused_as, case[2])
	end

	eq(cases.width(returning(6), FILES, nil), 6)
	eq(cases.width(returning(6.0), FILES, nil), 6)
	eq(select(2, cases.width(returning(6), FILES, nil)), nil, "nothing beside a width that was taken")

	-- A column that states no width is nil without being refused.
	local w, refused_as = cases.width(prepare { render = function() return "x" end }, FILES, nil)
	eq(w, nil)
	eq(refused_as, nil)
end)
