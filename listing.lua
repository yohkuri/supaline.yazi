--- @since 26.9.1
--- Folders prepared for drawing: each column's statistics, its effective
--- width, the context its rows are drawn with and the style of the separator
--- before it, for one folder in one pane of one linemode. A cache belongs to
--- the appearance it prepares under, and is replaced rather than cleared --
--- by a theme event, and by anything that makes a folder's stale -- so a
--- context handed out is never rebound.
local schema = require(".schema")

-- Taken off the module once, for the reason `session.lua` gives: an `auto`
-- width calls it for every file in the folder.
local layout_measure = require(".layout").measure

---@class supaline.ListingModule
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

--- One pane of one linemode, prepared in a folder.
---@alias supaline.Listings fun(mode: supaline.ModePlan, pane: string, folder: supaline.Folder?): supaline.Prepared[]

--- The style a separator is drawn in: none where its slot wrote nothing, so
--- that it draws as bare text rather than a span per row.
---@param look supaline.Resolved?
---@return unknown?
function M.sep_style(look) return look and look.written and look.style or nil end

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

-- The widths decided per folder, by the column's own function each calls:
-- `render` to measure every file, or the `width` function itself.
local PASS = { auto = "render", computed = "width" } ---@type table<string, supaline.Stage>

--- Which of the column's own functions deciding its width calls, once per
--- folder, and so whose a throw from it is reported as; nil for a width known
--- without a folder.
---@param col supaline.ColumnPlan
---@return supaline.Stage?
function M.pass(col) return PASS[col.width.kind] end

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
		widest = math.max(widest, layout_measure(col.render(files[i], ctx)))
	end
	return cap(widest, col.max_width)
end

--- The folders one appearance has prepared: at most eight, cleared whole when
--- a ninth arrives.
---@param appearance supaline.Appearance
---@param reporter supaline.Reporter survives a theme replacement, not a setup
---@return supaline.Listings
function M.new(appearance, reporter)
	local cache, cache_n = {}, 0 ---@type table<string, supaline.Prepared[]>, integer
	local last_mode, last_pane, last_cwd, last_n, last_prepared

	---@param cells supaline.Cell[]
	---@param files supaline.File[]?
	---@return supaline.Prepared[]
	local function prepare(cells, files)
		local prepared = {}
		for i, cell in ipairs(cells) do
			local col = cell.column
			local look, stats = appearance[col.slot], nil
			if files and col.stats then
				local ok, got = reporter.call(col, "stats", col.stats, files)
				if ok then
					stats = got
				end
				if look.steps and stats ~= nil and not M.has_extremes(stats) then
					reporter.stats(col)
				end
			end
			-- Published only once the width pass is done, so a render measured
			-- for `auto` sees `width` nil and nothing else does.
			local ctx = M.context(col, look, stats)
			local pass = M.pass(col)
			if files and pass then
				local ok, got, refused = reporter.call(col, pass, M.width, col, ctx, files)
				if ok and refused then
					reporter.width(col, refused)
				elseif ok then
					ctx.width = got
				end
			end
			local sep = cell.sep and cell.sep.slot
			prepared[i] = { cell = cell, ctx = ctx, sep_style = M.sep_style(sep and appearance[sep]) }
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
	local function get(mode, pane, folder)
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

	return get
end

return M
