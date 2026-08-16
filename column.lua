--- @since 26.8.15
--- Column registry and normalisation.
---
--- A column is written in one of three shapes, all of which collapse to the
--- same runtime object so that built-in and user columns are indistinguishable:
---
---   { "size", width = 9 }                       -- a registered column, by name
---   function(file, ctx) return "..." end        -- render-only shorthand
---   { render = fn, stats = fn, width = 6 }      -- an inline definition
---
--- `render(file, ctx)` runs for every visible row on every frame and must stay
--- O(1). Anything that needs to look at the whole folder belongs in
--- `stats(files)`, which runs once per folder and is cached by main.lua.
---
--- `render` may return either a single `AsLine`, or `text, style` -- the latter
--- avoids building an intermediate Line for the common case of a plain string.

local gradient = require(".gradient")

local M = { _registry = {} }

--- Register a reusable column under `name`, so it can be referenced as
--- `{ "name", ... }` from a linemode spec.
---@param name string
---@param def table `{ render = fn, stats = fn?, width = integer?, align = string?, base = string? }`
function M.register(name, def)
	if type(name) ~= "string" or type(def) ~= "table" or type(def.render) ~= "function" then
		error("supaline: column(name, def) needs a name and a def with a `render` function")
	end
	M._registry[name] = def
end

---@param name string
---@return table?
function M.get(name) return M._registry[name] end

-- Resolve the base colour for a column: explicit option first, then the
-- `[supaline]` theme section (`<name>_base`), then the definition's default.
local function base_color(name, opts, def)
	if opts.base then
		return opts.base
	end

	local section = th.supaline
	if section and name then
		local themed = section[name .. "_base"]
		if type(themed) == "string" then
			return themed
		end
	end
	return def.base
end

--- Turn one entry of a `linemodes` list into a runtime column.
---@param spec string|table|function
---@param cfg table plugin-wide options (`gradient`, `separator`, ...)
---@return table
function M.normalize(spec, cfg)
	local name, opts, def

	if type(spec) == "function" then
		name, opts, def = nil, {}, { render = spec }
	elseif type(spec) == "string" then
		name, opts = spec, {}
		def = M._registry[spec] or error("supaline: unknown column `" .. spec .. "`")
	elseif type(spec) == "table" and type(spec[1]) == "string" then
		name, opts = spec[1], spec
		def = M._registry[name] or error("supaline: unknown column `" .. name .. "`")
	elseif type(spec) == "table" and type(spec[1]) == "function" then
		name, opts, def = nil, spec, { render = spec[1] }
	elseif type(spec) == "table" and type(spec.render) == "function" then
		name, opts, def = spec.name, spec, spec
	else
		error("supaline: a column must be a name, a function, or a table with `render`")
	end

	local col = {
		name = name,
		width = opts.width or def.width,
		align = opts.align or def.align or "right",
		stats = opts.stats or def.stats,
		render = opts.render or def.render,
		opts = opts,
	}

	-- Build the gradient ramp once, at setup. `ctx.style()` then only indexes
	-- into it, so no colour maths happens while rendering.
	local color = base_color(name, opts, def)
	local plain = color and ui.Style():fg(color) or ui.Style()

	local mode = opts.gradient or cfg.gradient.mode
	local colors = cfg.gradient.colors
	local wants = color ~= nil and mode ~= "off" and colors ~= "off"
	if wants and colors == "auto" then
		wants = gradient.truecolor()
	end

	local ramp = wants and gradient.ramp(color, cfg.gradient.steps, cfg.gradient.min_luminance / 100) or nil

	-- One context table per column, reused across rows; main.lua swaps in the
	-- cached stats before each frame.
	local ctx = { base = plain, stats = nil, opts = opts }

	-- eza normalises raw values. That is faithful, but a listing spanning 1 KiB
	-- to 1 GiB pins almost everything to the dark end of the ramp, so `scale =
	-- "log"` is available for the columns where it matters (usually `size`).
	local log = (opts.scale or def.scale or cfg.gradient.scale) == "log"

	function ctx.ratio(value)
		local st = ctx.stats
		if not value or not st or not st.min then
			return nil
		elseif st.max == st.min then
			return 1
		end

		local lo, hi = st.min, st.max
		if log then
			value, lo, hi = math.log(value + 1), math.log(lo + 1), math.log(hi + 1)
			if hi == lo then
				return 1
			end
		end

		local r = (value - lo) / (hi - lo)
		return r < 0 and 0 or r > 1 and 1 or r
	end

	function ctx.style(ratio)
		if not ramp then
			return plain
		end
		return gradient.pick(ramp, ratio)
	end

	col.ctx = ctx
	return col
end

-- Display width of a plain string. Sizes, dates and permission strings are
-- ASCII, so the byte length is exact; anything else asks Yazi.
local function width_of(text)
	if not text:find("[\128-\255]") then
		return #text
	end
	return ui.Line(text):width()
end

--- Render one column for one file, padded to its declared width.
---@param col table
---@param file table `fs::File`
---@return unknown|string an `AsLine`
function M.cell(col, file)
	local out, style = col.render(file, col.ctx)
	if out == nil then
		out = ""
	end

	if not col.width then
		return style and ui.Span(tostring(out)):style(style) or out
	end

	if type(out) == "string" then
		local slack = col.width - width_of(out)
		if slack > 0 then
			local pad = string.rep(" ", slack)
			out = col.align == "left" and out .. pad or pad .. out
		end
		return style and ui.Span(out):style(style) or out
	end

	-- A Line/Span came back; pad around it rather than inside it.
	local line = ui.Line(out)
	local slack = col.width - line:width()
	if slack <= 0 then
		return line
	end

	local pad = string.rep(" ", slack)
	return col.align == "left" and ui.Line { line, pad } or ui.Line { pad, line }
end

return M
