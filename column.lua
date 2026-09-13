--- @since 26.9.1
--- Column registry, spec normalisation, and cell layout.
---
--- A column is written in one of four shapes, all of which collapse to the same
--- runtime object, so a built-in column and a user-written one are
--- indistinguishable to the renderer:
---
---   "size"                                  a registered column, by name
---   { "size", width = 9 }                   ... with its options overridden
---   function(file, ctx) return "..." end    render-only shorthand
---   { render = fn, stats = fn, width = 6 }  an inline definition
---
--- `render(file, ctx)` runs for every visible row on every frame and must stay
--- O(1). Anything that needs to look at the whole folder belongs in
--- `stats(files)`, which main.lua computes once per folder and caches.
---
--- `render` may return a single `AsLine`, or a value and a style. Returning
--- `text, style` skips building an intermediate Line, which is what the
--- built-in columns do; a style handed back with a Line is applied to it.

local colour = require(".colour")

--- What a `render` is handed, in terms a type checker can act on.
---
--- `types.yazi` describes `fs__File`, but not three of the fields this plugin
--- reads off one, and it describes `cha.perm` wrongly. Without the classes
--- below every column is checked against `table`, which is to say not at all:
--- `file.cha.is_dirr` costs nothing until it draws.
---
--- Measured on 26.9.1 (Homebrew 2026-09-01), with a probe linemode logging the
--- file it was handed:
---
---     file.idx         number, 1
---     file.in_current  boolean, true
---     cha.perm         function; `cha:perm()` returned "drwxr-xr-x"
---     url.spec         userdata; `spec.is_virtual` false for a local file
---
--- A newer Yazi is a reason to run that probe again and correct these, not to
--- work around them from the call site.

--- `perm` is a method here and a `string?` upstream. `test/stub.lua` has
--- modelled it as a method since it was written, from a measurement of its
--- own, and the plugin has always called it as one; the annotation is the
--- thing that is out of step.
---@class supaline.Cha : Cha
---@field perm fun(self: self): string?

--- The exposed complement of Yazi's internal `AuthKind::is_local()`. Upstream
--- declares `Url.is_regular` -- the spelling CI refuses -- and not this one, so
--- narrowing `file` without it would leave the type checker blessing the wrong
--- field and rejecting the right one.
---@class supaline.UrlSpec
---@field is_virtual boolean

---@class supaline.Url : Url
---@field spec supaline.UrlSpec

---@class supaline.File : fs__File
---@field idx integer the row's 1-based position in its own folder
---@field in_current boolean whether the row's folder is the tab's current one
---@field cha supaline.Cha
---@field url supaline.Url

--- Yazi's folder, with its listing narrowed. `tab__Folder.files` is an
--- `fs__Files` of `fs__File`, which is the class without the two fields above,
--- so the plugin would lose them the moment it took a row out of a folder
--- rather than being handed one.
---
--- A list rather than `fs__Files`: `#files` and `files[i]` are the only two
--- things done with one, both hold for Yazi's userdata and for the plain table
--- the harness builds, and one type covering both is what lets a spec exercise
--- the same code path.
---@class supaline.Folder : tab__Folder
---@field files supaline.File[]

--- A Line, with the method `cut` below calls on one. `types.yazi` declares
--- `ui.truncate` and nothing for `Line:truncate`, which 26.9.1 has and
--- `test/truncate_spec.lua` pins the behaviour of, so the checker refuses the
--- call on a value it has typed. Taking the line as `unknown` gets past that
--- and costs the rest: nothing else called on the same value is checked
--- either.
---
--- The cast is at the call to `cut` rather than on the `ui.Line` it is handed:
--- `Line:style` is declared returning `self`, which resolves to `ui.Line`, so
--- a line cast where it is made loses the class again at the first `:style`.
---
--- The two options are the ones this plugin passes and `truncate_spec.lua`
--- pins, not a claim about everything 26.9.1 accepts -- `ui.truncate` also
--- takes `rtl`, and whether the method does was never measured. Nothing rests
--- on it either way: a constructor's keys are not checked against this shape.
---@class supaline.Line : ui.Line
---@field truncate fun(self: self, opts: { max: integer, ellipsis: string? }): supaline.Line

--- One per column, reused across rows: what `render` reads a folder's measured
--- state out of. `bind` also keeps the folder's extremes on this table, under
--- names starting `_`; they are declared on `supaline.Scaled` below rather
--- than here, because a column that reaches for them is reaching past `ratio`.
---@class supaline.Ctx
---@field base unknown what to draw a row with no value in: the ramp's low end, or the flat colour
---@field source "spec"|"theme"|"definition" which of the three said what `base` is
---@field opts table the options the column was specified with
---@field stats any whatever this column's `stats` returned for the folder
---@field width integer? the effective width, `max_width` already applied
---@field ratio fun(value: number?): number? where a value sits, 0 to 1
---@field style fun(ratio: number?): unknown a ui.Style for that position

--- The same table, as `bind` and `ratio` see it: the extremes `ratio`
--- normalises against, and whether the scale is logarithmic. `bind` is the
--- only writer and `ratio` the only reader.
---
--- Not `supaline.Ramp`, which is what this was called before a column could
--- carry a `ramp` of its own: these are the ends of the *range*, and nothing
--- here knows a colour.
---@class supaline.Scaled : supaline.Ctx
---@field _lo number?
---@field _hi number?
---@field _log boolean

---@alias supaline.Render fun(file: supaline.File, ctx: supaline.Ctx): any, any?

--- Plugin-wide options, once `setup` has filled them in from `DEFAULTS`.
--- Separate from `supaline.Opts` in main.lua, which is what the user actually
--- wrote. `separator` and `order` are always present, so nothing that reads
--- one has a nil to think about; `scale` is the exception and has to be,
--- because a column definition can state one too and nil is what tells "the
--- user asked for this scale" from "nobody said".
---@class supaline.Cfg
---@field separator string
---@field order integer
---@field scale? "linear"|"log" what the user wrote in `setup`, if anything
--- `band` is optional for the same shape of reason `scale` is, though not the
--- same reason: `DEFAULTS` carries none, because the pair it would carry is
--- `colour.lua`'s to justify. Nil here means the default, and `colour.stops`
--- is where that is applied.
---@field band? supaline.Band the lightnesses a band runs between

--- Every option a column accepts. One set rather than two, because
--- `normalize` reads the spec and the definition behind it through a single
--- `pick` and neither side has a key the other cannot take.
---
--- This is a column's user-facing surface, and writing it down is what makes a
--- misspelling in the plugin's own handling of it cost something. It does not
--- reach the user's `init.lua` -- no check here ever sees that file -- so what
--- a user writes wrong is still `setup`'s to refuse at runtime, not a class's.
---@class supaline.ColumnOpts
---@field name string?
---@field render supaline.Render?
---@field stats fun(files: supaline.File[]): table?|nil
---@field refresh function? run whenever a linemode is installed, and on `cd`
---@field base unknown? a colour string, a ui.Style, or a function returning one
---@field ramp string|string[]|false|nil `#rrggbb` endpoints, `"#a -> #b"`, or `false` for none
---@field align "left"|"right"|nil
---@field overflow "ellipsis"|"clip"|"grow"|nil
---@field max_width integer?
---@field sep string|false|nil a separator of this column's own, `false` for none
---@field width number|"auto"|(fun(stats: any): number?)|nil a number is floored
---@field scale "linear"|"log"|nil

--- A registered column, as `register` stores it: the options above, with the
--- one field a column cannot do without.
---
--- `fetch` is declared so that the refusal in `register` reads a field that
--- exists. It is not an option -- a column that defines one is turned away,
--- because a `ya.sync` block written outside this file binds to a different
--- state table and then fails silently.
---@class supaline.ColumnDef : supaline.ColumnOpts
---@field render supaline.Render
---@field fetch unknown?

--- A spec entry written as a table: the second of the four shapes, the fourth,
--- and the third when it carries options beside the function. `[1]` is the
--- registered name or the inline `render`; everything else is that column's
--- options.
---
--- `[1]` constrains the value and not the index: `{ 42, width = 3 }` in a spec
--- is refused, `spec[2]` is not. Reading an index a class does not declare
--- costs nothing, here as anywhere.
---@class supaline.ColumnEntry : supaline.ColumnOpts
---@field [1] string|supaline.Render|nil

--- One entry of a linemode spec, in whichever of the four shapes it was
--- written. `normalize` is where they collapse, and it decides between them by
--- `type`, which is what lets this union narrow at each branch.
---@alias supaline.ColumnSpec string|supaline.Render|supaline.ColumnEntry

--- A normalised column: what the four spec shapes above all collapse to, and
--- the only shape the renderer ever sees.
---@class supaline.Column
---@field name string? nil for an inline definition, which has no name to give
---@field align "left"|"right"
---@field overflow "ellipsis"|"clip"|"grow"
---@field max_width integer?
---@field sep string|false|nil a separator of this column's own, `false` for none
---@field stats fun(files: supaline.File[]): table?|nil
---@field refresh function? run whenever a linemode is installed, and on `cd`
---@field render supaline.Render
---@field scale "linear"|"log"
---@field auto boolean? `width = "auto"`: measure the folder
---@field width_of fun(stats: any): number?|nil
---@field fixed integer? a stated width, `max_width` already applied
---@field needs_pass boolean whether this column costs a pass over the folder
---@field ctx supaline.Ctx

--- What one pass over one folder produced for one column. main.lua caches
--- these per folder and binds them; a column that needs no pass gets an empty
--- one.
---@class supaline.Entry
---@field stats any?
---@field width integer?

--- The module table. `require(".column")` resolves to this file, so a call into
--- it is read against the signatures below and `column.normalize(42, {})` is
--- refused. A name is not a signature, though: until this class existed
--- `column.normalizze({}, {})` cost nothing on the line above that refusal,
--- because a misspelled field bites only on a value carrying a declared class.
---
--- Declared on the table rather than written out the way `supaline.Main` is.
--- That one lists `main.lua`'s exports by hand, because in this checkout and
--- on the CI runner `require(".main")` reaches `types.yazi` instead of this
--- tree, and `module_spec.lua` has to pin it against the module it describes.
--- Which of the two wins is a property of the absolute path the tree sits at,
--- measured in `annotate-supaline/references/main-collision.md`. Here the
--- fields are whatever is assigned below, so no spec has to claim it and there
--- is nothing to keep in step.
---@class supaline.ColumnModule
local M = { _registry = {} }

--- Register a reusable column under `name`, so a linemode can refer to it as
--- `"name"` or `{ "name", ... }`.
---@param name string
---@param def supaline.ColumnDef
function M.register(name, def)
	if type(name) ~= "string" or name == "" then
		error("supaline: a column needs a non-empty name")
	elseif type(def) ~= "table" or type(def.render) ~= "function" then
		error(string.format("supaline: column `%s` needs a `render` function", name))
	elseif def.fetch then
		-- `ya.sync` blocks are matched between the sync and async VMs by the
		-- position of the call, and a block registered from the user's
		-- `init.lua` is never replayed on the async side. A third-party column
		-- therefore cannot own asynchronous state; say so rather than letting it
		-- fail silently at render time.
		error(
			string.format(
				"supaline: column `%s` cannot define `fetch`; a column that needs "
					.. "asynchronous state has to be built into supaline itself",
				name
			)
		)
	end
	M._registry[name] = def
end

---@param name string
---@return supaline.ColumnDef?
function M.get(name) return M._registry[name] end

--- A `stats` function over the extremes of the current listing, which is what
--- a `ramp` is stretched between and what `ctx.ratio` normalises against.
---
--- Here rather than in `builtin.lua` because it is not the built-ins' alone:
--- every ranged column wants exactly this loop, and a user-written one had no
--- way to reach it -- `builtin.lua` is not a module anything can require, so
--- the only option was to write it again. It was written again, in the test
--- fixture's own `init.lua`, and the copy drifted.
---
--- Values that do not exist stay out of the range, and so do values at or below
--- zero: a directory whose size Yazi has not evaluated must not drag the
--- minimum down, and neither must a file with no timestamp. Rounding is the
--- caller's -- `get` is where a timestamp is floored, because `render` has to
--- floor it the same way for the two to agree on a step.
---@param get fun(file: supaline.File): number?
---@return fun(files: supaline.File[]): table?
function M.extremes(get)
	return function(files)
		local min, max
		for i = 1, #files do
			local v = get(files[i])
			if v and v > 0 then
				if not min or v < min then
					min = v
				end
				if not max or v > max then
					max = v
				end
			end
		end
		return min and { min = min, max = max } or nil
	end
end

--- Resolve a column's colour: the spec first, then the `[supaline]` theme
--- section, then the definition's own default.
---
--- One source decides both halves. A spec that says anything about colour --
--- `base`, `ramp`, or both -- replaces the theme outright rather than half of
--- it, which is what "a `base` written in the spec wins over the theme" has
--- always meant and is the only rule that stays sayable in one sentence now
--- that there are two fields.
---
--- Within one source the two combine: `base` is the ground the ramp is patched
--- onto, so a theme's `bold` survives a gradient it knows nothing about.
---
--- `false` is how a spec says "neither" -- the spelling `sep` already uses, and
--- the only way to drop a colour the definition or the theme would otherwise
--- supply. It still counts as the spec saying something, so it takes the
--- source with it.
---
--- The theme section holds a string or a style table and nothing else -- an
--- array is refused by Yazi, taking the whole file with it -- so a themed ramp
--- arrives as a string, and `is_ramp` is what tells the two apart.
---
--- This runs inside `build()` rather than once at setup, and `build` is what
--- the `theme` event calls. Both halves of the timing need that. 26.9.1 has
--- `theme.toml` merged before any plugin code runs but **not the flavor**, so
--- a field the flavor supplies still holds Yazi's preset while `init.lua` is
--- running; and `app:theme` re-reads both mid-run, so a colour resolved once
--- is the old one from then on.
---@param name string?
---@param opts supaline.ColumnOpts
---@param def supaline.ColumnOpts
---@return unknown? base, unknown? ramp, "spec"|"theme"|"definition" source
local function colours_of(name, opts, def)
	if opts.base ~= nil or opts.ramp ~= nil then
		return opts.base or nil, opts.ramp or nil, "spec"
	end

	local section = name and th.supaline
	local themed = section and section[name]
	if themed ~= nil and themed ~= "" then
		if colour.is_ramp(themed) then
			return nil, themed, "theme"
		end
		return themed, nil, "theme"
	end
	return def.base or nil, def.ramp or nil, "definition"
end

--- What to call a column's colour in an error, in terms of the file it was
--- written in. A theme has no `base` field and no `ramp` field to name, so a
--- message that spoke of either would be describing a spec the reader never
--- wrote -- and "the colour of column `size`" says nothing about which of the
--- two files to open.
local WHERE = {
	spec = "the colour of column `%s`",
	theme = "the `[supaline] %s` colour in your theme",
	definition = "the default colour of column `%s`",
}

--- What to do about a ramp on a column with no extremes, likewise. `stats` is
--- a spec's to give and `base` a spec's to write, so a spec and a definition
--- get the same advice; a `theme.toml` has neither, and the only move left
--- there is a flat colour.
local NO_STATS = "Give the column a `stats` function, or write that colour as `base`"
local NO_STATS_THEMED = "Write a flat colour there instead"

--- What to call a `base` that was written as a function -- the job `WHERE`
--- does for a colour, in terms of the file the function was written in, since
--- a message naming `base` would send the reader to a line that is not the one
--- to change. A table of its own because there is no theme row to write: a
--- theme field holds a string or a style table and never a function.
local FN_WHERE = {
	spec = "the `base` function of column `%s`",
	definition = "the default `base` function of column `%s`",
}

--- Apply a column's `max_width`, if it has one. Every width a column can end
--- up with passes through here exactly once -- the stated one when the spec is
--- normalised, the derived ones when the folder is measured -- so `cell` never
--- has to cap anything per row.
---@param width integer?
---@param max integer?
---@return integer?
local function cap(width, max)
	if width and max and width > max then
		return max
	end
	return width
end

--- Turn one entry of a linemode spec into a runtime column.
---@param spec supaline.ColumnSpec
---@param cfg supaline.Cfg
---@return supaline.Column
function M.normalize(spec, cfg)
	local name, opts, def

	if type(spec) == "function" then
		name, opts, def = nil, {}, { render = spec }
	elseif type(spec) == "string" then
		name, opts = spec, {}
		def = M._registry[spec] or error(string.format("supaline: unknown column `%s`", spec))
	elseif type(spec) ~= "table" then
		error("supaline: a column must be a name, a function, or a table with `render`")
	elseif type(spec[1]) == "string" then
		-- Cast because reading `spec[1]` does not narrow `spec[1]`: the branch
		-- has just established the string, and `[1]` is declared as the union
		-- of both things a spec entry can put there.
		--
		-- One assignment per line, and not `name, opts = spec[1] --[[@as
		-- string]], spec`: stylua reflows that onto three lines and leaves the
		-- cast sitting after the comma, where it applies to nothing and the
		-- warning comes back. It fails loudly, so this is a note rather than a
		-- trap -- but the fix is to keep the lines apart, not to disable it.
		name = spec[1] --[[@as string]]
		opts = spec
		def = M._registry[name] or error(string.format("supaline: unknown column `%s`", name))
	elseif type(spec[1]) == "function" then
		local fn = spec[1] --[[@as supaline.Render]]
		name, opts, def = nil, spec, { render = fn }
	elseif type(spec.render) == "function" then
		name, opts, def = spec.name, spec, spec --[[@as supaline.ColumnDef]]
	else
		error("supaline: a column must be a name, a function, or a table with `render`")
	end

	-- An explicit nil test, not `opts[key] == nil and def[key] or opts[key]`:
	-- that idiom collapses a `def` value of `false` to nil, and `false` is the
	-- only value `sep` ever takes.
	--
	-- The return is annotated because it cannot be inferred. The key is a
	-- variable, so a language server unions every field either table can
	-- carry, the `render` function included, and then objects when a width
	-- from here reaches `cap`.
	---@return any
	local pick = function(key)
		local v = opts[key]
		if v == nil then
			v = def[key]
		end
		return v
	end

	local col = {
		name = name,
		align = pick("align") or "right",
		overflow = pick("overflow") or "ellipsis",
		max_width = pick("max_width"),
		sep = pick("sep"),
		stats = pick("stats"),
		refresh = pick("refresh"),
		render = opts.render or def.render,
		-- Not `pick`, which is the one place that would be wrong. `pick` reads
		-- the spec and then the definition, and a definition's scale has to
		-- lose to a `scale` written in `setup` -- otherwise the plugin-wide
		-- option cannot reach `size`, the one built-in that states one and the
		-- one whose values span orders of magnitude. So: the spec, then what
		-- the user asked for plugin-wide, then the column's own, then linear.
		--
		-- Linear is the fallback because the columns with nothing to say about
		-- it are the timestamps, whose values sit within a few years of each
		-- other; a log scale over those spreads nothing.
		scale = opts.scale or cfg.scale or def.scale or "linear",
	}

	local width = pick("width")
	if width == "auto" then
		col.auto = true
	elseif type(width) == "function" then
		col.width_of = width
	elseif type(width) == "number" then
		col.fixed = cap(math.floor(width), col.max_width)
	elseif width ~= nil then
		error(string.format('supaline: `width` of column `%s` must be a number, "auto", or a function', name or "?"))
	end

	-- A column that declares `stats` gets the folder pass, full stop. Gating it
	-- on whoever happens to consume the result -- a gradient ramp, a derived
	-- width -- leaves a column whose `render` reads `ctx.stats` directly with
	-- nothing to read, and says nothing about it.
	col.needs_pass = col.stats ~= nil or col.auto or col.width_of ~= nil

	local base, wanted, source = colours_of(name, opts, def)
	local where = string.format(WHERE[source], name or "?")

	-- A `base` written as a function is called here, and here is the whole of
	-- what it buys: `colours_of` above says why this runs inside `build` rather
	-- than once at setup, and a spec is re-read on every one of those passes
	-- but never evaluated again. A function is, so it sees the flavor that was
	-- not there while `init.lua` ran and follows every reload after it.
	--
	-- Once per column per build, never per row. `ramp` deliberately takes none:
	-- its endpoints need the `#rrggbb` channels `colour.lua`'s header measures
	-- a style cannot be read back as, so the one thing a function there could
	-- reach for is the one thing it could not use.
	local base_where = where
	if type(base) == "function" then
		local fn = string.format(FN_WHERE[source] or WHERE[source], name or "?")
		-- Two ways for this to go wrong and one mechanism for both. The likely
		-- one is the call itself: `th.status.perm_read` against a flavor with
		-- no `[status]` section raises `attempt to index a nil value`, and that
		-- reaches the user as `build`'s notification, where a message carrying
		-- no column name says nothing about which line to open.
		local ok, got = pcall(base)
		if not ok then
			error(string.format("supaline: %s raised: %s", fn, tostring(got)))
		end
		-- `or nil` for the reason `colours_of` writes it: `false` is how a spec
		-- says "no colour at all", and a function that hands one back is saying
		-- that rather than handing back a value Yazi would refuse.
		base, base_where = got or nil, "what " .. fn .. " returned"
	end
	local ground = colour.style(base, base_where)

	-- A ramp needs extremes to place a value between, and only a column that
	-- declares `stats` ever gets any: without one `ctx.ratio` is nil for every
	-- row and the ramp can only ever draw its low end. Refused here rather than
	-- drawn flat, because a gradient that silently is not one is exactly the
	-- kind of failure this plugin has no other way to report.
	if wanted ~= nil and col.stats == nil then
		error(
			string.format(
				"supaline: %s is a gradient, but that column has no `stats`, so there are no "
					.. "extremes to place a value between and the ramp could only ever draw its "
					.. "low end. %s",
				where,
				source == "theme" and NO_STATS_THEMED or NO_STATS
			)
		)
	end
	local ramp = wanted ~= nil and colour.styles(wanted, ground, where, cfg.band) or nil

	-- One context table per column, reused across rows. main.lua rebinds
	-- `stats` and `width` whenever the folder being drawn changes, not per row.
	--
	-- A row with no value to place draws the ramp's low end rather than the
	-- ground beneath it. The ground is where a themed `bold` or `bg` lives and
	-- may carry no colour of its own at all, so falling back to it would leave
	-- a directory in `size` uncoloured beside files that are not -- or worse,
	-- in the column definition's own default, which the user has just replaced.
	--
	-- `source` rather than a flag, because a render that wants to know is
	-- asking which file to leave alone: `permissions` draws itself out of the
	-- theme's own `[status]` styles and has to stop the moment a colour was
	-- written for it, wherever it was written.
	local ctx = { base = ramp and ramp[1] or ground, source = source, opts = opts, stats = nil, width = col.fixed }
	col.ctx = ctx

	--- Where `value` sits between the extremes of the current listing, 0 to 1.
	--- Returns nil when there is nothing to normalise against, which makes
	--- `ctx.style` fall back to the flat base colour.
	function ctx.ratio(value)
		local lo, hi = ctx._lo, ctx._hi
		if not value or not lo then
			return nil
		elseif hi == lo then
			return 1
		end

		local v = ctx._log and math.log(value + 1) or value
		local r = (v - lo) / (hi - lo)
		return r < 0 and 0 or r > 1 and 1 or r
	end

	--- The style for a position on the column's ramp, or the flat base when
	--- there is no ramp and when there is nothing to place.
	---
	--- Two closures rather than one branch inside one, because this runs for
	--- every visible row on every frame and most columns have no ramp at all.
	--- The ramp itself is already a list of finished styles, so a row that does
	--- have one costs an arithmetic and an array index.
	if ramp then
		local n = #ramp
		local last = n - 1
		function ctx.style(r)
			if r == nil then
				return ctx.base
			end
			-- `ratio` clamps, but `style` is public and a column may hand it
			-- anything; an index off the end would return nil and draw the cell
			-- with no colour at all, which looks like a theme that did not load.
			--
			-- `not (i >= 1)` rather than `i < 1`, because NaN answers false to
			-- both comparisons and would fall through as the index -- and a NaN
			-- is not hypothetical: `ratio` hands one back for any `scale = "log"`
			-- column whose extremes include a value at or below -1, where
			-- `math.log` of a non-positive number puts a NaN in `_lo`.
			local i = 1 + math.floor(r * last + 0.5)
			if not (i >= 1) then
				i = 1
			elseif i > n then
				i = n
			end
			return ramp[i]
		end
	else
		function ctx.style(_) return ctx.base end
	end

	return col
end

--- Bind one folder's precomputed statistics and width onto a column, and
--- prepare whatever `ctx.ratio` needs so that no work is repeated per row.
---@param col supaline.Column
---@param entry supaline.Entry
function M.bind(col, entry)
	local ctx = col.ctx --[[@as supaline.Scaled]]
	ctx.stats = entry.stats
	ctx.width = entry.width or col.fixed

	local st = entry.stats
	if type(st) ~= "table" or st.min == nil or st.max == nil then
		ctx._lo, ctx._hi, ctx._log = nil, nil, false
		return
	end

	if col.scale == "log" then
		ctx._lo, ctx._hi, ctx._log = math.log(st.min + 1), math.log(st.max + 1), true
	else
		ctx._lo, ctx._hi, ctx._log = st.min, st.max, false
	end
end

--- Display width of a plain string. Sizes, dates and permission strings are
--- ASCII, so the byte length is exact; anything else asks Yazi.
---@param text string
---@return integer
local function width_of(text)
	if not text:find("[\128-\255]") then
		return #text
	end
	return ui.width(text)
end

-- The mark `ui.truncate` leaves behind, and the one cell it takes.
local ELLIPSIS = "…"

-- Zero-width joiner. Whatever follows one belongs to the sequence it opened,
-- however wide that character measures on its own.
local ZWJ = "\226\128\141"

--- Whether `ch` is a skin-tone modifier, or one half of a flag. Both are two
--- cells alone and none at all behind what they attach to, so neither can be
--- told from a base character by measuring it.
---@param ch string one UTF-8 character
---@return boolean
local function is_tone(ch) return ch:find("^\240\159\143[\187-\191]$") ~= nil end

---@param ch string one UTF-8 character
---@return boolean
local function is_flag(ch) return ch:find("^\240\159\135[\166-\191]$") ~= nil end

--- Split `text` into grapheme clusters -- as much of that rule as a cell
--- needs: a base character, plus everything after it that only means anything
--- attached to it.
---
--- Necessary rather than tidy, because the width of a cluster is not the sum
--- of its characters' widths. Measured on 26.9.1: `❤` is one cell and the
--- variation selector after it is none, but `❤️` is two. A cut that counted
--- characters would hand back a cell more than the column asked for, and every
--- column after it would shift.
---@param text string
---@return table<integer, string>
local function clusters(text)
	local out, prev, half = {}, nil, false
	-- `[\0-\127\194-\244]` rather than `[%z...]`: `%z` stopped meaning the NUL
	-- byte after Lua 5.1 and matches the letter `z` on the 5.5 Yazi runs.
	for ch in text:gmatch("[\0-\127\194-\244][\128-\191]*") do
		local join
		if #out == 0 then
			join = false
		elseif is_flag(ch) then
			join = half -- a flag is a pair of regional indicators, never a third
		else
			-- Zero width covers the combining marks, the variation selectors and
			-- the joiner itself.
			join = ui.width(ch) == 0 or is_tone(ch) or prev == ZWJ
		end

		if join then
			out[#out] = out[#out] .. ch
		else
			out[#out + 1] = ch
		end
		prev, half = ch, is_flag(ch) and not join
	end
	return out
end

--- Cut a string to `width` display cells and add nothing. `ui.truncate` cannot
--- do this -- it always appends an ellipsis of its own -- so the general case
--- is walked here, one cluster at a time. Only ever reached by a cell that
--- overflows, and the ASCII path covers every built-in column.
---@param text string
---@param width integer
---@return string
local function hard_cut(text, width)
	if width < 1 then
		return ""
	elseif not text:find("[\128-\255]") then
		return text:sub(1, width)
	end

	local out, w = {}, 0
	for _, cluster in ipairs(clusters(text)) do
		local cw = ui.width(cluster)
		if w + cw > width then
			break
		end
		out[#out + 1], w = cluster, w + cw
	end
	return table.concat(out)
end

--- Cut a string to `width` cells and mark the cut, as `ui.truncate` does.
---
--- Yazi's own is exact for ASCII, which is every built-in column, so that is
--- still what an ASCII cell goes through. It counts one character at a time,
--- though, and a cluster wider than its characters slips past: measured on
--- 26.9.1, `ui.truncate("❤️abc", { max = 3 })` is `❤️a…`, four cells wide.
--- So anything carrying a byte over 127 is cut here instead, on a cluster
--- boundary and with the ellipsis's own cell held back.
---@param text string
---@param width integer
---@return string
local function soft_cut(text, width)
	if not text:find("[\128-\255]") then
		return ui.truncate(text, { max = width })
	elseif width < 1 then
		return ""
	end
	return hard_cut(text, width - 1) .. ELLIPSIS
end

--- Fit a plain string into `width`, padding or truncating as the column asks.
---
--- Either cut returns *at most* `width` cells, and either can come back short
--- when a wide character straddles the boundary, so the result is measured
--- again and padded.
---@return string
local function fit(text, width, align, overflow)
	local w = width_of(text)

	if w > width then
		if overflow == "grow" then
			return text
		elseif overflow == "clip" then
			text = hard_cut(text, width)
		else
			text = soft_cut(text, width)
		end
		w = width_of(text)
	end

	if w < width then
		local pad = string.rep(" ", width - w)
		return align == "left" and text .. pad or pad .. text
	end
	return text
end

--- Cut a renderable to `width` cells.
---
--- `Line:truncate` is the only way in -- a Line's spans cannot be read back
--- from Lua -- and it measures the line differently from `Line:width`, in two
--- ways that have to be corrected from out here. Both were measured on 26.9.1
--- and both come from one place: it counts one character at a time, and drops
--- the character that lands exactly on `max` to make room for the ellipsis.
---
---   * With `ellipsis = ""` there is nothing to make room for, but the drop
---     happens anyway: `{ max = 4 }` returns three cells of `abcdefgh`, where
---     the same string cut as a string returns four. Asking for one cell more
---     than the column has cancels it out exactly.
---   * A cluster wider than its characters -- `❤️` is two cells and its two
---     characters are one and none -- is left alone when it does not fit, so
---     what comes back can be *wider* than `max`. No `max` cuts that to the
---     cell, so cut again with a smaller one until it fits, and let it come
---     back short: short is padded below, long shifts every column after it.
---
--- Yazi's truncate mutates the line it is given and hands it back, so each
--- pass cuts the previous result further. `max = 0` empties a line whatever it
--- held, so the loop always ends.
---@param line supaline.Line
---@param width integer
---@param ellipsis string? `""` to cut without a mark, nil for Yazi's own
---@return supaline.Line
local function cut(line, width, ellipsis)
	local max = ellipsis == "" and width + 1 or width
	while max >= 0 do
		line = line:truncate { max = max, ellipsis = ellipsis }
		if line:width() <= width then
			break
		end
		max = max - 1
	end
	return line
end

--- Render one column for one file, fitted to its effective width.
---@param col supaline.Column
---@param file supaline.File
---@return unknown an `AsLine`
function M.cell(col, file)
	local out, style = col.render(file, col.ctx)
	if out == nil then
		out = ""
	end

	-- Already capped by `max_width` in `bind`.
	local width = col.ctx.width

	if type(out) == "string" then
		if width then
			out = fit(out, width, col.align, col.overflow)
		end
		return style and ui.Span(out):style(style) or out
	end

	-- A Line or Span came back; pad around it rather than inside it.
	local line = ui.Line(out)
	if style then
		-- `render` may hand back a style alongside a renderable as well as
		-- alongside a string, and dropping it here would lose the colour
		-- silently. A Line's style sits under its spans, so one that styled
		-- its own keeps them.
		line = line:style(style)
	end
	if not width then
		return line
	end

	local w = line:width()
	if w > width then
		if col.overflow == "grow" then
			return line
		end
		-- An empty ellipsis is how `Line:truncate` is asked to cut cleanly; left
		-- to itself it inserts "…" like `ui.truncate` does.
		line = cut(line --[[@as supaline.Line]], width, col.overflow == "clip" and "" or nil)
		-- `cut` returns *at most* `width`: a wide character straddling the edge
		-- comes back one cell short, and an unpadded cell drags every column
		-- after it out of line.
		w = line:width()
	end

	if w < width then
		local pad = string.rep(" ", width - w)
		return col.align == "left" and ui.Line { line, pad } or ui.Line { pad, line }
	end
	return line
end

--- The effective width of a column for one folder, for the two shapes that
--- derive it from the listing rather than stating it outright.
---@param col supaline.Column
---@param files supaline.File[]
---@param stats any
---@return integer?
function M.resolve_width(col, files, stats)
	if col.width_of then
		local w = col.width_of(stats)
		if type(w) ~= "number" then
			-- Returning nil here would leave the column with no width at all:
			-- no padding, no truncation, and a cell free to push into the file
			-- name. A stated width and "auto" both fail loudly; so does this.
			error(
				string.format(
					"supaline: the `width` function of column `%s` returned a %s; it must return a number",
					col.name or "?",
					type(w)
				)
			)
		end
		return cap(math.floor(w), col.max_width)
	elseif not col.auto then
		return col.fixed -- capped when the spec was normalised
	end

	-- "auto": render every file in the folder once and keep the widest result.
	-- O(n) per folder, cached by main.lua. `bind` applies `max_width` to
	-- whatever comes back, so there is no need to cap it here as well.
	local max, ctx = 0, col.ctx
	for i = 1, #files do
		local out = col.render(files[i], ctx)
		local w
		if out == nil then
			w = 0
		elseif type(out) == "string" then
			w = width_of(out)
		else
			w = ui.Line(out):width()
		end
		if w > max then
			max = w
		end
	end

	return cap(max, col.max_width)
end

return M
