--- @since 26.8.15
--- supaline -- a column framework for Yazi's linemode.
---
--- `setup` turns each entry of `linemodes` into a real linemode, so
--- `mgr.linemode` and the `linemode` action switch between them exactly the way
--- they switch between Yazi's own.
---
--- Rendering runs for every visible row on every frame, so it does little but
--- read from tables: per-folder statistics and derived widths are computed once
--- per folder and cached here, then bound onto each column whenever the folder
--- being drawn changes.

local column = require(".column")
require(".builtin")

-- Yazi calls `Linemode` for three panes. `solo()` guards `in_current` itself,
-- so a linemode never reaches the other two; a child added with
-- `children_add` is called for all of them and has to decide for itself.
local PANES = { "current", "parent", "preview" }

local DEFAULTS = {
	separator = " ",
	-- Order of the parent/preview child among Linemode's children. Anything
	-- below `padding` (2000) keeps it inside the linemode block.
	order = 1400,
	-- "linear" is what eza does. "log" spreads a listing whose values span
	-- orders of magnitude, which is usually what `size` wants.
	scale = "linear",
}

local M = {}

local cfg = DEFAULTS
local specs = {} ---@type table<string, table> the user's linemode definitions
local linemodes = {} ---@type table<string, table> normalised columns
local panes = {} ---@type table<string, table> which panes each linemode draws in
local seps = {} ---@type table<string, string> separator per linemode

-- Statistics and derived widths, keyed by linemode, folder and file count. The
-- count catches the common case of a file being added or removed; a write that
-- leaves it unchanged keeps stale extremes until the next file operation or
-- `cd`, which is the trade that keeps rendering O(1) per row.
local cache, cache_n, bound = {}, 0, nil

local DEFAULT_PANES = { "current" }

local PANES_HELP = 'supaline: `panes` takes a list of "current", "parent" and/or '
	.. '"preview" -- e.g. { "current", "preview" }'

--- Which panes a linemode draws in. Always a list, so there is one way to say
--- any given combination; listing all three is how you ask for all three.
---@param spec table
---@return table<string, boolean>
local function panes_of(spec)
	local want = spec.panes or DEFAULT_PANES

	if type(want) == "string" then
		error(string.format('%s; got the string `%s` -- write { "%s" }', PANES_HELP, want, want))
	elseif type(want) ~= "table" then
		error(string.format("%s; got a %s", PANES_HELP, type(want)))
	elseif #want == 0 then
		-- Either an empty list, or a map such as `{ current = true }`, which
		-- `ipairs` walks as empty. Both would draw nothing anywhere, without a
		-- word of complaint, so refuse them here instead.
		error(string.format("%s; got a table with no list entries", PANES_HELP))
	end

	local set = {}
	for _, name in ipairs(want) do
		local ok = false
		for _, pane in ipairs(PANES) do
			ok = ok or name == pane
		end
		if not ok then
			error(string.format("%s; got `%s`", PANES_HELP, tostring(name)))
		end
		set[name] = true
	end
	return set
end

--- The folder a row belongs to. Statistics for a parent- or preview-pane row
--- have to come from that pane's folder, not from `cx.active.current`.
---@param file table
---@return table?
local function folder_of(file)
	if file.in_current then
		return cx.active.current
	elseif file.in_preview then
		return cx.active.preview.folder
	end
	return cx.active.parent
end

--- Bind one folder's statistics and widths onto every column of a linemode.
--- Cheap and idempotent: it does nothing at all while the pane being drawn has
--- not changed.
---@param name string
---@param cols table
---@param folder table?
local function bind(name, cols, folder)
	if not folder then
		if bound ~= false then
			bound = false
			for _, col in ipairs(cols) do
				column.bind(col, {})
			end
		end
		return
	end

	local files = folder.files
	local key = name .. "\0" .. tostring(folder.cwd) .. "\0" .. #files
	if bound == key then
		return
	end

	local entries = cache[key]
	if not entries then
		entries = {}
		for i, col in ipairs(cols) do
			local entry = {}
			if col.needs_pass then
				entry.stats = col.stats and col.stats(files) or nil
				-- The width pass renders every file, and those renders read
				-- `ctx.ratio`, so the extremes have to be in place first.
				column.bind(col, entry)
				entry.width = column.resolve_width(col, files, entry.stats)
			end
			entries[i] = entry
		end

		if cache_n >= 8 then
			cache, cache_n = {}, 0
		end
		cache[key], cache_n = entries, cache_n + 1
	end

	for i, col in ipairs(cols) do
		column.bind(col, entries[i])
	end
	bound = key
end

---@param name string
---@param file table `fs::File`
---@return unknown an `AsLine`
local function render(name, file)
	local cols = linemodes[name]
	if not cols or #cols == 0 then
		return ""
	end

	bind(name, cols, folder_of(file))

	local sep, out = seps[name], {}
	for i, col in ipairs(cols) do
		if i > 1 and col.sep ~= false then
			out[#out + 1] = col.sep or sep
		end
		out[#out + 1] = column.cell(col, file)
	end
	return ui.Line(out)
end

--- Draw the active linemode in the parent and preview panes, for the linemodes
--- that ask for it. `solo()` has already drawn the current pane, so those rows
--- are skipped here.
---@param self table
---@return unknown an `AsLine`
local function child(self)
	local file = self._file
	if file.in_current then
		return ""
	end

	local name = cx.active.pref.linemode
	local set = name and panes[name]
	if not set or not set[file.in_preview and "preview" or "parent"] then
		return ""
	end

	-- `solo()` prepends a space to a line that has width; match it, so the two
	-- panes line up.
	local line = ui.Line(render(name, file))
	return line:visible() and ui.Line { " ", line } or line
end

--- (Re)build every linemode from the stored specs. Run once at setup and again
--- on every `theme` event: until that event fires `th.*` still holds preset
--- values, so any base colour resolved earlier is the wrong one.
local function build()
	local next_modes, next_panes, next_seps = {}, {}, {}
	for name, spec in pairs(specs) do
		local cols = {}
		for i, entry in ipairs(spec) do
			cols[i] = column.normalize(entry, cfg)
		end
		next_modes[name], next_panes[name] = cols, panes_of(spec)
		next_seps[name] = spec.separator or cfg.separator
	end

	linemodes, panes, seps = next_modes, next_panes, next_seps
	cache, cache_n, bound = {}, 0, nil
end

--- Register a reusable column, before `setup`, then refer to it by name from a
--- linemode spec. Accepts both `.column(name, def)` and `:column(name, def)`.
function M.column(a, b, c)
	if type(a) == "table" and type(b) == "string" then
		return column.register(b, c)
	end
	return column.register(a, b)
end

--- `_st` is Yazi's per-plugin state table. Nothing in this phase keeps state
--- across calls; the providers added later do, through `ya.sync` blocks
--- declared at the top level of this file.
---@param _st table plugin state, supplied by Yazi
---@param opts table?
function M.setup(_st, opts)
	opts = opts or {}

	cfg = {
		separator = opts.separator or DEFAULTS.separator,
		order = opts.order or DEFAULTS.order,
		scale = opts.scale or DEFAULTS.scale,
	}

	specs = opts.linemodes or {}
	if not next(specs) then
		error("supaline: `linemodes` is empty; there is nothing to render")
	end

	local wants_child = false
	for name, spec in pairs(specs) do
		if type(name) ~= "string" or #name < 1 or #name > 20 then
			error(string.format("supaline: a linemode name must be 1 to 20 characters, got `%s`", tostring(name)))
		elseif name == "none" or name == "solo" then
			-- `solo()` returns early for both, so the registration would never
			-- be reached and the linemode would silently do nothing.
			error(string.format("supaline: `%s` is reserved by Yazi and cannot be a linemode name", name))
		elseif type(spec) ~= "table" then
			error(string.format("supaline: linemode `%s` must be a list of columns", name))
		end

		local set = panes_of(spec)
		wants_child = wants_child or set.parent or set.preview
	end

	build()

	for name in pairs(specs) do
		Linemode[name] = function(self) return render(name, self._file) end
	end

	-- Added once, here rather than in `build`, so a theme reload does not stack
	-- up another child on every event.
	if wants_child then
		Linemode:children_add(child, cfg.order)
	end

	ps.sub("theme", build)

	-- A file operation can move a file between buckets, or change how wide the
	-- widest cell is, so drop the cached pass and let the next frame redo it.
	--
	-- `bulk-rename`, not `bulk`: 26.8.15 renamed the event without saying so,
	-- and `ps.sub` accepts an unknown kind without complaining.
	local invalidate = function()
		cache, cache_n, bound = {}, 0, nil
	end
	for _, kind in ipairs { "rename", "bulk-rename", "move", "delete", "trash" } do
		ps.sub(kind, invalidate)
	end
end

return M
