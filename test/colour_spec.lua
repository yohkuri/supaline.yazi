--- `colour.lua`: what a colour value may be, and the ramp built from one.
---
--- The stub's `ui.Style():fg` refuses what a real 26.9.1 refuses, from a
--- measured table, which is what lets the "not a colour" path be tested at all
--- -- the plugin asks Yazi's parser rather than carrying a list of its own.

local colour = require(".colour")

-- One test reads both name rules against each other, which is the only way to
-- see that they have come apart. Nothing else in this file reaches into
-- `column.lua`.
local column = require(".column")

--- A stop as the colour it is, so a mismatch reads as two colours rather than
--- as two channel numbers. Injective over the integers 0-255, so comparing two
--- of these is exactly comparing the channels.
---@param stop integer[]
---@return string
local function hex(stop) return string.format("#%02x%02x%02x", stop[1], stop[2], stop[3]) end

--- Both ends of two bands, against each other.
---@param a integer[][]
---@param b integer[][]
---@param why string?
local function same_band(a, b, why)
	for i = 1, 2 do
		eq(hex(a[i]), hex(b[i]), why)
	end
end

-- --- one colour ------------------------------------------------------------

test("colour: a hex triple comes back with its channels", function()
	-- Asserted rather than indexed straight: a hex triple that came back with
	-- no channels is the failure this test exists for, and "attempt to index a
	-- nil value" would name the harness for it.
	local rgb = assert(colour.colour("#0b3d91", "x"), "a hex colour has channels")
	eq(rgb[1], 0x0b)
	eq(rgb[2], 0x3d)
	eq(rgb[3], 0x91)

	local upper = assert(colour.colour("#FF8800", "x"))
	eq(upper[1], 255, "case is Yazi's business, not a second spelling")
end)

test("colour: a name and an index are colours with no channels to give", function()
	eq(colour.colour("cyan", "x"), nil, "what `cyan` is on screen is the terminal's palette, not ours")
	eq(colour.colour("129", "x"), nil)
	eq(colour.colour("reset", "x"), nil)
end)

test("colour: what Yazi's parser refuses is refused here, and named in the error", function()
	throws(function() colour.colour("#f80", "the colour of column `size`") end, "`#f80`")
	throws(function() colour.colour("#f80", "the colour of column `size`") end, "column `size`")
	throws(function() colour.colour("nosuchcolour", "x") end, "not a colour Yazi accepts")
	throws(function() colour.colour("256", "x") end, "not a colour Yazi accepts")
end)

test("colour: a value that is not a string is refused", function()
	throws(function() colour.colour(42, "x") end, "must be a colour string")
	-- `fg(nil)` and `fg(true)` return nil on a real Yazi instead of raising, so
	-- neither may reach it: the caller would be told the colour was fine.
	throws(function() colour.colour(nil, "x") end, "got a nil")
	throws(function() colour.colour(true, "x") end, "got a boolean")
end)

--- The nine attributes, each under the `ui.Style` method that drives it.
---
--- The names are written out in three places -- `colour.lua`'s allow-list, the
--- stub's methods, and here -- because neither of the other two can read the
--- other: the stub stands in for Yazi and must not require the plugin. This
--- table is what holds the three together, read on the way in by the `layer`
--- test and on the way out by the `build` one, so the pair is one list rather
--- than two that can drift.
local ATTRS = {
	bold = "bold",
	dim = "dim",
	italic = "italic",
	underline = "underline",
	blink = "blink",
	blink_rapid = "blink_rapid",
	reversed = "reverse",
	hidden = "hidden",
	crossed = "crossed",
}

--- The pair `colour.recommended` hands a reader to paste, which is what every
--- band measured below was measured at.
---
--- Written out rather than taken from that function. These numbers are the
--- ones the comments in `colour.lua` justify and the README quotes, so a spec
--- that moved the recommendation should fail these tests rather than move them
--- along with it.
---@type supaline.Band
local REC = { from = 0.35, to = 0.88 }

--- Every band a `<->` in these tests can ask for, under both keys.
---@type supaline.Bands
local BANDS = { fg = REC, bg = REC }

--- `#0b3d91` as `colour.band` takes it, for the tests that hand the same
--- colour to the plugin as a string and to the arithmetic as channels.
---@type integer[]
local NAVY = { 0x0b, 0x3d, 0x91 }

--- `colour.stops`, with a band behind the name a value asks for.
---
--- Most of what is below is about the arithmetic rather than about which band
--- was asked for, and reads better for not saying so on every line. The tests
--- that *are* about the name call `colour.stops` directly.
---@param value any
---@param band supaline.Band? the recommended pair when omitted
---@return integer[][]
local function stops(value, band) return colour.stops(value, "x", { fg = band or REC }, "fg") end

-- --- one writer's layer ----------------------------------------------------

--- A layer read from `value`, for the tests that go on to read a key off it.
--- Never `false` here: that is the one input `colour.layer` answers with
--- itself, and the test that plants it asserts on the value directly.
---
--- The bands are an argument because the tests about *which* band a key
--- reaches have to vary them; everything else wants the one pair `BANDS`
--- holds and says so by leaving it out. They reach `colour.layer` as the
--- painter built from them, which is what a column's style is read with --
--- `colour.flat` is the other painter and has a block of its own.
---@param value any
---@param bands supaline.Bands? `BANDS` when omitted
---@return supaline.Layer
local function layer(value, bands)
	local got = colour.layer(value, "x", colour.painter(bands or BANDS))
	if not got then
		error("a layer rather than `false`")
	end
	return got
end

test("layer: nothing written is an empty layer, and `false` is the layer itself", function()
	eq(next(layer(nil)), nil)

	-- Not a layer of eleven `false`s. An attribute's `false` is the attribute
	-- taken off -- the row's own bold along with a theme's -- where what
	-- `style = false` asks for is a cell drawn in whatever the row already
	-- carries. `merge` is what reads it, so it is handed on as it is.
	eq(colour.layer(false, "x", colour.painter(BANDS)), false)
end)

test("layer: a string is the `fg`, flat or a gradient", function()
	eq(layer("#0b3d91").fg, "#0b3d91")
	eq(layer("cyan").fg, "cyan", "a name is Yazi's to resolve, not ours")

	-- A gradient is kept as its stops, parsed on the way in so that a bad
	-- endpoint is refused while the layer is read rather than while it draws.
	local ramp = layer("#0b3d91 -> #7fd4ff").fg
	eq(type(ramp), "table")
	eq(#ramp, 2)
	eq(#layer("#7fd4ff <->").fg, 2, "a band derives both of its ends")

	throws(function() layer("#gg0000") end, "is not a colour Yazi accepts")
	throws(function() layer("cyan -> #7fd4ff") end, "cannot be a gradient endpoint")
end)

test("layer: a table is the theme's spelling, read key by key", function()
	-- The same keys `theme.toml` takes, so one style is written one way in both
	-- files. Read rather than built: a layer has to know which keys were
	-- written, because a key nobody wrote is what leaves the one beneath
	-- showing.
	local got = layer { fg = "#ff8800", bg = "#7a2d00", bold = true, reversed = true }
	eq(got.fg, "#ff8800")
	eq(got.bg, "#7a2d00")
	eq(got.bold, true)
	eq(got.reversed, true, "`reversed`, the theme's key; `reverse()` is the method's business")
	eq(got.italic, nil, "a key nobody wrote is not in the layer")

	-- `bold = false` is the attribute taken off rather than an error or an
	-- attribute never written, which is what the same line means in a theme: a
	-- field holds three states, and `false` is the one that strips a `bold` off
	-- the row beneath.
	eq(layer({ fg = "cyan", bold = false }).bold, false)
	eq(layer({ fg = "cyan" }).bold, nil, "nothing said is not the same as off")

	-- And a colour may be off, a gradient, or a band, under either key.
	eq(layer({ fg = false }).fg, false)
	eq(layer({ bg = false }).bg, false)
	eq(type(layer({ bg = "#0b3d91 -> #7fd4ff" }).bg), "table")
	eq(type(layer({ bg = "#0b3d91 <->" }).bg), "table")
end)

test("layer: every attribute a theme can write is read under its own name", function()
	-- The way in. `build` below is the way out, off the same table.
	for key in pairs(ATTRS) do
		eq(layer({ [key] = true })[key], true, key)
		eq(layer({ [key] = false })[key], false, key .. " = false")
	end
end)

test("layer: a `ui.Style` is read through `raw()`, so its keys are the same keys", function()
	-- A themed table field arrives as the `Style` Yazi parsed, and a spec may
	-- write one too. Both come through `raw()` in Yazi's own spelling of the
	-- colours, which `fg()` takes back -- the `raw` spec above pins that -- so
	-- the layer holds strings a style can be built from.
	local got = layer(ui.Style():fg("#ff8800"):bg("cyan"):bold():reverse())
	eq(got.fg, "#FF8800")
	eq(got.bg, "Cyan")
	eq(got.bold, true)
	eq(got.reversed, true, "the theme's key, which is the layer's")
	-- Suppressed on the line: `types.yazi` declares `bold` without the removal
	-- flag 26.9.1's takes, and the flag is what this line is about.
	---@diagnostic disable-next-line: redundant-parameter
	eq(layer(ui.Style():bold(true)).bold, false, "a removal, the shape a theme's `bold = false` arrives in")

	-- Nothing at all is a layer saying nothing, and is not refused: it is
	-- what a `[supaline]` field holding an empty table arrives as, and there
	-- is nothing wrong with it.
	eq(next(layer(ui.Style())), nil)
end)

test("layer: a key Yazi would have dropped is refused by name", function()
	-- The whole of what the table form buys over the theme's. Yazi hands a
	-- plugin the `Style` it parsed and never the table behind it, so a key it
	-- does not know is gone before `th.supaline` exists -- measured on 26.9.1,
	-- `strikethrough = true` in `[supaline]` left the column with no attribute
	-- and said nothing. Written in a spec it reaches this file verbatim.
	throws(function() layer { fg = "cyan", strikethru = true } end, "`strikethru` is not a style key")

	-- Every key nobody claimed, sorted, so the same mistake reports the same
	-- way twice running.
	throws(function() layer { zebra = true, apple = true } end, "`apple`, `zebra` are not style keys")

	-- The three a reader arrives at honestly, each pointed at the spelling that
	-- works rather than merely turned away.
	throws(function() layer { reverse = true } end, "`reversed` is the spelling")
	throws(function() layer { strikethrough = true } end, "`crossed` is the spelling")
	throws(function() layer { reset = true } end, 'write `fg = "reset"`')

	-- A list of colours is a table whose keys are `1` and `2`, and that is the
	-- whole of the answer: the list spelling of a gradient is not taken, and
	-- nothing here guesses that one was meant.
	throws(function() layer { "#aabbcc", "#ff8800" } end, "`1`, `2` are not style keys")
end)

test("layer: a colour is a colour and an attribute a boolean", function()
	-- `fg` and `bg` go through the same allow-list a bare string does, so there
	-- is one answer to "is this a colour" however it was written -- and the
	-- message says which key, since a table has two of them.
	throws(function() layer { fg = "#gg0000" } end, "x: `fg`: `#gg0000` is not a colour Yazi accepts")
	throws(function() layer { bg = 42 } end, "x: `bg` must be a colour string, got a number")

	-- A table under a colour key is refused as a table and no more is said:
	-- there is no list spelling of a gradient for it to have meant.
	throws(function() layer { fg = { "#aabbcc", "#ff8800" } } end, "`fg` must be a colour string, got a table")

	-- An attribute is not a colour, and a string there is the way that mistake
	-- arrives.
	throws(function() layer { bold = "yes" } end, "must be true or false")
end)

test("layer: what is not a style at all is refused", function()
	-- `ui.Style` with the call forgotten. Measured on 26.9.1: `type(ui.Style)`
	-- is `table` and `pairs` over it finds nothing, so it would otherwise read
	-- as a layer saying nothing and leave the column in whatever was beneath.
	throws(function() layer(ui.Style) end, "is the constructor")
	throws(function() layer {} end, "no keys in it")

	-- `Span:style` takes a Style or nil and nothing else. A value that is
	-- neither survives `setup` and then empties the screen, so it is turned
	-- away here instead -- and by what it answers to rather than by what it is.
	--
	-- `getmetatable` cannot do the telling: measured on 26.9.1, mlua gives all
	-- of Yazi's userdata `__metatable = false`, so `getmetatable(ui.Span("x"))`
	-- is `false` and equal to `getmetatable(ui.Style())`. `patch` is the Style
	-- method a Span does not have, and a Span is what this asserts on for
	-- exactly that reason -- the noun in the message is the only part that
	-- differs from a real Yazi, where a Span is userdata rather than a table.
	throws(
		function() colour.layer(ui.Span("x"), "the `style` of column `size`", colour.painter(BANDS)) end,
		"column `size`"
	)
	throws(function() layer(42) end, "is a number")
	throws(function() layer(true) end, "is a boolean")

	-- A renderable is refused here and on a real Yazi, and the two arrive at it
	-- differently: theirs is userdata and falls to the message above, the
	-- harness's is a Lua table and is read as a style table whose keys are
	-- nothing of the sort. Both name `where` and neither draws. Asserted on the
	-- key it found rather than on the noun, because the noun is the harness's.
	throws(function() layer(ui.Line {}) end, "`_parts` is not a style key")
end)

-- --- the three layers, merged ----------------------------------------------

test("merge: each key goes to the nearest layer that wrote it", function()
	local resolved, from = colour.merge {
		{ fg = "red", bg = "blue", bold = true },
		{ fg = "green", italic = true },
		{ bold = false },
	}
	eq(resolved.fg, "green")
	eq(resolved.bg, "blue")
	eq(resolved.bold, false)
	eq(resolved.italic, true)
	eq(resolved.dim, nil)

	-- And which layer each came from, for the message that has to name a file
	-- and for the column that asks who wrote its `fg`.
	eq(from.fg, 2)
	eq(from.bg, 1)
	eq(from.bold, 3)
	eq(from.italic, 2)
	eq(from.dim, nil)
end)

test("merge: `false` is written, so the layer beneath does not show through", function()
	local resolved, from = colour.merge { { fg = "red", bold = true }, { fg = false } }
	eq(resolved.fg, false)
	eq(from.fg, 2)
	eq(resolved.bold, true, "and a key the nearer layer left alone is still the farther one's")

	eq(next((colour.merge { {}, {}, {} })), nil, "three layers saying nothing say nothing")
end)

test("merge: a layer that is `false` whole starts the stack over", function()
	-- Both colours off and on record as off, so the column that asks who wrote
	-- its `fg` is told; every attribute unwritten rather than taken off, so
	-- the row keeps its own.
	local resolved, from = colour.merge { { fg = "red", bg = "blue", bold = true }, false }
	eq(resolved.fg, false)
	eq(resolved.bg, false)
	eq(resolved.bold, nil)
	eq(from.fg, 2)
	eq(from.bold, nil)

	-- And a layer above it writes over that as over anything.
	local again = colour.merge { { bold = true }, false, { fg = "green" } }
	eq(again.fg, "green")
	eq(again.bg, false)
	eq(again.bold, nil)
end)

-- --- what the merged layer builds -----------------------------------------

test("build: a flat layer is one style, and `false` on a colour is no colour", function()
	local ground, steps = colour.build { fg = "#ff8800", bg = "#7a2d00", bold = true, reversed = true, dim = false }
	eq(ground.fg, "#ff8800")
	eq(ground.bg, "#7a2d00")
	eq(ground.bold, true)
	eq(ground.reverse, true, "`reversed` in the layer, `reverse()` on the style")
	-- `rawget`, because a style carrying nothing under `dim` answers `Style.dim`,
	-- the method.
	eq(rawget(ground, "dim"), false, "the removal, which the method's own argument inverts")
	eq(steps, nil, "nothing to quantise")

	local off = colour.build { fg = false, bold = true }
	eq(rawget(off, "fg"), nil)
	eq(off.bold, true)

	eq(next(colour.build {}), nil, "nothing written builds an empty style")
end)

test("build: every attribute reaches its method, added or taken off", function()
	-- The other half of the loop in the `layer` spec above: Yazi's `bold(true)`
	-- takes bold off, so a `false` in the layer has to arrive as `bold(true)`
	-- and not as a second `bold()`.
	for key, method in pairs(ATTRS) do
		eq(rawget(colour.build { [key] = true }, method), true, key)
		eq(rawget(colour.build { [key] = false }, method), false, key .. " = false")
	end
end)

test("build: a gradient under `fg` is the quantisation's worth of styles, each on the ground", function()
	local ground, steps = colour.build(layer { fg = "#0b3d91 -> #7fd4ff", bold = true, bg = "#1e1e2e" })
	steps = assert(steps, "a gradient builds steps")
	eq(#steps, 64)
	eq(steps[1].fg, "#0b3d91")
	eq(steps[64].fg, "#7fd4ff")
	-- Both ends, because the ground is what every step is set on: one end
	-- carrying the rest would mean the fold had happened somewhere that only
	-- sees one.
	eq(steps[1].bold, true)
	eq(steps[64].bold, true)
	eq(steps[1].bg, "#1e1e2e")
	eq(steps[64].bg, "#1e1e2e")
	eq(rawget(ground, "fg"), nil, "the ground carries everything but the gradient")
end)

test("build: a gradient under `bg` paints the ground, and both keys may carry one", function()
	local _, steps = colour.build(layer { bg = "#0b3d91 -> #7fd4ff", fg = "#ffffff" })
	steps = assert(steps, "a gradient builds steps")
	eq(steps[1].bg, "#0b3d91")
	eq(steps[64].bg, "#7fd4ff")
	eq(steps[32].fg, "#ffffff", "a flat colour beside it is on every step")

	-- Two gradients land on the same step at the same ratio.
	local _, both = colour.build(layer { fg = "#000000 -> #ffffff", bg = "#0b3d91 -> #7fd4ff" })
	both = assert(both, "a gradient builds steps")
	eq(both[1].fg, "#000000")
	eq(both[1].bg, "#0b3d91")
	eq(both[64].fg, "#ffffff")
	eq(both[64].bg, "#7fd4ff")
end)

-- --- one style, for a separator ---------------------------------------------

test("flat: a separator's style is one layer built on its own, and takes no gradient", function()
	eq(colour.flat("#ff8800", "x").fg, "#ff8800")
	eq(colour.flat({ bold = true }, "x").bold, true)
	eq(colour.flat(ui.Style():fg("cyan"), "x").fg, "Cyan")

	-- A separator is drawn between two columns rather than on a file, so there
	-- is no value to place on a gradient and every spelling of one is refused
	-- by the value that was written.
	--
	-- Every spelling is the point, and it is what the painter bought. Read
	-- against a band table instead, these four took two different paths and
	-- came back with two different messages: the two carrying a `#rrggbb`
	-- reached this one, and `cyan <->` reached the endpoint parser, which
	-- answered "`cyan` is not a colour Yazi accepts. Write `#rrggbb`, a name
	-- such as `cyan`" -- refusing the very spelling it told the reader to
	-- write, about a colour that is not what is wrong. Which of the two fired
	-- was whichever of `M.stops`'s refusals came first. So the assertions below
	-- are one message four times over, deliberately, and a fifth spelling that
	-- found its way to a different one would be the same bug returning.
	local SAME = "is a gradient, and there is no value here to place"
	throws(function() colour.flat("#0b3d91 -> #7fd4ff", "x") end, "`#0b3d91 -> #7fd4ff` " .. SAME)
	throws(function() colour.flat("#0b3d91 <->", "x") end, "`#0b3d91 <->` " .. SAME)
	throws(function() colour.flat("#0b3d91 <-> nosuch", "x") end, "`#0b3d91 <-> nosuch` " .. SAME)
	throws(function() colour.flat("cyan <->", "x") end, "`cyan <->` " .. SAME)

	-- Under a key it is the value that is named, not the key: the bare-string
	-- form above has no key to name, and one message reading two ways is what
	-- put the reader in front of the wrong one to begin with.
	throws(function() colour.flat({ bg = "#0b3d91 <->" }, "x") end, "x: `bg`: `#0b3d91 <->` " .. SAME)
end)

-- --- what a style answers `raw()` with ------------------------------------

--- `raw()` off a style, cast the way `colour.lua` casts: `types.yazi` marks
--- `ui.Style` `(exact)` and declares no `raw`, so `supaline.Style` is what the
--- call is checked against.
---@param style unknown
---@return table
local function raw(style)
	return (style --[[@as supaline.Style]]):raw()
end

test("raw: a style answers with its keys, in Yazi's own spelling", function()
	-- The stub's `raw()` against a run of 26.9.1 -- `probes.md`, "A colour
	-- read back out of a style". A name comes back capitalised the way
	-- ratatui's `Display` writes it, a hex uppercased, an index as it was, and
	-- each attribute under the theme's key. `colour.lua` reads every
	-- `ui.Style` it is handed through this, and a themed field arrives as one,
	-- so a stub that answered any other way would let the theme specs prove
	-- nothing about the theme.
	eq(raw(ui.Style():fg("#ff8800")).fg, "#FF8800")
	eq(raw(ui.Style():fg("cyan")).fg, "Cyan")
	eq(raw(ui.Style():fg("129")).fg, "129")
	eq(raw(ui.Style():fg("reset")).fg, "Reset")
	eq(raw(ui.Style():fg("bright-red")).fg, "LightRed")
	eq(raw(ui.Style():fg("darkgray")).fg, "DarkGray")
	eq(raw(ui.Style():fg("bright-black")).fg, "DarkGray", "folded on the way in, so `Display` never sees it")
	eq(raw(ui.Style():fg("bright-white")).fg, "White")
	eq(raw(ui.Style():bg("light-blue")).bg, "LightBlue")

	local got = raw(ui.Style():bg("#112233"):bold():reverse())
	eq(got.bg, "#112233")
	eq(got.bold, true)
	eq(got.reversed, true, "the theme's key, not the method's name")
	eq(got.reverse, nil)
	eq(got.fg, nil, "nothing for a key nobody set")

	-- Suppressed on the line: `types.yazi` declares `bold` without the removal
	-- flag 26.9.1's takes, and the flag is what this line is about.
	---@diagnostic disable-next-line: redundant-parameter
	eq(raw(ui.Style():bold(true)).bold, false, "a removal is `false`, the shape a theme's `bold = false` arrives in")
	eq(next(raw(ui.Style())), nil, "an empty style answers an empty table")

	-- And what comes back goes back in: every spelling `raw()` writes is one
	-- `fg()` takes, on a real Yazi and here.
	for _, name in ipairs { "Reset", "LightRed", "DarkGray", "Cyan", "#FF8800" } do
		eq(raw(ui.Style():fg(name)).fg, name)
	end
end)

-- --- telling a ramp from a flat colour -------------------------------------

test("is_ramp: the arrow is what a flat colour can never contain", function()
	eq(colour.is_ramp("#0b3d91 -> #7fd4ff"), true)
	eq(colour.is_ramp("#0b3d91"), false)
	eq(colour.is_ramp("cyan"), false)
	eq(colour.is_ramp(nil), false)
	-- The style a theme hands over, not a bare `{}`: on a real Yazi it is
	-- userdata and here it is a table behind a metatable, and an implementation
	-- that reached for a field on it before testing the type would pass a bare
	-- table and fail on both of those.
	eq(colour.is_ramp(ui.Style():fg("red"):bold()), false, "a style out of the theme is not a ramp")
	eq(colour.is_ramp {}, false)
	-- `<->` carries the arrow inside it, so a band answers this without the
	-- test knowing there are two spellings. That is the reason it is spelled
	-- with one.
	eq(colour.is_ramp("#0b3d91 <->"), true, "a band is a ramp")
end)

-- --- endpoints -------------------------------------------------------------

test("stops: a string splits on the arrow, whitespace and all", function()
	local stops = stops("  #0b3d91   ->#ffffff->   #7fd4ff  ")
	eq(#stops, 3)
	eq(stops[1][3], 0x91)
	eq(stops[2][1], 0xff)
	eq(stops[3][1], 0x7f)
end)

test("stops: a name cannot anchor a ramp", function()
	-- A perfectly good flat colour, refused here alone: interpolating from it
	-- means guessing what the terminal draws it as, and the ramp's own end
	-- would then not meet it.
	throws(function() stops("cyan -> #7fd4ff") end, "cannot be a gradient endpoint")
	throws(function() stops("129 -> #7fd4ff") end, "cannot be a gradient endpoint")
end)

test("stops: one colour is a band with the marker, and a refusal without it", function()
	-- Under `fg` a bare colour is a flat colour and has to go on meaning one,
	-- so the marker is the only spelling of a band -- in a spec as in a theme.
	-- Both ends come out of `band`, which the tests below pin.
	same_band(stops("#7fd4ff <->"), colour.band({ 0x7f, 0xd4, 0xff }, REC))
	throws(function() stops("#7fd4ff") end, "is one colour, and a gradient needs two ends")
	throws(function() stops("#7fd4ff") end, "`#7fd4ff <->` to spread the one colour")

	-- A gradient is one string, so a list is refused as the wrong type.
	throws(function() stops { "#0b3d91", "#7fd4ff" } end, "must be a string like")
end)

test("stops: `<->` spreads one colour and says so when handed two", function()
	throws(function() stops("#0b3d91 <-> #7fd4ff") end, "is not a band")
	throws(function() stops("<->") end, "is not a band")
	-- The marker is the only thing removed, so what is left is read as a
	-- colour like any other and gets the message a bad colour gets.
	throws(function() stops("cyan <->") end, "cannot be a gradient endpoint")
end)

-- --- a band ----------------------------------------------------------------

test("band: a colour lighter than the band is still not an end of it", function()
	-- Every value below is from this implementation, on the arithmetic in
	-- `colour.lua`; the same numbers come out of the derivation by hand.
	--
	-- `#e8f4ff` sits at 0.96 in lightness, above the band's own top, and the
	-- band still runs 0.35 to 0.88 -- so the colour that was written appears
	-- nowhere on it. Both ends are fixed, and what the colour supplies is the
	-- hue. Widening the band to reach it would make this column's top step
	-- lighter than the next column's for no reason a reader could see.
	local stops = stops("#e8f4ff <->")
	eq(hex(stops[1]), "#383b3e")
	eq(hex(stops[2]), "#ced9e3")
end)

test("band: a colour darker than the band is not an end of it either", function()
	-- The other side, and it is fixed the same way. `#0b1a2f` sits at 0.22,
	-- below the band's floor of 0.35, and the low end is drawn at the floor
	-- rather than at the colour.
	local stops = stops("#0b1a2f <->")
	eq(hex(stops[1]), "#1f3b61")
	eq(hex(stops[2]), "#bfdaff")
end)

test("band: past the exposure's reach, lightness is bought with chroma", function()
	-- The exposure alone stops where the strongest channel hits 255, and for a
	-- dark colour that is not light: `#0b3d91` reaches 0.59 and no further,
	-- against the 0.83 of the `#7fd4ff` a hand-written ramp would have had.
	-- Above it the hue is held and the chroma spent, which is the only thing
	-- that can be given up without turning the colour.
	local hi = stops("#0b3d91 <->")[2]
	eq(hex(hi), "#c2d9ff")

	-- Having a channel at 255 already is not the same as being high enough: the
	-- exposure cannot move `#7fd4ff` at all, and 0.83 is below the ceiling, so
	-- this one buys the rest with chroma too. That is the whole of what a
	-- ceiling above 0.83 changes, and it is the reason this one is 0.88.
	local sat = stops("#7fd4ff <->")[2]
	eq(hex(sat), "#a8e1ff")

	-- And never more chroma than the exposure itself would have reached, so a
	-- colour is not made more vivid on the way to being made lighter. Grey has
	-- none to spend and stays grey.
	local grey = stops("#767676 <->")[2]
	eq(grey[1], grey[2])
	eq(grey[2], grey[3])
end)

test("band: a dark colour spreads upwards, which is the point of deriving both", function()
	-- The case the whole design turns on. `#0b3d91` has almost no room below
	-- the floor -- 0.39 in lightness against 0.35 -- so a band anchored at the
	-- colour and falling to the floor would be four hundredths wide and half
	-- its steps repeats. Taking the room above it instead spreads it from the
	-- floor to the ceiling, and every step is a colour of its own.
	local r = colour.ramp(stops("#0b3d91 <->"))
	local seen, n = {}, 0
	for _, hex in ipairs(r) do
		if not seen[hex] then
			seen[hex], n = true, n + 1
		end
	end
	eq(n, #r, "every step distinct")
	eq(r[1], "#08347f")
	eq(r[#r], "#c2d9ff")
end)

test("band: black is a grey band rather than a refusal", function()
	-- Refusing black -- no lightness to scale, no hue to hold -- is an
	-- exception with nothing behind it once both ends are fixed: a grey has no
	-- hue to hold at any lightness, and the band is drawn at the two the user
	-- asked for regardless. So the three greys furthest apart in sRGB all come
	-- out as the same band, and none of the three is a special case.
	local black = stops("#000000 <->")
	local mid = stops("#767676 <->")
	local white = stops("#ffffff <->")
	same_band(black, mid, "black against a mid grey")
	same_band(black, white, "black against white")
	eq(hex(black[1]), "#3a3a3a")
	eq(hex(black[2]), "#d7d7d7")
end)

test("band: the pair is directed, so writing it backwards inverts the ramp", function()
	-- What a light terminal needs, and the reason the two numbers are `from`
	-- and `to` rather than a floor and a ceiling with a boolean beside them:
	-- ratio 0 draws `from` whichever of the two is lighter, so inversion is the
	-- same option written the other way round and there is no second spelling
	-- to keep in step with the first.
	local up = colour.ramp(stops("#0b3d91 <->", { from = 0.35, to = 0.88 }))
	local down = colour.ramp(stops("#0b3d91 <->", { from = 0.88, to = 0.35 }))
	eq(#up, #down)
	for i = 1, #up do
		eq(down[i], up[#up + 1 - i], "step " .. i .. " is the other ramp's mirror")
	end
end)

test("bounds: nil is refused along with everything else that is not a table", function()
	-- Nothing falls back to the recommended pair, so nil reaching this function
	-- is a caller that read a name nobody defined and did not check.
	throws(function() colour.bounds(nil, "x") end, "must be a table of two lightnesses")
end)

test("recommended: a fresh table, so two callers cannot write to one band", function()
	local a, b = colour.recommended(), colour.recommended()
	eq(a.from, REC.from)
	eq(a.to, REC.to)
	a.from = 0.1
	eq(b.from, REC.from, "the second copy did not move with the first")
	eq(colour.recommended().from, REC.from, "and neither did the next one")
end)

-- --- bands by name ---------------------------------------------------------

test("bands: a `setup` that named no band defines none", function()
	-- Empty rather than nil, and rather than a pair. Every `<->` is then
	-- refused, which is the whole of what "no default" means: there is no name
	-- a band can be asked for by that answers without the user having said so.
	local none = colour.bands(nil, "x")
	eq(next(none), nil)
	throws(function() colour.stops("#0b3d91 <->", "x", none, "fg") end, "nothing defines `fg`")
end)

test("bands: the refusal carries the pair to paste and says nothing is defined", function()
	-- This message is the feature's front door: it is what a reader meets the
	-- first time they write `<->`, not a corner they reach by getting something
	-- wrong. So it has to carry the two numbers, the name the key asked for,
	-- and the fact that supaline is not withholding a better answer.
	local nothing = function() colour.stops("#0b3d91 <->", "x", {}, "fg") end
	throws(nothing, "{ from = 0.35, to = 0.88 }")
	throws(nothing, "band = { fg = ")
	throws(nothing, "cannot see that ground")
	throws(nothing, "No band is defined yet")
end)

test("bands: the refusal lists what is defined, which is where a typo shows up", function()
	-- The one thing lost by making `band` a namespace: no sweep can refuse
	-- `bgg`, because every name is a name somebody may have meant. What stands
	-- in for it is this list, read at the use site one step later.
	local defined = colour.bands({ fg = REC, bgg = REC }, "x")
	throws(function() colour.stops("#0b3d91 <->", "x", defined, "bg") end, "Defined: `bgg`, `fg`")
end)

test("bands: the key a band is written under is the band it asks for", function()
	local dark = { from = 0.1, to = 0.3 }
	local one = layer({ fg = "#0b3d91 <->", bg = "#0b3d91 <->" }, colour.bands({ fg = REC, bg = dark }, "x"))
	-- A `supaline.Paint` is a flat colour or a ramp's stops, and only the
	-- second is a band. What narrows it here is the key it was read off -- a
	-- band under this key is the whole of what each of these tests is for.
	same_band(one.fg --[[@as integer[][] ]], colour.band(NAVY, REC))
	same_band(one.bg --[[@as integer[][] ]], colour.band(NAVY, dark))
end)

test("bands: a bare string is the `fg` key, so it asks for the `fg` band", function()
	local two = colour.bands({ fg = REC, bg = { from = 0.1, to = 0.3 } }, "x")
	same_band(layer("#0b3d91 <->", two).fg --[[@as integer[][] ]], colour.band(NAVY, REC))
end)

test("bands: a name after the marker wins over the key it was written under", function()
	local dim = { from = 0.2, to = 0.45 }
	local three = colour.bands({ fg = REC, dim = dim }, "x")
	same_band(layer({ fg = "#0b3d91 <-> dim" }, three).fg --[[@as integer[][] ]], colour.band(NAVY, dim))
end)

test("bands: what follows the marker is a name, and a colour there says so", function()
	-- The tail of a `<->` is a band's name, and `#7fd4ff` is not one, so two
	-- endpoints written with the band marker are refused there rather than
	-- read as a colour.
	local one = { fg = REC }
	throws(function() colour.stops("#0b3d91 <-> #7fd4ff", "x", one, "fg") end, "is not a band name")
	throws(function() colour.stops("#0b3d91 <-> #7fd4ff", "x", one, "fg") end, "write them with `->`")
	throws(function() colour.stops("#0b3d91 <-> 0.4", "x", one, "fg") end, "is not a band name")
	throws(function() colour.stops("#0b3d91 <-> My_Band", "x", one, "fg") end, "is not a band name")
end)

test("bands: a band's own two keys are not names a `<->` can ask for", function()
	-- `from` and `to` pass the name shape and `M.bands` refuses them anyway, so
	-- a `<->` naming one reaches a name that cannot be defined rather than one
	-- that merely is not. The undefined-band refusal would answer it by saying
	-- to write `band = { from = { from = ... } }`, which is the thing `setup`
	-- turns away -- so it is caught before that, in the words the refusal at
	-- `setup` uses.
	local one = { fg = REC }
	throws(function() colour.stops("#0b3d91 <-> from", "x", one, "fg") end, "one of a band's own two keys")
	throws(function() colour.stops("#0b3d91 <-> to", "x", one, "fg") end, "Call the band something else")
	throws(function() colour.stops("#0b3d91 <-> to", "x", one, "fg") end, "`to`")
end)

test("bands: a name that is a Lua keyword is quoted where the refusal says to write it", function()
	-- `end` is a name the shape takes and `band = { ["end"] = ... }` defines,
	-- so it draws. What it may not do is come back bare: `band = { end = ... }`
	-- is a syntax error, and a refusal a reader pastes has to be a setting.
	local keyworded = colour.bands({ ["end"] = REC }, "x")
	eq(next(keyworded), "end", "`setup` takes it")
	same_band(
		colour.stops("#0b3d91 <-> end", "x", keyworded, "fg"),
		colour.band(NAVY, REC),
		"a keyword is a band name like any other"
	)
	throws(function() colour.stops("#0b3d91 <-> end", "x", {}, "fg") end, 'band = { ["end"] = ')

	-- Only where it has to be. An ordinary name stays bare, because bracketing
	-- every name would make the common message read as the awkward case.
	throws(function() colour.stops("#0b3d91 <-> dim", "x", {}, "fg") end, "band = { dim = ")
end)

test("bands: a band's name is a column's rule, without the cap that is Yazi's", function()
	-- The only cross-module test here, and it is load-bearing: the two `NAME`
	-- literals cannot be shared, because `column.lua` requires `colour.lua` and
	-- the lower layer cannot reach the upper one's. Nothing but this says they
	-- have come apart.
	--
	-- The band rule used to start `^[a-z]`, so `2x` and `_x` were names a
	-- column could have and a band could not. What retired that is measurement:
	-- the defence of the leading letter was "a name writable bare as a Lua
	-- key", and `_x` is one and was refused while `end` is not one and passed.
	for _, name in ipairs { "2x", "_x", "x_", "my_band2" } do
		column.register(name, { render = function() return "x" end })
		eq(next(colour.bands({ [name] = REC }, "x")), name, name .. " names both a column and a band")
	end

	-- The one difference left, and it belongs to Yazi rather than to either
	-- rule. A column name is capped at 20 because a `[supaline]` field is;
	-- nothing parses a band name, so nothing caps it.
	local long = string.rep("b", 21)
	throws(function()
		column.register(long, { render = function() return "x" end })
	end, "cannot be a column name")
	eq(next(colour.bands({ [long] = REC }, "x")), long, "a band of 21 characters is defined")
end)

test("bands: the flat pair written where a table of bands goes is refused by name", function()
	-- What a reader writes who takes `band` for one band rather than a table of
	-- them. Refused rather than read as the `fg` band, because two spellings of
	-- one thing is what this plugin turns down everywhere else -- and the
	-- message names the replacement.
	throws(function() colour.bands({ from = 0.35, to = 0.88 }, "x") end, "are a band's own keys")
	throws(function() colour.bands({ from = 0.35, to = 0.88 }, "x") end, "band = { fg = { from = 0.35, to = 0.88 } }")
	throws(function() colour.bands({ from = 0.35 }, "x") end, "are a band's own keys")
end)

test("bands: a name is lowercase letters, digits and `_`", function()
	-- The class a column's name holds, taken because this plugin has one shape
	-- a name is written in -- not because anything parses a band name.
	eq(next(colour.bands({ my_band2 = REC }, "x")), "my_band2")
	throws(function() colour.bands({ ["my-band"] = REC }, "x") end, "is not a band name")
	throws(function() colour.bands({ MyBand = REC }, "x") end, "is not a band name")
	throws(function() colour.bands({ [1] = REC }, "x") end, "is not a band name")
end)

test("bands: a band cannot be named after one of a band's own keys", function()
	-- `to = { ... }` is a band called `to`, which the flat-pair check above
	-- lets through -- it looks at the type, so a table under `to` is not the
	-- old spelling. It is refused here instead, and for its own reason.
	throws(function() colour.bands({ to = REC }, "x") end, "cannot also be a band's name")
	throws(function() colour.bands({ from = REC }, "x") end, "cannot also be a band's name")
end)

test("bands: each band is checked, and the refusal names which one", function()
	throws(function() colour.bands({ fg = { from = 0, to = 0.88 } }, "`band` in `setup`") end, "must be above 0")
	throws(function() colour.bands({ fg = { from = 0, to = 0.88 } }, "`band` in `setup`") end, "`band` in `setup`: `fg`")
	throws(function() colour.bands({ dim = "dark" }, "x") end, "x: `dim` must be a table")
end)

test("bounds: an end outside `(0, 1]` is refused, NaN included", function()
	-- 0 is black at every hue, so a band with an end there has one no colour
	-- reaches; above 1 is off the end of the space.
	throws(function() colour.bounds({ from = 0, to = 0.88 }, "x") end, "must be above 0")
	throws(function() colour.bounds({ from = 0.35, to = 1.2 }, "x") end, "must be above 0")
	throws(function() colour.bounds({ from = -0.1, to = 0.88 }, "x") end, "must be above 0")
	-- The one the range check is written backwards for: a NaN answers false to
	-- both comparisons, so `not (v > 0 and v <= 1)` refuses it where the
	-- complement would have let it through and drawn 64 uncoloured cells.
	local nan = 0 / 0
	throws(function() colour.bounds({ from = nan, to = 0.88 }, "x") end, "must be above 0")
end)

test("bounds: a band that is not two numbers is refused", function()
	throws(function() colour.bounds({ to = 0.88 }, "x") end, "`from` must be an Oklab lightness")
	throws(function() colour.bounds({ from = 0.35 }, "x") end, "`to` must be an Oklab lightness")
	throws(function() colour.bounds({ from = "dark", to = 0.88 }, "x") end, "`from` must be an Oklab lightness")
	throws(function() colour.bounds("dark", "x") end, "must be a table of two lightnesses")
end)

test("bounds: two ends at one lightness are taken rather than refused", function()
	local band = colour.bounds({ from = 0.6, to = 0.6 }, "x")
	eq(band.from, 0.6)
	eq(band.to, 0.6)
	-- Why they are taken: sixty-four steps of one colour is what a flat colour
	-- already is, so an equality test reads like the right refusal -- and it
	-- would catch this spelling and not the one beside it, which draws the
	-- identical column. Where flat stops being flat is a judgement, and the two
	-- ends are the writer's to make, degenerate ones included.
	local flat = colour.ramp(stops("#0b3d91 <->", { from = 0.5, to = 0.5 }))
	local near = colour.ramp(stops("#0b3d91 <->", { from = 0.5, to = 0.501 }))
	for i = 1, 64 do
		eq(flat[i], "#155ace")
		eq(near[i], flat[i])
	end
end)

test("bounds: the error names where the band was written", function()
	throws(function() colour.bounds({ from = 2, to = 0.5 }, "`band` in `setup`") end, "`band` in `setup`")
end)

-- --- the ramp --------------------------------------------------------------

test("ramp: as many colours as the quantisation says, endpoints exact", function()
	local r = colour.ramp(stops("#0b3d91 -> #7fd4ff"))
	-- The count is stated rather than read back off the module, so that changing
	-- the quantisation fails here instead of agreeing with itself.
	eq(#r, 64)
	-- Not a rounding accident: the conversion is a round trip, and every
	-- endpoint the fixtures here use comes back to the byte.
	eq(r[1], "#0b3d91")
	eq(r[#r], "#7fd4ff")
end)

test("ramp: it interpolates in Oklab, not in sRGB", function()
	-- Navy to yellow is where the two part company: halfway along, sRGB gives
	-- `#808040` and Oklab a far lighter, less muddy `#688e83`. Pinning the
	-- value is what makes a change of colour space a failing test rather than
	-- a difference nobody notices.
	local r = colour.ramp(stops("#000080 -> #ffff00"))
	eq(r[32], "#688e83")
	eq(r[33], "#6c9183")
	assert(r[32] ~= "#808040", "that is the sRGB midpoint")
end)

test("ramp: one stop is refused rather than indexed past the end", function()
	-- `stops` already refuses it, but `ramp` is exported beside it and a caller
	-- that built its endpoints another way would otherwise get "attempt to
	-- index a nil value" out of the interpolation instead of a refusal.
	throws(function() colour.ramp { { 0, 0, 0 } } end, "at least two colours")
end)

test("ramp: a third stop sits in the middle", function()
	-- 64 steps over two segments puts no step exactly on the middle stop, so
	-- the two either side of it are what say it is there.
	local r = colour.ramp(stops("#0b3d91 -> #ffffff -> #7fd4ff"))
	eq(r[1], "#0b3d91")
	eq(r[#r], "#7fd4ff")
	eq(r[32], "#fbfcfd")
	eq(r[33], "#fdfeff")
end)
