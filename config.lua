--- @since 26.9.1
--- Structural configuration compilation. Theme callbacks are left unevaluated.
local column = require(".column")
local diagnostics = require(".diagnostics")
local style = require(".style")
---@class supaline.ConfigModule
local M = {}
local PANES = { "current", "parent", "preview" }

--- What the user writes for one linemode: the columns in order, or a list of
--- columns under each pane that draws something, and the one option that
--- belongs to the linemode rather than to any column in it.
---
--- A pane is a key here rather than a value, so each of the three is a declared
--- field and `parent = 42` is refused by name. A key that is none of the four
--- names is past what the checker reaches into a table constructor, which is
--- what `OPTIONS` below is for.
---@class supaline.LinemodeSpec
---@field [integer] supaline.ColumnSpec
---@field current supaline.ColumnSpec[]? what the current pane draws, instead of the list above
---@field parent supaline.ColumnSpec[]? what the parent pane draws; nothing by default
---@field preview supaline.ColumnSpec[]? what the preview pane draws; nothing by default
---@field separator string|supaline.SepSpec|nil overrides the plugin-wide one

--- The table `setup` is handed. `linemodes` is the only field it cannot do
--- without and it is still optional here, because `setup` takes the dot call
--- as well as the colon call and has to look at what arrived before it can
--- say which one it was.
---@class supaline.Opts
---@field linemodes table<string, supaline.LinemodeSpec>?
---@field separator string|supaline.SepSpec|nil
---@field order integer?
---@field scale "linear"|"log"|nil
---@field band supaline.Bands? the bands a `<->` may name, by name

-- What `setup` itself takes, which is the only thing that refuses everything
-- else. The same reason `OPTIONS` above has, one level up: a key in the table
-- constructor `setup` is handed is past what `lua-language-server` checks
-- against `supaline.Opts` -- `(exact)` was measured not to change that -- so
-- `bnad`, `scal` and `seperator` reach this or they reach nobody. A `band`
-- written `bnad` defines no band at all, so the `<->`s that were to use it are
-- each refused for naming nothing -- loud, but pointed at the wrong table: the
-- reader is told to define `fg` while a whole `fg` sits three lines above,
-- spelled right, under a key nobody reads.
--
-- This is the outermost of the five tables a user writes. The other four -- a
-- linemode spec, a separator, a style, and a column spec or definition -- are
-- swept the same way, through `diagnostics.unknown`.
local SETUP_KEYS = {
	band = true,
	linemodes = true,
	order = true,
	scale = true,
	separator = true,
}

local function claims_setup(key) return SETUP_KEYS[key] end

-- The keys above, in the order the message lists them. `key_list_of` sorts,
-- for the reason it gives: `pairs` gives a set back in whatever order the hash
-- does, and a message that reorders itself between runs reads as a different
-- message.
local SETUP_KEY_LIST = diagnostics.key_list_of(SETUP_KEYS)

-- What a key that is none of them most likely meant. Both are mistakes about
-- where a thing goes rather than misspellings: one linemode written where the
-- table of them goes, and a linemode's columns written beside the table
-- instead of inside a linemode in it.
local SETUP_MEANT = {
	linemode = "`linemodes` is the spelling, and it is a table of them keyed by the name " .. "each one is switched to",
	columns = 'columns go inside a linemode -- `linemodes = { detail = { "size", "mtime" } }` '
		.. "-- rather than beside the table of them",
}

local SETUP_UNKNOWN = "supaline: %s. `setup` takes %s%s"

---@class supaline.Cfg
---@field separator string|supaline.SepSpec
---@field order integer
---@field scale "linear"|"log"|nil
---@field band supaline.Bands

---@class supaline.ModePlan
---@field name string
---@field cols table<string, supaline.ColumnPlan[]>
---@field outer boolean
---@field separator string|supaline.SepSpec|nil

---@class supaline.Plan
---@field cfg supaline.Cfg
---@field modes table<string, supaline.ModePlan>
---@field columns supaline.ColumnPlan[] each use once, shared pane lists deduplicated
---@field outer boolean

-- Quoted by every refusal that is about the shape of a linemode. A message
-- that says what is wrong without saying what to write instead sends the
-- reader back to the README for the half it left out, which is why the one
-- below names the keys a linemode takes rather than only the key it got.
local PANES_HELP = "supaline: a linemode is a list of columns, drawn in the current pane -- "
	.. 'e.g. { "size", "mtime" } -- or a list of columns under each pane it draws in -- '
	.. 'e.g. { current = { "size" }, parent = { "count" } }'

-- What a linemode may carry besides its columns and its panes. Anything else
-- is refused rather than ignored, because nothing else refuses it: a key in a
-- table constructor is past what `lua-language-server` checks against the
-- class -- `(exact)` was measured not to change that -- so `separatorr` and
-- `parnet` reach here or they reach nobody.
local OPTIONS = { separator = true }

local OPTION_HELP = "supaline: besides its columns a linemode takes `current`, `parent`, "
	.. "`preview` and `separator`; got %s"

-- A separator is drawn before its column, so the first column of a pane's
-- list has nothing before it and `render` skips the separator there. Written
-- on that column anyway, a `separator` is drawn nowhere and says nothing --
-- the silence every other refusal in this file exists for.
--
-- The message names the pane, because a list is the pane's rather than the
-- linemode's: two panes of one linemode each have a first column, and only a
-- list written under both is the same one twice.
local FIRST_SEP = "supaline: the first column of `%s` on linemode `%s` was given a "
	.. "`separator`, which is drawn by nobody: a separator goes before its column, and "
	.. "the first column has nothing before it. Write it on the column it should "
	.. "precede, or drop it -- `separator = false` is accepted there, since it asks for "
	.. "nothing and gets nothing"

-- `PANES` as a set, so a key can be classified without walking it. Derived
-- rather than written out, because a list and a set of the same three names
-- are two things to keep in step.
local IS_PANE = {} ---@type table<string, boolean>
for _, pane in ipairs(PANES) do
	IS_PANE[pane] = true
end

-- What a linemode spec is entitled to: its columns at the numeric keys, a pane
-- name, or one of the options above.
local function claims_spec(key) return type(key) == "number" or IS_PANE[key] or OPTIONS[key] end

--- How many columns are written in `list`, counting the ones `ipairs` would
--- never reach. `compile` walks a column list with `ipairs`, so it stops at
--- the first missing index and anything past a gap draws nowhere -- the same
--- silence a key nobody claimed is refused for, arrived at by arithmetic
--- rather than by spelling.
---
--- `#list` is what `ipairs` will reach and this is what was written, so the
--- two differing is the whole of the test. `#` alone cannot make it: a list
--- that starts at index 2 has an entry in it and a `#` of 0.
---@param list table
---@return integer
local function entries_of(list)
	local n = 0
	for key in pairs(list) do
		if type(key) == "number" then
			n = n + 1
		end
	end
	return n
end

--- What each pane of a linemode draws, keyed by pane name, with a pane that
--- draws nothing absent rather than empty. One table answers both "which
--- panes" and "which columns", so there is one thing for `compile` to walk and
--- one thing per row to look up.
---
--- A linemode written as a bare list of columns draws them in the current pane
--- and nowhere else, which is all Yazi itself does. Naming a pane gives that
--- pane a list of its own, and is then the only place columns may be written:
--- a list left beside the pane keys would be drawn nowhere, and drawing
--- nothing without a word is the failure this refuses rather than ships.
---@param spec supaline.LinemodeSpec
---@return table<string, supaline.ColumnSpec[]> by pane
local function panes_of(spec)
	local sets = {}
	for _, pane in ipairs(PANES) do
		local list = spec[pane]
		if list ~= nil then
			if type(list) ~= "table" then
				error(string.format("%s; `%s` was given a %s rather than a list of columns", PANES_HELP, pane, type(list)))
			elseif #list == 0 then
				-- Leaving the pane out says exactly this and says it in one
				-- place, so an empty list is a second spelling of nothing.
				error(string.format("%s; `%s` was given an empty list -- leave the pane out instead", PANES_HELP, pane))
			end
			-- A pane takes columns and nothing else. The options live on the
			-- linemode, one level up, where they apply to every pane it draws
			-- in -- and a name written in here is not refused for being the
			-- wrong option but dropped for being somewhere `ipairs` never
			-- goes, which is the same silence again.
			for key in pairs(list) do
				if type(key) ~= "number" then
					error(
						string.format(
							"%s; `%s` takes a list of columns and nothing else, and was given "
								.. "`%s` beside them -- an option goes on the linemode itself",
							PANES_HELP,
							pane,
							tostring(key)
						)
					)
				end
			end
			if entries_of(list) ~= #list then
				error(string.format("%s; `%s` has a gap in its numbering", PANES_HELP, pane))
			end
			sets[pane] = list
		end
	end

	local _, unknown = diagnostics.unknown(spec, claims_spec)
	if unknown then
		error(string.format(OPTION_HELP, unknown))
	end

	if next(sets) == nil then
		-- No pane was named, so the linemode's own list is what the current
		-- pane draws. An empty one draws nothing there, which is a thing to
		-- ask for and is pinned as one -- a gap in a list that has entries is
		-- not, and is refused here as it is under a pane.
		if entries_of(spec) ~= #spec then
			error(string.format("%s; this one has a gap in its numbering", PANES_HELP))
		end
		return { current = spec }
	-- Every column written on the linemode, not the ones `ipairs` would reach.
	-- A list starting at index 2 has a `#` of 0, so asking `#` here let a
	-- stray column through the moment a pane was named -- and refused the very
	-- same column when it sat at index 1.
	elseif entries_of(spec) > 0 then
		error(
			"supaline: a pane's columns are written under that pane's own name, so the "
				.. "columns beside them on the linemode would be drawn nowhere; move them "
				.. "under a pane"
		)
	end
	return sets
end

---@param opts supaline.Opts
---@param registry supaline.Registry
---@param is_yazis fun(name: string): boolean
---@return supaline.Plan
function M.compile(opts, registry, is_yazis)
	-- Before a single key is read off it, and before anything is committed. A
	-- key this function does not know is not a value it would ever object to;
	-- it is a key nothing reads, which is the whole of what stands between
	-- `scal = "log"` and a plugin that quietly scales nothing.
	local _, _, subject, hints = diagnostics.unknown(opts, claims_setup, "`setup`", SETUP_MEANT)
	if subject then
		error(string.format(SETUP_UNKNOWN, subject, SETUP_KEY_LIST, hints))
	end

	local sep = opts.separator
	if sep == nil then
		sep = " "
	end
	local cfg = {
		separator = column.snapshot_separator(sep),
		order = opts.order or 1400,
		scale = column.one_of("scale", opts.scale, "in `setup`"),
		band = style.bands(opts.band, "`band` in `setup`"),
	}
	local next_specs = opts.linemodes or {}
	if not next(next_specs) then
		error("supaline: `linemodes` is empty; there is nothing to render")
	end

	for name, spec in pairs(next_specs) do
		-- Yazi's limit is 1 to 20 *characters*; `#name` would refuse a CJK
		-- name of seven. `utf8.len` returns nil for a string that is not
		-- valid UTF-8, and such a name is Yazi's to refuse, not ours.
		local len = type(name) == "string" and (utf8.len(name) or #name) or nil
		if not len or len < 1 or len > 20 then
			error(string.format("supaline: a linemode name must be 1 to 20 characters, got `%s`", tostring(name)))
		elseif is_yazis(name) then
			error(
				string.format(
					"supaline: `%s` is part of Yazi's `Linemode` component; a linemode of "
						.. "that name would replace it. Overriding a built-in linemode "
						.. "(`size`, `mtime`, ...) is fine, replacing the component is not",
					name
				)
			)
		elseif type(spec) ~= "table" then
			error(string.format("%s; linemode `%s` is a %s", PANES_HELP, name, type(spec)))
		end
	end

	local plan = { cfg = cfg, modes = {}, columns = {}, outer = false }
	for name, spec in pairs(next_specs) do
		local sets = panes_of(spec)
		local built, cols = {}, {}
		for _, pane in ipairs(PANES) do
			local list = sets[pane]
			local made = list and built[list]
			if list and not made then
				local first = list[1]
				if type(first) == "table" and first.separator then
					error(string.format(FIRST_SEP, pane, name))
				end
				made = {}
				for i, entry in ipairs(list) do
					local col = registry.compile(entry, cfg)
					made[i] = col
					plan.columns[#plan.columns + 1] = col
				end
				built[list] = made
			end
			if made and #made > 0 then
				cols[pane] = made
			end
		end
		local outer = cols.parent ~= nil or cols.preview ~= nil
		plan.outer = plan.outer or outer
		plan.modes[name] = {
			name = name,
			cols = cols,
			outer = outer,
			separator = column.snapshot_separator(spec.separator),
		}
	end
	return plan
end

return M
