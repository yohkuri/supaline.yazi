--- @since 26.9.1
--- Column definitions and their setup-lifetime plans. A registry is explicit;
--- compiling a use snapshots framework-owned inputs but never calls user code.
local diagnostics = require(".diagnostics")
local style = require(".style")
---@class supaline.ColumnModule
local M = {}

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

---@alias supaline.Render fun(file: supaline.File, ctx: supaline.Ctx): any, any?

--- A separator as it is written: the text first, the style beside it. A column
--- spec's own shape under the same key, so `{ " | ", style = ... }` reads the
--- way `{ "size", style = ... }` does and takes the same spellings -- all but
--- a gradient, which `style.flat` refuses: a separator is drawn between two
--- columns rather than on a file, so it has no value to place on one.
---@class supaline.SepSpec
---@field [1] string what to draw
---@field style supaline.StyleSpec?

--- Every option a column accepts. One set rather than two, because
--- `compile` reads the spec and the definition behind it through a single
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
--- layers `style.column` stacks, with the theme between them, and each key is
--- taken from the nearest layer that wrote it rather than the whole table
--- from the nearest that wrote any.
---@field style supaline.StyleSpec?
---@field align "left"|"right"|nil
---@field overflow "ellipsis"|"clip"|"grow"|nil
---@field max_width integer?
---@field separator string|supaline.SepSpec|false|nil a separator of this column's own, `false` for none
---@field width number|"auto"|(fun(stats: any): number?)|nil a positive whole number of cells
---@field scale "linear"|"log"|nil
--- The names of the options this column reads off `ctx.opts` beyond the keys
--- every column takes. A definition writes it; a spec is checked against it,
--- which is the whole of what it is for.
---@field options string[]?

--- A registered column, as `register` stores it: the options above, with the
--- one field a column cannot do without.
---
--- No `fetch`. A column that writes one is turned away by the key sweep,
--- because a `ya.sync` block written outside main.lua binds to a different
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
--- over -- by this field at check time and by `compile` at run time -- and
--- only the second of the two can say where to put it instead.
---@class supaline.ColumnEntry : supaline.ColumnOpts
---@field [1] string?

--- One entry of a linemode spec, in whichever of the four shapes it was
--- written. `compile` is where they collapse, and it decides between them by
--- `type`, which is what lets this union narrow at each branch.
---@alias supaline.ColumnSpec string|supaline.Render|supaline.ColumnEntry

--- A width policy selects exactly one way to determine the cell width.

---@class supaline.Width
---@field kind "natural"|"fixed"|"auto"|"computed"
---@field value integer? fixed, already capped
---@field compute fun(stats: any): number?|nil

---@class supaline.StyleSource
---@field source supaline.StyleWriter
---@field value supaline.StyleSpec?

---@class supaline.ColumnPlan
---@field name string?
---@field align "left"|"right"
---@field overflow "ellipsis"|"clip"|"grow"
---@field max_width integer?
---@field separator string|supaline.SepSpec|false|nil
---@field stats fun(files: supaline.File[]): table?|nil
---@field refresh function?
---@field render supaline.Render
---@field scale "linear"|"log"
---@field width supaline.Width
---@field needs_pass boolean
---@field options table<string, any>
---@field styles supaline.StyleSource[] definition, theme lookup, use-site override

---@class supaline.Registry
---@field register fun(name: string, def: supaline.ColumnDef)
---@field compile fun(spec: supaline.ColumnSpec, cfg: supaline.Cfg): supaline.ColumnPlan

-- The keys every column claims, whatever it draws. `[1]` is the registered
-- name and is claimed by the predicate below rather than
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
-- is one line, and writing that line is choosing between `true`, a set, and
-- the name of a type. The readers below want a key claimed or not claimed, so
-- a set and a type name both read as `true` to every one of them.
--
-- A type name is for a key whose value is *called* rather than read. There
-- are three, and two of them were taken on trust for as long as they existed:
-- `render` was checked on its way through `register` and again where
-- `compile` dispatches on it, and `stats` and `refresh` were checked
-- nowhere. What that cost is the mistake the sets exist to end, arriving a
-- stage later. `stats = 42` compiled, and surfaced at bind time as "column
-- `x` threw from its `stats`" -- naming a function the reader never wrote as
-- the thing that threw. `refresh = 42` compiled too, and raised out of
-- `install`, which runs after `setup` has committed: every linemode left
-- unregistered, which Yazi draws as literal text. Both are knowable while
-- `setup` runs, and that is where a refusal is loudest.
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
	refresh = "function",
	render = "function",
	scale = { "linear", "log" },
	separator = true,
	stats = "function",
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

--- A width as a usable number of cells, or nil for anything that is not one.
---
--- `type` is asked before `math.tointeger`, and that order is half the check:
--- measured on 5.5.1, `math.tointeger("3")` answers 3, so a `width` written as
--- the string `"3"` would otherwise pass as an integer. It also covers the
--- three numbers that are numbers and not counts -- `inf`, `-inf` and NaN all
--- answer nil.
---
--- The floor is the other half, and it belongs here rather than beside each
--- refusal. Every source of a width empties the column the same way with a 0
--- -- a stated `width`, a stated `max_width`, and what a `width` function
--- returns all reach the same blank row -- so a floor left at one call site is
--- a door the next source gets written past. What a 0 costs is said beside the
--- refusals, which is where it belongs.
---
--- One function because all three ask it, and both halves are the kind of
--- thing a later reader tidies away -- the ordering into
--- `math.tointeger(value)`, the floor into whichever caller looks like it
--- needed one. Each caller words its own refusal, which is the part that
--- differs; this is the part that must not.
---@param value any
---@return integer? # the width, or nil for anything that cannot be one
local function cells_of(value)
	local cells = type(value) == "number" and math.tointeger(value) or nil
	if cells == nil or cells < 1 then
		return nil
	end
	return cells
end

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
	if cells == nil then
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
		string.format(
			"supaline: `%s` %s must be %s, got %s",
			key,
			where,
			diagnostics.key_list(values, "or"),
			as_written(value)
		)
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

-- The keys above, in the order the message lists them. `key_list_of` sorts,
-- because `pairs` gives a set in whatever order the hash does and a message
-- that reorders itself between runs reads as a different message.
local COLUMN_KEY_LIST = diagnostics.key_list_of(COLUMN_KEYS)

-- And the ones carrying a constraint, sorted for a second reason on top of
-- that one: `compile` walks these in order, so a spec that got two of them
-- wrong names the same one first on every run.
local CHECKED_KEYS = {}
do
	for key, claim in pairs(COLUMN_KEYS) do
		if claim ~= true then
			CHECKED_KEYS[#CHECKED_KEYS + 1] = key
		end
	end
	table.sort(CHECKED_KEYS)
end

--- Hold `key` to whatever `COLUMN_KEYS` constrains it to: one of a set of
--- values, a type, or nothing at all.
---
--- One function, walked over every constrained key, so declaring the key is
--- the whole of enabling its check. The sets were three calls written out by
--- hand and the keys wanting a type had none at all, which is the shape a
--- check goes missing in -- a rule applied at each of the places that
--- remembered it is a rule the next place does without.
---
--- Nil is not a value and is allowed, for the reason `M.one_of` gives.
---@param key string
---@param value any
---@param where string the rest of the sentence after the key
local function constrained(key, value, where)
	local claim = COLUMN_KEYS[key]
	if value == nil or claim == true then
		return
	end
	if type(claim) == "table" then
		M.one_of(key --[[@as "align"|"overflow"|"scale"]], value, where)
		return
	end
	if type(value) == claim then
		return
	end
	error(
		string.format(
			"supaline: `%s` %s must be a %s, got %s -- it is called rather than read, so "
				.. "anything else is refused now, while `setup` can still say so, instead of "
				.. "surfacing at the first row as this column throwing from a `%s` nobody wrote",
			key,
			where,
			claim,
			as_written(value),
			key
		)
	)
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
--- Which of the three style layers this table's own `style` writes, under the
--- name `WHERE`, `FN_WHERE` and `NO_STATS` all key by. A table that is both
--- the definition and the only use of it writes the definition's layer.
---@field mine supaline.StyleWriter
--- Whether the same table also writes the spec's layer. True for a use of a
--- column defined elsewhere and false for the two shapes that are their own
--- definition -- reading one of those as both wrote its style into two layers
--- at once, which `layers_of` records the cost of.
---@field spec boolean
---@field claims fun(key: any): any the two above, for a column declaring no options. Truthy is
--- the whole of the answer: a shared key whose entry is its set of values answers the set.

--- One role. `claims` is built here rather than assigned over the table below,
--- so nothing can add a role and forget it -- which is also why every other
--- fact that turns on the role is a field here rather than a condition at the
--- place that wants it.
---@param keys table<any, true>
---@param draws string
---@param mine supaline.StyleWriter
---@param spec boolean
---@return supaline.RoleKeys
local function role_keys(keys, draws, mine, spec)
	-- The answer for a column that declares no options, which is most of them:
	-- one closure per role, built once, so the common case allocates nothing.
	return {
		keys = keys,
		draws = draws,
		mine = mine,
		spec = spec,
		claims = function(key) return COLUMN_KEYS[key] or keys[key] end,
	}
end

local DRAWS_RENDER = "the `render` that says what it draws"

---@type table<supaline.Role, supaline.RoleKeys>
local ROLES = {
	-- `register("size", { render = fn })`. The call names it, and what it
	-- states is the default every use of that column starts from.
	registered = role_keys({ options = true }, DRAWS_RENDER, "definition", false),
	-- `{ render = fn, name = "size" }`: the definition and the only use of it
	-- are one table, so both keys a definition writes are read right here. A
	-- bare `function` is this role too, with nothing beside the render. Its
	-- style is written once, in the list the reader is already looking at,
	-- which is why it gets a name of its own rather than the definition's.
	inline = role_keys({ name = true, options = true }, DRAWS_RENDER, "inline", false),
	-- `{ "size", width = 8 }`: a use of a definition written elsewhere, naming
	-- it at `[1]`. `name` and `options` are that definition's, and so is the
	-- far layer -- this is the one shape with a spec layer to write.
	use = role_keys({ [1] = true }, "the name at `[1]` that says which column it is", "definition", true),
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
	local unknown, _, subject, hints = diagnostics.unknown(t, claims_of(role, def), "column", COLUMN_MEANT)
	if not unknown then
		return
	end
	-- Off the definition whichever table was swept: what this column also takes
	-- is most worth saying to the use site, which is the one that cannot see
	-- the definition.
	local own = def.options
	error(string.format(
		COLUMN_UNKNOWN,
		name or "?",
		subject,
		COLUMN_KEY_LIST,
		ROLES[role].draws,
		-- In the order the definition declared them, so `diagnostics.quoted`
		-- rather than the sorted `listed` behind every other name list here.
		own and string.format(". That column also takes %s", diagnostics.quoted(own)) or "",
		hints
	))
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
--- the platform does not have -- which is the argument `style.lua` took when
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
--- `compile`, and the check sits on that local rather than on the branches
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
local function register(definitions, name, def)
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
	definitions[name] = def
end

--- A `stats` function over the extremes of the current listing, which is what
--- a gradient is stretched between and what `ctx.ratio` normalises against.
---
--- Shared by built-in and user-written ranged columns through the public
--- `extremes` helper, so both use the same filtering and range convention.
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

---@param value any
---@return any
function M.snapshot_separator(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, v in pairs(value) do
		copy[key] = v
	end
	copy.style = style.snapshot(value.style)
	return copy
end

local function cap(width, max)
	if width and max and width > max then
		return max
	end
	return width
end

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

--- Turn one entry into a plan, without theme resolution or folder state.
---@param definitions table<string, supaline.ColumnDef>
---@param spec supaline.ColumnSpec
---@param cfg supaline.Cfg
---@return supaline.ColumnPlan
local function compile(definitions, spec, cfg)
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
		def = definitions[name] or error(string.format("supaline: unknown column `%s`", name))
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

	local sep = M.snapshot_separator(pick("separator"))
	-- Refused before they are defaulted, which is the whole of the fix: the
	-- `or` that supplies the default is also what swallowed a wrong value, so a
	-- check written after it would have nothing left to look at.
	local of_col = string.format("of column `%s`", name or "?")

	-- Every key that carries a constraint, held to it in one pass. Which keys
	-- those are is `COLUMN_KEYS`'s to say and not this function's, which is
	-- the whole of the arrangement: a key is declared in one place and
	-- checked because it was declared, rather than checked wherever somebody
	-- remembered to write the call. `stats` and `refresh` were what that cost
	-- -- both called, neither checked -- while `align` was refused twice over.
	--
	-- `scale` is checked again below, on the resolved value. What this pass
	-- sees is what `pick` reads, the spec's and the definition's; `setup`'s is
	-- a fourth source and reaches the record without coming through here.
	for _, key in ipairs(CHECKED_KEYS) do
		constrained(key, pick(key), of_col)
	end

	-- Not `pick`, which is the one place that would be wrong. `pick` reads the
	-- spec and then the definition, and a definition's scale has to lose to a
	-- `scale` written in `setup` -- otherwise the plugin-wide option cannot
	-- reach `size`, the one built-in that states one and the one whose values
	-- span orders of magnitude. So: the spec, then what the user asked for
	-- plugin-wide, then the column's own, then linear.
	--
	-- Linear is the fallback because the columns with nothing to say about it
	-- are the timestamps, whose values sit within a few years of each other; a
	-- log scale over those spreads nothing.
	--
	-- An explicit nil test rather than `opts.scale or cfg.scale or def.scale`,
	-- for the reason `pick` gives above and with one more behind it. The `or`
	-- chain skips a `false` along with a nil, so `scale = false` would fall
	-- through to the next source and be defaulted -- past `M.one_of`, which is
	-- the one thing that was going to tell the reader `false` is not a scale.
	-- The whole of the fix this file made for the other keys was refusing a
	-- value before the `or` that supplies the default; the same `or` reaches
	-- this one twice.
	local scale = opts.scale
	if scale == nil then
		scale = cfg.scale
	end
	if scale == nil then
		scale = def.scale
	end

	local col = {
		name = name,
		-- Refused by the pass above rather than here, so what is left on this
		-- line is the default. Both halves of the original one-liner are still
		-- present and still in that order -- refuse, then default -- which is
		-- what the fix was; they sit a dozen lines apart now.
		align = pick("align") or "right",
		overflow = pick("overflow") or "ellipsis",
		max_width = whole_cells("max_width", pick("max_width"), of_col),
		separator = sep,
		stats = pick("stats"),
		refresh = pick("refresh"),
		render = opts.render or def.render,
		-- The resolved value rather than each of the three, because two of them
		-- have already been looked at: `cfg.scale` is `setup`'s own key and
		-- `setup` refuses it by that name, where the message can say `setup`
		-- rather than name whichever column happened to be normalised first.
		-- What is left for this call is the spec's and the definition's.
		scale = M.one_of("scale", scale, of_col) or "linear",
	}

	local width = pick("width")
	if width == "auto" then
		col.width = { kind = "auto" }
	elseif type(width) == "function" then
		col.width = { kind = "computed", compute = width }
	elseif type(width) == "number" then
		col.width = { kind = "fixed", value = cap(whole_cells("width", width, of_col), col.max_width) }
	elseif width == nil then
		col.width = { kind = "natural" }
	else
		error(string.format('supaline: `width` of column `%s` must be a number, "auto", or a function', name or "?"))
	end
	col.needs_pass = col.stats ~= nil or col.width.kind == "auto" or col.width.kind == "computed"
	col.options = {}
	for _, key in ipairs(def.options or EMPTY) do
		col.options[key] = pick(key)
	end
	local written
	if role == "use" then
		written = style.snapshot(opts.style)
	end
	col.styles = {
		{ source = ROLES[role].mine, value = style.snapshot(def.style) },
		{ source = "theme" },
		{ source = "spec", value = written },
	}
	return col
end

---@return supaline.Registry
function M.new_registry()
	local definitions = {} ---@type table<string, supaline.ColumnDef>
	return {
		register = function(name, def) register(definitions, name, def) end,
		compile = function(spec, cfg) return compile(definitions, spec, cfg) end,
	}
end

return M
