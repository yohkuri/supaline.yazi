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

test("normalize: a use site may override the definition's `render`", function()
	-- `render` is a column key like any other, so a use site may write one and
	-- `column.lua` takes the spec's: `opts.render or def.render` rather than
	-- `pick`. Pinned because nothing else says so, and because the shape reads
	-- as a definition -- a definition is the other table that writes a
	-- `render`, and what tells the two apart is the name at `[1]`.
	column.register("over", { width = 6, align = "left", render = function() return "def" end })
	eq(cell { "over", render = function() return "spec" end }, "spec  ")
	eq(
		column.normalize({ "over", render = function() return "spec" end }, CFG).name,
		"over",
		"and the name the theme is looked up under is still the definition's"
	)
end)

test("normalize: an option written on the definition survives, `false` and all", function()
	-- A separator is the only option whose meaningful value is `false`, and the
	-- `opts[k] == nil and def[k] or opts[k]` idiom collapsed it to nil, so a
	-- definition that said `separator = false` still got a separator drawn.
	column.register("tight", { width = 3, separator = false, render = function() return "x" end })
	eq(column.normalize("tight", CFG).sep, false)
	eq(column.normalize({ "tight", separator = "|" }, CFG).sep.text, "|", "the use site still wins")
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

--- A column that declares an option, for the tests that write one at a use
--- site. `extra` goes on the definition, which is where a default lives.
---@param extra table?
local function timed(extra)
	local def = { width = 4, options = { "format" }, render = function() return "ab" end }
	for k, v in pairs(extra or {}) do
		def[k] = v
	end
	column.register("timed", def)
end

test("normalize: a key nobody claimed is refused by name", function()
	-- A misspelled key is drawn nowhere and mentioned nowhere: `pick` asks for
	-- the names it knows and never asks what else is there, and a table
	-- constructor is past what the checker reads against a class. So a column
	-- whose cap was written `max_widht` draws at its natural width, and this
	-- is the only thing that says so.
	column.register("fixed", { width = 4, render = function() return "ab" end })
	throws(function() column.normalize({ "fixed", max_widht = 2 }, CFG) end, "`max_widht` is not a column key")
	-- The message carries what to write instead, because the right spelling is
	-- not guessable from the wrong one.
	throws(function() column.normalize({ "fixed", max_widht = 2 }, CFG) end, "`max_width`")

	-- Every key at once, sorted: `pairs` gives them in whatever order the hash
	-- does, so naming the first found reports the same mistake differently
	-- from one run to the next and costs a second run to find the rest.
	throws(
		function() column.normalize({ "fixed", algin = 1, widht = 2 }, CFG) end,
		"`algin`, `widht` are not column keys"
	)

	-- An inline definition is the same table as its own spec, so it is swept
	-- the same way.
	throws(function()
		column.normalize({ render = function() return "x" end, overflw = "clip" }, CFG)
	end, "`overflw` is not a column key")

	-- A second element is a column written where no second column is read.
	throws(function() column.normalize({ "fixed", "mtime" }, CFG) end, "`2` is not a column key")
end)

test("normalize: every key a column takes passes the sweep", function()
	-- The other half of the refusal above, and the half that catches a key
	-- left out of the allow-list: a spelling that works is refused by nothing
	-- else here, so without this the sweep could quietly turn a real option
	-- into an error and every test above would still pass.
	column.register("wide", { width = 4, render = function() return "ab" end })
	local col = column.normalize({
		"wide",
		align = "left",
		overflow = "clip",
		max_width = 6,
		separator = "|",
		stats = function() return {} end,
		refresh = function() end,
		style = { bold = true },
		width = 5,
		scale = "log",
	}, CFG)
	eq(col.align, "left")
	eq(col.scale, "log")
end)

test("normalize: a column's own options are claimed, and only that column's", function()
	-- A column may read options of its own off `ctx.opts` -- `mtime` takes a
	-- `format` -- so one closed list for every column would refuse the option
	-- on the column that reads it. The definition declares them, which is what
	-- lets a misspelling of one be refused rather than ignored.
	timed()
	eq(column.normalize({ "timed", format = "%c" }, CFG).name, "timed")
	throws(function() column.normalize({ "timed", fromat = "%c" }, CFG) end, "`fromat` is not a column key")
	-- And the message says what that column takes beyond the shared keys.
	throws(function() column.normalize({ "timed", fromat = "%c" }, CFG) end, "also takes `format`")

	-- Declared by one column, so it is not a key on the next.
	column.register("bare", { width = 4, render = function() return "ab" end })
	throws(function() column.normalize({ "bare", format = "%c" }, CFG) end, "`format` is not a column key")
end)

test("normalize: `options` and `name` are the definition's to write", function()
	-- Both are read off the definition alone, so writing one at a use site is
	-- a key nobody reads. `options` is the worse of the two: it looks like it
	-- declares something, and what it declared was refused on the next line
	-- as a key the column does not take.
	column.register("plainer", { width = 4, render = function() return "ab" end })
	throws(function() column.normalize({ "plainer", options = { "pad" } }, CFG) end, "`options` goes on the definition")
	throws(function() column.normalize({ "plainer", name = "other" }, CFG) end, "read by nobody")

	-- The same two keys on the table that *is* the definition are its own.
	-- `normalize` reads `spec.name` in that shape, and nowhere else.
	local col = column.normalize({
		name = "inline",
		options = { "pad" },
		pad = 2,
		render = function() return "ab" end,
	}, CFG)
	eq(col.name, "inline")
	eq(col.ctx.opts.pad, 2)
end)

test("register: an inline definition's `options` is checked too", function()
	-- The check started in `register`, which one of the two writers never
	-- reaches: a spec that writes `render` inline is its own definition, and
	-- its `options` were taken on trust. `options = "format"` was accepted
	-- there and read as nothing, which is the silence the sweep exists to end,
	-- left standing on the key the sweep introduced.
	throws(function()
		local options = "format" ---@type any
		column.normalize({ render = function() return "x" end, options = options }, CFG)
	end, "declares `options` as a string")
	throws(function()
		local options = { "width" } ---@type any
		column.normalize({ render = function() return "x" end, options = options }, CFG)
	end, "which every column takes")
end)

test("register: a name supaline answers for is not a column's to declare", function()
	-- `fetch` is refused by the sweep with the reason it is refused for, and
	-- declaring it as an option is the whole of what it takes to walk past
	-- that: the column would be handed its own `fetch` in `ctx.opts` and the
	-- one place the plugin says why a column cannot own a fetcher would never
	-- be reached.
	throws(function()
		column.register("async", { options = { "fetch" }, render = function() return "x" end })
	end, "`fetch`, which supaline answers for itself")

	-- Read off the same table the hints are: a fourth name worth explaining is
	-- reserved by being explained, rather than by a second list to keep level.
	throws(function()
		local options = { "fetch" } ---@type any
		column.normalize({ render = function() return "x" end, options = options }, CFG)
	end, "which supaline answers for itself")
end)

test("register: `options` is a list, gaps and keys of its own included", function()
	-- `ipairs` stops at the first gap, so every name past one would be declared
	-- here, read by nothing, and refused at the use site as a key the column
	-- does not take -- the silence the sweep exists to end, in the table that
	-- writes it. `#` cannot see the gap either: the length of a table with one
	-- is whichever border Lua happens to find.
	throws(function()
		local options = { [1] = "a", [3] = "b" } ---@type any
		column.register("holed", { options = options, render = function() return "x" end })
	end, "a table with a gap in it")

	-- A name written as a key rather than as an entry is the same mistake
	-- wearing the other spelling, and `pairs` counts it where `ipairs` walks
	-- straight past.
	throws(function()
		local options = { "a", extra = "b" } ---@type any
		column.register("keyed", { options = options, render = function() return "x" end })
	end, "or with keys of its own")

	-- And a list with neither is what a column declares, so the check has to
	-- let it through: a refusal that caught this would refuse every column
	-- that reads an option at all.
	column.register("padded", { options = { "pad", "trim" }, render = function() return "x" end })
	eq(column.normalize({ "padded", pad = 2, trim = true }, CFG).ctx.opts.trim, true)
end)

test("normalize: `ctx.opts` holds the declared options and nothing else", function()
	-- Not the spec table. A column reading `opts.style` off that would get the
	-- one layer its use site wrote rather than the three merged, and
	-- `opts.width` the stated width rather than the effective one `ctx.width`
	-- already carries. Both are a different thing wearing the same name.
	timed()
	local ctx = column.normalize({ "timed", format = "%c", width = 9, style = "cyan" }, CFG).ctx
	eq(ctx.opts.format, "%c")
	eq(ctx.opts.width, nil, "the effective width is `ctx.width`")
	eq(ctx.opts.style, nil, "and the merged style is `ctx.style`")
	eq(ctx.width, 9, "which is the one the spec asked for, capped")

	-- A column that declared none gets a table rather than nil, so a
	-- third-party `ctx.opts.anything` reads as nothing written.
	column.register("bare", { width = 4, render = function() return "ab" end })
	eq(next(column.normalize("bare", CFG).ctx.opts), nil)
end)

test("normalize: a definition may default an option it declares", function()
	-- What narrowing `ctx.opts` buys: handed the spec verbatim, a column would
	-- never see a default its own definition wrote.
	timed { options = { "format", "pad" }, format = "%F", pad = false }
	eq(column.normalize("timed", CFG).ctx.opts.format, "%F", "the definition's, with no spec over it")
	eq(column.normalize({ "timed", format = "%c" }, CFG).ctx.opts.format, "%c", "and the use site still wins")

	-- Read with an explicit nil test, the way `pick` reads the shared keys, so
	-- a declared option whose meaningful value is `false` is not collapsed.
	eq(column.normalize("timed", CFG).ctx.opts.pad, false)
	eq(column.normalize({ "timed", pad = true }, CFG).ctx.opts.pad, true)
end)

test("register: a definition is swept the same way, and `options` is checked", function()
	-- Worse than a spec's, because it is read again for every spec that names
	-- the column.
	throws(function()
		column.register("bad", { render = function() return "x" end, algin = "left" })
	end, "`algin` is not a column key")

	throws(function()
		-- The wrong value is the test. Bound through an `any` rather than
		-- written into the table, because a suppression on a line stylua may
		-- reflow is a suppression that stops covering what it was put there
		-- for -- and this one would then fail the type check, not the suite.
		local options = "format" ---@type any
		column.register("odd", { render = function() return "x" end, options = options })
	end, "declares `options` as a string")
	throws(function()
		column.register("odd", { render = function() return "x" end, options = {} })
	end, "as an empty list")
	throws(function()
		local options = { 42 } ---@type any
		column.register("odd", { render = function() return "x" end, options = options })
	end, "a list holding a number")
	-- Declaring one changes nothing and reads as though the column had taken
	-- it over.
	throws(function()
		column.register("odd", { render = function() return "x" end, options = { "width" } })
	end, "which every column takes")
end)

test("register: `register` names the column, so `name` beside it is not read", function()
	-- Both of these were accepted and then ignored. `register` names the
	-- column; `[1]` is where a *spec* names one. A definition handed to
	-- `register` has neither, so a `name` in it renamed nothing and an entry at
	-- `[1]` drew nothing -- the silence the sweep exists to end, left standing
	-- in the one table that is read again for every spec naming the column.
	throws(function()
		column.register("real", { render = function() return "x" end, name = "alias" })
	end, "read by nobody")
	eq(column._registry["alias"], nil, "and nothing was ever registered under it")

	throws(function()
		local entry = { "alias", render = function() return "x" end } ---@type any
		column.register("regd", entry)
	end, "`1` is not a column key")
	-- And the hint says where `[1]` *is* read, because "not a column key" is
	-- true of it here and false of it on a spec.
	throws(function()
		local entry = { "alias", render = function() return "x" end } ---@type any
		column.register("regd", entry)
	end, "where a spec names the column it uses")
end)

test("normalize: `sep` is refused, and says what took its place", function()
	-- The withdrawn spelling. A column's separator was `sep` where the other
	-- two places that take one call it `separator`, and a key nobody claims is
	-- refused -- so what a reader who writes `sep` today needs is the name it
	-- went to, not that the plugin has never heard of it.
	local wrote_sep = function()
		---@diagnostic disable-next-line: undefined-field
		column.normalize({ "fixed", sep = "|" }, CFG)
	end
	throws(wrote_sep, "`sep` is not a column key")
	throws(wrote_sep, "`separator` is the spelling, on a column as in `setup`")
end)

test("normalize: a `render` at `[1]` is refused, and says where it goes", function()
	-- What is pinned is not the refusal but its message. A render at `[1]` is a
	-- reasonable thing to write, so the refusal has to say where the render goes
	-- instead, and the unknown-key message that would otherwise catch it does
	-- not.
	--
	-- Suppressed on the line, not at the top of the file: `[1]` is declared as a
	-- name, so a render there is refused by the checker as well as by the code
	-- under test, and planting one is what this test is.
	local at_one = function()
		---@diagnostic disable-next-line: assign-type-mismatch
		column.normalize({ function() return "ab" end, width = 6 }, CFG)
	end
	throws(at_one, "goes under `render`, not at `[1]`")
	-- The spelling itself, because the right one is not guessable from the
	-- wrong one.
	throws(at_one, "`{ render = fn, width = 6 }`")

	-- The shape it points at, with the keys only a definition writes read where
	-- they are written.
	local col = column.normalize({
		render = function() return "ab" end,
		name = "written",
		options = { "pad" },
		pad = 2,
	}, CFG)
	eq(col.name, "written", "and the name is the one the theme is looked up under")
	eq(col.ctx.opts.pad, 2)

	-- What it declared is still all it may read.
	throws(function()
		column.normalize({ render = function() return "ab" end, options = { "pad" }, pda = 2 }, CFG)
	end, "`pda` is not a column key")
end)

test("normalize: `[1]` beside an inline `render` is read by nobody", function()
	-- A string at `[1]` names a registered column and a function there is
	-- refused by the branch above, so what reaches this one is neither -- and is
	-- read by nothing once it does.
	throws(function()
		local entry = { [1] = true, render = function() return "x" end } ---@type any
		column.normalize(entry, CFG)
	end, "`1` is not a column key")
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

test("register: a name a theme field cannot hold is refused here", function()
	-- The rule is Yazi's, measured on 26.9.1 against a real one: a custom
	-- section's field name is 1-20 characters of lowercase letters, digits and
	-- `_`, and a name outside that is a TOML parse error that discards the
	-- whole of `theme.toml` and falls back to the preset. So it is refused at
	-- `register`, where the reader still has the name in front of them, rather
	-- than months later by a theme that takes their other colours with it.
	local function reg(name)
		return function()
			column.register(name, { render = function() return "" end })
		end
	end

	for _, name in ipairs { "my-col", "MyCol", "UPPER", "my col", "my.col", ("a"):rep(21) } do
		throws(reg(name), "cannot be a column name")
	end

	-- Yazi's message says "snake-case" and its parser does not mean it: these
	-- three are all taken by a real 26.9.1, so refusing them here would be
	-- supaline inventing a rule the platform does not have. Twenty characters
	-- is the boundary and it is inclusive.
	for _, name in ipairs { "_x", "x_", "2x", "a", ("a"):rep(20) } do
		reg(name)()
		eq(type(column._registry[name]), "table")
		column._registry[name] = nil
	end
end)

test("register: the same name rule reaches a definition that names itself", function()
	-- `register` is not the only way a column gets a name. A definition written
	-- inline names itself, under `name` beside its `render`, and `normalize`
	-- reads that straight off the spec -- so a check on `register` alone left
	-- it carrying the whole of the defect the check was written for. Pinned
	-- because that is exactly the shape the mistake takes: a rule spelled out
	-- once per site, with a site missing.
	--
	-- The name is not decorative here. It reaches `th.supaline[name]` the way a
	-- registered one does, which the theme test below shows, so an unthemeable
	-- name is as unthemeable written this way.
	local r = function() return "" end
	for _, name in ipairs { "my-col", "MyCol", ("a"):rep(21) } do
		throws(function() column.normalize({ render = r, name = name }, CFG) end, "cannot be a column name")
	end

	-- Nil is not a name and is not refused: an inline definition need not name
	-- itself, and one that does not has no theme layer to reach.
	eq(type(column.normalize({ render = r }, CFG)), "table")

	-- What makes the refusal worth having, rather than a rule for its own sake.
	with(
		stub.th,
		"supaline",
		{ my_col = ui.Style():fg("#ff0000") },
		function() eq(column.normalize({ render = r, name = "my_col" }, CFG).ctx.style.fg, "#FF0000") end
	)
end)

test("register: a column may not own asynchronous state", function()
	-- `ya.sync` blocks are matched by position between the two interpreters, so
	-- one registered from init.lua would never be replayed on the async side.
	-- Refused by the key sweep rather than by a branch of its own, which is
	-- what reaches the other way a column is written: an inline definition
	-- never goes through `register`, and would otherwise keep its `fetch` in
	-- silence.
	throws(function()
		column.register("async", { render = function() return "" end, fetch = function() end })
	end, "has to be built into supaline itself")
	throws(function()
		column.normalize({ render = function() return "x" end, fetch = function() end }, CFG)
	end, "has to be built into supaline itself")
end)

-- --- separators ------------------------------------------------------------

column.register("plain", { width = 2, render = function() return "x" end })

--- The record `normalize` puts on a column for the separator written at
--- `value`. Read through a column rather than through `setup` because a
--- column's own is the one of the three places that reached Yazi unread:
--- `separator = 42` emptied the pane, with the cause a whole session behind
--- it.
---@param value any
---@return supaline.Sep
local function separator(value)
	-- Cast because a column's record is `false` where the column drops the
	-- separator before it, and that is the one value nothing below writes:
	-- every call here hands in a separator for `column.separator` to read.
	return column.normalize({ "plain", separator = value }, CFG).sep --[[@as supaline.Sep]]
end

--- Assert that a separator is refused, with a message mentioning `pattern`.
---@param value any
---@param pattern string
local function refuses_sep(value, pattern)
	throws(function() separator(value) end, pattern)
end

test("separator: a string is the text and no style", function()
	eq(separator("|").text, "|")
	eq(separator("|").style, nil, "nobody wrote one, so `render` has no Span to build")
	eq(separator("").text, "", "an empty separator draws nothing and is not a mistake")
end)

test("separator: the table form carries a style", function()
	local one = separator { " | ", style = { fg = "#585b70" } }
	eq(one.text, " | ")
	eq(one.style.fg, "#585b70")
end)

test("separator: the table form with no style says what the bare string says", function()
	-- Allowed rather than refused as a second spelling of the bare string:
	-- every other optional key on every other spec may be left out, and
	-- refusing the omission here would make this the one place that cannot be.
	-- What it must not do is mean something else -- take the style from the
	-- level above -- because two spellings that differ only in what they
	-- inherit is the four-way inheritance this shape was chosen to avoid.
	eq(separator({ " | " }).text, " | ")
	eq(separator({ " | " }).style, nil)
end)

test("separator: a style written as a function is called", function()
	-- Called inside `normalize`, which runs inside `build`, so it follows a
	-- theme reload the way a column's `style` function does. That it is called
	-- again on the next build is `main_spec.lua`'s to say, since only `setup`
	-- has a build to run twice.
	eq(separator({ "|", style = function() return "#ff8800" end }).style.fg, "#ff8800")

	-- And named when it raises, which is the half the `pcall` around it is
	-- there for. The likely failure is the call itself: `th.status.perm_sep`
	-- against a flavor with no `[status]` section raises `attempt to index a
	-- nil value`, and it reaches the user as `build`'s notification -- where a
	-- message carrying no location says nothing about which line to open.
	refuses_sep(
		{ "|", style = function() return th.nosuch.field end },
		"the style function under `separator` of column `plain` raised"
	)
end)

test("separator: what a separator is refused for", function()
	-- Every one of these would be silence without `column.separator`: a
	-- column's own goes through no other check, and the rest are shapes only
	-- the table form can hold.
	refuses_sep(42, "`separator` of column `plain`")
	refuses_sep({ style = { fg = "cyan" } }, "given nothing to draw")
	refuses_sep({ 42, style = { fg = "cyan" } }, "given a number to draw")
	refuses_sep({ "|", styel = { fg = "cyan" } }, "`styel`")
	refuses_sep({ "", style = { fg = "cyan" } }, 'draws "" in a colour')

	-- `style = false` on a column turns off a colour the theme or the
	-- definition would otherwise supply. A separator
	-- has neither behind it, so the value has nothing to mean.
	refuses_sep({ "|", style = false }, "nothing there to turn off")
end)

test("separator: every key nobody claimed, in an order two runs agree on", function()
	-- `pairs` walks a table in whatever order the hash gives, so naming
	-- whichever came up first would hide the second misspelling until the first
	-- was fixed. The same sentence `panes_of` and `colour.layer` are both
	-- written under.
	refuses_sep({ "|", styel = 1, colour = 2 }, "`colour`, `styel`")
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
	-- `ui.truncate` appends an ellipsis of its own, and a second one leaves the
	-- width right, so the count is asserted rather than left to it.
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

test("cell: a renderable's padding is inside the column's style", function()
	-- The string path pads in `fit` and styles what came back, so a background
	-- covers the whole cell. A renderable used to be padded *outside* the style
	-- it had just been given, which left the spare cells bare: invisible under
	-- an `fg`, and a hole in the ground under a `bg`. `test/MANUAL.md` names
	-- that failure for the string path, where it cannot happen.
	--
	-- Both alignments, because the pad is built on either side of the line, and
	-- every part rather than the first: `first_style` would stop at the text
	-- and never reach the cells this is about.
	for _, align in ipairs { "left", "right" } do
		local col = column.normalize({
			render = function(_, ctx) return ui.Line("ab"), ctx.style end,
			width = 5,
			align = align,
			style = { bg = "#112233" },
		}, CFG)

		local parts = stub.drawn_styles(column.cell(col, stub.file {}))
		eq(#parts, 2, align .. ": the text and the pad")
		for i, style in ipairs(parts) do
			eq(style and style.bg, "#112233", string.format("%s-aligned, part %d", align, i))
		end
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

test("style: a gradient's endpoints sit at the ends of the range", function()
	local ctx = coloured { style = BLUES }
	eq(ctx.style_at(0).fg, "#0b3d91")
	eq(ctx.style_at(1).fg, "#7fd4ff")
	-- The bucket arithmetic, not just the ends: 64 steps put the halfway
	-- ratio on the 33rd, and `colour_spec.lua` pins what that colour is.
	eq(ctx.style_at(0.5).fg, "#4288c9")
end)

test("style: a row with no value draws the gradient's low end", function()
	-- Not the ground beneath it: that is where a `bold` lives and it may carry
	-- no colour at all, which would leave an unevaluated directory in `size`
	-- the one uncoloured cell in the column.
	local ctx = coloured { style = BLUES }
	eq(ctx.style_at(nil).fg, "#0b3d91")
	eq(ctx.style.fg, "#0b3d91")
end)

test("style: a ratio off the end is clamped, not left unstyled", function()
	-- `ratio` clamps, but `style` is public and a column may hand it anything.
	-- An index past the end would return nil, and a nil style draws a cell with
	-- no colour -- which reads as a theme that failed to load.
	local ctx = coloured { style = BLUES }
	eq(ctx.style_at(-1).fg, "#0b3d91")
	eq(ctx.style_at(2).fg, "#7fd4ff")
end)

test("style: a NaN ratio is clamped too, where a comparison would let it past", function()
	-- NaN answers false to `< 1` and to `> n` alike, so a clamp written as two
	-- comparisons hands `steps[nan]` back, which is nil -- and `cell` drops a
	-- nil style without a word. Not hypothetical: `ratio` produces one for any
	-- `scale = "log"` column whose extremes reach -1 or below, where `math.log`
	-- of a non-positive number is a NaN in `_lo`.
	local ctx = coloured { style = BLUES }
	eq(ctx.style_at(0 / 0).fg, "#0b3d91")

	local col = column.normalize({
		render = function() return "" end,
		stats = function() return { min = -10, max = 100 } end,
		scale = "log",
		style = BLUES,
	}, CFG)
	column.bind(col, { stats = { min = -10, max = 100 } })
	local r = col.ctx.ratio(5)
	assert(r ~= r, "a log scale over a negative minimum is where the NaN comes from")
	eq(col.ctx.style_at(r).fg, "#0b3d91", "and the cell is still coloured")
end)

test("style: `false` turns the style off, whatever the layers beneath say", function()
	-- The spelling a column's `separator` already uses, and the only way to
	-- drop a style the
	-- definition or the theme would otherwise supply -- every key of it, not
	-- the colour alone.
	column.register("hue3", {
		render = function() return "" end,
		stats = function() return nil end,
		style = { fg = BLUES, bold = true },
	})
	eq(column.normalize("hue3", CFG).ctx.style.fg, "#0b3d91", "the definition's gradient, without it")

	local ctx = column.normalize({ "hue3", style = false }, CFG).ctx
	eq(ctx.style_at(1), ctx.style, "no gradient left to index")
	-- `rawget`, because reading `.fg` off a style that has none hands back the
	-- setter rather than nil -- on a real Yazi as here.
	eq(rawget(ctx.style, "fg"), nil, "and no colour left either")
	eq(rawget(ctx.style, "bold"), nil, "nor the attribute")
	eq(ctx.fg_written, true, "and a colour is on record as having been written")
end)

test("style: one key can be turned off on its own, and the rest is kept", function()
	column.register("hue3b", { render = function() return "" end, style = { fg = "red", bg = "blue", bold = true } })
	local ctx = column.normalize({ "hue3b", style = { fg = false } }, CFG).ctx
	eq(rawget(ctx.style, "fg"), nil, "the colour is gone")
	eq(ctx.style.bg, "blue", "and the rest of the definition's is kept")
	eq(ctx.style.bold, true)
	eq(ctx.fg_written, true)

	eq(
		rawget(column.normalize({ "hue3b", style = { bold = false } }, CFG).ctx.style, "bold"),
		false,
		"an attribute off is a removal"
	)
	eq(
		column.normalize("hue3b", CFG).ctx.fg_written,
		true,
		"and with nothing written over it, the definition's colour is still a colour written"
	)
end)

test("style: the rest of the style is the ground a gradient is drawn on", function()
	local ctx = coloured { style = { fg = BLUES, bold = true, bg = "#1e1e2e" } }
	local style = ctx.style_at(1)
	eq(style.fg, "#7fd4ff", "the gradient decides the colour")
	eq(style.bold, true, "and everything else is kept")
	eq(ctx.style_at(0).bg, "#1e1e2e")
end)

test("style: a gradient may sit under `bg`, and needs extremes as one under `fg` does", function()
	local ctx = coloured { style = { bg = BLUES, fg = "#ffffff" } }
	eq(ctx.style_at(0).bg, "#0b3d91")
	eq(ctx.style_at(1).bg, "#7fd4ff")
	eq(ctx.style_at(1).fg, "#ffffff")
	eq(ctx.fg_written, true)

	throws(function()
		column.normalize({ render = function() return "" end, style = { bg = BLUES } }, CFG)
	end, "`bg` is a gradient, but that column has no `stats`")
end)

test("style: a column with no extremes to place a value between is refused", function()
	-- Without `stats` the ratio is nil for every row, so the gradient could
	-- only ever draw its low end. A gradient that silently is not one has
	-- nothing else to report it, so `normalize` does -- and names the writer,
	-- since a theme's gradient reaches a spec that wrote nothing of its own.
	throws(function()
		column.normalize({ render = function() return "" end, style = BLUES }, CFG)
	end, "the `style` of column `?`: `fg` is a gradient, but that column has no `stats`")
	throws(function()
		column.normalize({ render = function() return "" end, style = BLUES }, CFG)
	end, "Give the column a `stats` function, or write a flat colour")

	column.register("hue2b", { render = function() return "" end })
	with(stub.th, "supaline", { hue2b = BLUES }, function()
		throws(
			function() column.normalize("hue2b", CFG) end,
			"the `[supaline] hue2b` field in your theme: `fg` is a gradient"
		)
		throws(function() column.normalize("hue2b", CFG) end, "Write a flat colour there instead")
	end)
end)

test("style: a table is the theme's spelling, and anything else is refused", function()
	-- The spelling `theme.toml` uses, taken here too, so a style moves between
	-- the two files unchanged. `colour_spec.lua` pins the keys; this is the
	-- spec's own path to them.
	local ctx = coloured { style = { fg = "#ff8800", bold = true } }
	eq(ctx.style.fg, "#ff8800")
	eq(ctx.style.bold, true)

	-- Still an allow-list: what is not a colour, a style table, a `ui.Style`
	-- or `false` survives `setup` and then empties the screen, because
	-- `Span:style` takes a Style or nil and a number reaches Yazi as neither.
	throws(function() coloured { style = 42 } end, "is a number")
end)

test("style: a function is called for its style, and called again on the next build", function()
	-- The one way a spec can reach a colour the theme does not have yet. 26.9.1
	-- merges the flavor after `init.lua` has run, so `style = th.status.perm_read`
	-- captures Yazi's preset and keeps it: the stored spec is re-read on every
	-- `theme` event but never evaluated again. A function is evaluated again.
	local answer = "#112233"
	local spec = { style = function() return answer end }
	eq(coloured(spec).style.fg, "#112233")

	answer = "#445566"
	eq(coloured(spec).style.fg, "#445566", "the next build asks again")

	-- And a `ui.Style` comes back through it, which is what the field this was
	-- written for holds.
	local ctx = coloured { style = function() return ui.Style():fg("#778899"):bold() end }
	eq(ctx.style.fg, "#778899")
	eq(ctx.style.bold, true)

	-- Nil is how a function says "nothing", which is what lets one be written
	-- conditionally; `false` from one turns the style off as writing it does.
	eq(coloured({ style = function() return nil end }).fg_written, false)
	local off = coloured { style = function() return false end }
	eq(rawget(off.style, "fg"), nil)
	eq(off.fg_written, true, "`false` is a colour written, not a colour unwritten")
end)

test("style: an inline column is one writer, read once and read as the definition", function()
	-- `{ render = fn, style = ... }` is one table playing both parts, and the
	-- layers read a definition and a spec separately. Read as both, it wrote
	-- its style into two of the three layers: a `style` function ran twice per
	-- build, against what `layer_of` promises, so one that answered differently
	-- the second time built a style out of two answers that no single call ever
	-- returned -- and the table beat the theme, which is the one layer written
	-- to reach a definition.
	local calls, answers = 0, { { bg = "#112233" }, { fg = "#445566" } }
	local ctx = column.normalize({
		render = function() return "" end,
		name = "inline1",
		style = function()
			calls = calls + 1
			return answers[calls] or answers[#answers]
		end,
	}, CFG).ctx
	eq(calls, 1, "once per column per build, which is what `layer_of` promises")
	eq(rawget(ctx.style, "fg"), nil, "and the style is the one answer, not two merged")

	-- So the theme reaches it, the way it reaches any other definition's style.
	with(stub.th, "supaline", { inline2 = "red" }, function()
		local named = { render = function() return "" end, name = "inline2", style = "cyan" }
		eq(column.normalize(named, CFG).ctx.style.fg, "red", "the theme is nearer than a definition")
	end)

	-- A use of a column defined elsewhere still writes the spec's layer, which
	-- is the half that has to go on beating the theme.
	column.register("inline3", { render = function() return "" end })
	with(stub.th, "supaline", { inline3 = "red" }, function()
		eq(column.normalize({ "inline3", style = "cyan" }, CFG).ctx.style.fg, "cyan", "the spec is nearer")
		local off = column.normalize({ "inline3", style = false }, CFG).ctx
		eq(rawget(off.style, "fg"), nil, "and a spec's `false` still reaches the layer it turns off")
		eq(off.fg_written, true)
	end)
end)

test("style: `ui.Style` with the call forgotten is refused, not called", function()
	-- Measured on 26.9.1: `type(ui.Style)` is `table` and only `ui.Style()` is
	-- userdata. A table is a style, so the bare name would be read as one --
	-- `pairs` finds nothing on it, so it would come back a layer saying
	-- nothing, green and uncoloured. `colour.lua` tells the two apart by the
	-- `__call` a constructor carries, and the stub's `ui.Style` has one for the
	-- same reason Yazi's does.
	eq(type(ui.Style), "table")
	throws(function() coloured { style = ui.Style } end, "is the constructor")
end)

test("style: the spec is the nearest layer, key by key", function()
	-- Each key goes to the nearest of the three that wrote it, so a spec that
	-- writes a colour keeps the theme's attribute and the definition's ground.
	-- A themed table field is planted as the `ui.Style` Yazi hands a plugin.
	column.register("hue4", { render = function() return "" end, style = { bg = "#101010", italic = true } })
	with(stub.th, "supaline", { hue4 = ui.Style():fg("#00ccff"):bold() }, function()
		local ctx = column.normalize({ "hue4", style = function() return "#ff8800" end }, CFG).ctx
		eq(ctx.style.fg, "#ff8800", "the spec's colour")
		eq(ctx.style.bold, true, "the theme's bold")
		eq(ctx.style.bg, "#101010", "the definition's ground")
		eq(ctx.style.italic, true)
		eq(ctx.fg_written, true, "which is also what tells `permissions` to stop colouring itself")

		eq(column.normalize("hue4", CFG).ctx.fg_written, true, "and with no spec, the theme wrote one")
	end)
end)

test("style: a theme's gradient keeps its colour under a spec's attribute", function()
	-- The case the three layers exist for: the colour comes from the theme and
	-- the weight from the spec, on one cell, so a flavor's gradient can be
	-- given a bold without copying its endpoints into `init.lua`.
	column.register("att1", { render = function() return "" end, stats = function() return { min = 1, max = 9 } end })
	with(stub.th, "supaline", { att1 = BLUES }, function()
		local ctx = column.normalize({ "att1", style = { bold = true, bg = "#1e1e2e" } }, CFG).ctx
		eq(ctx.fg_written, true, "and the colour that was written is the theme's, which is the whole point")
		eq(ctx.style_at(0).fg, "#0b3d91")
		eq(ctx.style_at(1).fg, "#7fd4ff")
		eq(ctx.style_at(0).bold, true)
		eq(ctx.style_at(1).bg, "#1e1e2e")
	end)
end)

test("style: a theme's attribute reaches a column with no colour claimed", function()
	-- The other half of the same case: a theme may say `{ bold = true }` and
	-- keep the colour, in the one file a flavor author writes.
	column.register("att2", { render = function() return "" end })
	with(stub.th, "supaline", { att2 = ui.Style():bold() }, function()
		local ctx = column.normalize("att2", CFG).ctx
		eq(ctx.style.bold, true)
		eq(rawget(ctx.style, "fg"), nil)
		eq(ctx.fg_written, false, "nobody wrote a colour, so a column that paints its own goes on doing so")
	end)
end)

test("style: an empty string in the theme is nothing written", function()
	-- A field cleared rather than deleted, which is how a value goes away in a
	-- file someone else's flavor also writes. Read as nothing written, so the
	-- definition beneath it stands.
	column.register("blank", { render = function() return "" end, style = { fg = "cyan", bold = true } })
	with(stub.th, "supaline", { blank = "" }, function()
		local ctx = column.normalize("blank", CFG).ctx
		eq(ctx.style.fg, "cyan", "the definition's colour survives it")
		eq(ctx.style.bold, true)
		eq(ctx.fg_written, true, "written by the definition, since the theme wrote nothing")
	end)

	-- The theme's alone, and deliberately: everywhere else `""` is a colour
	-- Yazi does not accept, and a spec that wants no colour has `false` and
	-- has leaving the key out. Pinned on both sides, because an allowance that
	-- spreads to the other layers is one nobody would notice spreading.
	throws(function() column.normalize({ "blank", style = "" }, CFG) end, "is not a colour Yazi accepts")
end)

test("style: a nearer `true` wins over a farther `false`, and the other way round", function()
	-- A theme that says `bold = false` is a theme stripping a bold off whatever
	-- is beneath; a spec that then asks for one is the nearer writer, and wins,
	-- the way a spec's colour wins over a theme's everywhere else.
	column.register("att3", { render = function() return "" end, style = { bold = true } })
	-- Suppressed on the line: `types.yazi` declares `bold` without the removal
	-- flag 26.9.1's takes, and the flag is what this line plants.
	---@diagnostic disable-next-line: redundant-parameter
	with(stub.th, "supaline", { att3 = ui.Style():bold(true) }, function()
		eq(rawget(column.normalize("att3", CFG).ctx.style, "bold"), false, "the theme strips the definition's")
		eq(column.normalize({ "att3", style = { bold = true } }, CFG).ctx.style.bold, true, "and the spec puts it back")
	end)
end)

test("style: a function that fails is reported in terms of the file it was written in", function()
	-- Two ways to fail and one mechanism for both. A value `colour.layer` would
	-- refuse is named for the function rather than for `style`, because the
	-- line holding the function is not the line to change -- and a definition
	-- may carry one, where the reader has no `style` of their own to look at.
	-- Suppressed on the line: the class refuses this at check time, and the
	-- refusal under test is the runtime one.
	---@diagnostic disable-next-line: return-type-mismatch
	column.register("hue5", { render = function() return "" end, style = function() return 42 end })
	throws(function() column.normalize("hue5", CFG) end, "what the default `style` function of column `hue5` returned")

	-- The call raising is the likelier half: a flavor with no such section, a
	-- field that moved. Lua's own message for it carries no column at all. On
	-- a column of its own, because every layer is read: a definition's
	-- function that fails is refused whatever the spec wrote over it.
	column.register("hue5b", { render = function() return "" end })
	throws(function()
		column.normalize({ "hue5b", style = function() return th.nosuch.field end }, CFG)
	end, "the `style` function of column `hue5b` raised")
end)

test("style: a value Yazi would refuse says which column it was", function()
	column.register("hue", { render = function() return "" end, style = "nosuchcolour" })
	throws(function() column.normalize("hue", CFG) end, "the default `style` of column `hue`")

	column.register("hue2", {
		render = function() return "" end,
		stats = function() return nil end,
		style = "cyan -> #7fd4ff",
	})
	throws(function() column.normalize("hue2", CFG) end, "column `hue2`")

	column.register("att5", { render = function() return "" end })
	throws(
		function() column.normalize({ "att5", style = { fgg = "cyan" } }, CFG) end,
		"the `style` of column `att5`: `fgg` is not a style key"
	)
	-- Suppressed on the line rather than at the top of the file: the class
	-- refuses this at check time, and the refusal under test is the runtime one
	-- -- the only one a user's `init.lua` ever meets, since no check reads it.
	---@diagnostic disable-next-line: assign-type-mismatch
	throws(function() column.normalize({ "att5", style = 42 }, CFG) end, "the `style` of column `att5` is a number")
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
