--- Assemble a single column through the same stages as setup, without installing
--- a Linemode. Tests inspect each stage explicitly; no production compatibility
--- facade retains the old mutable Column object.
local appearance = require(".appearance")
local layout = require(".layout")
local runtime = require(".runtime")
local schema = require(".schema")

---@class supaline.ColumnCase
---@field plan supaline.ColumnPlan
---@field paint supaline.Resolved
---@field ctx supaline.Ctx

---@class supaline.ColumnCases
local M = {}

--- Where a case's column is written, so a refusal names it `spec` -- the way
--- one in a linemode names `setup.linemodes.detail[2]`.
M.AT = schema.path("spec")

---@param registry supaline.Registry
---@param spec supaline.ColumnSpec
---@param cfg supaline.Cfg
---@return supaline.ColumnCase
function M.prepare(registry, spec, cfg)
	local plan = registry.open(cfg).compile(spec, M.AT)
	local paint = appearance.slot(plan.slot, th.supaline or {})
	return { plan = plan, paint = paint, ctx = runtime.context(plan, paint, nil) }
end

---@param case supaline.ColumnCase
---@param file supaline.File
---@return unknown
function M.cell(case, file) return layout.cell(case.plan, case.ctx, file) end

---@param case supaline.ColumnCase
---@param entry { stats: any, width: integer? }
function M.for_folder(case, entry)
	case.ctx = runtime.context(case.plan, case.paint, entry.stats)
	if entry.width then
		case.ctx.width = entry.width
	end
end

---@param case supaline.ColumnCase
---@param files supaline.File[]
---@param stats any
---@return integer?
---@return string?
function M.width(case, files, stats)
	return runtime.width(case.plan, runtime.context(case.plan, case.paint, stats), files)
end

return M
