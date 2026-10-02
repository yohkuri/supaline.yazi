--- @since 26.9.1
--- @sync entry

--- The fixture's `case` plugin, copied to `config/plugins/case.yazi/main.lua`
--- by `test/setup.py`. Every folder, case and theme key the fixture binds
--- runs it, with what to do and which one:
---
---     plugin case -- cd <folder>     go to a folder `cases.toml` lists
---     plugin case -- show <case>     be put in the state a case names
---     plugin case -- theme <theme>   put a theme `cases.toml` lists in place
---
--- What each one does is a handful of Yazi's own commands, emitted in order
--- from one key press. Measured on 26.9.1, a `cd`, a `linemode` and a
--- `reveal` emitted together all land, and so does a `cd` emitted straight
--- after a `theme`'s `shell`, whose theme the screen then draws.

-- Where every folder the bindings and the table name is, and the script that
-- puts a theme in place, filled in by `setup.py` as every file it copies is.
-- Here rather than in either of those, so that what they carry is a name alone,
-- which needs no quoting in a keymap's `run` or in Yazi's own argument parser.
local ROOT = "@DIR@/fixture/"
local THEME_KEY = "'@DIR@/theme-key.py' "

-- The table `setup.py` writes from `cases.toml`: each case by its `id`, and
-- each theme by its `name`. `dofile` rather than `require`: measured on 26.9.1,
-- a `require` in the main chunk of a sync plugin yields, and the entry fails
-- with "attempt to yield from outside a coroutine" on every press.
local LISTED = dofile("@DIR@/config/plugins/case.yazi/cases.lua")

--- Say that a key named a case or a theme the table does not hold, which is a
--- fixture out of step with itself rather than anything a reader did.
---@param kind string
---@param name string?
local function unknown(kind, name)
	ya.notify {
		title = "case",
		content = kind .. " `" .. tostring(name) .. "` is not in the table setup.py wrote from cases.toml",
		timeout = 10,
		level = "error",
	}
end

local M = {}

---@param job { args: string[] }
function M:entry(job)
	local verb, name = job.args[1], job.args[2]

	if verb == "cd" then
		ya.emit("cd", { Url(ROOT .. name) })
		return
	end

	-- The script reloads once its copy has landed, which is why the reload is
	-- not emitted from here: a reload emitted beside the `shell` runs before
	-- the copy, measured on 26.9.1, and keeps the old theme. Its docstring has
	-- the rest. A name in the table needs no quoting, so it goes in bare.
	if verb == "theme" then
		if not LISTED.themes[name] then
			return unknown("theme", name)
		end
		ya.emit("shell", { THEME_KEY .. name, confirm = true })
		return
	end

	local case = verb == "show" and LISTED.cases[name]
	if not case then
		return unknown("case", name)
	end

	-- A `cd` to the folder already showing moves neither the hover nor the
	-- scroll, measured on 26.9.1, so a case pressed where it already is changes
	-- the linemode alone. `reveal` moves both, which is what a case that names
	-- a row asks for.
	if case.hover then
		ya.emit("reveal", { Url(ROOT .. case.folder .. "/" .. case.hover) })
	else
		ya.emit("cd", { Url(ROOT .. case.folder) })
	end
	ya.emit("linemode", { case.linemode })

	-- Switching the linemode does not re-peek, so without this the preview pane
	-- goes on showing what the last linemode drew into it until the hover
	-- moves. Measured on 26.9.1: a forced peek after the switch draws the new
	-- linemode's columns into a folder preview straight away.
	ya.emit("peek", { force = true })
end

return M
