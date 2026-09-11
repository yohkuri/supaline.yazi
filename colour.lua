--- @since 26.9.1
--- Colour values, and the ramps built from them.
---
--- Every colour a column draws passes through here, for two reasons that turn
--- out to be one: a gradient needs its endpoints as numbers, and Yazi's own
--- parser refuses a bad colour with `Failed to parse Colors` and nothing else
--- -- no column, no value, no mention of supaline. Measured on 26.9.1: an
--- invalid colour in the user's `[supaline]` section takes `setup` down with
--- that message alone, the plugin never installs, and Yazi draws the
--- linemode's *name* on every row.
---
--- What cannot be done here is read a colour back out. `ui.Style` is
--- write-only: it is userdata, `pairs` refuses it, `==` is false between two
--- styles built the same way, and `style.fg` hands back the setter rather than
--- the colour. So a ramp can never be derived from a style -- a
--- `[supaline] size = { fg = "#ff8800" }` out of the theme included, which
--- 26.9.1 turns into a `Style` before any plugin sees it -- and endpoints have
--- to arrive as strings this file parses itself.

--- The module table. Declared for the same reason `supaline.ColumnModule` is:
--- `require(".colour")` resolves to this tree and the signatures below are read
--- normally, but a misspelled `colour.stopss` costs nothing until the table
--- itself carries a class.
---@class supaline.ColourModule
local M = {}

-- How many styles a ramp is quantised into.
--
-- Not an option, because it costs nothing to be generous: the styles are built
-- once per theme and indexed per row, so a bigger number is that many more
-- userdata at build time and the same single array index afterwards. 64 puts
-- adjacent steps of the widest ramp measured -- green to red, which travels
-- furthest in hue -- 13/255 apart in the strongest channel, and puts more
-- distinct colours in the ramp than a terminal has rows to show at once.
--
-- Posterising a column on purpose is a different request, and quantising
-- coarsely is the wrong way to grant it: what a reader wants there is a colour
-- per *magnitude*, whose boundaries fall on 1K and 1M rather than on 1/64ths
-- of whatever the folder happened to hold.
local STEPS = 64

-- What separates one endpoint from the next in the string form. The string
-- form exists for `theme.toml`, whose custom sections take a string or a style
-- table and nothing else: an array there is not merely ignored, it is refused,
-- and the whole file goes with it. Measured on 26.9.1 -- `size = ["#111",
-- "#222"]` leaves `th.supaline` nil and Yazi prints `Failed to parse config`.
--
-- A string value, by contrast, reaches the plugin **verbatim and unvalidated**,
-- which is what lets a ramp be written in a theme at all.
local ARROW = "->"

local HEX = "^#(%x%x)(%x%x)(%x%x)$"

--- Whether Yazi's own colour parser takes `value`.
---
--- Asked rather than reimplemented. Yazi is on CalVer and its accepted
--- spellings are its own business; a list written here would go stale silently,
--- in the direction of refusing something that works. Measured on 26.9.1, it
--- takes `#rrggbb`, the sixteen names, `bright*` and `bright-*` variants,
--- `reset`, and a decimal index from "0" to "255" -- and refuses `#rgb`,
--- `#rrggbbaa`, `default`, an empty string and anything above 255.
---
--- Only ever called with a string. `fg(nil)` and `fg(true)` return nil instead
--- of raising, so a caller that let either through would be told the colour was
--- fine and then hand nil to `:bg()`.
---
--- The style it built on the way is handed back rather than thrown away: the
--- only way to find out whether Yazi takes a colour is to make one with it, and
--- `M.style` wants exactly that style.
---@param value string
---@return unknown? a ui.Style, or nil when the parser refused
local function styled(value)
	local ok, style = pcall(function() return ui.Style():fg(value) end)
	return ok and style or nil
end

---@param value string
---@param where string
local function refuse(value, where)
	error(
		string.format(
			"supaline: %s: `%s` is not a colour Yazi accepts. Write `#rrggbb`, a name "
				.. "such as `cyan`, a 256-colour index as a string such as `129`, or `reset`",
			where,
			value
		)
	)
end

--- Check one colour, and give back its channels.
---
--- Channels come back only for `#rrggbb`, and nil for everything else Yazi
--- takes: a name and a 256-colour index are whatever the terminal's palette
--- says they are, and this plugin has no way to ask. They are perfectly good
--- flat colours and cannot anchor a gradient.
---@param value any
---@param where string what to call this colour in an error
---@return integer[]? rgb
function M.colour(value, where)
	if type(value) ~= "string" then
		error(string.format("supaline: %s must be a colour string, got a %s", where, type(value)))
	end

	local r, g, b = value:match(HEX)
	if r then
		return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
	elseif not styled(value) then
		refuse(value, where)
	end
	return nil
end

--- The style a flat colour draws in, whichever way the user wrote it.
---
--- The whole "is this a colour" decision lives here, in one allow-list, so
--- there is one place to read and one message to keep right. A value that is
--- neither is refused *now*: `Span:style` takes a `Style` or nil and nothing
--- else, and anything else fails while drawing -- measured on 26.9.1,
--- `base = { fg = "#ff8800" }` survived `setup` and then emptied the screen,
--- with `Failed to redraw the Root component` in the log and nothing on it.
---
--- Telling a style from anything else has to be done by what it answers to,
--- not by what it is. `getmetatable` cannot do it: measured on 26.9.1, mlua
--- gives every one of Yazi's userdata `__metatable = false`, so
--- `getmetatable(ui.Style())`, `getmetatable(ui.Span("x"))` and
--- `getmetatable(ui.Line {})` are all `false` and all equal to each other --
--- a check written on the metatable waves a Span through as a colour. `patch`
--- is a `Style` method and nothing else here has one: on the same 26.9.1,
--- `style:patch(ui.Style())` succeeds where the Span and the Line both raise.
--- The harness's stand-in answers it too, which is what keeps one test a test
--- of this branch.
---@param value any nil, a colour string, or a ui.Style
---@param where string
---@return unknown a ui.Style
function M.style(value, where)
	if value == nil then
		return ui.Style()
	elseif type(value) == "string" then
		return styled(value) or refuse(value, where)
	elseif pcall(function() return value:patch(ui.Style()) end) then
		return value
	end

	error(
		string.format(
			"supaline: %s is a %s. Yazi takes a colour string or a `ui.Style` and nothing "
				.. "else, and anything else reaches it as neither: the linemode stops drawing "
				.. 'and the screen goes blank. Write `"#rrggbb"`, or `ui.Style():fg(...):bold()`',
			where,
			type(value) == "table" and "plain table" or type(value)
		)
	)
end

--- Whether a theme value asks for a ramp rather than a flat colour.
---
--- Only a theme value is ever in doubt: a spec writes `ramp` under its own key.
--- A theme field holds a string or a style table, so the question is entirely
--- about the string, and the arrow is the one thing a flat colour can never
--- contain. A style table is not a ramp and answers false through the same
--- test, whether it arrives as Yazi's userdata or as the harness's stand-in.
---@param value any
---@return boolean
function M.is_ramp(value) return type(value) == "string" and value:find(ARROW, 1, true) ~= nil end

---@param s string
---@return string[]
local function split(s)
	local out, pos = {}, 1
	while true do
		local a, b = s:find(ARROW, pos, true)
		-- `sub(pos, nil)` is `sub(pos)`, so the last piece falls out of the same
		-- line as the ones before it and there is one trim rather than two.
		out[#out + 1] = s:sub(pos, a and a - 1):match("^%s*(.-)%s*$")
		if not b then
			return out
		end
		pos = b + 1
	end
end

--- The endpoints of a ramp, in order, as RGB.
---
--- Every one of them has to be `#rrggbb`: an interpolation needs numbers at
--- both ends, and the numbers behind `cyan` are the terminal's rather than
--- ours. Guessing them would put a ramp on screen whose ends did not meet the
--- terminal's own cyan, which is worse than being told to write the colour out.
---@param value string|string[]
---@param where string
---@return integer[][]
function M.stops(value, where)
	local written
	if type(value) == "string" then
		written = split(value)
	elseif type(value) == "table" then
		written = value
	else
		error(string.format("supaline: %s must be a list of colours or a string like `#0b3d91 -> #7fd4ff`", where))
	end

	local stops = {}
	for i, one in ipairs(written) do
		local rgb = M.colour(one, string.format("%s, stop %d", where, i))
		if not rgb then
			error(
				string.format(
					"supaline: %s: `%s` cannot be a gradient endpoint. A name and a "
						.. "256-colour index are whatever the terminal's palette makes them, "
						.. "and a ramp interpolated from a guess would not meet either end; "
						.. "write `#rrggbb`",
					where,
					one
				)
			)
		end
		stops[i] = rgb
	end

	if #stops < 2 then
		error(string.format("supaline: %s needs at least two colours to interpolate between", where))
	end
	return stops
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

--- Back again, clamped into the gamut. A colour on the line between two
--- in-gamut endpoints can still sit outside it -- one step of navy to yellow
--- does -- and clamping each channel is enough where it is that rare.
---@return string a `#rrggbb`
local function from_oklab(L, A, B)
	local l = (L + 0.3963377774 * A + 0.2158037573 * B) ^ 3
	local m = (L - 0.1055613458 * A - 0.0638541728 * B) ^ 3
	local s = (L - 0.0894841775 * A - 1.2914855480 * B) ^ 3
	return string.format(
		"#%02x%02x%02x",
		to_srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
		to_srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
		to_srgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
	)
end

--- Quantise a set of endpoints into the colours a column draws.
---
--- Stops are spread evenly: two of them put the whole ramp between them, three
--- put the middle one at the halfway mark. Position is not written per stop,
--- because a stop's *value* is what a reader would want to place it by -- 1M,
--- last Tuesday -- and a ratio between a folder's extremes has no idea what
--- either of those means.
---@param stops integer[][]
---@return string[] `STEPS` colours, low end first
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
		out[i] = from_oklab(a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f)
	end
	return out
end

--- The styles a ramp draws, low end first: the endpoints as the user wrote
--- them, resolved, quantised, and each step patched onto `ground`.
---
--- The whole way from what a user wrote to what a row is drawn in stays inside
--- this file, so nothing outside it has to know that a ramp is carried as
--- `#rrggbb` in between -- the one thing a caller would have had to copy in
--- order to build the styles itself.
---
--- `patch` is field-wise, so a `bold` or a `bg` on the ground survives under a
--- colour that knows nothing about it.
---
--- Called from `normalize`, which `build()` re-runs on every `theme` event, so
--- a ramp follows a theme reload the way a flat colour does. Per row there is
--- then nothing left to do but index the result.
---@param value string|string[] the endpoints, as written
---@param ground unknown the ui.Style each step is patched onto
---@param where string
---@return unknown[] `STEPS` styles, low end first
function M.styles(value, ground, where)
	local out = {}
	for i, hex in ipairs(M.ramp(M.stops(value, where))) do
		out[i] = ground:patch(ui.Style():fg(hex))
	end
	return out
end

return M
