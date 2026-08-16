--- @since 26.8.15
--- supaline -- a column framework for Yazi's linemode.
---
--- `setup` turns each entry of `linemodes` into a real linemode, so
--- `mgr.linemode` and the `linemode` action can switch between them the same
--- way they switch between the presets.
---
--- Rendering runs for every visible row on every frame, so it does nothing but
--- read from tables: gradient ramps are built once at setup, and per-folder
--- statistics are computed once per folder and cached here.

local chezmoi = require(".chezmoi")
local column = require(".column")
local git = require(".git")
require(".builtin")

-- A plugin's sync state is scoped to the *file* its `ya.sync` call appears in,
-- not to the plugin as a whole -- a closure created inside git.lua writes to a
-- state that `setup`, running here, never sees. So every sync proxy is created
-- here instead, and handed to the providers.
--
-- They are also created unconditionally and in a fixed order: Yazi matches the
-- async and sync sides by the position of the `ya.sync` call, so anything
-- conditional or iteration-ordered would risk binding the wrong function.
local git_add = ya.sync(git.reduce_add)
local git_remove = ya.sync(git.reduce_remove)
local cz_claim = ya.sync(chezmoi.reduce_claim)
local cz_commit = ya.sync(chezmoi.reduce_commit)
local cz_abandon = ya.sync(chezmoi.reduce_abandon)

local DEFAULTS = {
	separator = " ",
	gradient = {
		-- "relative" follows eza: normalise against the extremes of the current
		-- listing. "off" keeps the flat base colour.
		mode = "relative",
		-- "auto" enables the ramp only when the terminal advertises 24-bit
		-- colour; "truecolor" forces it on, "off" forces it off.
		colors = "auto",
		-- "linear" is what eza does. "log" spreads a listing whose values span
		-- orders of magnitude -- worth setting on the `size` column.
		scale = "linear",
		steps = 24,
		min_luminance = 50,
	},
}

local M = {}

local cfg = DEFAULTS
local specs = {} ---@type table<string, table> the user's linemode definitions
local linemodes = {} ---@type table<string, table> normalised columns
local cache = { key = nil, values = {} }

--- Per-folder statistics, shared by every column of the active linemode.
---
--- The key deliberately includes the folder's file count: adding or removing a
--- file shifts the extremes, and that is the common case. Editing a file in
--- place without changing the count leaves the ramp slightly stale until the
--- next file operation or `cd` -- a trade we make to keep this O(1) per row.
---@param name string
---@param cols table
---@return table
local function stats_for(name, cols)
	local folder = cx.active.current
	local files = folder.files
	local key = name .. "\0" .. tostring(folder.cwd) .. "\0" .. #files

	if cache.key == key then
		return cache.values
	end

	local values = {}
	for i, col in ipairs(cols) do
		if col.stats then
			values[i] = col.stats(files)
		end
	end

	cache.key, cache.values = key, values
	return values
end

---@param name string
---@param file table `fs::File`
---@return unknown an `ui.Line`
local function render(name, file)
	local cols = linemodes[name]
	if not cols or #cols == 0 then
		return ""
	end

	local stats = stats_for(name, cols)
	local out = {}
	for i, col in ipairs(cols) do
		col.ctx.stats = stats[i]
		if i > 1 then
			out[#out + 1] = cfg.separator
		end
		out[#out + 1] = column.cell(col, file)
	end
	return ui.Line(out)
end

---@param spec table
---@param name string
---@return boolean
local function references(spec, name)
	for _, entry in ipairs(spec) do
		if entry == name or (type(entry) == "table" and entry[1] == name) then
			return true
		end
	end
	return false
end

--- (Re)build every linemode from the stored specs. Run at setup and again
--- whenever the theme reloads, since a new theme can change the base colours
--- the ramps are derived from.
local function build()
	for name, spec in pairs(specs) do
		local cols = {}
		for i, entry in ipairs(spec) do
			cols[i] = column.normalize(entry, cfg)
		end
		linemodes[name] = cols
	end
	cache.key = nil
end

--- Register a reusable column. Call this *before* `setup`, then refer to it by
--- name from a linemode spec:
---
---     require("supaline").column("nlink", { width = 3, render = ... })
---
---@param name string
---@param def table
function M.column(name, def) column.register(name, def) end

---@param st table plugin state, supplied by Yazi
---@param opts table?
function M.setup(st, opts)
	opts = opts or {}

	cfg = {
		separator = opts.separator or DEFAULTS.separator,
		gradient = {},
	}
	for k, v in pairs(DEFAULTS.gradient) do
		cfg.gradient[k] = (opts.gradient or {})[k] == nil and v or opts.gradient[k]
	end

	specs = opts.linemodes or {}
	if not next(specs) then
		error("supaline: `linemodes` is empty; nothing to render")
	end

	-- Bring up only the providers a linemode actually asks for, so an unused
	-- one costs no subscriptions and spawns no processes.
	local wants = { git = false, chezmoi = false }
	for _, spec in pairs(specs) do
		for name in pairs(wants) do
			wants[name] = wants[name] or references(spec, name)
		end
	end
	if wants.git then
		git.setup(st, opts.git)
	end
	if wants.chezmoi then
		chezmoi.setup(st, opts.chezmoi)
	end

	build()

	-- A file operation can move a file between size/time buckets, so drop the
	-- cached extremes and let the next frame recompute them.
	--
	-- `bulk-rename`, not `bulk`: Yazi 26.8.15 renamed the event without saying
	-- so in its changelog, and an unknown kind subscribes silently.
	local invalidate = function() cache.key = nil end
	for _, kind in ipairs { "rename", "bulk-rename", "move", "delete", "trash" } do
		ps.sub(kind, invalidate)
	end
	ps.sub("theme", build)

	for name in pairs(specs) do
		Linemode[name] = function(self) return render(name, self._file) end
	end
end

--- Fetcher entry. Providers are selected by argument -- `run = "supaline git"`
--- -- rather than by their own plugin entry, so that everything shares the one
--- state these sync proxies were bound to.
---
--- Yazi 26.8.15 replaced the old `(boolean, Err?)` return with a function that
--- reports one file per call. The providers still answer for the batch as a
--- whole, so their verdict is replayed here, file by file. `retry` is the old
--- boolean inverted: returning `false` used to mean "clear the loaded bit and
--- run me again on the next visit", which is how the Git column stays fresh.
---@param job table
---@return fun(): unknown?, table? drained by Yazi until it yields nothing
function M.fetch(_, job)
	local which = job.args and job.args[1]

	local done, err
	if which == "git" then
		done, err = git.fetch(job, git_add, git_remove)
	elseif which == "chezmoi" then
		done, err = chezmoi.fetch(job, cz_claim, cz_commit, cz_abandon)
	else
		done, err = true, Err('supaline: fetcher needs a provider argument, e.g. `run = "supaline git"`')
	end

	-- Every file has to be reported exactly once: Yazi retries whatever is left
	-- out and logs the fetcher as having quit early, and reporting one twice is
	-- a hard error. The error rides on the first file alone, so a batch-wide
	-- failure is logged once rather than once per file.
	local retry = done == false
	return ya.co(function()
		for _, file in ipairs(job.files) do
			coroutine.yield(file, { retry = retry, error = err })
			err = nil
		end
	end)
end

return M
