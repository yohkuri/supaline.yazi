--- @since 26.9.1
--- Yazi adapter and public API. Configuration, appearance and folder state have
--- separate lifetimes; only this module installs components and subscribes DDS.
local builtin = require(".builtin")
local column = require(".column")
local config = require(".config")
local diagnostics = require(".diagnostics")
local runtime = require(".runtime")
local style = require(".style")

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

--- Put a report in the log in full and a short form of it on the screen.
---
--- Both halves, always, and that pairing is the whole of what this holds. A
--- notification times out and is gone; `yazi.log` is where a reader goes
--- afterwards, and where a traceback or a nested `CallbackError` is worth
--- keeping at whatever length it comes in. What the screen gets is cut to the
--- sentence that says what to change, because a notification long enough to
--- fill the preview pane pushes its own first line off the top of it --
--- measured twice, on `build`'s three stacked tracebacks and on `broke`'s.
---
--- The four callers word their own strings and share nothing else; what they
--- must not each decide is the level, the timeout and the title. Two of them
--- pass one string, which says the whole of it is already short enough for the
--- screen -- a refusal supaline worded itself, rather than something a
--- traceback came wrapped around.
---@param logged any the whole of it, error object or string
---@param shown string? the one sentence for the screen, if it is not the whole
local function report(logged, shown)
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
	if not mode.cols[pane] then
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

--- Theme resolution is transactional. In particular, the unasked startup
--- theme event must replace the preset colours once the flavor has arrived.
--- Keep the plan and its report gates; discard all folder-derived state, since
--- a custom render/refresh may derive even its width from the theme.
local function build()
	if not active then
		return
	end
	local ok, appearance = pcall(style.resolve, active.plan, th.supaline or {})
	if not ok then
		return report(appearance, diagnostics.one_line(appearance):gsub("^.-:%d+: ", ""))
	end
	active.runtime = runtime.new(active.plan, appearance, active.reporter)
	active.runtime.refresh()
end

-- Subscribe once at load. A repeated setup only changes the active session.
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
		return registry.register(a, b)
	end
	-- The colon call. Anything else lands here too and `register` refuses it
	-- by name, which is what it did before when `a` was neither.
	return registry.register(b --[[@as string]], c --[[@as supaline.ColumnDef]])
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

--- Compile and resolve on locals; a refusal leaves the active session intact.
---@param _st table plugin state supplied by Yazi, unused
---@param opts supaline.Opts?
---@overload fun(opts: supaline.Opts)
function M.setup(_st, opts)
	if opts == nil and type(_st) == "table" and _st.linemodes ~= nil then
		opts = _st --[[@as supaline.Opts]]
	end
	local plan = config.compile(opts or {}, registry, is_yazis)
	local appearance = style.resolve(plan, th.supaline or {})
	local reporter = diagnostics.new(report)
	local candidate = { plan = plan, reporter = reporter, runtime = runtime.new(plan, appearance, reporter) }

	-- Configuration work is finished. User refresh hooks are contained by the
	-- runtime, so they cannot interrupt replacement halfway through registration.
	uninstall()
	active = candidate
	active.runtime.refresh()
	for name in pairs(plan.modes) do
		ours[name] = true
		installed.prev[#installed.prev + 1] = { name = name, was = Linemode[name] }
		Linemode[name] = function(self)
			local mode = active.plan.modes[name]
			if not mode or not mode.cols.current then
				return ""
			end
			return active.runtime.render(mode, "current", self._file, cx.active.current --[[@as supaline.Folder]])
		end
	end
	if plan.outer then
		installed.child = Linemode:children_add(child, plan.cfg.order)
	end
end

return M
