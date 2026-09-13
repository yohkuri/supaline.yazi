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
local colour = require(".colour")
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
	-- No `scale` here, on purpose, and it is the only option that is missing
	-- one. The other two have nowhere else to come from; a scale can also be
	-- stated on a column's own definition -- `size` states `log`, because its
	-- values span orders of magnitude where a timestamp's do not -- so a
	-- default written here would have to outrank that definition or lose to it,
	-- and either way one of the two is unreachable.
	--
	-- Left nil instead, so `cfg.scale` means "the user wrote a scale in
	-- `setup`" and nothing else. `column.lua` resolves the three sources in
	-- order and holds the fallback for a column that gets none of them.
	--
	-- No `band` either, for a different reason: its default is two Oklab
	-- lightnesses that only `colour.lua` can justify, so it is kept beside the
	-- measurements that settled it and `colour.bounds` hands it back.
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
---@field extremes fun(get: fun(file: supaline.File): number?): fun(files: supaline.File[]): table?

local M = {}

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
---@field separator supaline.SepValue? overrides the plugin-wide one

--- The table `setup` is handed. `linemodes` is the only field it cannot do
--- without and it is still optional here, because `setup` takes the dot call
--- as well as the colon call and has to look at what arrived before it can
--- say which one it was.
---@class supaline.Opts
---@field linemodes table<string, supaline.LinemodeSpec>?
---@field separator supaline.SepValue?
---@field order integer?
---@field scale "linear"|"log"|nil
---@field band supaline.Band? the lightnesses a band runs between

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
---@field cols table<string, supaline.Column[]> what each pane draws, by pane name
---@field outer boolean whether it draws anywhere but the current pane
---@field sep supaline.Sep what goes between two columns

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

-- The pane last bound, held as its four parts rather than as the composed
-- key. `bind` runs for every visible row on every frame and almost always
-- finds nothing has changed, so the check it does first has to be cheap:
-- `tostring(cwd)` crosses into Rust to build a path string, and the key
-- concatenates three more. Comparing the parts is enough to decide.
--
-- `folder.cwd` is a cached field, so within a frame both sides of the `cwd`
-- test are the same userdata and Lua settles it by pointer without reaching
-- for `__eq` at all; across frames it falls back to one Rust-side path
-- comparison, which still allocates nothing.
local bound_name, bound_pane, bound_cwd, bound_n = nil, nil, nil, nil

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

-- `PANES` as a set, so a key can be classified without walking it. Derived
-- rather than written out, because a list and a set of the same three names
-- are two things to keep in step.
local IS_PANE = {} ---@type table<string, boolean>
for _, pane in ipairs(PANES) do
	IS_PANE[pane] = true
end

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

	-- Every key nobody claimed, rather than the first one found. `pairs` walks
	-- a spec in whatever order the hash gives, so naming one of two
	-- misspellings makes the same mistake report differently from one run to
	-- the next -- and costs a second run to find the other half of it.
	local unknown = {}
	for key in pairs(spec) do
		if type(key) ~= "number" and not IS_PANE[key] and not OPTIONS[key] then
			unknown[#unknown + 1] = string.format("`%s`", tostring(key))
		end
	end
	if #unknown > 0 then
		table.sort(unknown)
		error(string.format(OPTION_HELP, table.concat(unknown, ", ")))
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
---@param pane string the pane being drawn
---@param cols supaline.Column[] what that pane draws
---@param folder supaline.Folder?
local function bind(name, pane, cols, folder)
	if not folder then
		-- The pane is in this test for the same reason it is in the key below,
		-- and is insurance in the same way: only the parent pane can be
		-- without a folder, so the two panes it tells apart cannot both
		-- arrive here.
		if bound_name ~= false or bound_pane ~= pane then
			bound_name, bound_pane, bound_cwd, bound_n = false, pane, nil, nil
			for _, col in ipairs(cols) do
				column.bind(col, {})
			end
		end
		return
	end

	local files, cwd = folder.files, folder.cwd
	local n = #files
	if bound_name == name and bound_pane == pane and bound_n == n and bound_cwd == cwd then
		return
	end

	-- The pane is part of the identity because two panes of one linemode may
	-- draw different columns, and `entries` is positional. Nothing puts one
	-- folder in two panes at once -- the parent, the current and the hovered
	-- directory are three different folders -- so this is insurance rather
	-- than a case anyone has seen, and it costs one comparison on an interned
	-- string.
	local key = name .. "\0" .. pane .. "\0" .. tostring(cwd) .. "\0" .. n
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
	bound_name, bound_pane, bound_cwd, bound_n = name, pane, cwd, n
end

--- Draw one row. The caller has already looked the linemode up, resolved the
--- pane and taken that pane's columns off the mode, because all three had to:
--- `solo()` only dispatches for `in_current` rows, `child` has just asked
--- `pane_of`, and a pane with no columns is how both of them decide there is
--- nothing to draw at all. `folder` is nil for a pane that has none -- the
--- parent of the filesystem root -- which `bind` handles.
---@param mode supaline.Mode
---@param pane string the pane being drawn
---@param cols supaline.Column[] what that pane draws, already looked up
---@param file supaline.File
---@param folder supaline.Folder? the folder the row belongs to
---@return unknown an `AsLine`
local function render(mode, pane, cols, file, folder)
	bind(mode.name, pane, cols, folder)

	local sep, out = mode.sep, {}
	for i, col in ipairs(cols) do
		if i > 1 and col.sep ~= false then
			local one = col.sep or sep
			-- A separator that states no colour goes in as the string it is.
			-- The Span is built per row and cannot be built anywhere else:
			-- `ui.Line` *consumes* what it is given, so one built once and
			-- drawn on every row is refused the second time and the pane stops
			-- drawing altogether. What is built once is the style.
			out[#out + 1] = one.style and ui.Span(one.text):style(one.style) or one.text
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
	local cols = mode.cols[pane]
	if not cols then
		return ""
	end

	-- `solo()` prepends a space to a line that has width; match it, so the two
	-- panes line up. A pane with nothing to draw is absent from `mode.cols`
	-- and was returned on above, so what arrives here is always a Line -- and
	-- one with no width of its own is handed back unwrapped, which is what
	-- `solo()` does with it too.
	local line = render(mode, pane, cols, file, folder)
	return line:visible() and ui.Line { " ", line } or line
end

--- A file operation can move a file between buckets, or change how wide the
--- widest cell is, so drop the cached pass and let the next frame redo it.
local function invalidate()
	cache, cache_n = {}, 0
	bound_name, bound_pane, bound_cwd, bound_n = nil, nil, nil, nil
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
		local sets = panes_of(spec)
		-- Keyed by the list the user wrote rather than by the pane it was
		-- written under, so one list handed to two panes is compiled once and
		-- shared. Sharing is what keeps one `ctx` per column and one `refresh`
		-- per `cd`; only one pane is ever bound at a time, which is what makes
		-- it safe.
		local built, cols = {}, {}
		-- Walked in `PANES` order and not in the spec's, so a spec that
		-- refuses to compile names the same pane every time it is read.
		for _, pane in ipairs(PANES) do
			local list = sets[pane]
			local made = list and built[list]
			if list and not made then
				made = {}
				for i, entry in ipairs(list) do
					local col = column.normalize(entry, with)
					made[i] = col
					if col.refresh then
						hooks[#hooks + 1] = col.refresh
					end
				end
				built[list] = made
			end
			-- A pane that draws nothing is absent rather than empty, which is
			-- what lets both callers decide there is nothing to draw without
			-- asking how many columns there are. Only the current pane can
			-- land here: `panes_of` refuses an empty list under a pane name,
			-- and a linemode with no columns at all is the one that reaches
			-- this with an empty list of its own.
			if made and #made > 0 then
				cols[pane] = made
			end
		end

		-- Resolved per linemode rather than once per build, because the message
		-- has to name the place the separator was written and only one of the
		-- two is a linemode's. It costs a style per linemode on a `theme`
		-- event, which is where `compile` runs from, and nothing per row. The
		-- cast below is what `with.separator` always being set buys: nil is
		-- `column.separator` saying nothing was written, and something was.
		local own, where = spec.separator, string.format("`separator` on linemode `%s`", name)
		if own == nil then
			own, where = with.separator, "`separator` in `setup`"
		end
		local reaches = cols.parent ~= nil or cols.preview ~= nil
		outer = outer or reaches
		modes[name] = {
			name = name,
			cols = cols,
			outer = reaches,
			sep = column.separator(own, where) --[[@as supaline.Sep]],
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

--- Rebuild every linemode from the stored specs. Subscribed to `theme` for
--- two reasons, one of them at startup. `app:theme` re-reads `theme.toml`
--- from disk mid-run, so a base colour resolved once at setup is the old one
--- from then on and nothing says so -- and 26.9.1 merges the flavor *after*
--- `init.lua` has run, announcing it with a `theme` event nobody asked for, so
--- a colour the flavor supplies is a preset's until this handler has run once.
--- Which panes a linemode wants cannot change under a theme reload, so the
--- third value is not wanted here.
---
--- The specs were compiled once already, inside `setup`, and nothing here has
--- touched them since -- but `compile` resolves colours, and on this path the
--- colours are the *theme's*. A `[supaline]` field that supaline refuses --
--- a colour Yazi will not parse, a gradient endpoint that is not `#rrggbb`, a
--- ramp on a column with no `stats` -- reaches this function and nowhere else,
--- because the user wrote it after `setup` had run.
---
--- So the message has to be delivered from here. There is nobody to raise to:
--- this runs from a `ps.sub` handler, and Yazi does not put an error out of one
--- in front of anyone. Editing `theme.toml` and pressing a key bound to
--- `app:theme` is the loop those messages were written for, and the failure
--- without this is a reload that changed nothing and said nothing -- exactly
--- what a plugin that ignored the event looks like.
---
--- Measured on 26.9.1: `ya.notify` from inside a sync `ps.sub` handler draws
--- the notification; it is not one of the calls that need an async context.
--- `ya.err` beside it, because a notification times out and `yazi.log` is
--- where a report of this comes from.
---
--- What is already installed is left alone. `install` is never reached, so the
--- last configuration that did compile keeps drawing -- the same rule `setup`
--- follows when it refuses a spec.
local function build()
	local ok, modes, hooks = pcall(compile, specs, cfg)
	if ok then
		return install(modes, hooks)
	end

	-- What `pcall` hands back is not the string `error` was given. Measured on
	-- 26.9.1: Yazi wraps it as `runtime error: <chunk>:<line>: <message>` and
	-- appends two stack tracebacks, and `ya.notify` draws every line of it --
	-- the notification came out eleven rows tall with the one sentence that
	-- says what to change second. Cut back to that sentence for the screen;
	-- `ya.err` is handed the error itself rather than the trimmed string, and
	-- Yazi renders that as a nested `CallbackError` carrying all three
	-- tracebacks -- which is what a log is for and what a notification is not.
	--
	-- The last pattern is lazy so it takes the shortest source prefix, which is
	-- the one Lua put there; the messages themselves open `supaline: ` and
	-- carry no `:<digits>: ` for it to stop at early. It reaches both
	-- spellings, `[string "supaline.colour"]:85: ` under Yazi and
	-- `./colour.lua:85: ` under the unit suite.
	local why = tostring(modes):gsub("\nstack traceback:.*", ""):gsub("^runtime error: ", ""):gsub("^.-:%d+: ", "")
	ya.err(modes)
	ya.notify { title = "supaline", content = why, level = "error", timeout = 10 }
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

--- The `stats` function the built-in ranged columns use, handed out so a
--- user-written one does not have to write the loop again. `get` reads the
--- value off a file, and is also where a timestamp is floored -- `render` has
--- to floor it the same way, or the two disagree about which step a row is on.
---
--- No colon form, because there is nothing here for `self` to shift: this takes
--- one argument and gives one back, so `supaline.extremes(...)` is the only
--- spelling and a `:` would swallow it.
---@param get fun(file: supaline.File): number?
---@return fun(files: supaline.File[]): table?
function M.extremes(get) return column.extremes(get) end

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
	--
	-- The separator is the one option nothing here refuses. Telling the table
	-- form from a string is `column.separator`'s, and that resolves the colour
	-- a table carries, which has to happen inside a build rather than once at
	-- setup. `compile` below is inside one and runs before the commit, so a
	-- separator written wrong still raises out of `setup` rather than arriving
	-- as a notification an hour later.
	local sep = opts.separator
	if sep == nil then
		sep = DEFAULTS.separator
	end

	---@type supaline.Cfg
	local next_cfg = {
		separator = sep,
		order = opts.order or DEFAULTS.order,
		-- Not `or` a default: see `DEFAULTS`. Nil here is what lets a column
		-- definition's own scale through.
		scale = opts.scale,
		-- Checked in `colour.lua`, where the two numbers mean something and
		-- where the default they fall back to lives. Before the commit, so a
		-- band written wrong leaves the configuration already running alone.
		band = colour.bounds(opts.band, "`band` in `setup`"),
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

	-- Compiling is what validates the columns and the panes, so it also has to
	-- happen before the commit -- and only once, rather than again inside
	-- `build`.
	local modes, hooks, wants_child = compile(next_specs, next_cfg)

	-- Committed. Nothing below here may raise on a configuration that got this
	-- far.
	cfg, specs = next_cfg, next_specs
	uninstall()
	install(modes, hooks)

	-- Registered whether or not the linemode draws in the current pane,
	-- because an unregistered name is not inert: `solo()` draws it as literal
	-- text. One that named the other panes alone draws nothing here instead.
	--
	-- `solo()` only dispatches for a row it has already found `in_current`, so
	-- the folder is the current one without asking.
	for name in pairs(specs) do
		ours[name] = true
		installed.names[#installed.names + 1] = name
		installed.prev[name] = Linemode[name]
		Linemode[name] = function(self)
			local mode = linemodes[name]
			local cols = mode and mode.cols.current
			if not cols then
				return ""
			end
			return render(mode, "current", cols, self._file, cx.active.current --[[@as supaline.Folder]])
		end
	end

	if wants_child then
		installed.child = Linemode:children_add(child, cfg.order)
	end
end

return M
