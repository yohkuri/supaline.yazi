--- @since 26.9.1
--- Pure sRGB/Oklab arithmetic. Parsing style syntax belongs to style.lua.
---@class supaline.ColourModule
local M = { STEPS = 64 }
local STEPS = M.STEPS

--- Decode a literal endpoint, without consulting a terminal palette.
---@param value string
---@return integer[]?
function M.rgb(value)
	local r, g, b = value:match("^#(%x%x)(%x%x)(%x%x)$")
	if r then
		return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
	end
end

-- --- Oklab ------------------------------------------------------------------
--
-- Interpolating in sRGB is the same thing for a ramp that stays in one hue --
-- measured over `#0b3d91` to `#7fd4ff`, the two agree to within 10/255 and
-- their steps are as evenly spaced as each other. It comes apart as soon as the
-- endpoints travel: green to red in sRGB turns the lightness *back on itself*
-- half way along, and navy to yellow spaces its steps unevenly by a factor of
-- two, where Oklab holds both to within a few percent. Since the point of this
-- phase is that endpoints are the user's to choose, the space has to be the one
-- that survives the choice.
--
-- Oklch -- the same space in polar form, interpolating hue around the circle --
-- was measured and rejected: green to red leaves the sRGB gamut on 12 of 16
-- steps and comes back clamped and distorted.

---@param c integer 0-255
---@return number
local function to_linear(c)
	c = c / 255
	if c <= 0.04045 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

---@param c number
---@return integer 0-255
local function to_srgb(c)
	c = c < 0 and 0 or c > 1 and 1 or c
	local v = c <= 0.0031308 and c * 12.92 or 1.055 * c ^ (1 / 2.4) - 0.055
	return math.floor(v * 255 + 0.5)
end

--- Sign-preserving cube root. The three cone responses are non-negative for
--- any colour that came out of `to_linear`, but the inverse matrices are run on
--- interpolated values, and a `^ (1/3)` on a negative number is a NaN that
--- would reach the screen as a black cell.
---@param v number
---@return number
local function cbrt(v)
	if v < 0 then
		return -((-v) ^ (1 / 3))
	end
	return v ^ (1 / 3)
end

--- Björn Ottosson's Oklab, from linear sRGB.
---@param rgb integer[]
---@return number L, number a, number b
local function to_oklab(rgb)
	local r, g, b = to_linear(rgb[1]), to_linear(rgb[2]), to_linear(rgb[3])
	local l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
	local m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
	local s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
	return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
end

--- Back to linear sRGB, and not yet clamped, so a caller can tell a colour the
--- display can show from one it cannot. `from_oklab` clamps and `fits` asks;
--- that second reader is the whole reason this is a step of its own.
---@return number r, number g, number b
local function linear_of(L, A, B)
	local l = (L + 0.3963377774 * A + 0.2158037573 * B) ^ 3
	local m = (L - 0.1055613458 * A - 0.0638541728 * B) ^ 3
	local s = (L - 0.0894841775 * A - 1.2914855480 * B) ^ 3
	return 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
end

--- Back again, clamped into the gamut. A colour on the line between two
--- in-gamut endpoints can still sit outside it -- one step of navy to yellow
--- does -- and clamping each channel is enough where it is that rare.
---
--- Channels rather than a `#rrggbb`, because both callers want them that way:
--- a ramp formats them, and a band hands them back as a stop, which is the
--- shape a stop already has.
---@return integer r, integer g, integer b
local function from_oklab(L, A, B)
	local r, g, b = linear_of(L, A, B)
	return to_srgb(r), to_srgb(g), to_srgb(b)
end

--- Whether the display can draw this colour without a clamp.
---@return boolean
local function fits(L, A, B)
	local r, g, b = linear_of(L, A, B)
	return r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1
end

--- The most chroma one hue can carry at one lightness.
---
--- Searched rather than solved. The sRGB gamut in Oklab is the image of a cube
--- under a cube root and two matrices, and the edge of it along one hue has no
--- closed form worth carrying here -- where a bisection over `fits` is exact
--- to a ten-thousandth in fifteen steps and runs once per band, at setup.
---
--- The bound is 0.5 because nothing in sRGB reaches it: the most chromatic
--- colour it has is pure blue, a little over 0.31.
---@param L number
---@param ua number the hue direction, unit length
---@param ub number
---@return number
local function chroma_at(L, ua, ub)
	local lo, hi = 0, 0.5
	for _ = 1, 32 do
		local mid = (lo + hi) / 2
		if fits(L, mid * ua, mid * ub) then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

--- The two ends one colour stands for: the band's two lightnesses, drawn in
--- the base's own hue, in the order a ratio walks them.
---
--- The **hue is held exactly** at both ends, and everything else here is in
--- service of that. Both sit on the one ray out of Oklab's lightness axis that
--- the base sits on, so every step between them does too: a straight line
--- between two multiples of the same direction is more of that direction.
---
--- Along that ray, as far as the display allows, a lightness is reached by
--- scaling `L`, `a` and `b` **together** -- an exposure change. Measured over
--- seven colours at four factors on this file's own arithmetic, scaling the
--- three by `s` gives, to the byte, the linear sRGB of the original multiplied
--- by `s` cubed. Nothing leaves the gamut going down, and the colour keeps its
--- character rather than merely its hue.
---
--- Moving `L` alone is what eza does, and it is the reason not to: with `a`
--- and `b` held, a saturated colour runs out of gamut in *both* directions and
--- the clamp turns it. Measured the same way -- `#ff8800` reaches the screen
--- at hue 32 degrees at the bottom and 90 at the top, from 56.5; `#0b3d91`
--- arrives at 196 from 260.7, a navy drawn as cyan.
---
--- Going up the exposure runs out first. The factor that puts the strongest
--- channel at 255 is the last one in gamut, so `#7fd4ff` and `#ff8800` -- a
--- channel already there -- cannot be lightened by it at all, and `#0b3d91`
--- only reaches 0.59. Above that the ray is walked by lightness alone, at
--- whatever chroma the display can still show, which is the one thing that can
--- be given up without moving the hue. Chroma can fall all the way to zero and
--- a grey is in gamut at every lightness, so **every lightness is reachable**
--- and no pair of bounds is one a base cannot be drawn at.
---
--- Two consequences worth knowing before writing a band rather than finding
--- them on screen:
---
--- * **A dark colour is not a dim band.** `#0b3d91` comes out spread over the
---   full 0.35 to 0.88 with every step of the ramp distinct, where the
---   exposure alone would have stopped at 0.59 and a floor alone at 0.39.
--- * **The written colour supplies the hue and nothing else.** It is not put
---   on the band anywhere, and unless its own lightness happens to fall
---   between the two bounds it is not on it at all.
---@param rgb integer[]
---@param band supaline.Band the two ends, which the caller resolved by name
---@return integer[][] two stops, ratio 0 first
function M.band(rgb, band)
	local L, A, B = to_oklab(rgb)
	local chroma = math.sqrt(A * A + B * B)

	-- Linear scales as the cube, so the cube root of the headroom is the
	-- factor that lands the strongest channel exactly on 255.
	local peak = math.max(to_linear(rgb[1]), to_linear(rgb[2]), to_linear(rgb[3]))
	local up = peak > 0 and (1 / peak) ^ (1 / 3) or 1

	-- The hue as a unit direction, taken once rather than per end. Black is the
	-- only colour in sRGB with no direction at all: the Oklab matrices do not
	-- cancel exactly, so `#010101` carries a chroma of 2.5e-09 and `#ffffff`
	-- one of 3.7e-08, and 255 of the 256 greys go down the ordinary path.
	-- Leaving it at zero is what lets black go down it too -- `chroma * s` is
	-- then zero, and the colour drawn is the grey at that lightness, which is
	-- the whole of what black has ever meant here.
	local ua, ub = 0, 0
	if chroma > 0 then
		ua, ub = A / chroma, B / chroma
	end

	--- The base drawn at one lightness, hue held. Both ends go through this,
	--- which is what makes them the same kind of thing: which of the two is
	--- lighter is `band`'s business and not this function's.
	---@param target number
	---@return integer[]
	local function at(target)
		-- Zero for black alone, and only to keep the division total; every
		-- multiple of zero below is zero, which is the answer black wants.
		local s = L > 0 and target / L or 0
		if L * up >= target then
			return { from_oklab(L * s, A * s, B * s) }
		end

		-- Never more chroma than the exposure would have reached, so a colour
		-- is not made more vivid than the one that was written on its way to
		-- being made lighter.
		local c = math.min(chroma * s, chroma_at(target, ua, ub))
		return { from_oklab(target, c * ua, c * ub) }
	end
	return { at(band.from), at(band.to) }
end

--- Quantise a set of endpoints into the colours a column draws.
---
--- Stops are spread evenly: two of them put the whole ramp between them, three
--- put the middle one at the halfway mark. Position is not written per stop,
--- because a stop's *value* is what a reader would want to place it by -- 1M,
--- last Tuesday -- and a ratio between a folder's extremes has no idea what
--- either of those means.
---@param stops integer[][]
---@return string[] `STEPS` colours, the first stop's end first
function M.ramp(stops)
	-- `M.stops` refuses a single colour on the way in, but this is reachable
	-- without it and `segments` would then be zero: `lab[seg + 1]` is nil and
	-- the failure reads as a bug in here rather than as a ramp with one end.
	if #stops < 2 then
		error("supaline: a ramp needs at least two colours to interpolate between")
	end

	local lab = {}
	for i, rgb in ipairs(stops) do
		lab[i] = { to_oklab(rgb) }
	end

	local out, segments = {}, #lab - 1
	for i = 1, STEPS do
		local t = (i - 1) / (STEPS - 1) * segments
		-- The last step lands exactly on the final stop, where `seg` would run
		-- one past the end.
		local seg = math.min(math.floor(t) + 1, segments)
		local f = t - (seg - 1)
		local a, b = lab[seg], lab[seg + 1]
		out[i] = string.format(
			"#%02x%02x%02x",
			from_oklab(a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f)
		)
	end
	return out
end

return M
