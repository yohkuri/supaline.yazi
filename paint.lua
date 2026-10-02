--- @since 26.9.1
--- What one colour key may hold: a colour Yazi's parser takes, a gradient
--- written `a -> b`, or one colour spread over a lightness range, written
--- `x <->`, and the ranges `setup` names.
---
--- Both spellings are strings because a `theme.toml` custom section takes a
--- string or a style table and nothing else: measured on 26.9.1, an array
--- there discards the whole file. A string reaches the plugin verbatim.
local colour = require(".colour")
local schema = require(".schema")

---@class supaline.PaintModule
local M = {}

local ARROW = "->"
-- It contains `ARROW`, so `M.is_ramp` answers a spread without being told of one.
local BOTH = "<->"

--- A lightness range: the two Oklab lightnesses a spread colour runs between.
--- `from` is what ratio 0 draws and `to` what ratio 1 draws.
---@alias supaline.LightnessRange { from: number, to: number }

--- Lightness ranges by name, as `setup` was given them. Nothing is behind it.
---@alias supaline.LightnessRanges table<string, supaline.LightnessRange>

--- What one colour key holds once read: a flat colour as written, a gradient
--- as its stops, or `false` for no colour.
---@alias supaline.Paint string|integer[][]|false

--- What a style is read with, so that what a gradient means is the caller's.
---@alias supaline.Painter fun(value: any, at: supaline.Path, key: string): supaline.Paint

-- The pair every refusal of an undefined range quotes, and applies to nobody.
--
-- 0.40 clears the lightest of five common dark grounds, One Dark at 0.293, by
-- a tenth of the scale. Merely lighter than the ground is not enough: 0.35 is,
-- and a navy row at 0.35 sinks into Solarized dark, whose ground is as blue as
-- the row, judged by eye on that ground. 0.90 was judged by eye against
-- 0.95 over nine hues on those five grounds: 0.95 still parts from white text,
-- but red, orange and yellow pale into one another there. A light terminal
-- wants this pair backwards, `{ from = 0.90, to = 0.40 }` -- the same 64
-- colours in the other order. supaline cannot see the ground a range is drawn
-- on, so this is a recommendation to paste and move rather than a default.
---@type supaline.LightnessRange
local RECOMMENDED = { from = 0.40, to = 0.90 }

--- The recommended pair, as a fresh table the caller may write to.
---@return supaline.LightnessRange
function M.recommended() return { from = RECOMMENDED.from, to = RECOMMENDED.to } end

-- Two places, as every document writes the pair: `%s` would print 0.4.
local RECOMMENDED_AS_WRITTEN = string.format("{ from = %.2f, to = %.2f }", RECOMMENDED.from, RECOMMENDED.to)

-- A range's name holds what a column's does. Nothing parses a range name, so the
-- 20-character cap Yazi puts on a column's is not taken; `colour_spec.lua`
-- reads the two rules against each other.
local NAME = "^[a-z0-9_]+$"

-- A range's own two keys, which no range can be called.
local RESERVED = { from = true, to = true }

--- Whether Yazi's own parser takes `value`. Asked rather than reimplemented,
--- so a spelling a later Yazi adds is not refused here. Only ever called with
--- a string: `fg(nil)` is the getter, and raises for nothing.
---@param value string
---@return boolean
local function accepted(value)
	return (pcall(function() return ui.Style():fg(value) end))
end

--- A colour Yazi takes, and its channels when it is `#rrggbb`. A name or a
--- 256-colour index is whatever the terminal's palette makes it, so it has no
--- channels here and cannot anchor a gradient.
---@param value any
---@param at supaline.Path
---@return integer[]? rgb
function M.colour(value, at)
	if type(value) ~= "string" then
		at:refuse("must be a colour string, got a %s", type(value))
	end
	local rgb = colour.rgb(value)
	if rgb then
		return rgb
	elseif not accepted(value) then
		at:refuse(
			"`%s` is not a colour Yazi accepts. Write `#rrggbb`, a name such as `cyan`, a 256-colour "
				.. "index as a string such as `129`, or `reset`",
			value
		)
	end
	return nil
end

--- Whether a value asks for a gradient: the arrow is the one thing a flat
--- colour never contains.
---@param value any
---@return boolean
function M.is_ramp(value) return type(value) == "string" and value:find(ARROW, 1, true) ~= nil end

--- One lightness range. `(0, 1]` is where anything is -- 0 is black at every
--- hue -- and the test is negated so that a NaN lands on the refusing side.
--- Equal ends are taken: where flat stops being flat is a judgement.
---@param value any
---@param at supaline.Path
---@return supaline.LightnessRange
function M.bounds(value, at)
	if type(value) ~= "table" then
		at:refuse(
			"must be a table of two lightnesses, as `%s` -- `from` is what ratio 0 draws and `to` "
				.. "what ratio 1 draws, so a light terminal writes the larger one first",
			RECOMMENDED_AS_WRITTEN
		)
	end
	local out = {}
	for _, k in ipairs { "from", "to" } do
		local v = value[k]
		if type(v) ~= "number" then
			at:key(k):refuse("must be an Oklab lightness, a number above 0 and at most 1, got %s", schema.as_written(v))
		elseif not (v > 0 and v <= 1) then
			at:key(k):refuse(
				"must be above 0 and at most 1, got %s. 0 is black at every hue and 1 is the lightest Oklab has",
				tostring(v)
			)
		end
		out[k] = v
	end
	return out
end

--- Every lightness range `setup` was given, by name. A namespace rather than a
--- fixed set, so no sweep refuses a misspelled one; the refusal of an undefined
--- range lists what is defined instead. No name is built in: `fg` and `bg` are
--- what the two keys ask for, not ranges that exist without being written.
---@param value any
---@param at supaline.Path
---@return supaline.LightnessRanges
function M.ranges(value, at)
	if value == nil then
		return {}
	elseif type(value) ~= "table" then
		at:refuse(
			"must be a table of lightness ranges by name, as `{ fg = %s }`, and a name is then what a `<->` asks for",
			RECOMMENDED_AS_WRITTEN
		)
	end
	-- The pair written where a table of them goes, told apart by what the key
	-- holds, so a range genuinely named `to` is refused for its name instead.
	if (value.from ~= nil and type(value.from) ~= "table") or (value.to ~= nil and type(value.to) ~= "table") then
		at:refuse(
			"`from` and `to` are a range's own keys, and `lightness` holds ranges by name. Write "
				.. "`lightness = { fg = %s }`, and name a second range to reach it from a `<->`",
			RECOMMENDED_AS_WRITTEN
		)
	end
	-- In the order of their names, so two ranges wrong at once are named in the
	-- same order on every run.
	local out = {}
	for _, name in ipairs(schema.sorted_keys(value)) do
		local one = value[name]
		if type(name) ~= "string" or not name:find(NAME) then
			at:refuse("`%s` is not a range name. A name holds lowercase letters, digits and `_`", tostring(name))
		elseif RESERVED[name] then
			at:refuse(
				"`%s` is one of a range's own two keys and cannot also be a range's name. Call the range something else",
				name
			)
		end
		out[name] = M.bounds(one, at:key(name))
	end
	return out
end

---@param s string
---@return string
local function trim(s) return (s:match("^%s*(.-)%s*$")) end

--- The colour before a `<->` and the range's name after it; nil when there is
--- no marker.
---@param s string
---@return string? colour, string? name
local function unmark(s)
	local a, b = s:find(BOTH, 1, true)
	if not a then
		return nil, nil
	end
	local name = trim(s:sub(b + 1))
	return trim(s:sub(1, a - 1)), name ~= "" and name or nil
end

---@param ranges supaline.LightnessRanges
---@return string
local function defined_in(ranges)
	local names = schema.sorted_keys(ranges)
	return #names > 0 and "Defined: " .. schema.quoted(names) or "No lightness range is defined yet"
end

---@param s string
---@return string[]
local function split(s)
	local out, pos = {}, 1
	while true do
		local a, b = s:find(ARROW, pos, true)
		out[#out + 1] = trim(s:sub(pos, a and a - 1))
		if not b then
			return out
		end
		pos = b + 1
	end
end

--- One end of a ramp. It has to be `#rrggbb`: interpolating from a palette
--- name would put a ramp on screen whose end did not meet the terminal's own.
---@param one string
---@param at supaline.Path
---@return integer[]
local function endpoint(one, at)
	local rgb = M.colour(one, at)
	if not rgb then
		at:refuse(
			"`%s` cannot be a gradient endpoint. A name and a 256-colour index are whatever the "
				.. "terminal's palette makes them, and a ramp interpolated from a guess would not meet "
				.. "either end; write `#rrggbb`",
			one
		)
	end
	return rgb --[[@as integer[] ]]
end

--- The stops of a gradient, in order, as RGB. `#a -> #b` writes them; `#x <->`
--- derives both from one colour at the range the key asks for -- `fallback`,
--- the key it was written under, unless a name follows the marker.
---@param value any
---@param at supaline.Path
---@param ranges supaline.LightnessRanges
---@param fallback string
---@return integer[][]
function M.stops(value, at, ranges, fallback)
	if type(value) ~= "string" then
		at:refuse("must be a string like `#0b3d91 -> #7fd4ff`, got a %s", type(value))
	end
	local body, name = unmark(value)
	if body then
		if body == "" or body:find("%s") then
			at:refuse(
				"`%s` does not spread a colour. `<->` spreads one over a lightness range, as `#ff8800 <->`; to choose "
					.. "the ends yourself, write them with `->`",
				value
			)
		elseif name and not name:find(NAME) then
			at:refuse(
				"`%s` is not a range name. What follows `<->` names a lightness range `setup` defined, in lowercase "
					.. "letters, digits and `_`; to choose the two ends of a ramp yourself, write them with `->`",
				name
			)
		elseif name and RESERVED[name] then
			at:refuse(
				"`%s` is one of a range's own two keys, so there is no range by that name to ask for -- "
					.. "`setup` refuses one that tries. Call the range something else and name it that",
				name
			)
		end
		local wanted = name or fallback
		local range = ranges[wanted]
		if not range then
			at:refuse(
				"`%s` asks for a lightness range and nothing defines `%s`. Both ends of a range are "
					.. "lightnesses the ground it is drawn on decides, and supaline cannot see that ground -- so "
					.. "there is no pair to fall back to. Put `lightness = { %s = %s }` in `setup` and move it to "
					.. "suit your terminal; "
					.. "`lua test/ramp.lua` draws a pair before you keep it. %s",
				value,
				wanted,
				schema.as_key(wanted),
				RECOMMENDED_AS_WRITTEN,
				defined_in(ranges)
			)
		end
		-- The colour last, so a `<->` naming nothing is told that first.
		return colour.spread(endpoint(body, at), range)
	end

	-- Each end is named by its place along the ramp, since one colour may be
	-- written at more than one of them.
	local stops = {}
	for i, one in ipairs(split(value)) do
		stops[i] = endpoint(one, schema.path(string.format("%s, stop %d", tostring(at), i)))
	end
	if #stops < 2 then
		at:refuse(
			"`%s` is one colour, and a gradient needs two ends. Write `#0b3d91 -> #7fd4ff`, or `%s <->` "
				.. "to spread the one colour over a lightness range",
			value,
			value
		)
	end
	return stops
end

--- The painter a column's style is read with: a gradient resolved against the
--- lightness ranges `setup` defined, anything else a colour Yazi takes.
---@param ranges supaline.LightnessRanges
---@return supaline.Painter
function M.painter(ranges)
	return function(value, at, key)
		if M.is_ramp(value) then
			return M.stops(value, at, ranges, key)
		end
		M.colour(value, at)
		return value
	end
end

--- The painter a separator's style is read with. A separator is drawn between
--- two columns rather than on a file, so there is no value to place on a
--- gradient, and every spelling of one is refused by the same sentence.
---@type supaline.Painter
function M.flat(value, at)
	if M.is_ramp(value) then
		at:refuse(
			"`%s` is a gradient, and there is no value here to place on one. A separator is drawn "
				.. "between two columns rather than on a file; write a flat colour",
			value
		)
	end
	M.colour(value, at)
	return value
end

return M
