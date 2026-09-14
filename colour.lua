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
--- A style can be read back out, and this file does it for every `ui.Style`
--- it is handed. `pairs` refuses the userdata, `==` is false between two
--- styles built the same way, and `style.fg` hands back the setter rather
--- than the colour -- but `raw()` answers with a plain table, `fg` and `bg` as
--- strings and the attributes as booleans, for a style Yazi built as readily
--- as for one built here. Measured on 26.9.1 -- `ui.Style():fg("#ff8800"):raw()`
--- comes back `{ fg = "#FF8800" }`, uppercased, and a flavor's
--- `th.status.perm_read` comes back `{ fg = "#F9E2AF" }` once the `theme`
--- event has landed. That is what lets a theme's table field and a spec's
--- `ui.Style` be read key by key, like a table written out, and take part in
--- the merge below instead of replacing it whole. `supaline.Style` declares
--- the method, and `.agents/skills/yazi-platform-traps/references/probes.md`
--- holds the run.
---
--- What it also allows and this file does not yet do is anchor a gradient on
--- a colour read out of a flavor: `raw().fg` off one is `#rrggbb`, which
--- `M.stops` would take, where Yazi's own preset answers with a name and would
--- have to be refused from inside a `theme` handler. Undesigned, not
--- impossible.

--- The module table. Declared for the same reason `supaline.ColumnModule` is:
--- `require(".colour")` resolves to this tree and the signatures below are read
--- normally, but a misspelled `colour.stopss` costs nothing until the table
--- itself carries a class.
---@class supaline.ColourModule
local M = {}

--- `ui.Style` as 26.9.1 has it, where `types.yazi` declares less. `raw()`
--- answers with the style as a plain table: `fg` and `bg` as strings, each
--- attribute under the theme's key as the boolean it holds, and nothing at all
--- for a key nobody set. It answers for a style Yazi built as readily as for
--- one built here, and Yazi's own `entity.lua` reads `raw().reversed` off one,
--- since v25.12.29. The annotations mark the class `(exact)` and declare no
--- `raw`, so a caller casts to this where the value arrives -- the same
--- arrangement `supaline.Line` makes for `truncate` -- and `test/stub.lua`
--- models the method, pinned by `colour_spec.lua` against the run in
--- `yazi-platform-traps/references/probes.md`.
---@class supaline.Style : ui.Style
---@field raw fun(self: self): supaline.StyleTable

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
--
-- `test/setup.sh` reads the number off this line with a `sed`, to build one
-- file per step, so the *shape* of the line is load-bearing from outside this
-- file: a trailing comment or a `<const>` breaks the read. It stops both
-- harnesses loudly and says so, but it says it about the fixture.
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

-- And what says "spread this one colour" where the same constraint applies.
-- A band has no second endpoint to write, so a theme field holding one would
-- otherwise be indistinguishable from a flat colour -- which is what
-- `size = "#ff8800"` has always meant and has to go on meaning.
--
-- It contains `ARROW`, so `is_ramp` answers a band without being told about
-- one, and the two spellings cannot disagree about what counts as a ramp.
local BOTH = "<->"

-- The two lightnesses a band runs between, as Oklab lightnesses, in the order
-- a ratio walks them: `from` is what ratio 0 draws, `to` what ratio 1 draws.
--
-- **Both ends are fixed.** The colour that was written supplies the hue and
-- nothing else; it is not placed in the band anywhere, and for a base outside
-- these two numbers it is not on the band at all. What that buys is that two
-- columns drawn from different hues put the same ratio at the same lightness,
-- so a row can be read across them -- where a band widened to swallow whatever
-- was written leaves the darkest cell of one column and the darkest cell of
-- the next meaning different things.
--
-- `from = 0.35` is where a step stops being *lighter than* the ground it is
-- drawn on. The premise under it is a dark terminal, and supaline has no way
-- to check: `types.yazi` declares no background for `th` to carry, and a
-- flavor that sets none leaves the terminal's own showing through, which is
-- not Yazi's to know either. Measured over five common dark grounds -- black,
-- Mocha, One Dark, Gruvbox dark, Solarized dark -- the lightest of them is One
-- Dark at an Oklab lightness of 0.293, and a floor of 0.30 puts the darkest
-- step level with it: contrast 1.00 over eight bases tried, which is a row
-- drawn in the background colour. 0.35 clears all five.
--
-- What it is not is a readability threshold. Clearing a ground by 0.06 is
-- worth a contrast of 1.20 at worst, well under what body text is held to, so
-- the end of a band is a colour a reader can see and not one they can
-- comfortably read. A band spends the room it is given; a column that has to
-- be read at both ends wants two endpoints instead.
--
-- `to = 0.88` by looking, which is the only way a number like this gets
-- settled. 0.83 was tried first and has an argument behind it -- it is where
-- `#7fd4ff` sits, so a band around one would have agreed with a hand-written
-- ramp to the byte -- and on a terminal it still read as a band that had not
-- quite brightened. The two were drawn at 64 steps over four bases and
-- compared side by side; 0.88 is the one that was easier to read.
--
-- **A light terminal wants the pair the other way round**, which is the other
-- half of what `setup`'s `band` is for: `{ from = 0.90, to = 0.35 }` puts the
-- pale end at ratio 0 and the dark one at ratio 1, and nothing else has to
-- change. 0.90 is the mirror of the default's own margin -- 0.35 clears the
-- lightest dark ground by 0.057, and 0.90 clears the darkest light ground by
-- 0.058, Latte's `#eff1f5` at 0.958. Its other end is not derivable and was
-- not derived: 0.35 is there because the dark default's is, and a light
-- terminal is worth looking at with `test/ramp.lua` before settling on one.
--- The two lightnesses a band runs between, `from` at ratio 0.
---@alias supaline.Band { from: number, to: number }

---@type supaline.Band
local DEFAULT_BAND = { from = 0.35, to = 0.88 }

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
--- Only ever called with a string. `fg()` handed nil or a boolean is the
--- getter rather than the setter -- it answers the colour the style holds, or
--- nil, and raises for neither -- so a caller that let either through would
--- be told the colour was fine.
---@param value string
---@return boolean
local function accepted(value)
	return (pcall(function() return ui.Style():fg(value) end))
end

-- The attribute keys a style table takes, in the order an error lists them,
-- and the one place that spelling and the `ui.Style` method behind it
-- disagree.
--
-- The spelling is `theme.toml`'s rather than the API's, which is the whole of
-- what taking a table here buys: one style, written the same way in both
-- files. The two names part company in exactly the place a reader is most
-- likely to get wrong -- the theme key is `reversed` where the method is
-- `reverse()` -- and a theme that writes the method name is not corrected,
-- it is ignored. Measured on 26.9.1: `reverse = true` in `[supaline]` left
-- the column with no attribute and said nothing anywhere.
--
-- Which is the other half of what this is for. Yazi hands a plugin the
-- `Style` it parsed, never the table behind it, so a key it does not know is
-- gone before `th.supaline` exists and no check here could ever see it; the
-- README is the only instrument the theme side has. A table written in a
-- spec reaches this file verbatim, so here a misspelling is refused by name.
local ATTRS = { "bold", "dim", "italic", "underline", "blink", "blink_rapid", "reversed", "hidden", "crossed" }

-- The two keys that hold a colour rather than an attribute, in the order an
-- error lists them. Written once because three places walk the pair -- reading
-- a layer, building one, and looking for a gradient in a merged one -- and a
-- fourth spelling of it is how one of them would be left behind on the day
-- Yazi grows a third.
local COLOURS = { "fg", "bg" }

-- The `ui.Style` method each of those keys drives, filled in for the eight
-- that answer to their own name, so that one table is both the allow-list the
-- refusal below reads and the lookup the style is built through.
local METHOD = { reversed = "reverse" }
for _, k in ipairs(ATTRS) do
	METHOD[k] = METHOD[k] or k
end

-- What a key that is none of those most likely meant. Only spellings a reader
-- arrives at honestly: `reverse` off the method name or another terminal
-- library, `strikethrough` off CSS, and `reset` off the colour of that name,
-- which is a colour rather than an attribute and has to be written as one.
local MEANT = {
	reverse = "`reversed` is the spelling, here and in `theme.toml`",
	strikethrough = "`crossed` is the spelling",
	reset = '`reset` is a colour rather than an attribute -- write `fg = "reset"`',
}

--- "`a`, `b` and `c`" out of a list of names, for a message that has to say
--- what a table does take.
---
--- Here because two allow-lists want it and the third would have written a
--- third copy. Each of them builds the list rather than spelling the sentence
--- out, so a key added to one cannot be missing from the message that lists
--- them; what that costs without this is the same `table.concat` expression,
--- with the same off-by-one in the range, in as many files as have keys.
---@param names string[] at least two
---@return string
function M.key_list(names)
	return string.format("`%s` and `%s`", table.concat(names, "`, `", 1, #names - 1), names[#names])
end

local KEY_LIST = M.key_list(ATTRS)

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
	elseif not accepted(value) then
		refuse(value, where)
	end
	return nil
end

--- The style a table written in a spec asks for.
---
--- Every key of `t` that `claims` does not answer for, sorted, and the same
--- names quoted and joined ready to drop into a message. Nil when every key
--- was claimed.
---
--- Every one of them rather than the first one found, and sorted: `pairs`
--- walks a table in whatever order the hash gives, so naming one of two
--- misspellings makes the same mistake report differently from one run to the
--- next, and costs a second run to find the other half of it.
---
--- What each caller has to say differs; what does not is the quoting, the
--- `is` or `are` that follows it, and the hint each name earns. Those three
--- drifted apart once already and are built here now, so a fourth allow-list
--- is a key set and a noun rather than a message assembled by hand.
---
--- Here because here is the only place all three callers can reach. This file
--- sits at the bottom of the require chain and knows nothing about a linemode
--- spec or a separator; `column.lua` and `main.lua` both require it, and
--- neither requires the other in the direction that would do. The three had
--- already drifted in where the quoting happens -- `panes_of` quoted each name
--- as it collected it, `M.layer` at the join -- which is the drift a fourth
--- copy would have continued.
---@param t table
---@param claims fun(key: any): boolean? whether the table is entitled to that key
---@param noun string? what one of this table's keys is called, for `subject`
---@param meant table<string, string>? what a given misspelling most likely meant
---@return string[]? names sorted, for a caller that has something to say about each
---@return string? quoted the same names, backquoted and comma-joined
---@return string? subject the same names, and whether they is or are not a `noun` key
---@return string? hints what each of them probably meant, joined, or ""
function M.unknown(t, claims, noun, meant)
	local names = {}
	for k in pairs(t) do
		if not claims(k) then
			names[#names + 1] = tostring(k)
		end
	end
	if #names == 0 then
		return nil
	end
	table.sort(names)

	local quoted = "`" .. table.concat(names, "`, `") .. "`"
	local subject = noun
		and string.format("%s %s", quoted, #names == 1 and "is not a " .. noun .. " key" or "are not " .. noun .. " keys")
	local hints = {}
	for _, k in ipairs(names) do
		hints[#hints + 1] = meant and meant[k]
	end
	return names, quoted, subject, #hints > 0 and ". " .. table.concat(hints, "; ") or ""
end

-- What a style table is entitled to: the two colours, and an attribute under
-- whichever of its two spellings. Derived from `METHOD` rather than written
-- out, because a list and a set of the same names are two things to keep in
-- step.
local function claims_style(k) return k == "fg" or k == "bg" or METHOD[k] ~= nil end

-- Every key a style holds, in the order an error lists them: the two colours
-- and then the nine attributes. What `M.merge` walks.
local KEYS = {}
for _, k in ipairs(COLOURS) do
	KEYS[#KEYS + 1] = k
end
for _, k in ipairs(ATTRS) do
	KEYS[#KEYS + 1] = k
end

--- Whether `value` is a `ui.Style` rather than something that merely looks
--- like one.
---
--- By what it answers to, not by what it is. `getmetatable` cannot do it:
--- measured on 26.9.1, mlua gives every one of Yazi's userdata
--- `__metatable = false`, so `getmetatable(ui.Style())`,
--- `getmetatable(ui.Span("x"))` and `getmetatable(ui.Line {})` are all `false`
--- and all equal to each other -- a check written on the metatable waves a
--- Span through as a colour. `patch` is a `Style` method and nothing else here
--- has one: on the same 26.9.1, `style:patch(ui.Style())` succeeds where the
--- Span and the Line both raise. The harness's stand-in answers it too, which
--- is what keeps one test a test of the branch that calls this.
---
--- Asked before the `type` test, and for a reason: the harness's stand-in for
--- a `Style` is a Lua table, so a check on `type` alone would take it in the
--- suite and refuse it in Yazi.
---@param value any
---@return boolean
local function is_style(value)
	return value ~= nil and pcall(function() return value:patch(ui.Style()) end)
end

--- A style as a user writes it in a spec: the keys `theme.toml` takes, in the
--- spelling `theme.toml` uses. `fg` and `bg` hold a colour Yazi's parser
--- takes, a gradient as `"#a -> #b"`, a band as `"#x <->"`, or `false` for
--- none; each attribute holds `true`, or `false` for the attribute taken off
--- whatever is beneath. A `ui.Style` answers `raw()` with the same shape, in
--- Yazi's own spelling of the colours.
---@class supaline.StyleTable
---@field fg string|false|nil
---@field bg string|false|nil
---@field bold boolean?
---@field dim boolean?
---@field italic boolean?
---@field underline boolean?
---@field blink boolean?
---@field blink_rapid boolean?
---@field reversed boolean?
---@field hidden boolean?
---@field crossed boolean?

--- What one writer may put under `style`: the table above, a colour string
--- standing for its `fg`, a `ui.Style`, or `false` for nothing at all --
--- neither a colour of its own nor whatever the writers beneath it said.
---@alias supaline.StyleValue string|supaline.StyleTable|ui.Style|false

--- ... or a function returning one of those, or nothing. Called each time
--- the linemode is built, which is how a spec borrows a colour from a flavor
--- that had not landed while `init.lua` ran.
---@alias supaline.StyleSpec supaline.StyleValue|(fun(): supaline.StyleValue?)

--- A colour as one layer holds it under `fg` or `bg`: a flat colour as the
--- string it was written as, a gradient as its stops, `false` for none.
---@alias supaline.Paint string|integer[][]|false

--- One writer's say about a column's style, read into the shape every
--- writer's is read into -- the definition's, the theme's and the spec's --
--- so that `M.merge` can take each key from the nearest of them. A key nobody
--- wrote is absent, which is what leaves it to the layer beneath.
---
--- `false` in place of a layer is the writer saying nothing at all: no
--- colour, and nothing from beneath either. It is not a layer of eleven
--- `false`s, because an attribute's `false` is the attribute *taken off* --
--- the row's own bold along with a theme's -- where a colour's `false` is
--- merely no colour. `M.merge` reads it as the two colours off and the
--- attributes left unwritten.
---@class supaline.Layer
---@field fg supaline.Paint?
---@field bg supaline.Paint?
---@field bold boolean?
---@field dim boolean?
---@field italic boolean?
---@field underline boolean?
---@field blink boolean?
---@field blink_rapid boolean?
---@field reversed boolean?
---@field hidden boolean?
---@field crossed boolean?

--- One colour or gradient under `fg` or `bg`, as the layer keeps it.
---
--- A gradient is told by the arrow, which is the one thing a flat colour can
--- never contain, and parsed here rather than kept as written so that every
--- refusal a style can earn is earned while the layer is read. Everything
--- else goes through `M.colour`, which refuses what is not a string -- a
--- table under `fg` included, and no more is said about one -- and what
--- Yazi's parser would not take.
---@param value any
---@param where string
---@param band supaline.Band? for a band, the default when omitted
---@return supaline.Paint
local function paint(value, where, band)
	if M.is_ramp(value) then
		return M.stops(value, where, band)
	end
	M.colour(value, where)
	return value
end

--- Read what one writer put under `style` into a layer.
---
--- The whole "is this a style" decision lives here, in one allow-list, so
--- there is one place to read and one message to keep right. A value that is
--- none of them is refused *now*: `Span:style` takes a `Style` or nil and
--- nothing else, and anything else fails while drawing -- measured on 26.9.1,
--- a value that was neither survived `setup` and then emptied the screen, with
--- `Failed to redraw the Root component` in the log and nothing on it.
---
--- A table is read key by key rather than built into a style: a layer has to
--- know which keys were written, because a key nobody wrote is what leaves
--- the one beneath showing. A `ui.Style` is read the same way, through
--- `raw()`, which hands back exactly the keys it holds in the theme's own
--- spelling -- so a themed table field, which arrives as the `Style` Yazi
--- parsed, and a spec's `ui.Style():fg(...):bold()` are one shape by the time
--- they are here. The shape tests are for a table the user typed: Yazi does
--- not hand back a constructor, and a `ui.Style()` holding nothing is a layer
--- that says nothing, which is allowed.
---@param value any nil, `false`, a colour string, a style table, or a ui.Style
---@param where string
---@param band supaline.Band? the default when omitted
---@return supaline.Layer|false
function M.layer(value, where, band)
	local t
	if value == nil then
		return {}
	elseif value == false then
		return false
	elseif type(value) == "string" then
		return { fg = paint(value, where, band) }
	elseif is_style(value) then
		t = (value --[[@as supaline.Style]]):raw()
	elseif type(value) ~= "table" then
		error(
			string.format(
				"supaline: %s is a %s. A style is a colour string, a table of style keys, a "
					.. "`ui.Style`, or `false`, and anything else reaches Yazi as none of them: the "
					.. 'linemode stops drawing and the screen goes blank. Write `"#rrggbb"`, '
					.. '`{ fg = "#ff8800", bold = true }`, or `ui.Style():fg(...):bold()`',
				where,
				type(value)
			)
		)
	else
		-- A table with a `__call` is a constructor rather than a style: `style
		-- = ui.Style`, with the call forgotten. Measured on 26.9.1, `type(ui.Style)`
		-- is `table` and `pairs` over it finds nothing, so without this it would
		-- read as a layer saying nothing and draw the column in whatever was
		-- beneath -- which is the silence this whole branch exists to end. The
		-- harness's `ui.Style` is the same shape, which is what keeps the test a
		-- test of this line.
		local mt = getmetatable(value)
		if type(mt) == "table" and mt.__call ~= nil then
			error(
				string.format(
					"supaline: %s is a table you can call rather than a style. `ui.Style` is the "
						.. 'constructor: write `ui.Style()` with the call, or `{ fg = "#ff8800", '
						.. "bold = true }` to say the same thing as a table",
					where
				)
			)
		elseif next(value) == nil then
			error(
				string.format(
					"supaline: %s is a style table with no keys in it, which says nothing at all. "
						.. 'Write the keys you mean, as `{ fg = "#ff8800", bold = true }`, or `false` '
						.. "to turn every key off",
					where
				)
			)
		end
		t = value
	end

	local unknown, _, subject, hints = M.unknown(t, claims_style, "style", MEANT)
	if unknown then
		error(
			string.format(
				"supaline: %s: %s. A style table takes `fg` and `bg`, "
					.. "plus %s -- the spelling `theme.toml` uses, so a style is written the "
					.. "same way in both files%s",
				where,
				subject,
				KEY_LIST,
				hints
			)
		)
	end

	local layer = {}
	for _, k in ipairs(COLOURS) do
		local v = t[k]
		if v == false then
			layer[k] = false
		elseif v ~= nil then
			layer[k] = paint(v, string.format("%s: `%s`", where, k), band)
		end
	end
	for _, k in ipairs(ATTRS) do
		local v = t[k]
		if v ~= nil and type(v) ~= "boolean" then
			error(
				string.format(
					"supaline: %s: `%s` is an attribute rather than a colour, so it must be true or false, got a %s",
					where,
					k,
					type(v)
				)
			)
		elseif v ~= nil then
			layer[k] = v
		end
	end
	return layer
end

--- Stack the layers, farthest writer first, and give each key to the nearest
--- one that wrote it.
---
--- `false` is written: a spec that turned a colour off has said something
--- about it, and the layer beneath does not show through. A layer that is
--- `false` whole starts the stack over with both colours off -- so a column
--- that asks who wrote its `fg` is told, and steps aside -- and every
--- attribute unwritten. The second value says which layer each key came
--- from, for the message that has to name a file and for that one column.
---@param layers (supaline.Layer|false)[]
---@return supaline.Layer resolved
---@return table<string, integer> from the index in `layers` of each key's writer
function M.merge(layers)
	local out, from = {}, {}
	for i, layer in ipairs(layers) do
		if layer == false then
			out, from = { fg = false, bg = false }, { fg = i, bg = i }
		else
			for _, k in ipairs(KEYS) do
				local v = layer[k]
				if v ~= nil then
					out[k], from[k] = v, i
				end
			end
		end
	end
	return out, from
end

--- Which colour key of a merged layer holds a gradient, if either does.
---
--- A gradient is parsed while the layer is read, so by here it is a table of
--- stops where a flat colour is a string, and `M.is_ramp`'s arrow is long
--- gone. Asked here rather than by each caller because the answer is what
--- `supaline.Paint` *is*, and two callers outside this file reading `type(v)
--- == "table"` is that shape written down in a third place and a fourth.
---
--- Both callers have something to say about the key rather than a yes or a
--- no, and both refuse the first one they find: a message about `fg` and a
--- message about `bg` say the same thing twice, and the second is earned
--- again as soon as the first is fixed.
---@param resolved supaline.Layer
---@return string? key `"fg"` or `"bg"`, nil when neither holds one
function M.gradient_in(resolved)
	for _, k in ipairs(COLOURS) do
		if type(resolved[k]) == "table" then
			return k
		end
	end
	return nil
end

--- Build what a row is drawn in out of the merged layer: one style, or
--- `STEPS` of them when `fg` or `bg` holds a gradient.
---
--- The ground carries everything but a gradient -- the flat colours, and each
--- attribute added or taken off through the method that does it. A gradient
--- is then a colour set on that ground per step, so a `bold` or a `bg` beside
--- it comes out on every step, and two gradients land on the same step at the
--- same ratio. Per row there is then nothing left to do but index the result.
---
--- The attribute methods take a removal flag rather than the value, so a
--- `false` in the layer goes in as `true`: `bold()` and `bold(false)` both
--- *add* the attribute and only `bold(true)` takes it off. Read off
--- `yazi-binding/src/style/style.rs` at 26.9.1 and measured through
--- `Style:raw()` -- `ui.Style():bold(true)` comes back `{ bold = false }`, the
--- same shape a theme's `bold = false` arrives in.
---@param resolved supaline.Layer
---@return unknown ground a ui.Style holding every key but a gradient
---@return unknown[]? steps `STEPS` styles, ratio 0 first, when there is a gradient
function M.build(resolved)
	local ground = ui.Style()
	for _, k in ipairs(ATTRS) do
		local v = resolved[k]
		if v ~= nil then
			ground = ground[METHOD[k]](ground, not v)
		end
	end
	local ramps
	for _, k in ipairs(COLOURS) do
		local v = resolved[k]
		if type(v) == "string" then
			ground = ground[k](ground, v)
		elseif type(v) == "table" then
			ramps = ramps or {}
			ramps[k] = M.ramp(v)
		end
	end
	if not ramps then
		return ground, nil
	end
	local steps = {}
	for i = 1, STEPS do
		local step = ground
		for k, hexes in pairs(ramps) do
			step = step[k](step, hexes[i])
		end
		steps[i] = step
	end
	return ground, steps
end

--- One style on its own, for a separator: a layer read and built with no
--- other writer to merge it with, and no value to place on a gradient.
---@param value any what `M.layer` takes
---@param where string
---@return unknown a ui.Style
function M.flat(value, where)
	-- `false` is a separator's caller's to refuse, and it does, before this is
	-- reached; here it would be a style saying nothing, which is what it is.
	local layer = M.layer(value, where) or {}
	local key = M.gradient_in(layer)
	if key then
		error(
			string.format(
				"supaline: %s: `%s` is a gradient, and there is no value here to place on one. "
					.. "A separator is drawn between two columns rather than on a file; write a "
					.. "flat colour",
				where,
				key
			)
		)
	end
	return (M.build(layer))
end

--- Whether a value asks for a gradient rather than a flat colour.
---
--- A colour is a string, a gradient is a string, and the arrow is the one
--- thing a flat colour can never contain. A style table is not a ramp and
--- answers false through the same test, whether it arrives as Yazi's userdata
--- or as the harness's stand-in.
---@param value any
---@return boolean
function M.is_ramp(value) return type(value) == "string" and value:find(ARROW, 1, true) ~= nil end

--- The band `setup` was given, checked, or the default when it was given none.
---
--- Checked here rather than in `main.lua` because the pair means something
--- only to this file, and because `test/ramp.lua` takes one on the command
--- line and wants the refusals a user's `init.lua` gets.
---
--- A lightness of 0 is black whatever the hue, so an end there is one no
--- colour reaches and a step most themes draw in their own background; `(0, 1]`
--- is the range with anything in it. Written as `v > 0 and v <= 1` and negated
--- rather than as the complement, because a NaN answers false to both and has
--- to land on the refusing side -- `math.huge / math.huge` in a user's own
--- arithmetic is the way one arrives.
---
--- The type and the range are the whole of it: nothing here reads the pair as
--- a pair. Equal ends draw sixty-four steps of one colour, which is what
--- a flat colour already is and is unlikely to be what the writer meant, and they are
--- taken anyway. An equality test catches one spelling of a thing with many --
--- `{ from = 0.5, to = 0.501 }` draws the same single colour and passes any
--- comparison of the two numbers -- and where flat stops being flat is a
--- judgement rather than a test. Asking after the ends are drawn does not help
--- either: whether the steps collapse depends on the hue they are drawn at,
--- which this function never sees, so one column's colour would refuse a band
--- the rest of them take.
---@param value any what `setup` was given, if anything
---@param where string
---@return supaline.Band
function M.bounds(value, where)
	if value == nil then
		return DEFAULT_BAND
	elseif type(value) ~= "table" then
		error(
			string.format(
				"supaline: %s must be a table of two lightnesses, as "
					.. "`{ from = 0.35, to = 0.88 }` -- `from` is what ratio 0 draws and `to` "
					.. "what ratio 1 draws, so a light terminal writes the larger one first",
				where
			)
		)
	end

	local out = {}
	for _, k in ipairs { "from", "to" } do
		local v = value[k]
		if type(v) ~= "number" then
			error(
				string.format(
					"supaline: %s: `%s` must be an Oklab lightness, a number above 0 and at " .. "most 1, got `%s`",
					where,
					k,
					tostring(v)
				)
			)
		elseif not (v > 0 and v <= 1) then
			error(
				string.format(
					"supaline: %s: `%s` must be above 0 and at most 1, got %s. 0 is black at "
						.. "every hue and 1 is the lightest Oklab has",
					where,
					k,
					tostring(v)
				)
			)
		end
		out[k] = v
	end

	return out
end

--- Take the `<->` off a value that carries one.
---
--- Only the marker is removed; what is left is a colour like any other, and
--- goes on to be read as the one stop a band is built from. So there is one
--- path from written value to stops, and `<->` decides nothing but whether
--- one colour is a band or a mistake.
---@param s string
---@return string body, boolean marked
local function unmark(s)
	local a, b = s:find(BOTH, 1, true)
	if not a then
		return s, false
	end
	return (s:sub(1, a - 1) .. s:sub(b + 1)):match("^%s*(.-)%s*$"), true
end

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

--- The endpoints of a gradient, in order, as RGB.
---
--- Every one of them has to be `#rrggbb`: an interpolation needs numbers at
--- both ends, and the numbers behind `cyan` are the terminal's rather than
--- ours. Guessing them would put a ramp on screen whose ends did not meet the
--- terminal's own cyan, which is worse than being told to write the colour out.
---
--- One string, in both files. `theme.toml`'s custom sections take a string or
--- a style table and nothing else -- an array there is refused, and the whole
--- file goes with it -- and a spec spells it the same way rather than a second
--- way of its own. **A colour with `<->` beside it is a band**, and `M.band`
--- derives both ends from it; a colour on its own is not a gradient at all and
--- is refused here, because under `fg` a bare colour is a flat colour and has
--- to go on meaning one.
---@param value any a string like `#0b3d91 -> #7fd4ff`, or `#7fd4ff <->`
---@param where string
---@param band supaline.Band? the default when omitted
---@return integer[][]
function M.stops(value, where, band)
	if type(value) ~= "string" then
		error(string.format("supaline: %s must be a string like `#0b3d91 -> #7fd4ff`, got a %s", where, type(value)))
	end
	local body, marked = unmark(value)
	if marked and (body == "" or body:find("%s")) then
		error(
			string.format(
				"supaline: %s: `%s` is not a band. `<->` spreads one colour both ways, "
					.. "as `#ff8800 <->`; to choose the ends yourself, write them with `->`",
				where,
				value
			)
		)
	end
	local written = marked and { body } or split(value)

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

	if marked then
		-- Forward, through the table: the band is Oklab arithmetic and the
		-- locals it runs on are declared below, where the rest of that
		-- arithmetic lives. Reachable by the time anything calls this.
		return M.band(stops[1], band)
	elseif #stops < 2 then
		error(
			string.format(
				"supaline: %s: `%s` is one colour, and a gradient needs two ends. Write "
					.. "`#0b3d91 -> #7fd4ff`, or `%s <->` to spread the one colour into a band",
				where,
				value,
				value
			)
		)
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
---@param band supaline.Band? the default when omitted
---@return integer[][] two stops, ratio 0 first
function M.band(rgb, band)
	band = band or DEFAULT_BAND

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
