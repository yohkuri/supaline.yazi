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
--- `require(".style")` resolves to this tree and the signatures below are read
--- normally, but a misspelled `style.stopss` costs nothing until the table
--- itself carries a class.
local colour = require(".colour")
local diagnostics = require(".diagnostics")
---@class supaline.StyleModule
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
-- The pure colour module exports the count used by the fixture too.
local STEPS = colour.STEPS

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
-- **A light terminal wants the pair the other way round**: `{ from = 0.90,
-- to = 0.35 }` puts the pale end at ratio 0 and the dark one at ratio 1, and
-- nothing else has to change. 0.90 is the mirror of the dark pair's own margin
-- -- 0.35 clears the lightest dark ground by 0.057, and 0.90 clears the
-- darkest light ground by 0.058, Latte's `#eff1f5` at 0.958. Its other end is
-- not derivable and was not derived: 0.35 is there because the dark pair's is,
-- and a light terminal is worth looking at with `test/ramp.lua` before
-- settling on one.
--
-- **None of this is applied to anybody.** Every sentence above measures a
-- population -- five grounds, four bases, one pair of eyes -- and a band is a
-- claim about the one ground it is drawn on, which is the reader's and which
-- the paragraph above says outright supaline cannot see. So what these numbers
-- buy is a recommendation to quote, not a value to reach for when nobody said:
-- a band with no definition behind it is refused, and the refusal carries this
-- pair for the reader to paste and then move. The alternative was to apply
-- them quietly, which draws a band that may be wrong for the ground and says
-- nothing about being adjustable at all -- the shape of failure the rest of
-- this plugin refuses.
--- The two lightnesses a band runs between, `from` at ratio 0.
---@alias supaline.Band { from: number, to: number }

--- Bands by name, as `setup` was given them. Every name a `<->` can reach is
--- in here; there is nothing behind it.
---@alias supaline.Bands table<string, supaline.Band>

---@type supaline.Band
local RECOMMENDED = { from = 0.35, to = 0.88 }

--- What a band with no definition is told to write, as a fresh table.
---
--- Fresh because what leaves here goes into a `supaline.Bands` its caller owns
--- -- `test/ramp.lua` builds one out of it -- and a shared table handed out
--- twice is two callers writing to one band.
---@return supaline.Band
function M.recommended() return { from = RECOMMENDED.from, to = RECOMMENDED.to } end

-- The pair as the refusals spell it, built once from the table above so the
-- message and the value cannot drift.
local RECOMMENDED_AS_WRITTEN = string.format("{ from = %s, to = %s }", RECOMMENDED.from, RECOMMENDED.to)

-- What a band's name may hold, which is the character class a column's name
-- holds -- for a reason that is not the column's. A column name has to survive
-- Yazi's parser as a `[supaline]` field; nothing parses a band name at all,
-- since it is a Lua key under `band` and a substring after a `<->`. The class
-- is taken anyway, because this plugin already has one shape a name is written
-- in and a second one would be a rule with nothing behind it.
--
-- What is not taken is the cap. `column.lua`'s `NAME` carries `NAME_MAX = 20`
-- beside it because the parser enforces 20; copying that here would be a limit
-- invented for symmetry, which is the same mistake as an invented class. So
-- the two agree on everything a measurement decides and differ on the one
-- thing no measurement reaches. `colour_spec.lua` reads them against each
-- other, which is what catches either literal drifting.
--
-- Two literals rather than one shared constant, and the direction is the
-- reason. Column names are constrained by Yazi theme fields; band names are
-- this parser's namespace. Keep the two policies separate; colour_spec.lua
-- checks their shared spellings and their deliberately different length caps.
--
-- This used to start `^[a-z]`, and the defence of that was measured and did
-- not hold. "A name that can be written bare as a Lua key" is not what the
-- pattern described: on 5.5.1 `end` passed it and `{ end = ... }` is a syntax
-- error -- `as_key` below exists to write that one back as `["end"]` -- while
-- `_x` is a legal bare key and was refused. `column.lua`'s own comment had
-- already written down that a leading letter would be inventing a restriction
-- the platform does not have, so the plugin was arguing with itself across two
-- files, and the half with a measurement behind it won.
local NAME = "^[a-z0-9_]+$"

-- And the two a band writes inside itself, which are therefore not names a
-- band can have. `to` is the one that would otherwise read as a band called
-- `to`; `from` is here so the pair is refused together.
local RESERVED = { from = true, to = true }

-- Lua's own keywords, which are names a band may have and keys a message may
-- not spell bare. `NAME` takes `end`, and `band = { ["end"] = ... }` defines
-- it, so refusing the name would take away a band that works; what cannot be
-- done is write it back as `band = { end = ... }`, which is a syntax error
-- rather than a setting. Lowercase only, because `NAME` is.
local KEYWORD = {}
for word in
	(
		"and break do else elseif end false for function goto if in local "
		.. "nil not or repeat return then true until while"
	):gmatch("%a+")
do
	KEYWORD[word] = true
end

-- What Lua takes as a bare key, which is narrower than `NAME` at one end as
-- well as at the other. A band name may start with a digit -- `NAME` allows
-- it, and rightly, since nothing parses a band name -- but `band = { 2x = ... }`
-- is a syntax error, so a refusal spelling it that way hands the reader
-- something that will not load. Exactly the fault a keyword has, arriving by
-- the other road, and `as_key` answers both the same way.
local BARE = "^[a-z_][a-z0-9_]*$"

--- `name` as a key in Lua source, for a message the reader is to paste.
---@param name string
---@return string
local function as_key(name)
	if KEYWORD[name] or not name:find(BARE) then
		return string.format("[%q]", name)
	end
	return name
end

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
--- Here because three allow-lists want it and a fourth would have written a
--- fourth copy. Each of them builds the list rather than spelling the sentence
--- out, so a key added to one cannot be missing from the message that lists
--- them; what that costs without this is the same `table.concat` expression,
--- with the same off-by-one in the range, in as many files as have keys.
---
--- `conj` is that fourth copy arriving: a list of the *values* a key takes
--- reads "`a`, `b` or `c`" where a list of keys reads "and", and that word is
--- the whole of the difference. No comma before it either way -- these
--- documents do not write one, and a list that punctuated itself differently
--- depending on the conjunction would be two styles rather than one helper.
local KEY_LIST = diagnostics.key_list(ATTRS)

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

	local rgb = colour.rgb(value)
	if rgb then
		return rgb
	elseif not accepted(value) then
		refuse(value, where)
	end
	return nil
end

--- `names` sorted and backquoted, ready to drop into a message, or nil when
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

--- What `M.layer` calls for every colour it finds, so that what a gradient
--- means belongs to the caller rather than to this function.
---
--- Two callers and two answers. A column has a value to place on a ramp, so
--- its painter resolves one against the bands `setup` defined. A separator has
--- none, so `M.flat`'s painter refuses a ramp at the point it is read, and the
--- refusal is the same one whichever spelling reached it.
---@alias supaline.Painter fun(value: any, where: string, fallback: string): supaline.Paint

--- The painter a column's style is read with.
---
--- One per build rather than one per layer: `column` reads three writers
--- with the same bands behind all three, and `layer_of` promises a paragraph
--- of its own that it runs once per column per build and never per row.
---
--- Written out here rather than behind a named function, the way `M.flat`
--- writes its own: a gradient is told by the arrow, which is the one thing a
--- flat colour can never contain, and it is resolved while the layer is read
--- so that every refusal a style can earn is earned there. Everything else
--- goes through `M.colour`, which refuses what is not a string -- a table
--- under `fg` included, and no more is said about one -- and what Yazi's
--- parser would not take.
---@param bands supaline.Bands every band `setup` defined
---@return supaline.Painter
function M.painter(bands)
	return function(value, where, fallback)
		if M.is_ramp(value) then
			return M.stops(value, where, bands, fallback)
		end
		M.colour(value, where)
		return value
	end
end

--- Snapshot framework-owned style fields without evaluating a style callback
--- or constructing a Yazi Style. Userdata are immutable opaque values. A table
--- implementing Style's methods is its harness stand-in (or a user wrapper).
--- Callable tables stay intact so layer() can refuse the constructor by name.
---@param value any
---@return any
function M.snapshot(value)
	if type(value) ~= "table" then
		return value
	end
	local mt = getmetatable(value)
	if
		(type(value.patch) == "function" and type(value.raw) == "function") or (type(mt) == "table" and mt.__call ~= nil)
	then
		return value
	end
	local copy = {}
	for key, v in pairs(value) do
		copy[key] = v
	end
	-- layer() refuses an empty table even if __index supplies style keys.
	-- For a nonempty table, capture the values it would read through __index
	-- as well as the written keys; the plan must not retain that metatable.
	if next(value) ~= nil then
		for _, key in ipairs(COLOURS) do
			copy[key] = value[key]
		end
		for _, key in ipairs(ATTRS) do
			copy[key] = value[key]
		end
	end
	return copy
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
--- A `<->` under `fg` asks for the band called `fg`, and one under `bg` for the
--- band called `bg`. The key is the name, which is what makes the common case
--- silent: a string that wants some other band says so after the marker, and
--- one that does not is asking for the band named after where it was written.
---
--- A bare string is the `fg` key spelled short, here as everywhere else, so it
--- asks for `fg` too.
---@param value any nil, `false`, a colour string, a style table, or a ui.Style
---@param where string
---@param painter supaline.Painter what a colour, and a gradient, mean to the caller
---@return supaline.Layer|false
function M.layer(value, where, painter)
	local t
	if value == nil then
		return {}
	elseif value == false then
		return false
	elseif type(value) == "string" then
		return { fg = painter(value, where, "fg") }
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

	local unknown, _, subject, hints = diagnostics.unknown(t, claims_style, "style", MEANT)
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
			layer[k] = painter(v, string.format("%s: `%s`", where, k), k)
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
---@class supaline.StyleLayer
---@field values supaline.Layer|false
---@field source supaline.StyleWriter

---@param layers supaline.StyleLayer[]
---@return supaline.Layer resolved
---@return table<string, supaline.StyleWriter> from the writer of each key
function M.merge(layers)
	local out, from = {}, {}
	for _, record in ipairs(layers) do
		local layer, source = record.values, record.source
		if layer == false then
			out, from = { fg = false, bg = false }, { fg = source, bg = source }
		else
			for _, k in ipairs(KEYS) do
				local v = layer[k]
				if v ~= nil then
					out[k], from[k] = v, source
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
			ramps[k] = colour.ramp(v)
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
	-- Never `false` and never nil: a separator's `style = false` is refused by
	-- name in this module, and one with no style returns there before this is
	-- called. So what arrives is a value `M.layer` reads into a layer, and the
	-- cast says so where a fallback would stand in for a value that cannot come.
	--
	-- The painter refuses rather than resolves, which is the whole of why this
	-- is a painter at all. Read against the bands `setup` defined, the two
	-- spellings of a gradient failed for two different reasons and only one of
	-- them was this one: `#0b3d91 <-> nosuch` reached the undefined-band
	-- refusal, while `cyan <->` reached the endpoint parser and came back with
	-- `cyan` is not a colour Yazi accepts, write a name such as `cyan` -- advice
	-- that refuses what it tells the reader to write, and that would still fail
	-- if followed, because what is wrong is not the colour. Which of the two
	-- fired was whichever of `M.stops`'s refusals came first, so it was
	-- arbitrary from the reader's side.
	local layer = M.layer(value, where, function(v, w)
		if M.is_ramp(v) then
			error(
				string.format(
					"supaline: %s: `%s` is a gradient, and there is no value here to place on one. "
						.. "A separator is drawn between two columns rather than on a file; write a "
						.. "flat colour",
					w,
					v
				)
			)
		end
		M.colour(v, w)
		return v
	end) --[[@as supaline.Layer]]
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

--- One band, checked.
---
--- Checked here rather than in `main.lua` because the pair means something
--- only to this file, and because `test/ramp.lua` takes one on the command
--- line and wants the refusals a user's `init.lua` gets.
---
--- Nil is refused along with everything else that is not a table. Nothing
--- falls back to the pair above, so nil arriving here is a caller that read a
--- name nobody defined and did not check, rather than a user who said
--- nothing.
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
---@param value any
---@param where string
---@return supaline.Band
function M.bounds(value, where)
	if type(value) ~= "table" then
		error(
			string.format(
				"supaline: %s must be a table of two lightnesses, as `%s` -- `from` is what "
					.. "ratio 0 draws and `to` what ratio 1 draws, so a light terminal writes "
					.. "the larger one first",
				where,
				RECOMMENDED_AS_WRITTEN
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

--- Every band `setup` was given, by name.
---
--- A namespace rather than a fixed set, which costs this option the sweep
--- every other table a user writes gets: `claims_setup` refuses a key `setup`
--- does not take, `claims_style` one a style does not, and there is no
--- equivalent here because every name is a name somebody may have meant. A
--- band called `bgg` is a band called `bgg`.
---
--- What stands in for it is at the use site. A `<->` naming a band nobody
--- defined is refused, and that refusal lists what *is* defined -- so the
--- misspelling is read off the message, one step later than a sweep would have
--- caught it and in the same session.
---
--- No name is built in and none is filled in. `fg` and `bg` are ordinary names
--- that `M.layer` happens to look up, because they are what the two keys are
--- called; a `setup` that defines neither is a `setup` where every `<->` is
--- refused, which is the whole of what "no default" means here.
---@param value any what `setup` was given under `band`, if anything
---@param where string
---@return supaline.Bands
function M.bands(value, where)
	if value == nil then
		return {}
	elseif type(value) ~= "table" then
		error(
			string.format(
				"supaline: %s must be a table of bands by name, as "
					.. "`{ fg = %s }`, and a name is then what a `<->` asks for",
				where,
				RECOMMENDED_AS_WRITTEN
			)
		)
	end

	-- The pair itself, written where a table of them goes. Told apart by what
	-- the key holds rather than by the key, so a band genuinely named `to`
	-- reaches the name check below and is refused there for being a reserved
	-- word, rather than being reported as this. Anything that is not a table is
	-- this rather than that: `{ from = "0.35" }` is the same mistake as
	-- `{ from = 0.35 }` and wants the same answer, where the number test sent
	-- it to the reserved-word message and told it to rename a band it never
	-- named.
	if (value.from ~= nil and type(value.from) ~= "table") or (value.to ~= nil and type(value.to) ~= "table") then
		error(
			string.format(
				"supaline: %s: `from` and `to` are a band's own keys, and `band` holds bands "
					.. "by name. Write `band = { fg = %s }`, and name a second band to reach it "
					.. "from a `<->`",
				where,
				RECOMMENDED_AS_WRITTEN
			)
		)
	end

	local out = {}
	for name, one in pairs(value) do
		if type(name) ~= "string" or not name:find(NAME) then
			error(
				string.format(
					"supaline: %s: `%s` is not a band name. A name holds lowercase letters, " .. "digits and `_`",
					where,
					tostring(name)
				)
			)
		elseif RESERVED[name] then
			error(
				string.format(
					"supaline: %s: `%s` is one of a band's own two keys and cannot also be a "
						.. "band's name. Call the band something else",
					where,
					name
				)
			)
		end
		out[name] = M.bounds(one, string.format("%s: `%s`", where, name))
	end

	return out
end

--- `s` with whatever space sits around it taken off.
---
--- Named rather than written out at each of the three sites that want it. The
--- pattern is one a reader checks rather than reads -- the lazy `(.-)` between
--- two anchored `%s*` is what makes it a trim, and a greedy `(.*)` looks
--- identical at a glance and eats the trailing space instead.
---@param s string
---@return string
local function trim(s) return (s:match("^%s*(.-)%s*$")) end

--- Split a value on its `<->`: the colour before it, the band's name after.
---
--- The two halves come back apart rather than rejoined: a name after the
--- marker is a second thing rather than more of the colour before it. That is
--- also what refuses `#a <-> #b` -- `#b` is not a band name -- which reports
--- the mistake where it is made.
---
--- Nil rather than the string back when there is no marker, because the colour
--- before a marker that is not there is not a colour this function found -- it
--- is the whole value, which the caller already has. Which makes the first
--- return the answer to "was it marked" as well, and `#ff8800 <->` marked with
--- an empty body still answers yes.
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

--- The bands there are, for a refusal to list.
---@param bands supaline.Bands
---@return string
local function defined_in(bands)
	local names = {}
	for name in pairs(bands) do
		names[#names + 1] = name
	end
	table.sort(names)
	local quoted = #names > 0 and diagnostics.quoted(names) or nil
	return quoted and "Defined: " .. quoted or "No band is defined yet"
end

---@param s string
---@return string[]
local function split(s)
	local out, pos = {}, 1
	while true do
		local a, b = s:find(ARROW, pos, true)
		-- `sub(pos, nil)` is `sub(pos)`, so the last piece falls out of the same
		-- line as the ones before it and there is one trim rather than two.
		out[#out + 1] = trim(s:sub(pos, a and a - 1))
		if not b then
			return out
		end
		pos = b + 1
	end
end

--- One end of a ramp, or a refusal saying why it is not one.
---
--- Both paths below want this and they want it a different number of times --
--- a band reads one colour, a written gradient reads however many were
--- written -- so it is here rather than in a loop the band path has to enter
--- in order to leave.
---@param one string
---@param where string
---@param i integer which stop, for the message
---@return integer[]
local function endpoint(one, where, i)
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
	return rgb
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
---@param bands supaline.Bands every band `setup` defined
---@param fallback string the band a `<->` that names none is asking for
---@return integer[][]
function M.stops(value, where, bands, fallback)
	if type(value) ~= "string" then
		error(string.format("supaline: %s must be a string like `#0b3d91 -> #7fd4ff`, got a %s", where, type(value)))
	end
	local body, name = unmark(value)
	if body then
		if body == "" or body:find("%s") then
			error(
				string.format(
					"supaline: %s: `%s` is not a band. `<->` spreads one colour both ways, "
						.. "as `#ff8800 <->`; to choose the ends yourself, write them with `->`",
					where,
					value
				)
			)
		elseif name and not name:find(NAME) then
			error(
				string.format(
					"supaline: %s: `%s` is not a band name. What follows `<->` names a band "
						.. "`setup` defined, in lowercase letters, digits and `_`; to choose "
						.. "the two ends of a ramp yourself, write them with `->`",
					where,
					name
				)
			)
		elseif name and RESERVED[name] then
			-- Caught here as well as in `M.bands`, rather than left to the
			-- undefined-band refusal below. That one answers a name nobody has
			-- defined *yet* by saying how to define it, and this is a name
			-- nobody can define: what it would have said to write is
			-- `band = { from = { from = ... } }`, which `M.bands` refuses.
			error(
				string.format(
					"supaline: %s: `%s` is one of a band's own two keys, so there is no band "
						.. "by that name to ask for -- `setup` refuses one that tries. Call the "
						.. "band something else and name it that",
					where,
					name
				)
			)
		end

		-- The key this was written under when the string named nothing, which
		-- is the whole of how `bg = "#x <->"` reaches a band of its own: the
		-- name is read off the writing, and a string that wants another one
		-- says so.
		local wanted = name or fallback
		local band = bands[wanted]
		if not band then
			error(
				string.format(
					"supaline: %s: `%s` is a band and nothing defines `%s`. Both ends of a band "
						.. "are lightnesses the ground it is drawn on decides, and supaline "
						.. "cannot see that ground -- so there is no pair to fall back to. Put "
						.. "`band = { %s = %s }` in `setup` and move it to suit your terminal; "
						.. "`lua test/ramp.lua` draws a pair before you keep it. %s",
					where,
					value,
					wanted,
					as_key(wanted),
					RECOMMENDED_AS_WRITTEN,
					defined_in(bands)
				)
			)
		end

		-- Forward, through the table: the band is Oklab arithmetic and the
		-- locals it runs on are declared below, where the rest of that
		-- arithmetic lives. Reachable by the time anything calls this.
		--
		-- The colour is read last, after the band it is to be spread into has
		-- resolved, so a `<->` naming nothing is told that before it is told
		-- anything about its colour.
		return colour.band(endpoint(body, where, 1), band)
	end

	local stops = {}
	for i, one in ipairs(split(value)) do
		stops[i] = endpoint(one, where, i)
	end

	if #stops < 2 then
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

-- A separator accepts only its text and an optional flat style.
local SEP_KEYS = { [1] = true, style = true }

local function claims_sep(key) return SEP_KEYS[key] end

local SEP_HELP = "supaline: %s must be a string or a table, got a %s -- "
	.. '`" | "` draws that between two columns, `{ " | ", style = ... }` draws it in a '
	.. 'colour, and `""` draws nothing at all. `false` drops the separator before a '
	.. "column and is a column's `separator`, never a linemode's"

local SEP_UNKNOWN = "supaline: %s: %s. A separator table takes what to draw as `[1]` "
	.. 'and `style` beside it -- `{ " | ", style = { fg = "#585b70" } }`'

local SEP_TEXT = "supaline: %s was given %s to draw. The first element of a separator table "
	.. 'is the text, as `{ " | ", style = ... }`; a table with no text in it reaches Yazi as '
	.. "a span of nothing and the linemode stops drawing"

local SEP_EMPTY = 'supaline: %s draws "" in a colour, which draws nothing: a span of no '
	.. 'cells shows no style. Write `""` on its own to put nothing between two columns, or '
	.. "give the separator something to draw"

local SEP_FALSE = "supaline: %s has `style = false`, and there is nothing there to turn off. "
	.. "A column's `style = false` drops what its theme or its definition would otherwise "
	.. "supply; a separator has neither behind it, so leaving `style` out is how one goes "
	.. "uncoloured"

--- Call a function a spec wrote where a value would go, and name it if it
--- raises.
---
--- Two keys take one, for one reason: a column's `style` and a separator's
--- own. A spec is re-read on every build and never evaluated again, so a
--- value freezes whatever the theme held while `init.lua` ran; a function is
--- called inside `build`, where the flavor has landed, and again on every
--- `app:theme` after it.
---
--- The `pcall` is the half both need. The likely failure is the call itself:
--- `th.status.perm_read` against a flavor with no `[status]` section raises
--- `attempt to index a nil value`, and that reaches the user as `build`'s
--- notification -- where a message carrying no name says nothing about which
--- line to open. So `what` is the caller's to supply, and the two spell it
--- differently: a column's names the file it was written in, a separator's
--- names the separator.
---@param fn function
---@param what string what to call the function in a message
---@return any
local function called(fn, what)
	local ok, got = pcall(fn)
	if not ok then
		error(string.format("supaline: %s raised: %s", what, tostring(got)))
	end
	return got
end

--- Read a separator, in whichever of the two shapes it was written. Every
--- place that takes one comes through here: `separator` in `setup`,
--- `separator` on a linemode, and a column's own. Unrefused, `separator = 42`
--- reaches Yazi and empties the pane.
---
--- Nil is what "nothing was written" looks like and is handed back as it is,
--- for the caller to fall back from.
---
--- `false` is the value worth a check of its own, and it arrives here as the
--- wrong type rather than as a shape. It reads like a column's
--- `separator = false` and it is falsy, so unrefused on a linemode it falls
--- through to the separator it was written to be rid of and the linemode
--- draws the very thing it asked to drop -- in silence, because a separator
--- is not read until a row is, so a wrong one is a render-time failure with
--- the cause a whole session behind it. `column` takes a column's `false`
--- before this is reached, which is why only the meaningless one gets here.
---@param value any
---@param where string names where it was written, for the message
---@return supaline.Sep?
function M.separator(value, where)
	if value == nil then
		return nil
	elseif type(value) == "string" then
		return { text = value }
	elseif type(value) ~= "table" then
		error(string.format(SEP_HELP, where, type(value)))
	end

	-- Through the `noun`, like every other sweep here. Spelled out, this was the
	-- one caller of the five still wording its own "is not a ... key", which is
	-- exactly the half of a message `diagnostics.unknown` was given a `noun` to hold
	-- -- and the half it records having watched drift apart once already.
	local unknown, _, subject = diagnostics.unknown(value, claims_sep, "separator")
	if unknown then
		error(string.format(SEP_UNKNOWN, where, subject))
	end

	local text = value[1]
	if type(text) ~= "string" then
		error(string.format(SEP_TEXT, where, text == nil and "nothing" or "a " .. type(text)))
	end

	local style = value.style
	if type(style) == "function" then
		-- The same repair a column's `style` gets, through the same helper: a
		-- separator written in a theme's colour has to follow that theme.
		style = called(style, string.format("the style function under %s", where))
	end

	if style == false then
		error(string.format(SEP_FALSE, where))
	elseif style == nil then
		-- The table form with the colour left out. It says exactly what the
		-- bare string says and is allowed to: every other optional key on every
		-- other spec may be omitted, and refusing the omission here would make
		-- this the one place that cannot be. What it must not do is mean
		-- something else -- take the style from the level above -- because two
		-- spellings that differ only in what they inherit is the four-way
		-- inheritance this shape was chosen to avoid, moved inside it.
		return { text = text }
	end

	if text == "" then
		error(string.format(SEP_EMPTY, where))
	end
	return { text = text, style = M.flat(style, string.format("the style under %s", where)) }
end

---@alias supaline.StyleWriter "definition"|"inline"|"theme"|"spec"

--- What to call each writer's style in an error, in terms of the file it was
--- written in. A theme has no `style` key to name, so a message that spoke of
--- one would be describing a spec the reader never wrote.
---
--- Four rows for three layers, because the layer a definition writes is
--- written by two different-looking things. `register` states a default every
--- use of that column starts from, and saying so points the reader at the call
--- that declared it. A column written inline in a linemode has no default to
--- be: its style is written once, in the list the reader is already looking
--- at, which is where a spec's is written -- so it gets the spec's words while
--- occupying the definition's layer. Keyed rather than decided by a condition,
--- for the reason `NO_STATS` gives below.
local WHERE = {
	spec = "the `style` of column `%s`",
	theme = "the `[supaline] %s` field in your theme",
	definition = "the default `style` of column `%s`",
	inline = "the `style` of column `%s`",
}

--- And what to call one written as a function, since a message naming
--- `style` would send the reader to a line that is not the one to change. No
--- theme row, and nothing stands in for the missing one: a theme field holds a
--- string or a style table and never a function, so a theme's layer never asks
--- this table for a name.
local FN_WHERE = {
	spec = "the `style` function of column `%s`",
	definition = "the default `style` function of column `%s`",
	inline = "the `style` function of column `%s`",
}

--- What to do about a gradient on a column with no extremes, per writer.
--- `stats` is a definition's to give and a flat colour a spec's to write, so
--- those two get the same advice; a `theme.toml` has neither, and the only
--- move left there is the flat colour. Keyed the way `WHERE` and `FN_WHERE`
--- are, so a fourth writer is a row in three tables rather than a row in two
--- and a condition to find.
local NO_STATS = {
	spec = "Give the column a `stats` function, or write a flat colour there instead",
	definition = "Give the column a `stats` function, or write a flat colour there instead",
	inline = "Give the column a `stats` function, or write a flat colour there instead",
	theme = "Write a flat colour there instead",
}

---@param value any
---@param source supaline.StyleWriter
---@param name string?
---@param painter supaline.Painter
---@return supaline.Layer|false
local function layer_of(value, source, name, painter)
	local where = string.format(WHERE[source], name or "?")
	if type(value) == "function" then
		-- Named for the file it was written in rather than for `style`, because
		-- a definition's function is not on a line the reader has.
		local fn = string.format(FN_WHERE[source], name or "?")
		value, where = called(value, fn), "what " .. fn .. " returned"
	end
	return M.layer(value, where, painter)
end

---@class supaline.Sep
---@field text string
---@field style unknown?

---@class supaline.ColumnAppearance
---@field style unknown
---@field steps unknown[]?
---@field fg_written boolean
---@field sep supaline.Sep|false|nil

---@class supaline.Appearance
---@field columns table<supaline.ColumnPlan, supaline.ColumnAppearance>
---@field separators table<supaline.ModePlan, supaline.Sep>

--- Resolve one column without altering its plan. A source travels with its
--- values, so a refusal never has to index a parallel list of writer names.
---@param col supaline.ColumnPlan
---@param bands supaline.Bands
---@param theme table
---@return supaline.ColumnAppearance
function M.column(col, bands, theme)
	local sep ---@type supaline.Sep|false|nil
	if col.separator == false then
		sep = false
	else
		sep = M.separator(col.separator, string.format("`separator` of column `%s`", col.name or "?"))
	end
	local layers = {}
	local painter = M.painter(bands)
	for i, recipe in ipairs(col.styles) do
		local value = recipe.value
		if recipe.source == "theme" then
			value = nil
			if col.name then
				value = theme[col.name]
			end
			if value == "" then
				value = nil
			end
		end
		layers[i] = {
			values = layer_of(value, recipe.source, col.name, painter),
			source = recipe.source,
		}
	end
	local resolved, from = M.merge(layers)
	local gradient = col.stats == nil and M.gradient_in(resolved)
	if gradient then
		local source = from[gradient]
		error(
			string.format(
				"supaline: %s: `%s` is a gradient, but that column has no `stats`, so there are "
					.. "no extremes to place a value between and the ramp could only ever draw "
					.. "its low end. %s",
				string.format(WHERE[source], col.name or "?"),
				gradient,
				NO_STATS[source]
			)
		)
	end
	local ground, steps = M.build(resolved)
	return { style = steps and steps[1] or ground, steps = steps, fg_written = from.fg ~= nil, sep = sep }
end

--- Resolve every recipe before a candidate may replace the running appearance.
--- One shared column list has one recipe per column, even across three panes.
---@param plan supaline.Plan
---@param theme table
---@return supaline.Appearance
function M.resolve(plan, theme)
	local appearance = { columns = {}, separators = {} }
	local wide = M.separator(plan.cfg.separator, "`separator` in `setup`")
	for _, col in ipairs(plan.columns) do
		appearance.columns[col] = M.column(col, plan.cfg.band, theme)
	end
	for _, mode in pairs(plan.modes) do
		appearance.separators[mode] = M.separator(mode.separator, string.format("`separator` on linemode `%s`", mode.name))
			or wide
	end
	return appearance
end

return M
