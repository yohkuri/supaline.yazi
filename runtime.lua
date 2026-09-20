--- @since 26.9.1
--- Folder preparation and drawing. Each cached pane owns its contexts; plans
--- and appearances are read-only inputs, never rebound to a different folder.
local layout = require(".layout")

---@class supaline.RuntimeModule
local M = {}

---@class supaline.Ctx
---@field style unknown the flat style, or the ramp's low end
---@field fg_written boolean an explicit foreground, including false
---@field opts table<string, any> declared column options only
---@field stats any the column's folder statistics
---@field width integer? effective width, already capped
---@field ratio fun(value: number?): number?
---@field style_at fun(ratio: number?): unknown

---@class supaline.PreparedColumn
---@field column supaline.ColumnPlan
---@field ctx supaline.Ctx

---@class supaline.Runtime
---@field render fun(mode: supaline.ModePlan, pane: string, file: supaline.File, folder: supaline.Folder?): unknown
---@field invalidate fun()
---@field refresh fun()

---@param stats any
---@return boolean
function M.has_extremes(stats)
	return type(stats) == "table" and type(stats.min) == "number" and type(stats.max) == "number"
end

--- No range state is stored on the public context or on the column plan.
--- During auto measurement width is initially nil; the completed context is
--- published to the cache only after the width pass has finished.
---@param col supaline.ColumnPlan
---@param paint supaline.ColumnAppearance
---@param stats any
---@param width integer?
---@return supaline.Ctx
function M.context(col, paint, stats, width)
	local lo, hi
	local log = col.scale == "log"
	if M.has_extremes(stats) then
		lo, hi = stats.min, stats.max
		if log then
			lo, hi = math.log(lo + 1), math.log(hi + 1)
		end
	end
	local ctx = {
		style = paint.style,
		fg_written = paint.fg_written,
		opts = col.options,
		stats = stats,
		width = width or col.width.value,
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
	local steps = paint.steps
	if steps then
		local n, last = #steps, #steps - 1
		function ctx.style_at(r)
			if r == nil then
				return ctx.style
			end
			local i = 1 + math.floor(r * last + 0.5)
			-- NaN is possible with a custom logarithmic range below -1.
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

local function cap(width, max) return max and width > max and max or width end

--- User callbacks may throw; the folder pass contains this whole operation.
--- An unusable returned width is a refusal, not a callback exception.
---@param col supaline.ColumnPlan
---@param ctx supaline.Ctx
---@param files supaline.File[]
---@return integer?
---@return string?
function M.width(col, ctx, files)
	local width = col.width
	if width.kind == "computed" then
		local w = width.compute(ctx.stats)
		local cells = type(w) == "number" and math.tointeger(w) or nil
		if not cells or cells < 1 then
			local t = type(w)
			local written = (t == "string" or t == "number") and string.format("`%s`", tostring(w)) or "a " .. t
			return nil,
				string.format(
					"supaline: the `width` function of column `%s` returned %s; it must return a whole number of cells, 1 or more",
					col.name or "?",
					written
				)
		end
		return cap(cells, col.max_width)
	elseif width.kind ~= "auto" then
		return width.value
	end
	local widest = 0
	for i = 1, #files do
		local out = col.render(files[i], ctx)
		local measured = layout.measure(out)
		widest = math.max(widest, measured)
	end
	return cap(widest, col.max_width)
end

---@param plan supaline.Plan
---@param appearance supaline.Appearance
---@param reporter supaline.Reporter survives a theme replacement, not a setup
---@return supaline.Runtime
function M.new(plan, appearance, reporter)
	local cache, cache_n = {}, 0 ---@type table<string, supaline.PreparedColumn[]>, integer
	local last_mode, last_pane, last_cwd, last_n, last_prepared
	-- A missing folder is a pane identity too. In particular, two modes drawing
	-- the filesystem root's absent parent must not borrow each other's context.
	local absent = {} ---@type table<supaline.ModePlan, table<string, supaline.PreparedColumn[]>>

	local function invalidate()
		cache, cache_n, absent = {}, 0, {}
		last_mode, last_pane, last_cwd, last_n, last_prepared = nil, nil, nil, nil, nil
	end

	---@param cols supaline.ColumnPlan[]
	---@param files supaline.File[]?
	---@return supaline.PreparedColumn[]
	local function prepare(cols, files)
		local prepared = {}
		for i, col in ipairs(cols) do
			local paint, stats = appearance.columns[col], nil
			if files and col.stats then
				local ok, got = pcall(col.stats, files)
				if ok then
					stats = got
				else
					reporter.threw(col, "stats", got)
				end
				if paint.steps and stats ~= nil and not M.has_extremes(stats) then
					reporter.stats(col)
				end
			end
			local ctx = M.context(col, paint, stats)
			if files and col.needs_pass then
				local ok, got, why = pcall(M.width, col, ctx, files)
				if not ok then
					reporter.threw(col, col.width.kind == "computed" and "width" or "render", got)
				elseif why then
					reporter.width(col, why)
				else
					ctx.width = got
				end
			end
			prepared[i] = { column = col, ctx = ctx }
		end
		return prepared
	end

	---@param mode supaline.ModePlan
	---@param pane string
	---@param folder supaline.Folder?
	---@return supaline.PreparedColumn[]
	local function prepared_for(mode, pane, folder)
		if not folder then
			local by_pane = absent[mode]
			if not by_pane then
				by_pane = {}
				absent[mode] = by_pane
			end
			if not by_pane[pane] then
				by_pane[pane] = prepare(mode.cols[pane])
			end
			return by_pane[pane]
		end
		local files, cwd = folder.files, folder.cwd
		local n = #files
		if last_mode == mode and last_pane == pane and last_cwd == cwd and last_n == n then
			return last_prepared
		end
		local key = mode.name .. "\0" .. pane .. "\0" .. tostring(cwd) .. "\0" .. n
		local prepared = cache[key]
		if not prepared then
			prepared = prepare(mode.cols[pane], files)
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
		local prepared = prepared_for(mode, pane, folder)
		local out = {}
		for i, one in ipairs(prepared) do
			local col, ctx = one.column, one.ctx
			local sep = appearance.columns[col].sep
			if i > 1 and sep ~= false then
				sep = sep or appearance.separators[mode]
				out[#out + 1] = sep.style and ui.Span(sep.text):style(sep.style) or sep.text
			end
			-- Keep layout in the protected call: a malformed renderable or a
			-- failing truncate is just as capable of blanking Yazi's Root.
			local ok, cell = pcall(layout.cell, col, ctx, file)
			if not ok then
				reporter.threw(col, "render", cell)
				cell = string.rep("!", ctx.width or 1)
			end
			out[#out + 1] = cell
		end
		return ui.Line(out)
	end
	return { render = render, invalidate = invalidate, refresh = refresh }
end

return M
