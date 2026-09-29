--- @since 26.9.1
--- Folders prepared for drawing, and the rows drawn from them. A plan and an
--- appearance are read-only inputs; each prepared folder owns its contexts.
---
--- Every call into a column's own code is made here under `pcall`. Measured on
--- 26.9.1: an error raised under a linemode's render blanks the whole screen,
--- on every frame, and `refresh` runs from places nobody can raise to.
local layout = require(".layout")
local report = require(".report")
local schema = require(".schema")

---@class supaline.RuntimeModule
local M = {}

--- What a `render` is handed beside the file.
---@class supaline.Ctx
---@field style unknown the flat style, or the ramp's low end
---@field fg_written boolean an explicit foreground, including false
---@field opts table<string, any> declared column options only
---@field stats any the column's folder statistics
---@field width integer? effective width, already capped
---@field ratio fun(value: number?): number?
---@field style_at fun(ratio: number?): unknown

---@class supaline.Prepared
---@field cell supaline.Cell
---@field ctx supaline.Ctx
---@field sep_style unknown? the style the separator before the cell is drawn in, nil for none

---@class supaline.Runtime
---@field render fun(mode: supaline.ModePlan, pane: string, file: supaline.File, folder: supaline.Folder?): unknown
---@field invalidate fun()
---@field refresh fun()

---@param stats any
---@return boolean
function M.has_extremes(stats)
	return type(stats) == "table" and type(stats.min) == "number" and type(stats.max) == "number"
end

--- The context one column is drawn with in one folder. The range lives in
--- the closures rather than on the context, so a context handed out is never
--- rebound to another folder.
---@param col supaline.ColumnPlan
---@param look supaline.Resolved
---@param stats any
---@return supaline.Ctx
function M.context(col, look, stats)
	local lo, hi
	local log = col.scale == "log"
	if M.has_extremes(stats) then
		lo, hi = stats.min, stats.max
		if log then
			lo, hi = math.log(lo + 1), math.log(hi + 1)
		end
	end
	local ctx = {
		style = look.style,
		fg_written = look.fg_written,
		opts = col.options,
		stats = stats,
		width = col.width.value,
	}
	function ctx.ratio(value)
		if not value or not lo then
			return nil
		end
		if hi == lo then
			return 1
		end
		local v = log and math.log(value + 1) or value
		local r = (v - lo) / (hi - lo)
		return r < 0 and 0 or r > 1 and 1 or r
	end
	local steps = look.steps
	if steps then
		local n, last = #steps, #steps - 1
		function ctx.style_at(r)
			if r == nil then
				return ctx.style
			end
			local i = 1 + math.floor(r * last + 0.5)
			-- A log scale over extremes at or below -1 makes a NaN, which
			-- answers false to every comparison.
			if not (i >= 1) then
				i = 1
			elseif i > n then
				i = n
			end
			return steps[i]
		end
	else
		function ctx.style_at(_) return ctx.style end
	end
	return ctx
end

---@param width integer
---@param max integer?
---@return integer
local function cap(width, max) return max and width > max and max or width end

--- A column's width in one folder. What a `width` function returns that is
--- no count of cells is supaline's refusal, and comes back, as written,
--- beside a nil rather than raised: the caller's `pcall` could not tell it
--- from the function throwing.
---@param col supaline.ColumnPlan
---@param ctx supaline.Ctx
---@param files supaline.File[]
---@return integer?
---@return string? refused what a `width` function returned instead, as written
function M.width(col, ctx, files)
	local width = col.width
	if width.kind == "computed" then
		local w = width.compute(ctx.stats)
		local cells = schema.cells_of(w)
		if not cells then
			return nil, schema.as_written(w)
		end
		return cap(cells, col.max_width)
	elseif width.kind ~= "auto" then
		return width.value
	end
	local widest = 0
	for i = 1, #files do
		widest = math.max(widest, layout.measure(col.render(files[i], ctx)))
	end
	return cap(widest, col.max_width)
end

---@param plan supaline.Plan
---@param appearance supaline.Appearance
---@param reporter supaline.Reporter survives a theme replacement, not a setup
---@return supaline.Runtime
function M.new(plan, appearance, reporter)
	-- At most eight folders, cleared whole when a ninth arrives.
	local cache, cache_n = {}, 0 ---@type table<string, supaline.Prepared[]>, integer
	local last_mode, last_pane, last_cwd, last_n, last_prepared

	local function invalidate()
		cache, cache_n = {}, 0
		last_mode, last_pane, last_cwd, last_n, last_prepared = nil, nil, nil, nil, nil
	end

	---@param cells supaline.Cell[]
	---@param files supaline.File[]?
	---@return supaline.Prepared[]
	local function prepare(cells, files)
		local prepared = {}
		for i, cell in ipairs(cells) do
			local col = cell.column
			local look, stats = appearance[col.slot], nil
			if files and col.stats then
				local ok, got = pcall(col.stats, files)
				if ok then
					stats = got
				else
					reporter.threw(col, "stats", got)
				end
				if look.steps and stats ~= nil and not M.has_extremes(stats) then
					reporter.stats(col)
				end
			end
			-- Published only once the width pass is done, so a render measured
			-- for `auto` sees `width` nil and nothing else does.
			local ctx = M.context(col, look, stats)
			if files and col.needs_pass then
				local ok, got, refused = pcall(M.width, col, ctx, files)
				if not ok then
					reporter.threw(col, col.width.kind == "computed" and "width" or "render", got)
				elseif refused then
					reporter.width(col, refused)
				else
					ctx.width = got
				end
			end
			local sep = cell.sep and cell.sep.slot and appearance[cell.sep.slot]
			prepared[i] = { cell = cell, ctx = ctx, sep_style = sep and sep.written and sep.style or nil }
		end
		return prepared
	end

	--- A missing folder is a pane of its own too: two linemodes drawing the
	--- filesystem root's absent parent must not share a context. Its key has
	--- one separator where a folder's has three, so no folder can spell it.
	---@param mode supaline.ModePlan
	---@param pane string
	---@param folder supaline.Folder?
	---@return supaline.Prepared[]
	local function prepared_for(mode, pane, folder)
		local files, cwd = folder and folder.files, folder and folder.cwd
		local n = files and #files or 0
		if last_mode == mode and last_pane == pane and last_cwd == cwd and last_n == n then
			return last_prepared
		end
		local key = mode.name .. "\0" .. pane
		if cwd then
			key = key .. "\0" .. tostring(cwd) .. "\0" .. n
		end
		local prepared = cache[key]
		if not prepared then
			prepared = prepare(mode.panes[pane], files)
			if cache_n >= 8 then
				cache, cache_n = {}, 0
			end
			cache[key], cache_n = prepared, cache_n + 1
		end
		last_mode, last_pane, last_cwd, last_n, last_prepared = mode, pane, cwd, n, prepared
		return prepared
	end

	local function refresh()
		for _, col in ipairs(plan.columns) do
			if col.refresh then
				local ok, err = pcall(col.refresh)
				if not ok then
					reporter.threw(col, "refresh", err)
				end
			end
		end
	end

	local function render(mode, pane, file, folder)
		local out = {}
		for _, one in ipairs(prepared_for(mode, pane, folder)) do
			local cell, ctx = one.cell, one.ctx
			local sep = cell.sep
			if sep then
				local style = one.sep_style
				out[#out + 1] = style and ui.Span(sep.text):style(style) or sep.text
			end
			-- Layout inside the protected call too: a malformed renderable or a
			-- failing truncate blanks the screen as surely as a throwing render.
			local ok, drawn = pcall(layout.cell, cell.column, ctx, file)
			if not ok then
				reporter.threw(cell.column, "render", drawn)
				drawn = string.rep(report.BROKEN, ctx.width or 1)
			end
			out[#out + 1] = drawn
		end
		return ui.Line(out)
	end

	return { render = render, invalidate = invalidate, refresh = refresh }
end

return M
