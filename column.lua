--- @since 26.9.1
--- Column registry, spec normalisation, and cell layout.
---
--- A column is written in one of four shapes, all of which collapse to the same
--- runtime object, so a built-in column and a user-written one are
--- indistinguishable to the renderer:
---
---   "size"                                  a registered column, by name
---   { "size", width = 9 }                   ... with its options overridden
---   function(file, ctx) return "..." end    an inline definition, render only
---   { render = fn, stats = fn, width = 6 }  ... with options beside it
---
--- `[1]` is what tells a use of a column from a definition of one, and holds
--- one kind of value: the name of a column registered elsewhere. A table with a
--- name there is a use of that column, and everything else in it -- `render`
--- included -- overrides the definition's. A table with nothing there is the
--- definition, and a render written at `[1]` is refused.
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

--- Yazi's tab, with the method `types.yazi` leaves out. 26.9.1's `tab::Tab`
--- answers `history(url)` with the folder it has already listed for that URL,
--- or nil for one it has never opened, which is what `builtin.lua` asks a
--- directory for its entry count.
---
--- Declared here rather than left to the harness. `tab__Tab` is `(exact)`, so
--- the stub's own `_G.cx` table adds nothing to it, and the call type-checked
--- only because `builtin_spec.lua` assigned `cx.active.history` under a
--- file-wide `inject-field` disable -- a check on the plugin passing because
--- of a line in a test, and going quiet the moment that line was written any
--- other way.
---@class supaline.Tab : tab__Tab
---@field history fun(self: self, url: Url): supaline.Folder?

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
--- What the column is drawn in when there is no value to place: the
--- gradient's low end, or the flat style. Named for the key that produced it,
--- so a column reads back what its writer wrote.
---@field style unknown a ui.Style
--- Whether any of the three writers put an `fg` there, `false` included. The
--- one question a column that paints its own characters has to ask:
--- `permissions` colours each out of the theme's `[status]` styles and steps
--- aside for a colour written for the column -- while a `bold` or a `bg`
--- written for it arrives in `style` and goes under the characters without
--- asking anything.
---
--- Which of the three wrote it is not here. That answer names a file to go
--- and edit, which is what a refusal is for; `render` is running, and there
--- is nothing it could do with the name.
---@field fg_written boolean
--- The options this column declared in `options`, taken from the spec and
--- falling back to the definition. Not the spec itself: a column reading
--- `opts.style` off that would get the one layer its use site wrote rather
--- than the three merged, which is a different thing wearing the same name.
---@field opts table<string, any>
---@field stats any whatever this column's `stats` returned for the folder
---@field width integer? the effective width, `max_width` already applied
---@field ratio fun(value: number?): number? where a value sits, 0 to 1
---@field style_at fun(ratio: number?): unknown a ui.Style for that position

--- The same table, as `bind` and `ratio` see it: the extremes `ratio`
--- normalises against, and whether the scale is logarithmic. `bind` is the
--- only writer and `ratio` the only reader.
---
--- These are the ends of the *range* rather than of a gradient: nothing here
--- knows a colour.
---@class supaline.Scaled : supaline.Ctx
---@field _lo number?
---@field _hi number?
---@field _log boolean

---@alias supaline.Render fun(file: supaline.File, ctx: supaline.Ctx): any, any?

--- A separator as it is written: the text first, the style beside it. A column
--- spec's own shape under the same key, so `{ " | ", style = ... }` reads the
--- way `{ "size", style = ... }` does and takes the same spellings -- all but
--- a gradient, which `colour.flat` refuses: a separator is drawn between two
--- columns rather than on a file, so it has no value to place on one.
---@class supaline.SepSpec
---@field [1] string what to draw
---@field style supaline.StyleSpec?

--- A separator once `M.separator` has read it. The text and the style travel as
--- one value, which is what lets the three places a separator may be written --
--- `setup`, a linemode, a column's own -- fall back through the single `or`
--- in `main.lua`'s `render`: whichever level wrote one supplies both halves of
--- it, and none of them supplies half.
---
--- `style` stays nil when nobody wrote one, and that is load-bearing rather
--- than tidy. `render` builds a `ui.Span` only where it finds a style, so a
--- separator nobody coloured is the shared string it has always been and costs
--- no allocation per row. Normalising it to an empty `ui.Style` would put that
--- cost on everyone who never asked for a colour.
---@class supaline.Sep
---@field text string
---@field style unknown? nil when the separator carries no colour

--- Plugin-wide options, once `setup` has filled them in from `DEFAULTS`.
--- Separate from `supaline.Opts` in main.lua, which is what the user actually
--- wrote. `separator` and `order` are always present, so nothing that reads
--- one has a nil to think about; `scale` is the exception and has to be,
--- because a column definition can state one too and nil is what tells "the
--- user asked for this scale" from "nobody said".
---@class supaline.Cfg
--- As the user wrote it, not as `render` reads it: `compile` turns it into a
--- `supaline.Sep` on every build, so a `style` written as a function is called
--- again on each one. A record resolved into here would freeze at `setup`.
---@field separator string|supaline.SepSpec
---@field order integer
---@field scale? "linear"|"log" what the user wrote in `setup`, if anything
--- Always present and never nil, unlike `scale` above: `colour.bands` answers
--- an empty table for a `setup` that defined none, because "no band is
--- defined" is a state a `<->` is refused against rather than one that falls
--- back to anything. An empty table and a missing one would say the same thing
--- and only one of them can be indexed.
---@field band supaline.Bands the bands a `<->` may name, by name

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
--- Not read through `pick`: a definition's and a spec's are two of the three
--- layers `layers_of` stacks, with the theme between them, and each key is
--- taken from the nearest layer that wrote it rather than the whole table
--- from the nearest that wrote any.
---@field style supaline.StyleSpec?
---@field align "left"|"right"|nil
---@field overflow "ellipsis"|"clip"|"grow"|nil
---@field max_width integer?
---@field separator string|supaline.SepSpec|false|nil a separator of this column's own, `false` for none
---@field width number|"auto"|(fun(stats: any): number?)|nil a number is floored
---@field scale "linear"|"log"|nil
--- The names of the options this column reads off `ctx.opts` beyond the keys
--- every column takes. A definition writes it; a spec is checked against it,
--- which is the whole of what it is for.
---@field options string[]?

--- A registered column, as `register` stores it: the options above, with the
--- one field a column cannot do without.
---
--- No `fetch`. A column that writes one is turned away by the key sweep,
--- because a `ya.sync` block written outside this file binds to a different
--- state table and then fails silently, so there is no field here for a read
--- to reach.
---@class supaline.ColumnDef : supaline.ColumnOpts
---@field render supaline.Render

--- A spec entry written as a table: the second of the four shapes and the
--- fourth. `[1]` is the name of a column registered elsewhere; everything else
--- in the table is that column's options.
---
--- `[1]` constrains the value and not the index: `{ 42, width = 3 }` in a spec
--- is refused, `spec[2]` is not. Reading an index a class does not declare
--- costs nothing, here as anywhere. A `render` written there is refused twice
--- over -- by this field at check time and by `normalize` at run time -- and
--- only the second of the two can say where to put it instead.
---@class supaline.ColumnEntry : supaline.ColumnOpts
---@field [1] string?

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
--- Read, where `supaline.ColumnOpts.separator` is what was written. A user
--- writes `separator` wherever one may be written -- on `setup`, on a
--- linemode, on a column -- and `sep` is the `supaline.Sep` it was read into.
---@field sep supaline.Sep|false|nil a separator of this column's own, `false` for none
---@field stats fun(files: supaline.File[]): table?|nil
---@field refresh function? run whenever a linemode is installed, and on `cd`
---@field render supaline.Render
---@field scale "linear"|"log"
---@field auto boolean? `width = "auto"`: measure the folder
---@field width_of fun(stats: any): number?|nil
---@field fixed integer? a stated width, `max_width` already applied
---@field needs_pass boolean whether this column costs a pass over the folder
--- Whether this column draws a ramp, which is what says it needs extremes to
--- place a row between. `normalize` refuses a gradient on a column with no
--- `stats`, so this being true also says there is a `stats` function --
--- which is what lets `main.lua` tell a `stats` that came back wrong from a
--- column that legitimately has none.
---@field ramped boolean
--- What has already been reported about this column, keyed by `main.lua`'s
--- name for each thing it says. Three things are worth saying once and then
--- not again -- a `stats` with no extremes, a `width` function returning a
--- number nobody can use, and a column throwing -- and all three are reached
--- from a pass that runs while a folder is drawn, so a report that did not
--- remember itself would be a drip rather than a message. A table rather
--- than a field apiece, so a fourth costs a key instead of a fourth field on
--- a class that is otherwise about drawing.
---@field told table<string, true>
---@field ctx supaline.Ctx

--- What one pass over one folder produced for one column. main.lua caches
--- these per folder and binds them; a column that needs no pass gets an empty
--- one.
---@class supaline.Entry
---@field stats any?
---@field width integer?

--- The module table. `require(".column")` resolves to this file, so a call into
--- it is read against the signatures below and `column.normalize(42, {})` is
--- refused. A name is not a signature, though: without this class
--- `column.normalizze({}, {})` costs nothing on the line above that refusal,
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

-- The keys every column claims, whatever it draws. `[1]` is the registered
-- name or the `render` and is claimed by the predicate below rather than
-- written in here, because it is an index rather than an option and the
-- message names it separately.
--
-- Nothing else refuses one of these misspelled. A key in a table constructor
-- is past what `lua-language-server` checks against a class -- `(exact)` was
-- measured not to change that -- so `algin` and `max_widht` reach this or they
-- reach nobody, and a column whose cap was written `max_widht` draws at its
-- natural width and says nothing about why.
--
-- A key whose value is a list takes only what the list holds, and `M.one_of`
-- refuses anything else -- a value nobody accepts, which until now was
-- accepted by being *ignored*: `align = "centre"` fell through to the `or
-- "right"` that defaults it and drew a right aligned column without a word,
-- and `scale = "LOG"` scaled nothing. The sets sit in here rather than in a
-- table beside it so that the two cannot fall out of step: a new shared key
-- is one line, and writing that line is choosing between `true` and a set.
-- The readers below want a key claimed or not claimed, so a list reads as
-- `true` to every one of them.
--
-- Each set is in the order its message lists them, which is the order
-- README's table lists them in -- these are read as a set of choices rather
-- than looked up one at a time, so `pairs` order would reword the message
-- between runs the way it would the key list below. Only the keys every
-- column shares are in here at all, and that is the line rather than an
-- omission: a column's own options are the column's to check. What `format`
-- may hold is knowable to `mtime` and to nothing else, which is why `options`
-- declares the names and stops there.
local COLUMN_KEYS = {
	align = { "left", "right" },
	max_width = true,
	overflow = { "ellipsis", "clip", "grow" },
	refresh = true,
	render = true,
	scale = { "linear", "log" },
	separator = true,
	stats = true,
	style = true,
	width = true,
}

--- What the reader wrote, for the tail of a message that names it back.
---
--- A string or a number is shown as written and everything else is named by
--- its type: a misspelling is worth showing letter for letter and a width is
--- worth showing at all, while a table is worth showing neither way. The
--- type-only half is the shape `check_options` uses a few lines down.
---@param value any
---@return string
local function as_written(value)
	local t = type(value)
	if t == "string" or t == "number" then
		return string.format("`%s`", tostring(value))
	end
	return "a " .. t
end

--- A width as a whole number of cells, or nil for anything that is not one.
---
--- `type` is asked before `math.tointeger`, and that order is the whole check:
--- measured on 5.5.1, `math.tointeger("3")` answers 3, so a `width` written as
--- the string `"3"` would otherwise pass as an integer. It also covers the
--- three numbers that are numbers and not counts -- `inf`, `-inf` and NaN all
--- answer nil.
---
--- One function because two keys and a `width` function all ask it, and the
--- ordering above is the kind of thing a later reader tidies into
--- `math.tointeger(value)` without knowing what it was for. Each caller words
--- its own refusal, which is the part that differs; this is the part that
--- must not.
---@param value any
---@return integer?
local function cells_of(value) return type(value) == "number" and math.tointeger(value) or nil end

--- Refuse a width that is not a whole number of cells, or that is no cells at
--- all.
---
--- Both keys that state one come through here. `max_width` had no check of any
--- kind: a string reached `cap`, which compares it against a number, and the
--- reader got `attempt to compare string with number` from a line of this file
--- rather than anything naming the key they wrote.
---
--- A width of 0 or less is the quieter one. It was taken, carried through
--- `cap` and laid out, and `fit` padded the cell to no cells -- so the column
--- drew as the empty string on every row, which reads as a column that is not
--- there rather than as a setting that was wrong.
---
--- Non-integral is refused rather than floored. Flooring is a guess about
--- which of two whole numbers was meant, made silently and on a value the
--- reader had already got wrong; `2.5` is a mistake wherever it came from, and
--- the arithmetic that produced it is worth the reader's attention rather than
--- this function's rounding. An integral float is not that mistake -- `3.0` is
--- 3 -- so it is taken and narrowed.
---@param key "width"|"max_width"
---@param value any
---@param where string
---@return integer? # the value as an integer, or nil if none was written
local function whole_cells(key, value, where)
	if value == nil then
		return nil
	end
	local cells = cells_of(value)
	if cells == nil or cells < 1 then
		error(
			string.format(
				"supaline: `%s` %s must be a whole number of cells, 1 or more, got %s -- a column "
					.. "of no cells draws as the empty string on every row, which reads as a column "
					.. "that is not there rather than as a width that was wrong",
				key,
				where,
				as_written(value)
			)
		)
	end
	return cells
end

--- Refuse a value none of the ones `key` takes covers.
---
--- Nil is not a value and is allowed: every one of these keys has a default,
--- and "nobody wrote one" is what reaches it. The value comes back unchanged,
--- so a caller reads it and defaults it in one line rather than two.
---
--- `where` is the rest of the sentence after the key, because the same key is
--- written in two places that have to name themselves differently: `of column
--- `size`` and `in `setup``.
---@param key "align"|"overflow"|"scale"
---@param value any
---@param where string
---@return any # the value, unchanged
function M.one_of(key, value, where)
	if value == nil then
		return value
	end
	local values = COLUMN_KEYS[key] --[[@as string[] ]]
	for _, ok in ipairs(values) do
		if value == ok then
			return value
		end
	end
	error(
		string.format("supaline: `%s` %s must be %s, got %s", key, where, colour.key_list(values, "or"), as_written(value))
	)
end

-- And the two a definition may write that a use of it may not. Which
-- definitions may write which of them is `ROLES` below -- `register` names the
-- column it is handed, so `name` is not that one's to write either. What this
-- set is for is `check_options`, where declaring either as an option declares
-- a name the column has already.
local DEFINITION_KEYS = { name = true, options = true }

-- Stands in for a list nobody wrote, so a loop over one allocates nothing.
-- Never written to, and never handed out.
local EMPTY = {}

-- The keys above, in the order the message lists them. Sorted, because `pairs`
-- gives a set in whatever order the hash does, and a message that reorders
-- itself between runs reads as a different message.
local COLUMN_KEY_LIST
do
	local names = {}
	for key in pairs(COLUMN_KEYS) do
		names[#names + 1] = key
	end
	table.sort(names)
	COLUMN_KEY_LIST = colour.key_list(names)
end

--- The part a table of column keys plays, which is what says which of the keys
--- only some of them read it is entitled to. Three, over the four shapes a
--- column is written in and the definition `register` is handed: a name and a
--- name with options beside it are both uses of a column defined elsewhere,
--- and a bare render and a render with options beside it are both inline
--- definitions.
---
--- Written down rather than derived from table identity. `t == def` looks
--- exact and answers two of the three: an inline definition is its own spec,
--- and so is the table `register` is handed, so identity takes the second for
--- the first and accepts a `name` beside a render that `register` has already
--- named.
---@alias supaline.Role "registered"|"inline"|"use"

--- What each of them claims beyond `COLUMN_KEYS`, and what its message calls
--- the thing that says what to draw.
---
--- `[1]` is in here rather than in `COLUMN_KEYS` because its meaning is the
--- whole difference between the three: a spec names its column there, and a
--- definition -- inline or registered -- has nothing there for anyone to
--- read.
---@class supaline.RoleKeys
---@field keys table<any, true>
---@field draws string
---@field claims fun(key: any): any the two above, for a column declaring no options. Truthy is
--- the whole of the answer: a shared key whose entry is its set of values answers the set.

--- One role. `claims` is built here rather than assigned over the table below,
--- so nothing can add a role and forget it.
---@param keys table<any, true>
---@param draws string
---@return supaline.RoleKeys
local function role_keys(keys, draws)
	-- The answer for a column that declares no options, which is most of them:
	-- one closure per role, built once, so the common case allocates nothing.
	return { keys = keys, draws = draws, claims = function(key) return COLUMN_KEYS[key] or keys[key] end }
end

local DRAWS_RENDER = "the `render` that says what it draws"

---@type table<supaline.Role, supaline.RoleKeys>
local ROLES = {
	-- `register("size", { render = fn })`. The call names it.
	registered = role_keys({ options = true }, DRAWS_RENDER),
	-- `{ render = fn, name = "size" }`: the definition and the only use of it
	-- are one table, so both keys a definition writes are read right here. A
	-- bare `function` is this role too, with nothing beside the render.
	inline = role_keys({ name = true, options = true }, DRAWS_RENDER),
	-- `{ "size", width = 8 }`: a use of a definition written elsewhere, naming
	-- it at `[1]`. `name` and `options` are that definition's.
	use = role_keys({ [1] = true }, "the name at `[1]` that says which column it is"),
}

--- What one table is entitled to: the shared keys, whichever of the rest its
--- role reads, and the options the definition behind it declares.
---
--- A column may read options of its own off `ctx.opts` -- `mtime` takes a
--- `format` -- so the set is not one list for every column, and a closed one
--- would refuse `format` on the column that reads it. `options` is how a
--- definition says which keys those are, and saying so is what lets `fromat`
--- be refused on the same column.
---@param role supaline.Role how this table was written
---@param def supaline.ColumnOpts whose `options` say what this column also takes
---@return fun(key: any): any # truthy if the key is claimed; see `supaline.RoleKeys`
local function claims_of(role, def)
	local this = ROLES[role]
	local own = def.options
	if own == nil then
		return this.claims
	end
	local set = {}
	for _, key in ipairs(own) do
		set[key] = true
	end
	return function(key) return COLUMN_KEYS[key] or this.keys[key] or set[key] end
end

-- What a key that is none of them most likely meant. Three of the four are
-- names this plugin really reads, written where they are not read rather than
-- misspelled, so a message that only said "not a column key" would be true
-- and useless. `1` is one of them under the spelling `unknown` gives it, since
-- what a key is called in a message is whatever `tostring` makes of it.
local COLUMN_MEANT = {
	fetch = "`fetch` is supaline's own rather than a column's: a column that needs "
		.. "asynchronous state has to be built into supaline itself, because a `ya.sync` "
		.. "block written anywhere else binds to a different state table and then fails "
		.. "silently",
	options = "`options` goes on the definition, which is where a column says what it "
		.. "reads; a use of that column can write one of the names it declared, and cannot "
		.. "add to them",
	["1"] = "`[1]` is where a spec names the column it uses, and holds nothing else; a "
		.. "definition writes its `render` under that name, and beside one `[1]` is read by "
		.. "nobody",
	name = "a column is named by the `register` call that declares it, by the `[1]` a spec "
		.. "names it with, or by a `name` written beside an inline `render`; anywhere else it "
		.. "is read by nobody",
}

-- `%4$s` is the role's own `draws`: refusing `1` on a definition, under a
-- sentence saying a column is named at `[1]`, is a message arguing with
-- itself.
local COLUMN_UNKNOWN = "supaline: column `%s`: %s. A column takes %s, beside %s -- "
	.. '`{ "size", width = 8, style = "cyan" }`%s%s'

local COLUMN_OPTIONS = "supaline: column `%s` declares `options` as %s. It is the list of "
	.. 'names that column reads off `ctx.opts`, as `options = { "format" }`, and is what '
	.. "lets one of them be refused when it is misspelled"

--- Check the `options` a definition declares, before anything is read through
--- them.
---
--- Here rather than in `register`, which is where it started and where it
--- reached one of the two writers: a spec that writes `render` inline is its
--- own definition and never goes through `register`, so its `options` were
--- taken on trust. `options = "format"` was accepted there and read as
--- nothing, which is the silence the sweep around this exists to end, left
--- standing on the key the sweep introduced.
---@param def supaline.ColumnOpts
---@param name string?
local function check_options(def, name)
	local own = def.options
	if own == nil then
		return
	elseif type(own) ~= "table" then
		error(string.format(COLUMN_OPTIONS, name or "?", "a " .. type(own)))
	end

	-- Counted through `pairs` and then read back by index, rather than walked
	-- with `ipairs`: a gap or a key of its own stops `ipairs` where it is, and
	-- every name past that point would be declared here, ignored, and refused
	-- at the use site as a key the column does not take. That is the silence
	-- this check exists to end, standing in the table that writes it -- and
	-- `#` cannot see it either, since the length of a table with a gap is
	-- whichever border Lua happens to find.
	local n = 0
	for _ in pairs(own) do
		n = n + 1
	end
	if n == 0 then
		error(string.format(COLUMN_OPTIONS, name or "?", "an empty list"))
	end

	for i = 1, n do
		local key = own[i]
		if key == nil then
			-- `n` entries with `1 .. n` all filled is the whole of what a list
			-- is, so one missing index means the rest are somewhere else.
			error(string.format(COLUMN_OPTIONS, name or "?", "a table with a gap in it, or with keys of its own"))
		elseif type(key) ~= "string" then
			error(string.format(COLUMN_OPTIONS, name or "?", "a list holding a " .. type(key)))
		elseif COLUMN_KEYS[key] or DEFINITION_KEYS[key] then
			-- Declaring one changes nothing -- every column claims it already
			-- -- and reads as though this column had taken it over.
			error(
				string.format(COLUMN_OPTIONS, name or "?", string.format("a list naming `%s`, which every column takes", key))
			)
		elseif COLUMN_MEANT[key] then
			-- A name the sweep has a reason for is not a column's to take over,
			-- and taking one over switches that reason off: `options = { "fetch" }`
			-- is the whole of what it costs to have a `fetch` accepted, and the
			-- refusal it walks past is the only place the plugin says why a column
			-- cannot own one. Read off `COLUMN_MEANT`, so a fourth name worth
			-- explaining is reserved by being explained.
			error(
				string.format(
					COLUMN_OPTIONS,
					name or "?",
					string.format("a list naming `%s`, which supaline answers for itself", key)
				)
			)
		end
	end
end

--- Refuse every key a column is not entitled to, naming all of them at once.
---
--- Both writers of a column come through here: the spec a user puts in a
--- linemode, and the definition a third party hands `register`. They are one
--- table in the shape that writes `render` inline, and a definition's
--- misspelling is the worse of the two -- it is read again for every spec that
--- names the column.
---@param t table the table that was written
---@param name string?
---@param def supaline.ColumnOpts whose `options` say what this column also takes
---@param role supaline.Role how `t` was written
local function refuse_unknown(t, name, def, role)
	-- Only a definition's own `options` are this table's to answer for. A use
	-- site is a different table, and that column's were checked when the
	-- definition it names was read.
	if role ~= "use" then
		check_options(def, name)
	end
	local unknown, _, subject, hints = colour.unknown(t, claims_of(role, def), "column", COLUMN_MEANT)
	if not unknown then
		return
	end
	-- Off the definition whichever table was swept: what this column also takes
	-- is most worth saying to the use site, which is the one that cannot see
	-- the definition.
	local own = def.options
	error(
		string.format(
			COLUMN_UNKNOWN,
			name or "?",
			subject,
			COLUMN_KEY_LIST,
			ROLES[role].draws,
			own and string.format(". That column also takes `%s`", table.concat(own, "`, `")) or "",
			hints
		)
	)
end

--- What a column may be called, which is decided by `theme.toml` rather than
--- here: a column's theme layer is `th.supaline[name]`, so the name has to be
--- one a custom theme section can hold as a field.
---
--- Measured on 26.9.1, and reimplemented rather than asked because there is
--- nothing to ask -- the rule is enforced while Yazi parses the file, before
--- any plugin code runs, and there is no call that answers "would this name
--- do". So it can go stale, and the direction it would go stale in is
--- refusing a name a newer Yazi accepts. Re-measure it there before believing
--- this line over the platform.
---
--- Yazi's own message says "1-20 characters in snake-case" and its parser is
--- looser than that reads: `_x`, `x_` and `2x` are all taken, so what is
--- actually enforced is the length and the character class. Holding a name to
--- a leading letter on top of that would be supaline inventing a restriction
--- the platform does not have -- which is the argument `colour.lua` took when
--- it dropped the leading letter from the rule a band name is held to, and
--- the reason the two patterns now read the same.
local NAME = "^[a-z0-9_]+$"
local NAME_MAX = 20

--- Refuse a name no `[supaline]` field can be called, wherever it was written.
---
--- Two callers, and only two because of where the second one sits. `register`
--- names the column it is handed and checks it there, so that a name it cannot
--- keep is turned away as it is declared rather than at the first use of it.
--- Every other way of naming a column settles the name in one local inside
--- `normalize`, and the check sits on that local rather than on the branches
--- that assign it.
---
--- Nil is not a name and is allowed: an inline definition need not name itself,
--- and one that does not has no theme layer to reach.
---@param name string?
---@param where string how the name got here, for the message
local function refuse_name(name, where)
	if name == nil or (type(name) == "string" and name:find(NAME) and #name <= NAME_MAX) then
		return
	end

	-- Refused here rather than left to the theme, because the theme refuses it
	-- in the worst available way: `[supaline] my-col = ...` is a TOML parse
	-- error, and Yazi answers one by discarding the *whole file* and falling
	-- back to its preset -- so a name like this costs the reader every other
	-- colour they wrote, not just this column's. And a reader who never tries
	-- to theme the column is told nothing at all: the name takes, the column
	-- draws, and the one layer a flavor could have reached is unreachable for
	-- as long as it keeps that name.
	error(
		string.format(
			"supaline: `%s` cannot be a column name, %s. A column's theme layer is the "
				.. "`[supaline]` field called after it, and Yazi takes a field name of 1 to %d "
				.. "characters from lowercase letters, digits and `_` -- a name it refuses takes "
				.. "the whole of `theme.toml` down with it. Call the column something else and "
				.. "name it that",
			tostring(name),
			where,
			NAME_MAX
		)
	)
end

--- Register a reusable column under `name`, so a linemode can refer to it as
--- `"name"` or `{ "name", ... }`.
---@param name string
---@param def supaline.ColumnDef
function M.register(name, def)
	if type(name) ~= "string" or name == "" then
		error("supaline: a column needs a non-empty name")
	end
	refuse_name(name, "which is what `register` was given")

	if type(def) ~= "table" or type(def.render) ~= "function" then
		error(string.format("supaline: column `%s` needs a `render` function", name))
	end

	-- `fetch` is refused by the sweep rather than here, and the reason travels
	-- with it: an inline `{ render = ... }` never reaches this function, so a
	-- branch here would have covered one of the two ways a column is written
	-- and left the other silent.
	refuse_unknown(def, name, def, "registered")
	M._registry[name] = def
end

--- A `stats` function over the extremes of the current listing, which is what
--- a gradient is stretched between and what `ctx.ratio` normalises against.
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

--- Who wrote one layer of a column's style, as the three tables below key it.
--- Three layers and four names: see `WHERE`.
---@alias supaline.StyleWriter "definition"|"inline"|"theme"|"spec"

--- What to call each writer's style in an error, in terms of the file it was
--- written in. A theme has no `style` key to name, so a message that spoke of
--- one would be describing a spec the reader never wrote.
---
--- Four rows for three layers, because the layer a definition writes is
--- written by two different-looking things. `register` states a default every
--- use of that column starts from, and saying so points the reader at the call
--- that declared it. A column written inline in a linemode has no default to
--- be: its style is written once, in the list the reader is already looking
--- at, which is where a spec's is written -- so it gets the spec's words while
--- occupying the definition's layer. Keyed rather than decided by a condition,
--- for the reason `NO_STATS` gives below.
local WHERE = {
	spec = "the `style` of column `%s`",
	theme = "the `[supaline] %s` field in your theme",
	definition = "the default `style` of column `%s`",
	inline = "the `style` of column `%s`",
}

--- And what to call one written as a function, since a message naming
--- `style` would send the reader to a line that is not the one to change. No
--- theme row, and nothing stands in for the missing one: a theme field holds a
--- string or a style table and never a function, so a theme's layer never asks
--- this table for a name.
local FN_WHERE = {
	spec = "the `style` function of column `%s`",
	definition = "the default `style` function of column `%s`",
	inline = "the `style` function of column `%s`",
}

--- What to do about a gradient on a column with no extremes, per writer.
--- `stats` is a definition's to give and a flat colour a spec's to write, so
--- those two get the same advice; a `theme.toml` has neither, and the only
--- move left there is the flat colour. Keyed the way `WHERE` and `FN_WHERE`
--- are, so a fourth writer is a row in three tables rather than a row in two
--- and a condition to find.
local NO_STATS = {
	spec = "Give the column a `stats` function, or write a flat colour there instead",
	definition = "Give the column a `stats` function, or write a flat colour there instead",
	inline = "Give the column a `stats` function, or write a flat colour there instead",
	theme = "Write a flat colour there instead",
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

-- The keys a written separator claims. `[1]` is what to draw and `style` is
-- what to draw it in; anything else is a misspelling, and nothing else here
-- would say so -- a key in a table constructor is past what
-- `lua-language-server` checks against a class, `(exact)` included, so `styel`
-- reaches this or it reaches nobody.
local SEP_KEYS = { [1] = true, style = true }

local function claims_sep(key) return SEP_KEYS[key] end

local SEP_HELP = "supaline: %s must be a string or a table, got a %s -- "
	.. '`" | "` draws that between two columns, `{ " | ", style = ... }` draws it in a '
	.. 'colour, and `""` draws nothing at all. `false` drops the separator before a '
	.. "column and is a column's `separator`, never a linemode's"

local SEP_UNKNOWN = "supaline: %s: %s %s. A separator table takes what to draw as `[1]` "
	.. 'and `style` beside it -- `{ " | ", style = { fg = "#585b70" } }`'

local SEP_TEXT = "supaline: %s was given %s to draw. The first element of a separator table "
	.. 'is the text, as `{ " | ", style = ... }`; a table with no text in it reaches Yazi as '
	.. "a span of nothing and the linemode stops drawing"

local SEP_EMPTY = 'supaline: %s draws "" in a colour, which draws nothing: a span of no '
	.. 'cells shows no style. Write `""` on its own to put nothing between two columns, or '
	.. "give the separator something to draw"

local SEP_FALSE = "supaline: %s has `style = false`, and there is nothing there to turn off. "
	.. "A column's `style = false` drops what its theme or its definition would otherwise "
	.. "supply; a separator has neither behind it, so leaving `style` out is how one goes "
	.. "uncoloured"

--- Call a function a spec wrote where a value would go, and name it if it
--- raises.
---
--- Two keys take one, for one reason: a column's `style` and a separator's
--- own. A spec is re-read on every build and never evaluated again, so a
--- value freezes whatever the theme held while `init.lua` ran; a function is
--- called inside `build`, where the flavor has landed, and again on every
--- `app:theme` after it.
---
--- The `pcall` is the half both need. The likely failure is the call itself:
--- `th.status.perm_read` against a flavor with no `[status]` section raises
--- `attempt to index a nil value`, and that reaches the user as `build`'s
--- notification -- where a message carrying no name says nothing about which
--- line to open. So `what` is the caller's to supply, and the two spell it
--- differently: a column's names the file it was written in, a separator's
--- names the separator.
---@param fn function
---@param what string what to call the function in a message
---@return any
local function called(fn, what)
	local ok, got = pcall(fn)
	if not ok then
		error(string.format("supaline: %s raised: %s", what, tostring(got)))
	end
	return got
end

--- Read a separator, in whichever of the two shapes it was written. Every
--- place that takes one comes through here: `separator` in `setup`,
--- `separator` on a linemode, and a column's own. Unrefused, `separator = 42`
--- reaches Yazi and empties the pane.
---
--- Nil is what "nothing was written" looks like and is handed back as it is,
--- for the caller to fall back from.
---
--- `false` is the value worth a check of its own, and it arrives here as the
--- wrong type rather than as a shape. It reads like a column's
--- `separator = false` and it is falsy, so unrefused on a linemode it falls
--- through to the separator it was written to be rid of and the linemode
--- draws the very thing it asked to drop -- in silence, because a separator
--- is not read until a row is, so a wrong one is a render-time failure with
--- the cause a whole session behind it. `normalize` takes a column's `false`
--- before this is reached, which is why only the meaningless one gets here.
---@param value any
---@param where string names where it was written, for the message
---@return supaline.Sep?
function M.separator(value, where)
	if value == nil then
		return nil
	elseif type(value) == "string" then
		return { text = value }
	elseif type(value) ~= "table" then
		error(string.format(SEP_HELP, where, type(value)))
	end

	local unknown, quoted = colour.unknown(value, claims_sep)
	if unknown then
		error(
			string.format(SEP_UNKNOWN, where, quoted, #unknown == 1 and "is not a separator key" or "are not separator keys")
		)
	end

	local text = value[1]
	if type(text) ~= "string" then
		error(string.format(SEP_TEXT, where, text == nil and "nothing" or "a " .. type(text)))
	end

	local style = value.style
	if type(style) == "function" then
		-- The same repair a column's `style` gets, through the same helper: a
		-- separator written in a theme's colour has to follow that theme.
		style = called(style, string.format("the style function under %s", where))
	end

	if style == false then
		error(string.format(SEP_FALSE, where))
	elseif style == nil then
		-- The table form with the colour left out. It says exactly what the
		-- bare string says and is allowed to: every other optional key on every
		-- other spec may be omitted, and refusing the omission here would make
		-- this the one place that cannot be. What it must not do is mean
		-- something else -- take the style from the level above -- because two
		-- spellings that differ only in what they inherit is the four-way
		-- inheritance this shape was chosen to avoid, moved inside it.
		return { text = text }
	end

	if text == "" then
		error(string.format(SEP_EMPTY, where))
	end
	return { text = text, style = colour.flat(style, string.format("the style under %s", where)) }
end

--- One writer's style, read into a layer.
---
--- A function is called here, and here is the whole of what it buys:
--- `normalize` runs inside `build`, which is what the `theme` event calls, and
--- a spec is re-read on every one of those passes but never evaluated again. A
--- function is, so it sees the flavor that was not there while `init.lua` ran
--- and follows every reload after it. Once per column per build, never per
--- row.
---@param value any what that writer wrote, if anything
---@param source supaline.StyleWriter
---@param name string?
---@param painter supaline.Painter
---@return supaline.Layer|false
local function layer_of(value, source, name, painter)
	local where = string.format(WHERE[source], name or "?")
	if type(value) == "function" then
		-- Named for the file it was written in rather than for `style`, because
		-- a definition's function is not on a line the reader has.
		local fn = string.format(FN_WHERE[source], name or "?")
		value, where = called(value, fn), "what " .. fn .. " returned"
	end
	return colour.layer(value, where, painter)
end

--- The three layers of a column's style, farthest first: the definition's own,
--- the `[supaline]` theme field named after the column, and the spec's.
--- `colour.merge` takes them in this order and gives each key to the nearest
--- one that wrote it. What to call each is handed back beside them rather than
--- kept in a constant, because the first one's name depends on which shape
--- wrote it and a second copy of that decision is a second thing to keep in
--- step.
---
--- The theme section holds a string or a style table and nothing else -- an
--- array is refused by Yazi, taking the whole file with it -- and a table
--- arrives as the `ui.Style` Yazi parsed, which `colour.layer` reads back
--- through `raw()`. An empty string there is read as nothing written.
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
---@param bands supaline.Bands
---@param role supaline.Role which part the table the column was written in plays
---@return (supaline.Layer|false)[]
---@return supaline.StyleWriter[] what to call each layer, in the same order
local function layers_of(name, opts, def, bands, role)
	local section = name and th.supaline
	local themed = section and section[name]
	if themed == "" then
		themed = nil
	end

	-- Only a use of a column defined elsewhere has a spec to read. The other
	-- shape that reaches here is one table playing both parts, and reading
	-- that table as both wrote its style into two of the three layers at once.
	-- Two things came of it, and the second is the worse: a `style` function
	-- ran twice per build, against what `layer_of` promises a paragraph above,
	-- so one that answered differently the second time built a style out of two
	-- answers no single call had returned; and the table sat at the near end of
	-- the merge as well as the far one, where it beat the theme -- the one
	-- layer that exists so a flavor can reach a colour a definition chose.
	--
	-- An inline table carries a `render`, which is what a definition is, so it
	-- writes the definition's layer and the spec's stays empty.
	--
	-- An `and`/`or` would drop a `style = false` on the way past, which is the
	-- one spelling that means something and is falsy.
	local written
	if role == "use" then
		written = opts.style
	end

	-- One painter behind all three writers: the bands are the same for each,
	-- and `layer_of` runs once per column per build rather than per row.
	local painter = colour.painter(bands)
	local mine = role == "use" and "definition" or "inline"
	return {
		layer_of(def.style, mine, name, painter),
		layer_of(themed, "theme", name, painter),
		layer_of(written, "spec", name, painter),
	}, { mine, "theme", "spec" }
end

-- What a spec may be at all, for the two places that have to say so: a value
-- that is no kind of table, and a table that is a table and nothing more.
-- Written once because it is one sentence -- a reword that reached one of them
-- and missed the other would answer `"size"` and `{ "size" }` differently, and
-- those are the same mistake.
local COLUMN_SHAPE = "supaline: a column must be a name, a function, or a table with `render`"

-- Its own message rather than the shape one above, which is about not knowing
-- what a column is. Whoever writes this knows: they wrote a render, in the one
-- place that no longer reads one, and what they need is where it goes instead.
local RENDER_AT_ONE = "supaline: a column's `render` goes under `render`, not at `[1]`: write "
	.. "`{ render = fn, width = 6 }`. `[1]` is where a spec names the column it "
	.. "uses, and a function is not a name"

--- Turn one entry of a linemode spec into a runtime column.
---@param spec supaline.ColumnSpec
---@param cfg supaline.Cfg
---@return supaline.Column
function M.normalize(spec, cfg)
	-- The sugar, before anything dispatches on it. Since `[1]` holds only a
	-- name, a spec table is either a `[1]` or a `render`, and the two bare
	-- spellings are those two written short: `"size"` is `{ "size" }` and `fn`
	-- is `{ render = fn }`. Rewriting them here rather than giving each a branch
	-- of its own is what lets the two messages above be written once -- a pair
	-- kept in step by hand is a pair that drifts.
	--
	-- A fresh table each time, so nothing here writes into what the user wrote.
	if type(spec) == "string" then
		spec = { spec }
	elseif type(spec) == "function" then
		spec = { render = spec }
	elseif type(spec) ~= "table" then
		error(COLUMN_SHAPE)
	end

	local name, opts, def, role

	if type(spec[1]) == "string" then
		name, opts, role = spec[1], spec, "use"
		def = M._registry[name] or error(string.format("supaline: unknown column `%s`", name))
	elseif type(spec[1]) == "function" then
		error(RENDER_AT_ONE)
	elseif type(spec.render) == "function" then
		name, opts, def, role =
			spec.name,
			spec,
			spec, --[[@as supaline.ColumnDef]]
			"inline"
	else
		error(COLUMN_SHAPE)
	end

	-- On the local rather than in the branches above. Every shape assigns `name`
	-- before anything reads it, so a rule put here covers the shapes written
	-- above and the ones nobody has written yet: a spelling added to that chain
	-- arrives already refused, rather than waiting to be remembered.
	--
	-- One clause covers it because one role can reach here with a name of its
	-- own: a `use` took its name out of the registry, where `register` checked
	-- it on the way in. A shape added above that names itself another way wants
	-- this wording looked at, which is the whole of what it wants.
	refuse_name(name, "which is the `name` this definition gave itself")

	-- Every shape reaches here with a table, the two desugared ones included --
	-- theirs holds the one key the sugar put in it, which its role claims, so
	-- they sweep clean rather than being skipped. The definition says what this
	-- column takes beyond the shared keys, and a registered one was swept by
	-- `register` when it arrived.
	refuse_unknown(opts, name, def, role)

	-- An explicit nil test, not `opts[key] == nil and def[key] or opts[key]`:
	-- that idiom collapses a `def` value of `false` to nil, and `separator` is
	-- the key written `false` on purpose.
	--
	-- The return is annotated because it cannot be inferred. The key is a
	-- variable, so a language server unions every field either table can
	-- carry, the `render` function included, and then objects when a width
	-- from here reaches `cap`.
	---@return any
	local pick = function(key)
		local v = opts[key] ---@type any
		if v == nil then
			v = def[key]
		end
		return v
	end

	-- `false` is taken before the reader, because it is the one value a
	-- separator may be that `M.separator` refuses: on a column it says "draw
	-- nothing before this one", which is a column's answer and not a
	-- linemode's, and the message it would otherwise get is written to say so.
	local sep = pick("separator")
	if sep ~= false then
		sep = M.separator(sep, string.format("`separator` of column `%s`", name or "?"))
	end

	-- Refused before they are defaulted, which is the whole of the fix: the
	-- `or` that supplies the default is also what swallowed a wrong value, so a
	-- check written after it would have nothing left to look at.
	local of_col = string.format("of column `%s`", name or "?")

	local col = {
		name = name,
		align = M.one_of("align", pick("align"), of_col) or "right",
		overflow = M.one_of("overflow", pick("overflow"), of_col) or "ellipsis",
		max_width = whole_cells("max_width", pick("max_width"), of_col),
		sep = sep,
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
		-- The resolved value rather than each of the three, because two of them
		-- have already been looked at: `cfg.scale` is `setup`'s own key and
		-- `setup` refuses it by that name, where the message can say `setup`
		-- rather than name whichever column happened to be normalised first.
		-- What is left for this call is the spec's and the definition's.
		scale = M.one_of("scale", opts.scale or cfg.scale or def.scale, of_col) or "linear",
	}

	local width = pick("width")
	if width == "auto" then
		col.auto = true
	elseif type(width) == "function" then
		col.width_of = width
	elseif type(width) == "number" then
		col.fixed = cap(whole_cells("width", width, of_col), col.max_width)
	elseif width ~= nil then
		error(string.format('supaline: `width` of column `%s` must be a number, "auto", or a function', name or "?"))
	end

	-- A column that declares `stats` gets the folder pass, full stop. Gating it
	-- on whoever happens to consume the result -- a gradient ramp, a derived
	-- width -- leaves a column whose `render` reads `ctx.stats` directly with
	-- nothing to read, and says nothing about it.
	col.needs_pass = col.stats ~= nil or col.auto or col.width_of ~= nil

	-- Empty, and built here rather than on first use, so the record has one
	-- shape from the moment it exists. `setup` builds fresh records, which is
	-- what re-arms every report this holds: a reader who has just changed the
	-- configuration is owed the message again.
	col.told = {}

	local layers, sources = layers_of(name, opts, def, cfg.band, role)
	local resolved, from = colour.merge(layers)

	-- A gradient needs extremes to place a value between, and only a column
	-- that declares `stats` ever gets any: without one `ctx.ratio` is nil for
	-- every row and the ramp can only ever draw its low end. Refused here
	-- rather than drawn flat, because a gradient that silently is not one is
	-- exactly the kind of failure this plugin has no other way to report.
	-- Named for the writer that put it there, which need not be the one that
	-- wrote the rest of the style.
	local gradient = col.stats == nil and colour.gradient_in(resolved)
	if gradient then
		local source = sources[from[gradient]]
		error(
			string.format(
				"supaline: %s: `%s` is a gradient, but that column has no `stats`, so there are "
					.. "no extremes to place a value between and the ramp could only ever draw "
					.. "its low end. %s",
				string.format(WHERE[source], name or "?"),
				gradient,
				NO_STATS[source]
			)
		)
	end
	local ground, steps = colour.build(resolved)

	-- One context table per column, reused across rows. main.lua rebinds
	-- `stats` and `width` whenever the folder being drawn changes, not per row.
	--
	-- A row with no value to place draws the ramp's low end rather than the
	-- ground beneath it. The ground is where a `bold` or a `bg` lives and may
	-- carry no colour of its own at all, so falling back to it would leave a
	-- directory in `size` uncoloured beside files that are not.
	--
	-- `fg_written` is whether any layer put an `fg` there, `false` included: a
	-- spec that turned the colour off has said something about it, and a column
	-- that paints its own characters -- `permissions` -- steps aside for that
	-- as it does for a colour. What was written beside the `fg` needs no field
	-- of its own: it is in `style` and in every step, and `cell` puts a Line's
	-- style under its spans.
	-- What a column reads off `ctx.opts`: the options it declared, and nothing
	-- else that happens to be written beside them. Read through `pick`, which
	-- is the one place that knows the spec wins and that `false` is a value, so
	-- a declared option layers the way every shared key does and a definition
	-- can default one. A column that declared none gets an empty table rather
	-- than nil, so a `ctx.opts.anything` reads as nothing written.
	local options = {}
	for _, key in ipairs(def.options or EMPTY) do
		options[key] = pick(key)
	end

	-- Kept on the record rather than left in the closures below, because the
	-- one caller that has to know is `main.lua`, and `steps` is a local here.
	col.ramped = steps ~= nil

	local ctx = {
		style = steps and steps[1] or ground,
		fg_written = from.fg ~= nil,
		opts = options,
		stats = nil,
		width = col.fixed,
	}
	col.ctx = ctx

	--- Where `value` sits between the extremes of the current listing, 0 to 1.
	--- Returns nil when there is nothing to normalise against, which makes
	--- `ctx.style_at` fall back to the column's own style.
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

	--- The style for a position on the column's ramp, or the column's own
	--- style when there is no ramp and when there is nothing to place.
	---
	--- Two closures rather than one branch inside one, because this runs for
	--- every visible row on every frame and most columns have no ramp at all.
	--- The steps are already a list of finished styles, so a row that does
	--- have one costs an arithmetic and an array index.
	if steps then
		local n = #steps
		local last = n - 1
		function ctx.style_at(r)
			if r == nil then
				return ctx.style
			end
			-- `ratio` clamps, but `style_at` is public and a column may hand it
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
			return steps[i]
		end
	else
		function ctx.style_at(_) return ctx.style end
	end

	return col
end

--- What a `stats` has to come back with for a ramp to have anything to place a
--- row against: the extremes of the listing it was handed.
---
--- Exported because two files ask it and only one of them may answer. `bind`
--- below is what actually decides whether the ramp gets its endpoints, and
--- `main.lua` reports the column that did not supply them -- so if the two
--- spelled the test separately, a later change to the shape would leave the
--- report disagreeing with the binder, which is the silent failure the report
--- exists to end.
---
--- Where the report is raised is a different question, and it is `main.lua`'s:
--- this function is handed a `stats` and cannot tell one that came back wrong
--- from a column that has none, while the call site knows whether it called a
--- `stats` at all.
---
--- Only a ramped column is held to this. A `stats` is also how a column
--- derives a width or carries anything its own `render` reads off `ctx.stats`,
--- and a column using it that way owes nobody a `min` and a `max`.
---
--- Numbers, not merely present, and that is the half a presence test gets
--- wrong. `bind` just below does arithmetic on both the moment this answers
--- true -- `math.log(st.min + 1)` under `scale = "log"`, and `ctx.ratio`
--- subtracts them on every row whichever scale it is -- and none of that is
--- contained: `bind` is supaline's own code, called from the folder pass
--- rather than through the `pcall` a column's own functions go under. So a
--- `stats` handing back `{ min = "a", max = "z" }` would pass a test for
--- presence and then raise from inside Yazi's redraw, which costs the whole
--- screen rather than the column. `broke` in `main.lua` carries that
--- measurement.
---@param st any
---@return boolean
function M.has_extremes(st) return type(st) == "table" and type(st.min) == "number" and type(st.max) == "number" end

--- Bind one folder's precomputed statistics and width onto a column, and
--- prepare whatever `ctx.ratio` needs so that no work is repeated per row.
---@param col supaline.Column
---@param entry supaline.Entry
function M.bind(col, entry)
	local ctx = col.ctx --[[@as supaline.Scaled]]
	ctx.stats = entry.stats
	ctx.width = entry.width or col.fixed

	local st = entry.stats
	if not M.has_extremes(st) then
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
		local padded = col.align == "left" and ui.Line { line, pad } or ui.Line { pad, line }
		-- Styled a second time, around the pad. The string path pads in `fit`
		-- and styles what came back, so its spare cells are inside the style
		-- for free; here the pad cannot be built until the line has been
		-- measured, which is after `line` was styled. A Line's style sits
		-- under its spans, so this reaches the bare pad and leaves both the
		-- text and whatever the render styled its own spans with.
		--
		-- Applying one style twice is safe where applying one *span* twice is
		-- not: `ctx.style` is reused on every row of every column already, by
		-- the string path a few lines above.
		return style and padded:style(style) or padded
	end
	return line
end

--- The effective width of a column for one folder, for the two shapes that
--- derive it from the listing rather than stating it outright.
---
--- A `width` function that comes back with something that is not a count of
--- cells is **returned** as a refusal rather than raised as one, and that is
--- the only thing in this file that answers a mistake by returning. The
--- reason is the caller: this runs inside a render pass, and `main.lua` calls
--- it under `pcall` because a column's own code can raise anything from here
--- and an error under a render blanks Yazi's whole screen. A refusal raised
--- into that wrapper comes back out of it indistinguishable from the
--- reader's function throwing, and would be worded as one -- "column `x`
--- threw from its `width`" for a function that threw nothing and returned
--- `0`. Two different mistakes, one sentence, and the more common of the two
--- described wrongly.
---
--- Narrowing the `pcall` to `col.width_of(stats)` would sort the two out as
--- well, and is the wrong half to take: it puts this refusal back on the path
--- that takes the screen down.
---
--- A width of nil with no reason beside it is not a refusal. A column that
--- states no width at all has none to resolve, and that is what comes back.
---@param col supaline.Column
---@param files supaline.File[]
---@param stats any
---@return integer? # the width, or nil for a column that states none
---@return string? # why the `width` function's return was unusable, if it was
function M.resolve_width(col, files, stats)
	if col.width_of then
		local w = col.width_of(stats)
		local cells = cells_of(w)
		if cells == nil or cells < 1 then
			-- Taking it would leave the column with no width at all: no padding,
			-- no truncation, and a cell free to push into the file name.
			--
			-- Held to what a stated `width` is held to, and not because symmetry
			-- is tidy: a function returning 0 empties the column exactly as
			-- `width = 0` did, and closing one door and not the other leaves the
			-- same blank column reachable by the spelling nobody checked. What
			-- differs is only how the two are said -- a stated width is refused
			-- in `setup`, which stops Yazi before anything draws, and this one
			-- cannot be known until the folder is being rendered.
			return nil,
				string.format(
					"supaline: the `width` function of column `%s` returned %s; it must return a whole "
						.. "number of cells, 1 or more",
					col.name or "?",
					as_written(w)
				)
		end
		return cap(cells, col.max_width)
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
