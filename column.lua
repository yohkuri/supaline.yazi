--- @since 26.9.1
--- Column definitions, the registry that holds them, and the plan one use of a
--- column compiles to. Nothing here calls a function a column wrote but a
--- `validate`, which is configuration: what it refuses, `setup` refuses.
---
--- There are two tables a column is written as. A **definition** says what a
--- column draws: the table `column(name, def)` registers, or one written
--- inline in a linemode. A **use** names a registered one at `[1]` and may
--- override any of its keys. Every entry of a linemode is one of the two --
--- `"size"` is `{ "size" }` and `fn` is `{ render = fn }` -- and an inline
--- definition compiles as a definition with no use.
local schema = require(".schema")
local style = require(".style")

---@class supaline.ColumnModule
local M = {}

---@alias supaline.Render fun(file: supaline.File, ctx: supaline.Ctx): any, any?

--- Every key a column accepts, on a definition and on a use alike. This is the
--- column's user-facing surface; what a user writes wrong in it is `setup`'s
--- to refuse at run time, since no check here ever sees their `init.lua`.
---@class supaline.ColumnOpts
---@field render supaline.Render?
---@field stats fun(files: supaline.File[]): table?|nil
---@field refresh function? run at `setup`, after every theme that resolves, and on `cd`
---@field style supaline.StyleSpec?
---@field align "left"|"right"|nil
---@field overflow "ellipsis"|"clip"|"grow"|nil
---@field max_width integer?
---@field separator string|supaline.SepSpec|false|nil a separator of this column's own, `false` for none
---@field width number|"auto"|(fun(stats: any): number?)|nil a positive whole number of cells
---@field scale "linear"|"log"|nil
--- The names of the options this column reads off `ctx.opts`, beyond the keys
--- every column takes. A definition writes it; a use is checked against it.
---@field options string[]?
--- A check per declared option, asked about each value of it written: nil
--- takes the value, and a string is what is wrong with it.
---@field validate table<string, fun(value: any): string?>?
--- The name an inline definition gives itself, which its theme layer is
--- looked up by. `register` names the column it is handed.
---@field name string?

--- A registered column: the options above, with the one field a column
--- cannot do without. No `fetch`: a `ya.sync` block written outside
--- `main.lua` binds to a different state table and fails silently.
---@class supaline.ColumnDef : supaline.ColumnOpts
---@field render supaline.Render

--- A use written as a table: `[1]` names a registered column, and everything
--- else is that column's options.
---@class supaline.ColumnEntry : supaline.ColumnOpts
---@field [1] string?

--- One entry of a linemode, in whichever of the four shapes it was written.
---@alias supaline.ColumnSpec string|supaline.Render|supaline.ColumnEntry

--- How a column's width is decided: one of four ways, exactly.
---@class supaline.Width
---@field kind "natural"|"fixed"|"auto"|"computed"
---@field value integer? fixed, already capped
---@field compute fun(stats: any): number?|nil

---@class supaline.ColumnPlan
---@field name string?
---@field align "left"|"right"
---@field overflow "ellipsis"|"clip"|"grow"
---@field max_width integer?
---@field width supaline.Width
---@field scale "linear"|"log"
---@field render supaline.Render
---@field stats fun(files: supaline.File[]): table?|nil
---@field refresh function?
---@field options table<string, any> the declared options, and nothing else
---@field separator supaline.Sep|false|nil the column's own, `false` for none
---@field slot supaline.Slot the definition's style, the theme's and the use's

--- What compiling one column needs from `setup`.
---@class supaline.Cfg
---@field scale "linear"|"log"|nil
---@field lightness supaline.LightnessRanges

---@class supaline.Registry
---@field register fun(name: string, def: supaline.ColumnDef)
---@field open fun(cfg: supaline.Cfg): supaline.Catalogue

--- The registry as one `setup` reads it, with the options that `setup` applies
--- to every column it compiles.
---@class supaline.Catalogue
---@field compile fun(spec: supaline.ColumnSpec, at: supaline.Path): supaline.ColumnPlan

--- A definition, parsed.
---@class supaline.Definition
---@field at supaline.Path where it was written
---@field name string?
---@field fields table<string, any> each key it wrote, parsed; `style` is left for `compile`
---@field options string[]? the names it declared
---@field validate table<string, function>? its checks, by the option each one checks

---@type supaline.Parser
local function width(value, at)
	if value == "auto" then
		return { kind = "auto" }
	elseif type(value) == "function" then
		return { kind = "computed", compute = value }
	elseif type(value) == "number" then
		return { kind = "fixed", value = schema.cells(value, at) }
	end
	at:refuse('must be a number of cells, "auto", or a function, got %s', schema.as_written(value))
end

---@type supaline.Parser
local function separator(value, at)
	if value == false then
		return false
	end
	return style.separator(value, at)
end

-- The keys every column takes. `style` is read by `compile` rather than here,
-- because a gradient in it resolves against the lightness ranges `setup`
-- defines, which a definition registered before `setup` cannot know.
local COMMON = {
	align = schema.enum { "left", "right" },
	max_width = schema.cells,
	overflow = schema.enum { "ellipsis", "clip", "grow" },
	refresh = schema.fn,
	render = schema.fn,
	scale = schema.enum { "linear", "log" },
	separator = separator,
	stats = schema.fn,
	style = schema.any,
	width = width,
}

local COMMON_LIST = schema.key_list(schema.sorted_keys(COMMON))

-- The keys only a definition writes.
local DEFINITION_KEYS = { name = true, options = true, validate = true }

-- What a stray key most likely meant. Each is a name the plugin reads,
-- written where it is not read.
local MEANT = {
	fetch = "`fetch` is supaline's own rather than a column's: a column that needs asynchronous "
		.. "state has to be built into supaline itself, because a `ya.sync` block written anywhere "
		.. "else binds to a different state table and then fails silently",
	options = "`options` goes on the definition, which is where a column says what it reads; a "
		.. "use of that column can write one of the names it declared, and cannot add to them",
	["1"] = "`[1]` is where a spec names the column it uses, and holds nothing else; a definition "
		.. "writes its `render` under that name, and beside one `[1]` is read by nobody",
	name = "a column is named by the `column` call that registers it, by the `[1]` a spec names "
		.. "it with, or by a `name` written beside an inline `render`; anywhere else it is read by nobody",
	validate = "`validate` goes on the definition, beside the `options` it checks; the values a use "
		.. "writes are checked by it, and a use cannot add to it",
}

-- What a column may be called is `theme.toml`'s rule: its theme layer is the
-- `[supaline]` field called after it. Measured on 26.9.1, Yazi takes 1 to 20
-- characters of lowercase letters, digits and `_` -- looser than its own
-- "snake-case" message, since `_x`, `x_` and `2x` all parse -- and answers
-- anything else by discarding the whole of `theme.toml`. `probes.md` has it.
-- Written out rather than asked: the rule is applied while Yazi parses the
-- file, before any plugin code runs, so there is nothing to ask the way
-- `paint.colour` asks Yazi's colour parser.
local NAME = "^[a-z0-9_]+$"
local NAME_MAX = 20

---@param name any
---@param at supaline.Path
---@return string
local function column_name(name, at)
	if type(name) ~= "string" or not name:find(NAME) or #name > NAME_MAX then
		at:refuse(
			"`%s` cannot be a column name. A column's theme layer is the `[supaline]` field called after "
				.. "it, and Yazi takes a field name of 1 to %d characters from lowercase letters, digits "
				.. "and `_` -- a name it refuses takes the whole of `theme.toml` down with it. Call the "
				.. "column something else and name it that",
			tostring(name),
			NAME_MAX
		)
	end
	return name
end

--- The options a definition declares, as a list of names. Its shape is asked
--- of `schema.shape` as well as walked: `ipairs` alone would stop at a gap and
--- leave every name past it declared, ignored, and refused at the use site.
---@param own any
---@param at supaline.Path
---@return string[]?
local function options_of(own, at)
	if own == nil then
		return nil
	end
	local function refuse(got)
		at:refuse(
			'must be the list of names this column reads off `ctx.opts`, as `options = { "format" }`, '
				.. "got %s -- it is what lets one of them be refused when it is misspelled",
			got
		)
	end
	if type(own) ~= "table" then
		refuse("a " .. type(own))
	elseif next(own) == nil then
		refuse("an empty list")
	end
	local out = {}
	for i, key in ipairs(own) do
		if type(key) ~= "string" then
			refuse("a list holding a " .. type(key))
		elseif COMMON[key] or DEFINITION_KEYS[key] then
			refuse(string.format("a list naming `%s`, which every column takes", key))
		elseif MEANT[key] then
			-- Declaring one would switch off the only place that says why a
			-- column cannot own it.
			refuse(string.format("a list naming `%s`, which supaline answers for itself", key))
		end
		out[i] = key
	end
	local others, dense = schema.shape(own)
	if #others > 0 or not dense then
		refuse("a table with a gap in it, or with keys of its own")
	end
	return out
end

--- One check: handed a value, and saying what is wrong with it. Not
--- `schema.fn`, whose message is about a function called while drawing.
---@type supaline.Parser
local function check(value, at)
	if type(value) ~= "function" then
		at:refuse(
			"must be a function, handed a value and returning nil for one it takes or a string saying "
				.. "what is wrong with it, got %s",
			schema.as_written(value)
		)
	end
	return value
end

--- The checks a definition writes, by the option each one checks. Keyed
--- rather than one function over every option, so a value that fails is
--- refused at the path it was written at -- the use's, or the definition's own
--- default -- rather than at a use that may never have written it.
---@param own any
---@param options string[]?
---@param at supaline.Path
---@return table<string, function>?
local function validators_of(own, options, at)
	if own == nil then
		return nil
	elseif type(own) ~= "table" or next(own) == nil then
		at:refuse(
			"must be a table of checks by the option each one checks, as "
				.. "`validate = { format = function(value) ... end }`, got %s",
			type(own) == "table" and "an empty table" or schema.as_written(own)
		)
	end
	local fields = {}
	for _, key in ipairs(options or {}) do
		fields[key] = check
	end
	local help = options
			and string.format("It checks only the options this column declares in `options`: %s", schema.quoted(options))
		or "This column declares no `options`, so there is nothing for it to check"
	return schema.record(fields, "`validate`", help)(own, at)
end

--- The parser for one declared option: the value as written, asked of the
--- definition's check on it first when there is one. A check that throws is
--- refused rather than contained, the way a `style` function's throw is,
--- because `setup` can still say so and nothing has drawn yet.
---
--- The second value is read too, because `nil, reason` is how Lua says no:
--- taken by its first value alone, it would let through every value it means
--- to refuse. An empty string is a refusal that says nothing, and is refused
--- as one.
---@param own function?
---@return supaline.Parser
local function option(own)
	if not own then
		return schema.any
	end
	return function(value, at)
		local ok, reason, more = pcall(own, value)
		if not ok then
			at:refuse("the column's check on it raised: %s", tostring(reason))
		elseif type(reason) == "string" and reason ~= "" then
			at:refuse("%s", reason)
		elseif reason ~= nil or more ~= nil then
			local said = reason == nil and "nil and then " .. schema.as_written(more) or schema.as_written(reason)
			at:refuse(
				"the column's check on it returned %s; a check returns nil alone for a value it takes, or "
					.. "a string saying what is wrong with one",
				said
			)
		end
		return value
	end
end

--- A record parser over the shared keys, `extra`, and the options declared.
---@param extra table<any, supaline.Parser>
---@param options string[]?
---@param validate table<string, function>?
---@param draws string what the message calls the key that says what to draw
---@return fun(t: table, at: supaline.Path): table
local function column_record(extra, options, validate, draws)
	local fields = {}
	for k, parse in pairs(COMMON) do
		fields[k] = parse
	end
	for k, parse in pairs(extra) do
		fields[k] = parse
	end
	for _, k in ipairs(options or {}) do
		fields[k] = option(validate and validate[k])
	end
	local also = options and string.format(". That column also takes %s", schema.quoted(options)) or ""
	local help =
		string.format('A column takes %s, beside %s -- `{ "size", width = 8, style = "cyan" }`%s', COMMON_LIST, draws, also)
	return schema.record(fields, "column", help, MEANT)
end

local DRAWS_RENDER = "the `render` that says what it draws"
local DRAWS_NAME = "the name at `[1]` that says which column it is"

-- What a linemode's entry may be, for one that is none of them.
local SHAPES = "must be a name, a function, or a table with `render`"

--- Read a definition. `render` is the one key a definition cannot leave out,
--- and asked for before the rest so that a table naming nothing is told what
--- it lacks rather than which of its keys is stray.
---@param t any
---@param at supaline.Path
---@param name string? the name `register` gave it
---@return supaline.Definition
local function definition(t, at, name)
	if type(t) ~= "table" or t.render == nil then
		at:refuse(name and "needs a `render` function, which is what says what the column draws" or SHAPES)
	end
	local options = options_of(t.options, at:key("options"))
	local validate = validators_of(t.validate, options, at:key("validate"))
	local extra = { options = schema.any, validate = schema.any }
	if not name then
		extra.name = column_name
	end
	local fields = column_record(extra, options, validate, DRAWS_RENDER)(t, at)
	return { at = at, name = name or fields.name, fields = fields, options = options, validate = validate }
end

--- Where a column's theme layer is written: its `[supaline]` field, spelled
--- the way TOML spells it -- a column name is always a bare key there. Not
--- `theme.toml`, since a flavor may supply the section instead.
---@param name string
---@return supaline.Path
local function theme_at(name) return schema.path("theme [supaline]." .. name) end

--- A column with no `stats` refuses a gradient. Refused on the merged
--- result, since a nearer flat colour may replace a farther gradient: without
--- `stats` every row's ratio is nil, and the ramp could only ever draw its
--- low end.
---@param resolved supaline.Layer
---@param from supaline.Writers
local function no_gradient(resolved, from)
	local key = style.gradient_in(resolved)
	if not key then
		return
	end
	local writer = from[key]
	writer.at:refuse(
		"`%s` is a gradient, but this column has no `stats`, so there are no extremes to place a value "
			.. "between and the ramp could only ever draw its low end. %s",
		key,
		writer.theme and "Write a flat colour there instead"
			or "Give the column a `stats` function, or write a flat colour there instead"
	)
end

--- One use of a definition, as a plan. Each key comes from the use when it
--- wrote one and from the definition otherwise -- `false` included, which is
--- what a `separator` is written as on purpose -- except `scale`: `setup`'s
--- outranks a registered definition's, or the plugin-wide option could not
--- reach `size`. An inline definition has no use: it is written where a use
--- is, and outranks `setup` the way a use does.
---@param def supaline.Definition
---@param use table? nil for an inline definition
---@param at supaline.Path where the use was written
---@param cfg supaline.Cfg
---@param read supaline.Reader what a style written for a column means under this `setup`'s ranges
---@return supaline.ColumnPlan
local function merge(def, use, at, cfg, read)
	local fields = def.fields
	---@return any
	local function pick(key)
		local v = use and use[key]
		if v == nil then
			v = fields[key]
		end
		return v
	end

	local max_width, stats = pick("max_width"), pick("stats")
	local width = pick("width") or { kind = "natural" } ---@type supaline.Width
	if width.kind == "fixed" and max_width and width.value > max_width then
		width = { kind = "fixed", value = max_width }
	end

	-- Three writers, farthest first: the definition's default, the theme's
	-- field, and the use's own. An inline definition is one table and one
	-- writer, so it writes the definition's layer and the theme stays nearer.
	local sources = {}
	sources[#sources + 1] = style.source(fields.style, def.at:key("style"), read)
	if def.name then
		sources[#sources + 1] = { at = theme_at(def.name), theme = def.name }
	end
	if use then
		sources[#sources + 1] = style.source(use.style, at:key("style"), read)
	end

	---@type supaline.ColumnPlan
	local col = {
		name = def.name,
		align = pick("align") or "right",
		overflow = pick("overflow") or "ellipsis",
		max_width = max_width,
		width = width,
		render = pick("render"),
		stats = stats,
		refresh = pick("refresh"),
		separator = pick("separator"),
		-- Timestamps sit within a few years of each other, and a log scale
		-- over those spreads nothing, so linear is what nobody asked for.
		scale = (use or fields).scale or cfg.scale or fields.scale or "linear",
		options = {},
		slot = { sources = sources, read = read, check = stats == nil and no_gradient or nil },
	}

	for _, key in ipairs(def.options or {}) do
		col.options[key] = pick(key)
	end
	return col
end

--- A registry of definitions. A registry is explicit, so two registries never
--- share a column, and nothing registers itself by being required.
---
--- A definition is read when it is registered, so a mistake in it is refused
--- at the call that wrote it, and read again by every `setup`: editing the
--- table in place takes effect on the next one, as the README promises.
---@return supaline.Registry
function M.new_registry()
	local definitions = {} ---@type table<string, { t: table, at: supaline.Path }>

	local function register(name, def)
		local at =
			schema.path(string.format("column(%s)", type(name) == "string" and string.format("%q", name) or tostring(name)))
		column_name(name, at)
		definition(def, at, name)
		definitions[name] = { t = def, at = at }
	end

	--- The registry as one `setup` reads it. Each definition is read at most
	--- once by it, and only when a linemode names it, so one no linemode uses
	--- is not read again at all.
	---@param cfg supaline.Cfg
	---@return supaline.Catalogue
	local function open(cfg)
		-- By registration rather than by name, so a column registered again
		-- after this was opened is not answered from here.
		local read = {} ---@type table<table, { def: supaline.Definition, use: fun(t: table, at: supaline.Path): table }>
		local reader = style.reader(cfg.lightness)

		---@param registered { t: table, at: supaline.Path }
		---@param name string
		local function lookup(registered, name)
			local one = read[registered]
			if not one then
				local def = definition(registered.t, registered.at, name)
				one = { def = def, use = column_record({ [1] = schema.any }, def.options, def.validate, DRAWS_NAME) }
				read[registered] = one
			end
			return one
		end

		--- Turn one entry of a linemode into a plan. The entry is read, never
		--- written to, and nothing it holds is called but a `validate`.
		---@param spec any
		---@param at supaline.Path
		---@return supaline.ColumnPlan
		local function compile(spec, at)
			if type(spec) == "string" then
				spec = { spec }
			elseif type(spec) == "function" then
				spec = { render = spec }
			elseif type(spec) ~= "table" then
				at:refuse("%s, got a %s", SHAPES, type(spec))
			end

			local def, use
			if type(spec[1]) == "string" then
				local registered = definitions[spec[1]]
				if not registered then
					at:refuse("unknown column `%s`", spec[1])
				end
				local one = lookup(registered, spec[1])
				def, use = one.def, one.use(spec, at)
			elseif type(spec[1]) == "function" then
				at:key(1):refuse(
					"a column's `render` goes under `render`, not at `[1]`: write `{ render = fn, width = 6 }`. "
						.. "`[1]` is where a spec names the column it uses, and a function is not a name"
				)
			elseif spec[1] ~= nil and spec.render == nil then
				at:refuse(SHAPES)
			else
				def = definition(spec, at, nil)
			end
			return merge(def, use, at, cfg, reader)
		end

		return { compile = compile }
	end

	return { register = register, open = open }
end

return M
