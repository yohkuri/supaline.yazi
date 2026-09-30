--- @since 26.9.1
--- @sync entry

--- The fixture's `case` plugin, copied to `config/plugins/case.yazi/main.lua`
--- by `test/setup.py`. Every folder key and every case key the fixture binds
--- runs it, with what to do and which one:
---
---     plugin case -- cd <folder>     go to a folder `cases.toml` lists
---     plugin case -- show <case>     be put in the state a case names
---
--- What either one does is a handful of Yazi's own commands, emitted in order
--- from one key press. Measured on 26.9.1, a `cd`, a `linemode` and a
--- `reveal` emitted together all land.

-- The table `setup.py` writes from `cases.toml`, by absolute path. `dofile`
-- rather than `require`: measured on 26.9.1, a `require` in the main chunk of a
-- sync plugin yields, and the entry fails with "attempt to yield from outside a
-- coroutine" on every press.
local TABLE = dofile("@DIR@/config/plugins/case.yazi/cases.lua")

--- Say that a key named nothing the table holds, which is a fixture out of step
--- with itself rather than anything a reader did.
---@param what string
local function unknown(what)
	ya.notify {
		title = "case",
		content = what .. " is not in the table setup.py wrote from cases.toml",
		timeout = 10,
		level = "error",
	}
end

local M = {}

---@param job { args: string[] }
function M:entry(job)
	local verb, name = job.args[1], job.args[2]

	if verb == "cd" then
		local folder = TABLE.folders[name]
		if not folder then
			return unknown("folder `" .. tostring(name) .. "`")
		end
		ya.emit("cd", { Url(folder) })
		return
	end

	local case = verb == "show" and TABLE.cases[name]
	if not case then
		return unknown("case `" .. tostring(name) .. "`")
	end

	-- A `cd` to the folder already showing moves neither the hover nor the
	-- scroll, measured on 26.9.1, so a case pressed where it already is changes
	-- the linemode alone. `reveal` moves both, which is what a case that names
	-- a row asks for.
	if case.hover then
		ya.emit("reveal", { Url(case.folder):join(case.hover) })
	else
		ya.emit("cd", { Url(case.folder) })
	end
	ya.emit("linemode", { case.linemode })

	-- Switching the linemode does not re-peek, so without this the preview pane
	-- goes on showing what the last linemode drew into it until the hover
	-- moves. Measured on 26.9.1: a forced peek after the switch draws the new
	-- linemode's columns into a folder preview straight away.
	ya.emit("peek", { force = true })
end

return M
