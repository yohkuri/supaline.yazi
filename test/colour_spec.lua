--- `colour.lua`: what a colour value may be, and the ramp built from one.
---
--- The stub's `ui.Style():fg` refuses what a real 26.9.1 refuses, from a
--- measured table, which is what lets the "not a colour" path be tested at all
--- -- the plugin asks Yazi's parser rather than carrying a list of its own.

local colour = require(".colour")

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

-- --- the style a flat colour draws in --------------------------------------

test("style: a colour string and a style both come back as a style", function()
	eq(colour.style("#0b3d91", "x").fg, "#0b3d91")
	eq(colour.style("cyan", "x").fg, "cyan", "a name is Yazi's to resolve, not ours")

	-- Handed back as it stands, so a theme's `bold` and `bg` survive.
	local own = ui.Style():fg("red"):bold()
	eq(colour.style(own, "x"), own)

	-- Nothing at all is still a style: the ground a ramp is patched onto, and
	-- what a column with no colour of its own draws in. Asserted by handing it
	-- back through the allow-list rather than by reading a field off it --
	-- `style.fg` is the setter, not the colour, on a real Yazi and here.
	local blank = colour.style(nil, "x")
	eq(colour.style(blank, "x"), blank)
end)

test("style: anything Yazi would not take as a style is refused", function()
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
	throws(function() colour.style(ui.Span("x"), "the colour of column `size`") end, "column `size`")
	throws(function() colour.style(ui.Line {}, "x") end, "Yazi takes a colour string")
	throws(function() colour.style({ fg = "#ff8800" }, "x") end, "plain table")
	-- A metatable is not what makes a style, which is the whole of the repair:
	-- this one passed before, straight through to the blank screen.
	throws(function() colour.style(setmetatable({ fg = "#ff8800" }, {}), "x") end, "plain table")
	throws(function() colour.style(42, "x") end, "is a number")
	throws(function() colour.style(true, "x") end, "is a boolean")
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
end)

-- --- endpoints -------------------------------------------------------------

test("stops: a string splits on the arrow, whitespace and all", function()
	local stops = colour.stops("  #0b3d91   ->#ffffff->   #7fd4ff  ", "x")
	eq(#stops, 3)
	eq(stops[1][3], 0x91)
	eq(stops[2][1], 0xff)
	eq(stops[3][1], 0x7f)
end)

test("stops: a list says the same thing", function()
	local stops = colour.stops({ "#0b3d91", "#7fd4ff" }, "x")
	eq(#stops, 2)
	eq(stops[2][2], 0xd4)
end)

test("stops: a name cannot anchor a ramp", function()
	-- A perfectly good flat colour, refused here alone: interpolating from it
	-- means guessing what the terminal draws it as, and the ramp's own end
	-- would then not meet it.
	throws(function() colour.stops("cyan -> #7fd4ff", "x") end, "cannot be a gradient endpoint")
	throws(function() colour.stops("129 -> #7fd4ff", "x") end, "cannot be a gradient endpoint")
end)

test("stops: one colour is not a ramp", function()
	throws(function() colour.stops({ "#0b3d91" }, "x") end, "at least two colours")
	throws(function() colour.stops("#0b3d91", "x") end, "at least two colours")
	-- The wrong value is the test, so the refusal is suppressed on the line
	-- rather than at the top of the file.
	---@diagnostic disable-next-line: param-type-mismatch
	throws(function() colour.stops(42, "x") end, "must be a list of colours")
end)

-- --- the ramp --------------------------------------------------------------

test("ramp: as many colours as the quantisation says, endpoints exact", function()
	local r = colour.ramp(colour.stops("#0b3d91 -> #7fd4ff", "x"))
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
	local r = colour.ramp(colour.stops("#000080 -> #ffff00", "x"))
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

test("styles: each step is patched onto the ground, which keeps the rest of it", function()
	-- The whole way from what a user wrote to what a row draws in lives in this
	-- module, so nothing outside it has to know a ramp is `#rrggbb` in between.
	local styles = colour.styles("#0b3d91 -> #7fd4ff", ui.Style():fg("red"):bold(), "x")
	eq(#styles, 64)
	eq(styles[1].fg, "#0b3d91", "the ramp decides the colour")
	eq(styles[#styles].fg, "#7fd4ff")
	eq(styles[1].bold, true, "and everything else is kept")
end)

test("ramp: a third stop sits in the middle", function()
	-- 64 steps over two segments puts no step exactly on the middle stop, so
	-- the two either side of it are what say it is there.
	local r = colour.ramp(colour.stops("#0b3d91 -> #ffffff -> #7fd4ff", "x"))
	eq(r[1], "#0b3d91")
	eq(r[#r], "#7fd4ff")
	eq(r[32], "#fbfcfd")
	eq(r[33], "#fdfeff")
end)
