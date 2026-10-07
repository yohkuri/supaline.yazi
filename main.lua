--- @since 26.9.1
--- @sync entry
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
local schema = require(".schema")
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
---@field entry fun(st: table, job: { args: table })

local M = {}

local registry = column.new_registry()
for name, def in pairs(builtin.definitions()) do
	registry.register(name, def)
end

local active ---@type supaline.Session?

-- What supaline has put on `Linemode`: each linemode it installed, with what
-- that name held before, the child it added, and what each child of another
-- plugin's that a `toggle` hid drew before -- weakly, so a child its plugin
-- has taken out is let go rather than kept until the next `setup`.
---@type { prev: { name: string, was: any }[], child: any?, hidden: table<supaline.LinemodeChild, function> }
local installed = { prev = {}, child = nil, hidden = setmetatable({}, { __mode = "k" }) }

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

--- What a hidden child draws.
local function blank() return "" end

--- Give back what a `toggle` hid: a child that still draws `blank` draws what
--- it drew before. One that has drawn something else since was changed by
--- somebody else, and is theirs.
---@param c supaline.LinemodeChild
---@param draw function
local function unhide(c, draw)
	if c[1] == blank then
		c[1] = draw
	end
end

--- Restore overridden Yazi linemodes, and the children a `toggle` hid, before
--- registering a replacement setup -- whose `toggles` may not name them.
local function uninstall()
	for _, one in ipairs(installed.prev) do
		Linemode[one.name] = one.was
	end
	if installed.child then
		Linemode:children_remove(installed.child)
	end
	for c, draw in pairs(installed.hidden) do
		unhide(c, draw)
	end
	installed = { prev = {}, child = nil, hidden = setmetatable({}, { __mode = "k" }) }
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

--- Hide the children another plugin added at `order`, or show them again.
--- Read off 26.9.1's `linemode.lua`, `redraw` calls whatever a child holds at
--- `[1]` each time it draws, so the child stays where its plugin put it and
--- only what it draws is swapped. Measured on 26.9.1 in a detached tmux, with
--- a child `init.lua` added at 1500 the way git.yazi's `setup` adds its sign:
--- gone at the first press and back at the second, with the columns drawn
--- throughout. Yazi's own two are named by a string where every other child
--- holds something `redraw` calls, and supaline's own child is not another
--- plugin's, so neither is hidden.
---
--- Which of the two a press does is asked of `_children` as it stands, not
--- of what an earlier press recorded: a plugin may have added a child there
--- since -- its `setup` may run after supaline's -- or taken one out and put
--- it back, and a press that showed a child no longer drawn would change
--- nothing on the screen.
---@param name string
---@param order integer
local function flip(name, order)
	local found, any_hidden, children = {}, false, Linemode._children --[[@as supaline.LinemodeChild[] ]]
	for _, c in ipairs(children) do
		if c.order == order and c.id ~= installed.child and type(c[1]) ~= "string" then
			found[#found + 1] = c
			any_hidden = any_hidden or c[1] == blank
		end
	end
	if #found == 0 then
		return tell(
			string.format(
				"supaline: `toggle %s` hides what another plugin added at `order = %d` among `Linemode`'s "
					.. "children, and nothing is there. `toggles` takes the `order` that plugin's `setup` "
					.. "was given -- git.yazi's is 1500 unless its `setup` names another",
				name,
				order
			)
		)
	end
	for _, c in ipairs(found) do
		local draw = installed.hidden[c]
		if not any_hidden then
			installed.hidden[c], c[1] = c[1], blank
		elseif draw then
			unhide(c, draw)
			installed.hidden[c] = nil
		end
	end
	ui.render()
end

-- What a press of `toggle` takes, for every refusal of one.
local USAGE = "`plugin supaline -- toggle <name>` takes one name: a linemode supaline installed, switched to "
	.. "and from `none`, or one of `setup`'s `toggles`"

--- Every name `toggle` would take under `plan`, sorted, for a refusal to list.
---@param plan supaline.Plan
---@return string
local function toggleable(plan)
	local names = {}
	for _, from in ipairs { plan.modes, plan.toggles } do
		for name in pairs(from) do
			names[name] = true
		end
	end
	return schema.quoted(schema.sorted_keys(names))
end

--- `plugin supaline -- toggle <name>`, from a key. A linemode supaline
--- installed is switched to, or to `none` when it is the one showing, in the
--- active tab, as Yazi's own `linemode` is; a name under `toggles` hides or
--- shows another plugin's children in every tab at once, since all of them
--- draw through the one `Linemode`.
---
--- Sync, because otherwise a key runs an entry in a Lua state of its own,
--- where nothing `setup` did is there. Read off 26.9.1's source, a sync entry
--- is handed the module `init.lua`'s `require` loaded, so `active` here is the
--- one `setup` set. Yazi reads `@sync` only among the annotations at the top
--- of the file, and `module_spec.lua` holds it there.
---
--- What is wrong with a press is told rather than raised. Read off 26.9.1's
--- `plugin_do.rs`, an error out of a sync entry reaches the log alone, and a
--- key that does nothing with nothing on the screen to say why is the quiet
--- failure every refusal here exists to prevent.
---@param _st table plugin state supplied by Yazi, unused
---@param job { args: table }
function M.entry(_st, job)
	if not active then
		return tell(
			"supaline: "
				.. USAGE
				.. ", and no configuration is in force: `setup` was never called, or refused what it was handed"
		)
	end
	local plan, args = active.plan, job.args
	-- Anything past the name is a mistake, and dropping it would be the
	-- quiet half of one. So is nothing at all where the name goes, which is
	-- what a binding without the `--` hands over: measured on 26.9.1,
	-- `plugin supaline toggle git` arrives as `toggle` alone.
	local others, _, words = schema.shape(args)
	local name = #others == 0 and words <= 2 and args[2]
	if args[1] ~= "toggle" or type(name) ~= "string" then
		return tell(string.format("supaline: %s -- %s here", USAGE, toggleable(plan)))
	end

	local order = plan.toggles[name]
	if order then
		return flip(name, order)
	elseif plan.modes[name] then
		-- Back to `none` rather than to whatever showed before the switch on:
		-- that would make a second press depend on the presses before it, in
		-- each tab apart, and need a linemode per tab kept by supaline, where
		-- `none` is the one state every tab can be told to be in.
		ya.emit("linemode", { cx.active.pref.linemode == name and "none" or name })
	else
		tell(string.format("supaline: nothing to toggle is called `%s`. %s -- %s here", name, USAGE, toggleable(plan)))
	end
end

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
