--- @since 26.9.1
--- What a plan is drawn in under one theme. Resolved once at `setup` and again
--- on every `theme` event, from the theme handed in, never from a global: a
--- colour read once and kept goes stale on the next `app:theme`, and the
--- flavor itself lands with a `theme` event after `init.lua` has run.
---
--- A refusal here leaves nothing half-built, so the caller's appearance goes
--- on drawing until one resolves.
local style = require(".style")

---@class supaline.AppearanceModule
local M = {}

--- One slot's resolved style.
---@class supaline.Resolved
---@field style unknown the flat style, or the ramp's low end
---@field steps unknown[]? the ramp, ratio 0 first
---@field fg_written boolean whether any layer wrote an `fg`, `false` included
---@field written boolean whether any layer wrote anything; a separator whose slot wrote nothing draws bare

--- Every slot of a plan, resolved.
---@alias supaline.Appearance table<supaline.Slot, supaline.Resolved>

--- Call a function the configuration wrote where a value goes. The call is
--- the likely failure -- a flavor with no such section -- and Lua's message
--- carries no column, so the path is put on it.
---@param fn function
---@param at supaline.Path the function's own path, called
---@return any
local function called(fn, at)
	local ok, got = pcall(fn)
	if not ok then
		at:refuse("raised: %s", tostring(got))
	end
	return got
end

--- One source's layer under `theme`, and the path of what was read.
---@param source supaline.Source
---@param read supaline.Reader
---@param theme table
---@return supaline.Layer|false
---@return supaline.Path
local function layer_of(source, read, theme)
	if source.call then
		local at = source.at:call()
		return read(called(source.call, at), at), at
	elseif source.theme then
		-- A field cleared rather than deleted is nothing written; everywhere
		-- else `""` is a colour Yazi refuses.
		local value = theme[source.theme]
		if value == "" then
			value = nil
		end
		return read(value, source.at), source.at
	end
	return source.layer, --[[@as supaline.Layer|false]]
		source.at
end

--- One slot's style: its sources merged, nearest writer winning key by key.
---@param slot supaline.Slot
---@param theme table
---@return supaline.Resolved
function M.slot(slot, theme)
	local layers = {}
	for i, source in ipairs(slot.sources) do
		local values, at = layer_of(source, slot.read, theme)
		layers[i] = { values = values, source = { at = at, theme = source.theme ~= nil } }
	end
	local resolved, from = style.merge(layers)
	-- Refused on the merged result, since a nearer flat colour may replace a
	-- farther gradient: without `stats` every row's ratio is nil, and the ramp
	-- could only ever draw its low end.
	local key = slot.ranged == false and style.gradient_in(resolved)
	if key then
		local source = from[key]
		source.at:refuse(
			"`%s` is a gradient, but this column has no `stats`, so there are no extremes to place a value "
				.. "between and the ramp could only ever draw its low end. %s",
			key,
			source.theme and "Write a flat colour there instead"
				or "Give the column a `stats` function, or write a flat colour there instead"
		)
	end
	local ground, steps = style.build(resolved)
	return {
		style = steps and steps[1] or ground,
		steps = steps,
		fg_written = from.fg ~= nil,
		written = next(resolved) ~= nil,
	}
end

--- Every slot of `plan`, under `theme`.
---@param plan supaline.Plan
---@param theme table
---@return supaline.Appearance
function M.resolve(plan, theme)
	local out = {} ---@type supaline.Appearance
	for _, slot in ipairs(plan.slots) do
		out[slot] = M.slot(slot, theme)
	end
	return out
end

return M
