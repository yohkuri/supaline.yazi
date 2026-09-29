--- @since 26.9.1
--- What `setup` is handed, read once into a plan: which columns each pane of
--- each linemode draws, and the separator before each of them. Nothing here
--- reads the theme or calls a function the configuration wrote.
local paint = require(".paint")
local schema = require(".schema")
local style = require(".style")

---@class supaline.ConfigModule
local M = {}

local PANES = { "current", "parent", "preview" }

--- One linemode: the columns in order, or a list of columns under each pane
--- that draws something, and the one option that belongs to the linemode.
---@class supaline.LinemodeSpec
---@field [integer] supaline.ColumnSpec
---@field current supaline.ColumnSpec[]? what the current pane draws, instead of the list above
---@field parent supaline.ColumnSpec[]? what the parent pane draws; nothing by default
---@field preview supaline.ColumnSpec[]? what the preview pane draws; nothing by default
---@field separator string|supaline.SepSpec|nil overrides the plugin-wide one

--- The table `setup` is handed. `linemodes` is optional here only because
--- `setup` takes a dot call as well as a colon call, and has to look at what
--- arrived before it can say which one it was.
---@class supaline.Opts
---@field linemodes table<string, supaline.LinemodeSpec>?
---@field separator string|supaline.SepSpec|nil
---@field order integer?
---@field scale "linear"|"log"|nil
---@field band supaline.Bands? the bands a `<->` may name, by name

--- One column in one pane, and what is drawn before it.
---@class supaline.Cell
---@field column supaline.ColumnPlan
---@field sep supaline.Sep? nil for the first column, and for one that wrote `separator = false`

---@class supaline.ModePlan
---@field name string
---@field panes table<string, supaline.Cell[]> only the panes that draw something
---@field outer boolean whether a pane besides the current one draws

---@class supaline.Plan
---@field order integer where the parent/preview child sits among `Linemode`'s
---@field modes table<string, supaline.ModePlan>
---@field columns supaline.ColumnPlan[] every column once, a list shared by two panes compiled once
---@field slots supaline.Slot[] every column's slot and every styled separator's, drawn or not, once
---@field outer boolean

local SETUP_FIELDS = {
	band = paint.bands,
	linemodes = schema.any,
	order = schema.whole,
	scale = schema.enum { "linear", "log" },
	separator = style.separator,
}

local SETUP_MEANT = {
	linemode = "`linemodes` is the spelling, and it is a table of them keyed by the name each one is switched to",
	columns = 'columns go inside a linemode -- `linemodes = { detail = { "size", "mtime" } }` -- rather '
		.. "than beside the table of them",
}

local SETUP_HELP = "`setup` takes " .. schema.key_list(schema.sorted_keys(SETUP_FIELDS))
local SETUP = schema.record(SETUP_FIELDS, "setup", SETUP_HELP, SETUP_MEANT)

-- What every refusal about the shape of a linemode says it could have been.
local LINEMODE = 'A linemode is a list of columns, drawn in the current pane -- `{ "size", "mtime" }` -- '
	.. 'or a list of columns under each pane it draws in -- `{ current = { "size" }, parent = { "count" } }`'

-- What a linemode takes besides its columns: a pane's name, or its one option.
local OWN = { table.unpack(PANES) }
OWN[#OWN + 1] = "separator"
local IS_OWN = {}
for _, key in ipairs(OWN) do
	IS_OWN[key] = true
end

local function linemode_key(key) return type(key) == "number" or IS_OWN[key] end

--- What each pane of a linemode draws, with a pane that draws nothing absent.
--- A bare list is the current pane's, which is all Yazi itself draws in.
--- Naming a pane gives it a list of its own, and is then the only place
--- columns may be written: one left beside the pane keys would draw nowhere.
---@param spec table
---@param at supaline.Path
---@return table<string, table>
local function lists_of(spec, at)
	local lists = {}
	for _, pane in ipairs(PANES) do
		local list, where = spec[pane], at:key(pane)
		if list ~= nil then
			if type(list) ~= "table" then
				where:refuse("must be a list of columns, got a %s. %s", type(list), LINEMODE)
			elseif next(list) == nil then
				-- Leaving the pane out says exactly this, in one place.
				where:refuse("is an empty list -- leave the pane out instead. %s", LINEMODE)
			end
			local others, dense = schema.shape(list)
			if #others > 0 then
				where:refuse(
					"takes a list of columns and nothing else, and was given %s beside them -- an option "
						.. "goes on the linemode itself",
					schema.quoted(others)
				)
			elseif not dense then
				where:refuse("has a gap in its numbering, and nothing past a gap is drawn. %s", LINEMODE)
			end
			lists[pane] = list
		end
	end

	schema.sweep(spec, at, linemode_key, "linemode", "Besides its columns a linemode takes " .. schema.key_list(OWN))

	local _, dense, numbered = schema.shape(spec)
	if next(lists) == nil then
		-- An empty list draws nothing in the current pane, which is a thing
		-- to ask for; a gap in one that has entries is not.
		if not dense then
			at:refuse("has a gap in its numbering, and nothing past a gap is drawn. %s", LINEMODE)
		end
		return { current = spec }
	end
	if numbered > 0 then
		at:refuse(
			"names a pane, so its columns go under that pane's own name, and the ones beside the pane "
				.. "keys would be drawn nowhere; move them under a pane"
		)
	end
	return lists
end

---@param opts any
---@param registry supaline.Registry
---@param is_yazis fun(name: string): boolean whether a name would replace part of Yazi's `Linemode`
---@return supaline.Plan
function M.compile(opts, registry, is_yazis)
	local root = schema.path("setup")
	if type(opts) ~= "table" then
		root:refuse(
			'must be handed a table of options, as `setup { linemodes = { detail = { "size", "mtime" } } }`, got %s',
			schema.as_written(opts)
		)
	end
	local o = SETUP(opts, root)
	local columns = registry.open { scale = o.scale, band = o.band or {} }
	local wide = o.separator or { text = " " }

	local linemodes, at = o.linemodes, root:key("linemodes")
	if linemodes ~= nil and type(linemodes) ~= "table" then
		at:refuse("must be a table of linemodes by name, got a %s", type(linemodes))
	elseif linemodes == nil or next(linemodes) == nil then
		at:refuse("names no linemode, so there is nothing to render")
	end
	---@cast linemodes table

	local names = schema.sorted_keys(linemodes)
	for _, name in ipairs(names) do
		-- Yazi's limit is 1 to 20 characters, not bytes; a name that is not
		-- valid UTF-8 is Yazi's to refuse.
		local len = type(name) == "string" and (utf8.len(name) or #name) or nil
		if type(name) == "number" then
			-- The one mistake this is likely to be: the columns written where
			-- the table of linemodes goes, so the key is a position.
			at:refuse(
				'is a list, and a linemode is found by its name: write `linemodes = { detail = { "size", "mtime" } }`, '
					.. "keyed by the name each one is switched to"
			)
		elseif not len or len < 1 or len > 20 then
			at:refuse("`%s` cannot be a linemode name: Yazi takes one of 1 to 20 characters", tostring(name))
		elseif is_yazis(name) then
			at:refuse(
				"`%s` is part of Yazi's `Linemode` component; a linemode of that name would replace it. "
					.. "Overriding a built-in linemode (`size`, `mtime`, ...) is fine, replacing the component is not",
				name
			)
		elseif type(linemodes[name]) ~= "table" then
			at:key(name):refuse("must be a table, got a %s. %s", type(linemodes[name]), LINEMODE)
		end
	end

	---@type supaline.Plan
	local plan = { order = o.order or 1400, modes = {}, columns = {}, slots = {}, outer = false }
	-- Every slot is resolved on every build, drawn or not -- the plugin-wide
	-- separator under a linemode of one column included -- so what a function
	-- written for one returns is refused while `setup` can still say so. The
	-- columns' come first, so of two refusals the column's is the one said.
	local seps, seen = {}, {}
	---@param sep supaline.Sep|false|nil
	local function keep(sep)
		local slot = sep and sep.slot
		if slot and not seen[slot] then
			seen[slot] = true
			seps[#seps + 1] = slot
		end
	end
	keep(wide)
	for _, name in ipairs(names) do
		local spec, where = linemodes[name], at:key(name)
		local lists = lists_of(spec, where)
		local own = spec.separator ~= nil and style.separator(spec.separator, where:key("separator")) or wide
		keep(own)

		local built, panes = {}, {}
		for _, pane in ipairs(PANES) do
			local list = lists[pane]
			local cells = list and built[list]
			if list and not cells then
				local base = list == spec and where or where:key(pane)
				-- A separator goes before its column, so one the spec wrote on
				-- the first is drawn by nobody. A registered column's own may
				-- head a list: it is read at every use, and refusing it would
				-- stop that column being written first anywhere.
				local first = list[1]
				if type(first) == "table" and first.separator then
					base:key(1):key("separator"):refuse(
						"is drawn by nobody: a separator goes before its column, and the first column has "
							.. "nothing before it. Write it on the column it should precede, or drop it -- "
							.. "`separator = false` is accepted there, since it asks for nothing and gets nothing"
					)
				end
				cells = {}
				for i, entry in ipairs(list) do
					local col = columns.compile(entry, base:key(i))
					plan.slots[#plan.slots + 1] = col.slot
					keep(col.separator)
					local sep = nil ---@type supaline.Sep?
					if i > 1 and col.separator ~= false then
						sep = col.separator or own
					end
					cells[i] = { column = col, sep = sep }
					plan.columns[#plan.columns + 1] = col
				end
				built[list] = cells
			end
			if cells and #cells > 0 then
				panes[pane] = cells
			end
		end
		local outer = panes.parent ~= nil or panes.preview ~= nil
		plan.outer = plan.outer or outer
		plan.modes[name] = { name = name, panes = panes, outer = outer }
	end
	table.move(seps, 1, #seps, #plan.slots + 1, plan.slots)
	return plan
end

return M
