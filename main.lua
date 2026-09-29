--- @since 26.9.1
--- Yazi adapter and public API. The only module that reads `cx`, `th` and
--- `ya`, subscribes and installs; everything under it is handed what it needs.
---
--- Three lifetimes: a plan per `setup`, an appearance per theme, prepared
--- folders per listing. A theme event keeps the plan and its report gates and
--- replaces the rest.
local appearance = require(".appearance")
local builtin = require(".builtin")
local column = require(".column")
local config = require(".config")
local report = require(".report")
local runtime = require(".runtime")

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

---@class supaline.Session
---@field plan supaline.Plan
---@field runtime supaline.Runtime
---@field reporter supaline.Reporter

local active ---@type supaline.Session?
local installed = { prev = {}, child = nil } ---@type table

-- Yazi keeps the component's machinery on the table linemodes are looked up
-- on, so a linemode named after any of it replaces it -- `new` takes out the
-- constructor. `Linemode` is asked what it holds rather than listed, since
-- Yazi adds to it between releases. Only Yazi's own linemodes are exempt;
-- `none` is not, because `solo()` returns before it could dispatch to it.
local OVERRIDABLE = {
	size = true,
	permissions = true,
	btime = true,
	mtime = true,
	atime = true,
	owner = true,
}

-- Names supaline itself put on `Linemode`, so a second `setup` does not refuse
-- what the first registered.
local ours = {} ---@type table<string, boolean>

---@param name string
---@return boolean
local function is_yazis(name)
	if OVERRIDABLE[name] or ours[name] then
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
--- and the log keeps the traceback.
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

--- The parent- and preview-pane child. Yazi calls a child for rows in every
--- pane, where `solo()` guards `in_current` for itself, so the current pane
--- is refused here or it would draw twice.
local function child(self)
	local file = self._file --[[@as supaline.File]]
	if file.in_current or not active then
		return ""
	end
	local name = cx.active.pref.linemode
	local mode = name and active.plan.modes[name]
	if not mode or not mode.outer then
		return ""
	end
	local pane, folder = pane_of(file)
	if not mode.panes[pane] then
		return ""
	end
	local line = active.runtime.render(mode, pane, file, folder)
	-- Match solo()'s leading space, including its empty-line behaviour.
	return line:visible() and ui.Line { " ", line } or line
end

local function invalidate()
	if active then
		active.runtime.invalidate()
	end
end

local function moved()
	if not active then
		return
	end
	active.runtime.invalidate()
	active.runtime.refresh()
end

--- Resolve the plan against the theme as it is now. Yazi fires this unasked a
--- few milliseconds after `init.lua`, when the flavor lands, and again on
--- every `app:theme`. A refusal keeps the last appearance drawing, and says
--- so: raised from here it would reach nobody. What `pcall` hands back is
--- Yazi's wrapping of it -- `schema.lua` says why -- so the screen gets its
--- first line, which is the refusal as it was written.
local function build()
	if not active then
		return
	end
	local ok, got = pcall(appearance.resolve, active.plan, th.supaline or {})
	if not ok then
		return tell(got, report.one_line(got))
	end
	active.runtime = runtime.new(active.plan, got, active.reporter)
	active.runtime.refresh()
end

-- Subscribed once at load, so a repeated `setup` replaces the active session
-- rather than stacking a second subscription onto it.
ps.sub("theme", build)
ps.sub("cd", moved)
for _, kind in ipairs { "rename", "bulk-rename", "move", "delete", "trash" } do
	ps.sub(kind, invalidate)
end

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
function M.extremes(get) return runtime.extremes(get) end

--- Compile and resolve before anything is replaced, so a refusal leaves the
--- running session as it was.
---@param _st table plugin state supplied by Yazi, unused
---@param opts supaline.Opts?
---@overload fun(opts: supaline.Opts)
function M.setup(_st, opts)
	if opts == nil and type(_st) == "table" and _st.linemodes ~= nil then
		opts = _st --[[@as supaline.Opts]]
	end
	local plan = config.compile(opts or {}, registry, is_yazis)
	local look = appearance.resolve(plan, th.supaline or {})
	local reporter = report.new(tell)
	local candidate = { plan = plan, reporter = reporter, runtime = runtime.new(plan, look, reporter) }

	-- Nothing below may raise: the old session is gone by the next line. A
	-- `refresh` is a column's own code and the runtime contains it.
	uninstall()
	active = candidate
	active.runtime.refresh()
	for name in pairs(plan.modes) do
		ours[name] = true
		installed.prev[#installed.prev + 1] = { name = name, was = Linemode[name] }
		Linemode[name] = function(self)
			local mode = active.plan.modes[name]
			if not mode or not mode.panes.current then
				return ""
			end
			return active.runtime.render(mode, "current", self._file, cx.active.current --[[@as supaline.Folder]])
		end
	end
	if plan.outer then
		installed.child = Linemode:children_add(child, plan.order)
	end
end

return M
