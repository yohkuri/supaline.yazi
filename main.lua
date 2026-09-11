--- @since 26.9.1
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

-- Required for its side effects: loading it registers the built-in columns
-- through `column.register`, the same entry point a user column uses.
require(".builtin")
local column = require(".column")

-- Yazi calls `Linemode` for three panes. `solo()` guards `in_current` itself,
-- so a linemode never reaches the other two; a child added with
-- `children_add` is called for all of them and has to decide for itself.
local PANES = { "current", "parent", "preview" }

---@type supaline.Cfg
local DEFAULTS = {
	separator = " ",
	-- Order of the parent/preview child among Linemode's children. Anything
	-- below `padding` (2000) keeps it inside the linemode block.
	order = 1400,
	-- The default for the columns that do not state one, which today is every
	-- timestamp column: a folder's mtimes sit within a few years of each other,
	-- and a linear ratio is what spreads them out. `size` states `log` on its
	-- own definition, because its values span orders of magnitude -- so
	-- changing this does not change `size`.
	scale = "linear",
}

--- The module table, as a spec sees it.
---
--- In this checkout and on the CI runner, `require(".main")` does not resolve
--- to this file. `types.yazi` ships a `main.lua` of its own -- 3,235 lines of
--- annotations, and no `return` -- and it sits on `workspace.library`, so the
--- name resolves there and every call a spec makes into the plugin is checked
--- against a module that exports nothing. Nothing says so:
--- `main.setup(42, ...)` and `main.columnn(...)` were both accepted before
--- this class existed.
---
--- Declaring the shape here and claiming it at the `require` is what puts those
--- calls back under the check, the same way `supaline.Stub` does for the stub.
--- Both entry points take a dot call and a colon call, and a `@field` carries
--- no `@overload`, so each is written as the union of its two shapes -- leave
--- one out and the spec that writes it that way is refused for no reason.
---
--- Which of the two files wins follows from the absolute path this tree sits
--- at, not from either name: a checkout sorting before
--- `~/.config/yazi/plugins/types.yazi/` reads `.main` from here instead. The
--- class is claimed at the `require` either way and stays right;
--- `annotate-supaline/references/main-collision.md` has the measurement and
--- the paths that flip it.
---@class supaline.Main
---@field setup fun(st: table, opts: supaline.Opts?)|fun(opts: supaline.Opts)
---@field column fun(name: string, def: supaline.ColumnDef)|fun(self: table, name: string, def: supaline.ColumnDef)

local M = {}

--- What the user writes for one linemode: the columns in order, and the two
--- options that belong to the linemode rather than to any column in it.
---@class supaline.LinemodeSpec
---@field [integer] supaline.ColumnSpec
---@field panes string[]? the panes it draws in; `{ "current" }` by default
---@field separator string? overrides the plugin-wide one

--- The table `setup` is handed. `linemodes` is the only field it cannot do
--- without and it is still optional here, because `setup` takes the dot call
--- as well as the colon call and has to look at what arrived before it can
--- say which one it was.
---@class supaline.Opts
---@field linemodes table<string, supaline.LinemodeSpec>?
---@field separator string?
---@field order integer?
---@field scale "linear"|"log"|nil

local cfg = DEFAULTS
local specs = {} ---@type table<string, supaline.LinemodeSpec> the user's linemode definitions

-- One record per linemode -- the class below -- rather than three tables keyed
-- by the same name. `render` and `child` then take one hash lookup per row
-- between them instead of three, and there is one thing to keep in step
-- instead of three.

--- One linemode in service. `compile` is the only thing that builds one, and
--- every field is read per row.
---@class supaline.Mode
---@field name string
---@field cols supaline.Column[]
---@field panes table<string, boolean> the panes it draws in, by name
---@field outer boolean whether it draws anywhere but the current pane
---@field sep string what goes between two columns

local linemodes = {} ---@type table<string, supaline.Mode>

-- The `refresh` hooks of every column in service, flattened. A column that
-- caches something across rows -- the current year, say -- declares one, and it
-- is run whenever a linemode is installed and on every `cd`.
local refreshers = {} ---@type table<integer, function>

-- Statistics and derived widths, keyed by linemode, folder and file count. The
-- count catches the common case of a file being added or removed; a write that
-- leaves it unchanged keeps stale extremes until the next file operation or
-- `cd`, which is the trade that keeps rendering O(1) per row.
local cache, cache_n = {}, 0 ---@type table<string, supaline.Entry[]>, integer

-- The pane last bound, held as its three parts rather than as the composed
-- key. `bind` runs for every visible row on every frame and almost always
-- finds nothing has changed, so the check it does first has to be cheap:
-- `tostring(cwd)` crosses into Rust to build a path string, and the key
-- concatenates three more. Comparing the parts is enough to decide.
--
-- `folder.cwd` is a cached field, so within a frame both sides of the `cwd`
-- test are the same userdata and Lua settles it by pointer without reaching
-- for `__eq` at all; across frames it falls back to one Rust-side path
-- comparison, which still allocates nothing.
local bound_name, bound_cwd, bound_n = nil, nil, nil

local DEFAULT_PANES = { "current" }

-- Everything a previous `setup` put on `Linemode`, so the next one can take it
-- back off. Two names and a child id would each be their own special case, and
-- the one left without a case is the one that leaks: `Linemode[name]` was, and
-- a linemode dropped by a second `setup` stayed registered and drew nothing --
-- where Yazi draws an unregistered name as literal text.
--
-- `prev` holds what each name was bound to before, which is what lets an
-- override of one of Yazi's own linemodes be handed back.
local installed = { names = {}, prev = {}, child = nil } ---@type table

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
---@param spec supaline.LinemodeSpec
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

--- Which of the two panes outside the current one a row is in, and the folder
--- it belongs to. Statistics for such a row have to come from that pane's
--- folder, not from `cx.active.current`.
---
--- Only ever asked about a row already known not to be `in_current`, because
--- that is one free field read and this is not.
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
---@param file supaline.File
---@return string pane, supaline.Folder? folder
local function pane_of(file)
	-- `idx` is the row's 1-based position in its own folder, so this is O(1).
	--
	-- Cast at the boundary, here and below: Yazi hands back a `tab__Folder`,
	-- and what makes it a `supaline.Folder` is the listing's element type,
	-- which is this plugin's claim about Yazi rather than Yazi's own.
	local folder = cx.active.preview.folder --[[@as supaline.Folder?]]
	local at = folder and folder.files[file.idx]
	if at and at.url == file.url then
		return "preview", folder
	end
	return "parent", cx.active.parent --[[@as supaline.Folder?]]
end

--- Bind one folder's statistics and widths onto every column of a linemode.
--- Cheap and idempotent: it does nothing at all while the pane being drawn has
--- not changed.
---@param name string
---@param cols supaline.Column[]
---@param folder supaline.Folder?
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

--- Draw one row. The caller has already looked the linemode up and resolved
--- the pane, because both of them had to: `solo()` only dispatches for
--- `in_current` rows, and `child` has just asked `pane_of`. `folder` is nil
--- for a pane that has none -- the parent of the filesystem root -- which
--- `bind` handles.
---@param mode supaline.Mode
---@param file supaline.File
---@param folder supaline.Folder? the folder the row belongs to
---@return unknown an `AsLine`
local function render(mode, file, folder)
	local cols = mode.cols
	if #cols == 0 then
		return ""
	end

	bind(mode.name, cols, folder)

	local sep, out = mode.sep, {}
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
	-- Cast rather than annotated: `self` is Yazi's own linemode table, and the
	-- only thing this needs from it is what `_file` holds.
	local file = self._file --[[@as supaline.File]]
	-- Cheapest first. One child serves every linemode, so it is called for
	-- every parent and preview row even when the active linemode wants
	-- neither, and `pane_of` is far dearer than either of these tests.
	if file.in_current then
		return "" -- `solo()` has already drawn it
	end

	local name = cx.active.pref.linemode
	local mode = name and linemodes[name]
	if not mode or not mode.outer then
		return ""
	end

	local pane, folder = pane_of(file)
	if not mode.panes[pane] then
		return ""
	end

	-- `solo()` prepends a space to a line that has width; match it, so the two
	-- panes line up. `render` returns a Line or the empty string, so there is
	-- nothing to re-wrap.
	local line = render(mode, file, folder)
	if line == "" then
		return ""
	end
	return line:visible() and ui.Line { " ", line } or line
end

--- A file operation can move a file between buckets, or change how wide the
--- widest cell is, so drop the cached pass and let the next frame redo it.
local function invalidate()
	cache, cache_n = {}, 0
	bound_name, bound_cwd, bound_n = nil, nil, nil
end

--- Run every column's `refresh` hook. Subscribed to `cd` through `moved`,
--- which is the event that fires often enough to keep a value cached across
--- rows -- the current year -- from going stale in a session left open.
local function refresh()
	for i = 1, #refreshers do
		refreshers[i]()
	end
end

--- A `cd` is both of the above at once. The cached pass goes with it: the key
--- holds the folder and its file count, so a folder revisited after a write
--- that left the count alone -- one file grown, one timestamp touched -- would
--- otherwise be drawn with the extremes and the width measured on the way out.
--- That is what "until the next file operation or `cd`" means.
local function moved()
	invalidate()
	refresh()
end

--- Turn a set of specs into runtime linemodes. Pure, and the only place that
--- validates a spec: `column.normalize` and `panes_of` both raise, so a
--- configuration that does not compile never reaches module state.
---@param from table<string, supaline.LinemodeSpec>
---@param with supaline.Cfg
---@return table<string, supaline.Mode> modes, function[] hooks, boolean outer whether any mode leaves the current pane
local function compile(from, with)
	local modes, hooks, outer = {}, {}, false
	for name, spec in pairs(from) do
		local cols = {}
		for i, entry in ipairs(spec) do
			local col = column.normalize(entry, with)
			cols[i] = col
			if col.refresh then
				hooks[#hooks + 1] = col.refresh
			end
		end

		local set = panes_of(spec)
		local reaches = set.parent or set.preview or false
		outer = outer or reaches
		modes[name] = {
			name = name,
			cols = cols,
			panes = set,
			outer = reaches,
			sep = spec.separator or with.separator,
		}
	end
	return modes, hooks, outer
end

--- Put a compiled set of linemodes into service, dropping everything derived
--- from the last one.
local function install(modes, hooks)
	linemodes, refreshers = modes, hooks
	invalidate()
	refresh()
end

--- Take back everything the last `setup` put on `Linemode`. Names go back to
--- what they were bound to, so an override of one of Yazi's own linemodes is
--- handed back rather than left as a supaline one that draws nothing.
local function uninstall()
	for _, name in ipairs(installed.names) do
		Linemode[name] = installed.prev[name]
	end
	if installed.child then
		-- `Linemode:redraw()` calls every child it holds, so a second one
		-- would draw the parent and preview panes twice over.
		Linemode:children_remove(installed.child)
	end
	installed = { names = {}, prev = {}, child = nil }
end

--- Rebuild every linemode from the stored specs. Subscribed to `theme`
--- because `app:theme` re-reads `theme.toml` from disk mid-run: a base colour
--- resolved once at setup is the old one from then on, and nothing says so.
--- Which panes a linemode wants cannot change under a theme reload, so the
--- third value is not wanted here.
local function build()
	local modes, hooks = compile(specs, cfg)
	install(modes, hooks)
end

-- Subscribed at load rather than in `setup`, so calling `setup` twice cannot
-- subscribe twice and there is no flag to keep. Every handler reads module
-- state, which is empty and harmless until `setup` fills it.
--
-- `bulk-rename`, not `bulk`: the event was renamed without saying so, and
-- `ps.sub` accepts an unknown kind without complaining.
ps.sub("theme", build)
ps.sub("cd", moved)
for _, kind in ipairs { "rename", "bulk-rename", "move", "delete", "trash" } do
	ps.sub(kind, invalidate)
end

--- Register a reusable column, before `setup`, then refer to it by name from a
--- linemode spec. Accepts both `.column(name, def)` and `:column(name, def)`.
---
--- The colon call shifts every argument along by one, which one signature
--- cannot say; the `@overload` says it for callers. The dot form is tested
--- first so that the branch the parameters above describe is the branch that
--- reads them, and the casts sit in the colon branch, where the checker is
--- working from the overload rather than from the signature.
---@param a string the column's name
---@param b supaline.ColumnDef its definition
---@overload fun(self: table, name: string, def: supaline.ColumnDef)
function M.column(a, b, c)
	if type(a) == "string" then
		return column.register(a, b)
	end
	-- The colon call. Anything else lands here too and `register` refuses it
	-- by name, which is what it did before when `a` was neither.
	return column.register(b --[[@as string]], c --[[@as supaline.ColumnDef]])
end

--- `_st` is Yazi's per-plugin state table. Nothing in this phase keeps state
--- across calls; the providers added later do, through `ya.sync` blocks
--- declared at the top level of this file.
---@param _st table plugin state, supplied by Yazi
---@param opts supaline.Opts?
---@overload fun(opts: supaline.Opts)
function M.setup(_st, opts)
	-- `.setup{...}` as well as `:setup{...}`, matching `M.column`. The dot form
	-- lands the options in the state parameter, which is Yazi's own table and
	-- never carries `linemodes`; without this the error names the one thing the
	-- user got right.
	if opts == nil and type(_st) == "table" and _st.linemodes ~= nil then
		opts = _st --[[@as supaline.Opts]]
	end
	opts = opts or {}

	-- Everything up to the commit below works on locals. A `setup` that is
	-- refused must leave the configuration already running untouched: the
	-- `theme` handler reads `specs`, so a rejected spec left there would make
	-- every later theme event throw instead of rebuilding.
	---@type supaline.Cfg
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
	local modes, hooks, wants_child = compile(next_specs, next_cfg)

	-- Committed. Nothing below here may raise on a configuration that got this
	-- far.
	cfg, specs = next_cfg, next_specs
	uninstall()
	install(modes, hooks)

	-- Registered whatever `panes` says, because an unregistered name is not
	-- inert: `solo()` draws it as literal text. A linemode that has not asked
	-- for the current pane draws nothing there instead.
	--
	-- `solo()` only dispatches for a row it has already found `in_current`, so
	-- the folder is the current one without asking.
	for name in pairs(specs) do
		ours[name] = true
		installed.names[#installed.names + 1] = name
		installed.prev[name] = Linemode[name]
		Linemode[name] = function(self)
			local mode = linemodes[name]
			if not mode or not mode.panes.current then
				return ""
			end
			return render(mode, self._file, cx.active.current --[[@as supaline.Folder]])
		end
	end

	if wants_child then
		installed.child = Linemode:children_add(child, cfg.order)
	end
end

return M
