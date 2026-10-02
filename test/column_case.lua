--- One column compiled the way `setup` compiles each of a linemode's, without
--- installing a Linemode, so a spec can look at each stage on its own.
local appearance = require(".appearance")
local layout = require(".layout")
local listing = require(".listing")
local schema = require(".schema")

---@class supaline.ColumnCase
---@field plan supaline.ColumnPlan
---@field paint supaline.Resolved
---@field ctx supaline.Ctx

--- Where a case's column is written, so a refusal names it `spec` -- the way
--- one in a linemode names `setup.linemodes.detail[2]`.
local AT = schema.path("spec")

--- The `setup` a case is compiled under unless it names another.
---@type supaline.Cfg
local CFG = { scale = "linear", lightness = {} }

---@class supaline.ColumnCases
local M = {}

--- A compiler over `registry`, reading the theme as it stands when called.
---@param registry supaline.Registry
---@return fun(spec: supaline.ColumnSpec, cfg: supaline.Cfg?): supaline.ColumnCase
function M.compiler(registry)
	return function(spec, cfg)
		local plan = registry.open(cfg or CFG).compile(spec, AT)
		local paint = appearance.slot(plan.slot, th.supaline or {})
		return { plan = plan, paint = paint, ctx = listing.context(plan, paint, nil) }
	end
end

--- The cell `case` draws for `file`, an empty file unless one is given.
---@param case supaline.ColumnCase
---@param file supaline.File?
---@return unknown
function M.cell(case, file) return layout.cell(case.plan, case.ctx, file or stub.file {}) end

--- Bind `case` to a folder's extremes, the way a listing binds it.
---@param case supaline.ColumnCase
---@param stats any
function M.bind(case, stats) case.ctx = listing.context(case.plan, case.paint, stats) end

--- The width `case` takes over `files`, and the refusal beside it if any.
---@param case supaline.ColumnCase
---@param files supaline.File[]
---@param stats any
---@return integer?
---@return string?
function M.width(case, files, stats)
	return listing.width(case.plan, listing.context(case.plan, case.paint, stats), files)
end

return M
