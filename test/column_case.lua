--- Assemble a single column through the same stages as setup, without installing
--- a Linemode. Tests inspect each stage explicitly; no production compatibility
--- facade retains the old mutable Column object.
local column = require(".column")
local layout = require(".layout")
local runtime = require(".runtime")
local style = require(".style")

---@class supaline.ColumnCase
---@field plan supaline.ColumnPlan
---@field paint supaline.ColumnAppearance
---@field ctx supaline.Ctx

---@class supaline.ColumnCases
local M = {}

---@param registry supaline.Registry
---@param spec supaline.ColumnSpec
---@param cfg supaline.Cfg
---@return supaline.ColumnCase
function M.prepare(registry, spec, cfg)
	local plan = registry.compile(spec, cfg)
	local paint = style.column(plan, cfg.band or {}, th.supaline or {})
	return { plan = plan, paint = paint, ctx = runtime.context(plan, paint, nil) }
end

---@param case supaline.ColumnCase
---@param file supaline.File
---@return unknown
function M.cell(case, file) return layout.cell(case.plan, case.ctx, file) end

---@param case supaline.ColumnCase
---@param entry { stats: any, width: integer? }
function M.for_folder(case, entry) case.ctx = runtime.context(case.plan, case.paint, entry.stats, entry.width) end

---@param case supaline.ColumnCase
---@param files supaline.File[]
---@param stats any
---@return integer?
---@return string?
function M.width(case, files, stats)
	return runtime.width(case.plan, runtime.context(case.plan, case.paint, stats), files)
end

return M
