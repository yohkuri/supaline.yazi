--- @since 26.9.1
--- One `setup`'s lifetime: its plan, the reporter whose gates it keeps, and the
--- appearance and prepared folders of the theme it draws under. A theme event
--- replaces those two and keeps the rest; a new `setup` replaces the session
--- whole. No Yazi globals: `main.lua` hands in the theme and the sink that
--- writes the log and the screen.
local appearance = require(".appearance")
local listing = require(".listing")
local report = require(".report")

-- Taken off the module once, at load, because `draw` calls it for every cell
-- of every frame. What `require` hands back is a proxy that builds a new
-- wrapper on each read of a function field, and a call through one enters and
-- leaves a nested runtime. Measured on 26.9.1, over a row of six built-in
-- columns: 57.7us with `layout.cell` read per cell, 42.9us with this local,
-- and 33.0us with the function reached through no wrapper at all -- what the
-- one kept here still costs on every call. `main_spec.lua` holds what a
-- frame reads this way to a count that does not grow with the folder.
local layout_cell = require(".layout").cell

---@class supaline.SessionModule
local M = {}

---@class supaline.Session
---@field plan supaline.Plan
---@field draw fun(mode: supaline.ModePlan, pane: string, file: supaline.File, folder: supaline.Folder?): unknown
---@field retheme fun(theme: table)
---@field refresh fun()
---@field moved fun()
---@field invalidate fun()

--- A session drawing `plan` under `theme`. Resolving the theme is the one
--- thing here that can fail, and it raises, so a `setup` that could not draw
--- replaces nothing.
---@param plan supaline.Plan
---@param theme table
---@param sink fun(logged: any, shown: string?)
---@return supaline.Session
function M.new(plan, theme, sink)
	local reporter = report.new(sink)
	local resolved = appearance.resolve(plan, theme)
	local prepared = listing.new(resolved, reporter)

	--- Forget every folder prepared, keeping the appearance.
	local function invalidate() prepared = listing.new(resolved, reporter) end

	--- Every column's `refresh`. One that throws is told off and the rest go
	--- on refreshing.
	local function refresh()
		for _, col in ipairs(plan.columns) do
			if col.refresh then
				reporter.call(col, "refresh", col.refresh)
			end
		end
	end

	--- Resolve the plan against the theme as it is now. A refusal keeps the
	--- last appearance drawing, and says so: raised from a `theme` event it
	--- would reach nobody. What `pcall` hands back is Yazi's wrapping of it --
	--- `schema.lua` says why -- so the screen gets its first line, which is
	--- the refusal as it was written.
	---@param now table
	local function retheme(now)
		local ok, got = pcall(appearance.resolve, plan, now)
		if not ok then
			return sink(got, report.one_line(got))
		end
		resolved = got
		invalidate()
		refresh()
	end

	--- One row of one pane, which the caller has checked draws something.
	---@param mode supaline.ModePlan
	---@param pane string
	---@param file supaline.File
	---@param folder supaline.Folder?
	---@return unknown
	local function draw(mode, pane, file, folder)
		local out = {}
		for _, one in ipairs(prepared(mode, pane, folder)) do
			local cell, ctx = one.cell, one.ctx
			local sep = cell.sep
			if sep then
				local style = one.sep_style
				out[#out + 1] = style and ui.Span(sep.text):style(style) or sep.text
			end
			-- Layout inside the protected call too: a malformed renderable or a
			-- failing truncate blanks the screen as surely as a throwing render.
			local ok, drawn = reporter.call(cell.column, "render", layout_cell, cell.column, ctx, file)
			if not ok then
				drawn = string.rep(report.BROKEN, ctx.width or 1)
			end
			out[#out + 1] = drawn
		end
		return ui.Line(out)
	end

	local function moved()
		invalidate()
		refresh()
	end

	return {
		plan = plan,
		draw = draw,
		retheme = retheme,
		refresh = refresh,
		moved = moved,
		invalidate = invalidate,
	}
end

return M
