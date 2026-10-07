--- @since 26.9.1
--- Yazi adapter and public API. The only module that reads `cx`, `th` and
--- `ya`, subscribes and installs; everything under it is handed what it needs.
---
--- Three lifetimes: a plan per `setup`, an appearance per theme, prepared
--- folders per listing. A session, in `session.lua`, is one plan with the
--- other two; this file holds the active session, and what it has put on
--- `Linemode`.
local builtin = require(".builtin")
local column = require(".column")
local config = require(".config")
local session = require(".session")

--- The module table, as a spec sees it.
---
--- In this checkout and on the CI runner, `require(".main")` resolves to
--- `types.yazi`'s own `main.lua` -- annotations and no `return` -- so without
--- this class every call a spec makes into the plugin is checked against a
--- module that exports nothing, silently. Each entry point takes a dot call
--- and a colon call, and a `@field` carries no `@overload`, so each is the
--- union of its two shapes. `annotate-supaline/references/main-collision.md`
--- has the measurement and the paths that flip it.
---@class supaline.Main
---@field setup fun(st: table, opts: supaline.Opts?)|fun(opts: supaline.Opts)
---@field column fun(name: string, def: supaline.ColumnDef)|fun(self: table, name: string, def: supaline.ColumnDef)
---@field extremes fun(get: fun(file: supaline.File): number?): fun(files: supaline.File[]): table?

local M = {}

local registry = column.new_registry()
for name, def in pairs(builtin.definitions()) do
	registry.register(name, def)
end

local active ---@type supaline.Session?

-- What supaline has put on `Linemode`: each linemode it installed, with what
-- that name held before, and the child it added.
---@type { prev: { name: string, was: any }[], child: any? }
local installed = { prev = {}, child = nil }

-- Yazi keeps the component's machinery on the table linemodes are looked up
-- on, so a linemode named after any of it replaces it -- `new` takes out the
-- constructor. `Linemode` is asked what it holds rather than listed, since
-- Yazi adds to it between releases. Only Yazi's own linemodes are exempt;
-- `none` is not on the table at all, and `config.lua` refuses it by name.
local OVERRIDABLE = {
	size = true,
	permissions = true,
	btime = true,
	mtime = true,
	atime = true,
	owner = true,
}

--- Whether a linemode of this name would replace part of Yazi's `Linemode`.
--- What supaline installed itself does not, so a second `setup` does not
--- refuse what the first registered. Asked while `setup` compiles, before the
--- active session is replaced, so its linemodes are the ones on `Linemode`; a
--- name an earlier session installed holds what it held before again, and is
--- asked about like any other.
---@param name string
---@return boolean
local function is_yazis(name)
	if OVERRIDABLE[name] or (active and active.plan.modes[name]) then
		return false
	end
	return Linemode[name] ~= nil or name:sub(1, 1) == "_"
end

--- Which pane outside the current one a row is in, and its folder, which is
--- where its statistics come from. Asked only of a row not `in_current`.
---
--- `in_preview` is not the counterpart of `in_current`: it holds for the
--- previewed folder's cursor row alone, and there is no `in_parent`. So the
--- preview folder is asked whether the row is its own -- `file.idx` is the
--- row's position in its own folder, so this is O(1).
---@param file supaline.File
---@return string pane, supaline.Folder? folder
local function pane_of(file)
	-- Cast at the boundary: what makes Yazi's folder a `supaline.Folder` is
	-- this plugin's claim about its listing.
	local folder = cx.active.preview.folder --[[@as supaline.Folder?]]
	local at = folder and folder.files[file.idx]
	if at and at.url == file.url then
		return "preview", folder
	end
	return "parent", cx.active.parent --[[@as supaline.Folder?]]
end

--- Put a report in the log in full and a short form of it on the screen. A
--- notification long enough to fill the preview pane pushes its own first
--- line off the top -- measured on 26.9.1 -- so the screen gets one sentence
--- and the log keeps the whole.
---@param logged any the whole of it
---@param shown string? the sentence for the screen, if it is not the whole
local function tell(logged, shown)
	ya.err(logged)
	ya.notify { title = "supaline", content = shown or logged, level = "error", timeout = 20 }
end

--- Restore overridden Yazi linemodes before registering a replacement setup.
local function uninstall()
	for _, one in ipairs(installed.prev) do
		Linemode[one.name] = one.was
	end
	if installed.child then
		Linemode:children_remove(installed.child)
	end
	installed = { prev = {}, child = nil }
end

--- The parent- and preview-pane child, drawing with `current`. Yazi calls a
--- child for rows in every pane, where `solo()` guards `in_current` for
--- itself, so the current pane is refused here or it would draw twice.
---@param current supaline.Session
local function child(current, self)
	local file = self._file --[[@as supaline.File]]
	if file.in_current then
		return ""
	end
	local name = cx.active.pref.linemode
	local mode = name and current.plan.modes[name]
	if not mode or not mode.outer then
		return ""
	end
	local pane, folder = pane_of(file)
	if not mode.panes[pane] then
		return ""
	end
	local line = current.draw(mode, pane, file, folder)
	-- Match solo()'s leading space, including its empty-line behaviour.
	return line:visible() and ui.Line { " ", line } or line
end

--- Put the session's linemodes on `Linemode`, and the child that draws the
--- other two panes when any linemode asks for one. Each draws with the
--- session it was installed for: the next `setup` uninstalls it before
--- another session can be active.
---@param current supaline.Session
local function install(current)
	local plan = current.plan
	for name, mode in pairs(plan.modes) do
		installed.prev[#installed.prev + 1] = { name = name, was = Linemode[name] }
		-- Handed no width. Read off 26.9.1's source, only Current, Parent and
		-- the folder previewer hold an `_area`, so dropping columns by priority
		-- as a pane narrows would mean replacing their `redraw`; a list per pane
		-- is the answer to a narrow one.
		Linemode[name] = function(self)
			if not mode.panes.current then
				return ""
			end
			return current.draw(mode, "current", self._file, cx.active.current --[[@as supaline.Folder]])
		end
	end
	if plan.outer then
		installed.child = Linemode:children_add(function(self) return child(current, self) end, plan.order)
	end
end

-- Subscribed once at load, so a repeated `setup` replaces the active session
-- rather than stacking a second subscription onto it. Yazi fires `theme`
-- unasked a few milliseconds after `init.lua`, when the flavor lands, and
-- again on every `app:theme`.
ps.sub("theme", function()
	if active then
		active.retheme(th.supaline or {})
	end
end)
ps.sub("cd", function()
	if active then
		active.moved()
	end
end)
for _, kind in ipairs { "rename", "bulk-rename", "move", "delete", "trash" } do
	ps.sub(kind, function()
		if active then
			active.invalidate()
		end
	end)
end
-- A folder is prepared once per file count, and a listing can change without
-- its count changing: a file written from outside, or a directory's size
-- arriving after the listing under `sort_by = "size"`. Measured on 26.9.1,
-- neither is a `cd` or a file operation, and each publishes `load` for that
-- folder.
--
-- Only the folder it names is forgotten. Yazi publishes it for every folder
-- the cursor previews too, and forgetting all of them was measured to cost a
-- stats pass over the current folder for each step down a list of
-- directories -- eleven for ten steps, 2.4ms a column over 10000 files.
--
-- The frame is asked for here because Yazi draws the change before it calls
-- this: measured, the row showed a directory's new size under the extremes
-- taken without it, and nothing drew again until the next key.
--
-- No key recomputes everything, because this already reaches every listing
-- one could fix: read off 26.9.1's source, `yazi-core/src/tab/folder.rs`
-- publishes `load` whenever a folder's entries or stage change. What else
-- goes stale is a `refresh`'s until the next `cd` -- the year in a session
-- that never moves, the permission styles after a theme supaline refused --
-- and `builtin.lua` says both.
ps.sub("load", function(body)
	-- Cast at the boundary: `load` always carries the folder's URL.
	local url = (body --[[@as { url: any }]]).url
	if active and active.forget(url) then
		ui.render()
	end
end)

--- Register a reusable column, before `setup`, to be named from a linemode.
--- Takes `.column(name, def)` and `:column(name, def)` alike.
---@param a string the column's name
---@param b supaline.ColumnDef its definition
---@overload fun(self: table, name: string, def: supaline.ColumnDef)
function M.column(a, b, c)
	if type(a) == "string" then
		return registry.register(a, b)
	end
	-- The colon call. Anything else lands here too, and `register` refuses it.
	return registry.register(b --[[@as string]], c --[[@as supaline.ColumnDef]])
end

--- The `stats` the built-in ranged columns use, for a user-written one. `get`
--- reads the value off a file and is where a timestamp is floored -- `render`
--- has to floor it the same way. No colon form: this takes one argument.
---@param get fun(file: supaline.File): number?
---@return fun(files: supaline.File[]): table?
function M.extremes(get) return builtin.extremes(get) end

--- Compile and resolve before anything is replaced, so a refusal leaves the
--- running session as it was.
---@param _st table plugin state supplied by Yazi, unused
---@param opts supaline.Opts?
---@overload fun(opts: supaline.Opts)
function M.setup(_st, opts)
	-- The dot call: what arrived first is the options, or something that
	-- was meant to be and is refused as them. Not a helper shared with
	-- `column`, which tells its two calls apart by another test: a shared one
	-- would take the test as an argument.
	if opts == nil and (type(_st) ~= "table" or _st.linemodes ~= nil) then
		opts = _st --[[@as supaline.Opts]]
	end
	local plan = config.compile(opts or {}, registry, is_yazis)
	local candidate = session.new(plan, th.supaline or {}, tell)

	-- Nothing below may raise: the old session is gone by the next line. A
	-- `refresh` is a column's own code and the session contains it.
	uninstall()
	active = candidate
	candidate.refresh()
	install(candidate)
end

return M
