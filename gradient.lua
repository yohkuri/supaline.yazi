--- @since 26.8.15
--- Oklab-based colour ramps, modelled on eza's `--color-scale-mode=gradient`.
---
--- eza normalises a value against the extremes of the current listing and then
--- rewrites only the *lightness* of the base colour, leaving hue and chroma
--- alone, so the ramp still belongs to the user's theme. The curve is
---
---     L = min_l + (1 - min_l) * exp(-4 * (1 - ratio))
---
--- which keeps the bulk of the range near `min_l` and reserves the bright end
--- for the genuinely large/recent entries.
---
--- Unlike eza we do a gamma-correct sRGB round trip; eza feeds gamma-encoded
--- bytes straight into a linear-sRGB constructor, so its hues drift slightly
--- from the colour you configured. The shape of the ramp is identical.

local M = {}

-- The 16 ANSI names Yazi accepts, so a base colour can be written either as
-- "#rrggbb" or as a theme-friendly name.
local NAMED = {
	black = { 0, 0, 0 },
	red = { 205, 0, 0 },
	green = { 0, 205, 0 },
	yellow = { 205, 205, 0 },
	blue = { 0, 0, 238 },
	magenta = { 205, 0, 205 },
	cyan = { 0, 205, 205 },
	white = { 229, 229, 229 },
	darkgray = { 127, 127, 127 },
	lightred = { 255, 0, 0 },
	lightgreen = { 0, 255, 0 },
	lightyellow = { 255, 255, 0 },
	lightblue = { 92, 92, 255 },
	lightmagenta = { 255, 0, 255 },
	lightcyan = { 0, 255, 255 },
	gray = { 229, 229, 229 },
}

---@param color string a "#rrggbb" literal or one of the ANSI colour names
---@return number? r 0..255
---@return number? g 0..255
---@return number? b 0..255
local function parse(color)
	if type(color) ~= "string" then
		return
	end

	local hex = color:match("^#(%x%x%x%x%x%x)$")
	if hex then
		return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
	end

	local named = NAMED[color:lower():gsub("[%s_-]", "")]
	if named then
		return named[1], named[2], named[3]
	end
end

local function srgb_to_linear(c)
	if c <= 0.04045 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

local function linear_to_srgb(c)
	if c <= 0.0031308 then
		c = c * 12.92
	else
		c = 1.055 * c ^ (1 / 2.4) - 0.055
	end
	return c < 0 and 0 or c > 1 and 1 or c
end

local function cbrt(x) return x < 0 and -((-x) ^ (1 / 3)) or x ^ (1 / 3) end

---@return number L
---@return number a
---@return number b
local function linear_to_oklab(r, g, b)
	local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

	local l_, m_, s_ = cbrt(l), cbrt(m), cbrt(s)
	return 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
end

---@return number r linear light
---@return number g linear light
---@return number b linear light
local function oklab_to_linear(L, a, b)
	local l_ = L + 0.3963377774 * a + 0.2158037573 * b
	local m_ = L - 0.1055613458 * a - 0.0638541728 * b
	local s_ = L - 0.0894841775 * a - 1.2914855480 * b

	local l, m, s = l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_
	return 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
end

--- Does this terminal claim 24-bit colour? Callers may override via
--- `colors = "truecolor" | "off"`; "auto" lands here.
---@return boolean
function M.truecolor()
	local ok, env = pcall(os.getenv, "COLORTERM")
	if not ok or not env then
		return false
	end
	return env == "truecolor" or env == "24bit"
end

--- Build a ramp of `steps` styles running from the dimmest to the brightest
--- variant of `color`. Ratios are quantised into this table at render time so
--- that no colour maths -- and no `ui.Style` allocation -- happens per row.
---@param color string base colour
---@param steps integer number of quantisation buckets
---@param min_l number lightness floor, 0..1 (eza's --color-scale-min-luminance / 100)
---@return table? ramp array of `ui.Style`, or nil if `color` is unparseable
function M.ramp(color, steps, min_l)
	local r, g, b = parse(color)
	if not r then
		return
	end

	local L, ca, cb = linear_to_oklab(srgb_to_linear(r / 255), srgb_to_linear(g / 255), srgb_to_linear(b / 255))
	local _ = L -- the base lightness is discarded; the ramp supplies its own

	local ramp = {}
	for i = 1, steps do
		local ratio = steps == 1 and 1 or (i - 1) / (steps - 1)
		local l = min_l + (1 - min_l) * math.exp(-4 * (1 - ratio))
		l = l < 0 and 0 or l > 1 and 1 or l

		local lr, lg, lb = oklab_to_linear(l, ca, cb)
		ramp[i] = ui.Style():fg(
			string.format(
				"#%02x%02x%02x",
				math.floor(linear_to_srgb(lr) * 255 + 0.5),
				math.floor(linear_to_srgb(lg) * 255 + 0.5),
				math.floor(linear_to_srgb(lb) * 255 + 0.5)
			)
		)
	end
	return ramp
end

--- Pick a style out of a ramp built by `M.ramp`.
---@param ramp table
---@param ratio number? 0..1; nil selects the brightest end
---@return unknown ui.Style
function M.pick(ramp, ratio)
	if not ratio then
		return ramp[#ramp]
	elseif ratio ~= ratio then -- NaN, i.e. a listing where min == max
		return ramp[#ramp]
	end

	local i = math.floor(ratio * (#ramp - 1) + 1.5)
	return ramp[i < 1 and 1 or i > #ramp and #ramp or i]
end

return M
