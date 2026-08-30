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

local builtin = require(".builtin")
local column = require(".column")

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
local cache, cache_n = {}, 0

-- The pane last bound, held as its three parts rather than as the composed
-- key. `bind` runs for every visible row on every frame and almost always
-- finds nothing has changed, so the check it does first must not allocate:
-- `tostring(cwd)` crosses into Rust to build a path string, and the key
-- concatenates three more. Comparing the parts is enough to decide.
local bound_name, bound_cwd, bound_n = nil, nil, nil

local DEFAULT_PANES = { "current" }

-- What a previous `setup` left on `Linemode` and on the DDS bus. Held across
-- calls because neither may simply be added a second time -- see the end of
-- `setup`.
local child_id = nil ---@type integer?
local subscribed = false

-- Yazi keeps the component's own machinery on the very table the linemodes are
-- looked up on, so a linemode named after any of it silently replaces the
-- machinery -- `new` takes out the constructor, `padding` takes out a child
-- every row draws.
--
-- The check asks `Linemode` what it holds rather than listing it: Yazi is on
-- CalVer and adds to the component between releases, and a name written down
-- here goes stale the moment it does. Only Yazi's own linemodes are exempt --
-- replacing `size` is a thing to want, replacing `redraw` is not. `none` is
-- deliberately not among them, because `solo()` returns before it could ever
-- dispatch to it.
local OVERRIDABLE = {
	size = true,
	permissions = true,
	btime = true,
	mtime = true,
	atime = true,
	owner = true,
}

-- Names supaline itself put on `Linemode`, so calling `setup` twice does not
-- refuse everything the first call registered.
local ours = {} ---@type table<string, boolean>

--- Whether `name` would replace something of Yazi's rather than sit alongside
--- it.
---@param name string
---@return boolean
local function is_yazis(name)
	if OVERRIDABLE[name] or ours[name] then
		return false
	end
	return Linemode[name] ~= nil or name:sub(1, 1) == "_"
end

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

--- The pane a row is being drawn in, and the folder it belongs to. Statistics
--- for a parent- or preview-pane row have to come from that pane's folder, not
--- from `cx.active.current`.
---
--- `in_preview` is not the counterpart of `in_current` its name suggests.
--- `in_current` is folder-wide -- Yazi compares the row's folder against the
--- tab's current one -- but `in_preview` is
---
---     me.idx == me.folder.cursor && tab.hovered() is this folder
---
--- so it is set on the previewed folder's *cursor row alone*. Every other
--- preview row reports false, and there is no `in_parent` to tell it apart
--- from a parent-pane row: both are simply "not current". Ask the preview
--- folder whether the row is one of its own instead.
---@param file table
---@return string pane, table? folder
local function pane_of(file)
	if file.in_current then
		return "current", cx.active.current
	end
	-- `idx` is the row's 1-based position in its own folder, so this is O(1).
	local folder = cx.active.preview.folder
	local at = folder and folder.files[file.idx]
	if at and at.url == file.url then
		return "preview", folder
	end
	return "parent", cx.active.parent
end

--- Bind one folder's statistics and widths onto every column of a linemode.
--- Cheap and idempotent: it does nothing at all while the pane being drawn has
--- not changed.
---@param name string
---@param cols table
---@param folder table?
local function bind(name, cols, folder)
	if not folder then
		if bound_name ~= false then
			bound_name, bound_cwd, bound_n = false, nil, nil
			for _, col in ipairs(cols) do
				column.bind(col, {})
			end
		end
		return
	end

	local files, cwd = folder.files, folder.cwd
	local n = #files
	if bound_name == name and bound_n == n and bound_cwd == cwd then
		return
	end

	local key = name .. "\0" .. tostring(cwd) .. "\0" .. n
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
	bound_name, bound_cwd, bound_n = name, cwd, n
end

--- Draw one row. The caller resolves the pane, because both of them already
--- know it: `solo()` only dispatches for `in_current` rows, and `child` has
--- just asked `pane_of`. `folder` is nil for a pane that has none -- the
--- parent of the filesystem root -- which `bind` handles.
---@param name string
---@param file table `fs::File`
---@param folder table? the folder the row belongs to
---@return unknown an `AsLine`
local function render(name, file, folder)
	local cols = linemodes[name]
	if not cols or #cols == 0 then
		return ""
	end

	bind(name, cols, folder)

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
	local pane, folder = pane_of(file)
	if pane == "current" then
		return ""
	end

	local name = cx.active.pref.linemode
	local set = name and panes[name]
	if not set or not set[pane] then
		return ""
	end

	-- `solo()` prepends a space to a line that has width; match it, so the two
	-- panes line up.
	local line = ui.Line(render(name, file, folder))
	return line:visible() and ui.Line { " ", line } or line
end

--- Turn a set of specs into runtime linemodes. Pure, and the only place that
--- validates a spec: `column.normalize` and `panes_of` both raise, so a
--- configuration that does not compile never reaches module state.
---@param from table<string, table>
---@param with table plugin-wide options
---@return table modes, table sets, table separators
local function compile(from, with)
	local modes, sets, separators = {}, {}, {}
	for name, spec in pairs(from) do
		local cols = {}
		for i, entry in ipairs(spec) do
			cols[i] = column.normalize(entry, with)
		end
		modes[name], sets[name] = cols, panes_of(spec)
		separators[name] = spec.separator or with.separator
	end
	return modes, sets, separators
end

--- Put a compiled set of linemodes into service, dropping everything derived
--- from the last one.
local function install(modes, sets, separators)
	linemodes, panes, seps = modes, sets, separators
	cache, cache_n = {}, 0
	bound_name, bound_cwd, bound_n = nil, nil, nil

	-- `smart` compares against the current year, which is a constant for the
	-- life of a session and must not be asked for once per row.
	builtin.refresh()
end

--- Rebuild every linemode from the stored specs. Subscribed to `theme`: until
--- that event fires `th.*` still holds preset values, so any base colour
--- resolved earlier is the wrong one.
local function build() install(compile(specs, cfg)) end

--- A file operation can move a file between buckets, or change how wide the
--- widest cell is, so drop the cached pass and let the next frame redo it.
local function invalidate()
	cache, cache_n = {}, 0
	bound_name, bound_cwd, bound_n = nil, nil, nil
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
	-- `.setup{...}` as well as `:setup{...}`, matching `M.column`. The dot form
	-- lands the options in the state parameter, which is Yazi's own table and
	-- never carries `linemodes`; without this the error names the one thing the
	-- user got right.
	if opts == nil and type(_st) == "table" and _st.linemodes ~= nil then
		opts = _st
	end
	opts = opts or {}

	-- Everything up to the commit below works on locals. A `setup` that is
	-- refused must leave the configuration already running untouched: the
	-- `theme` handler reads `specs`, so a rejected spec left there would make
	-- every later theme event throw instead of rebuilding.
	local next_cfg = {
		separator = opts.separator or DEFAULTS.separator,
		order = opts.order or DEFAULTS.order,
		scale = opts.scale or DEFAULTS.scale,
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
			error(string.format("supaline: linemode `%s` must be a list of columns", name))
		end
	end

	-- Compiling is what validates the columns and the `panes` list, so it also
	-- has to happen before the commit -- and only once, rather than again
	-- inside `build`.
	local modes, sets, separators = compile(next_specs, next_cfg)

	local wants_child = false
	for _, set in pairs(sets) do
		if set.parent or set.preview then
			wants_child = true
		end
	end

	-- Committed. Nothing below here may raise on a configuration that got this
	-- far.
	cfg, specs = next_cfg, next_specs
	install(modes, sets, separators)

	-- Registered whatever `panes` says, because an unregistered name is not
	-- inert: `solo()` draws it as literal text. A linemode that has not asked
	-- for the current pane draws nothing there instead.
	--
	-- `solo()` only dispatches for a row it has already found `in_current`, so
	-- the folder is the current one without asking.
	for name in pairs(specs) do
		ours[name] = true
		Linemode[name] = function(self)
			local set = panes[name]
			if not set or not set.current then
				return ""
			end
			return render(name, self._file, cx.active.current)
		end
	end

	-- Replace the child a previous `setup` added rather than stacking another:
	-- `Linemode:redraw()` calls every child it holds, so a second one draws
	-- the parent and preview panes twice over.
	if child_id then
		Linemode:children_remove(child_id)
		child_id = nil
	end
	if wants_child then
		child_id = Linemode:children_add(child, cfg.order)
	end

	-- Subscribed once for the life of the session, for the same reason. Both
	-- handlers read the module state this call has just replaced, so a second
	-- `setup` needs no second subscription and a second one would only run
	-- them twice per event.
	--
	-- `bulk-rename`, not `bulk`: 26.8.15 renamed the event without saying so,
	-- and `ps.sub` accepts an unknown kind without complaining.
	if not subscribed then
		subscribed = true
		ps.sub("theme", build)
		-- The year `mtime` compares against is read in `install`; `cd` is the
		-- event that fires often enough to keep it current.
		ps.sub("cd", builtin.refresh)
		for _, kind in ipairs { "rename", "bulk-rename", "move", "delete", "trash" } do
			ps.sub(kind, invalidate)
		end
	end
end

return M
