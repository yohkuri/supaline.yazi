--- `colour.lua`: what a colour value may be, and the ramp built from one.
---
--- The stub's `ui.Style():fg` refuses what a real 26.9.1 refuses, from a
--- measured table, which is what lets the "not a colour" path be tested at all
--- -- the plugin asks Yazi's parser rather than carrying a list of its own.

local colour = require(".colour")

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
	-- `<->` carries the arrow inside it, so a band answers this without the
	-- test knowing there are two spellings. That is the reason it is spelled
	-- with one.
	eq(colour.is_ramp("#0b3d91 <->"), true, "a band is a ramp")
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

test("stops: one colour is a band, however it was written", function()
	-- Three spellings, one path: `<->` exists for the theme, where a field
	-- holds one value and a flat colour has to go on meaning a flat colour; a
	-- spec needs none of that, because the key already says `ramp`.
	local marked = colour.stops("#0b3d91 <->", "x")
	local bare = colour.stops("#0b3d91", "x")
	local listed = colour.stops({ "#0b3d91" }, "x")
	same_band(bare, marked, "written bare")
	same_band(listed, marked, "written as a list of one")
end)

test("stops: an empty list names nothing to interpolate", function()
	throws(function() colour.stops({}, "x") end, "names no colour")
	-- The wrong value is the test, so the refusal is suppressed on the line
	-- rather than at the top of the file.
	---@diagnostic disable-next-line: param-type-mismatch
	throws(function() colour.stops(42, "x") end, "must be a list of colours")
end)

test("stops: `<->` spreads one colour and says so when handed two", function()
	throws(function() colour.stops("#0b3d91 <-> #7fd4ff", "x") end, "is not a band")
	throws(function() colour.stops("<->", "x") end, "is not a band")
	-- The marker is the only thing removed, so what is left is read as a
	-- colour like any other and gets the message a bad colour gets.
	throws(function() colour.stops("cyan <->", "x") end, "cannot be a gradient endpoint")
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
	local stops = colour.stops("#e8f4ff <->", "x")
	eq(hex(stops[1]), "#383b3e")
	eq(hex(stops[2]), "#ced9e3")
end)

test("band: a colour darker than the band is not an end of it either", function()
	-- The other side, and it is fixed the same way. `#0b1a2f` sits at 0.22,
	-- below the band's floor of 0.35, and the low end is drawn at the floor
	-- rather than at the colour.
	local stops = colour.stops("#0b1a2f <->", "x")
	eq(hex(stops[1]), "#1f3b61")
	eq(hex(stops[2]), "#bfdaff")
end)

test("band: past the exposure's reach, lightness is bought with chroma", function()
	-- The exposure alone stops where the strongest channel hits 255, and for a
	-- dark colour that is not light: `#0b3d91` reaches 0.59 and no further,
	-- against the 0.83 of the `#7fd4ff` a hand-written ramp would have had.
	-- Above it the hue is held and the chroma spent, which is the only thing
	-- that can be given up without turning the colour.
	local hi = colour.stops("#0b3d91 <->", "x")[2]
	eq(hex(hi), "#c2d9ff")

	-- Having a channel at 255 already is not the same as being high enough: the
	-- exposure cannot move `#7fd4ff` at all, and 0.83 is below the ceiling, so
	-- this one buys the rest with chroma too. That is the whole of what a
	-- ceiling above 0.83 changes, and it is the reason this one is 0.88.
	local sat = colour.stops("#7fd4ff <->", "x")[2]
	eq(hex(sat), "#a8e1ff")

	-- And never more chroma than the exposure itself would have reached, so a
	-- colour is not made more vivid on the way to being made lighter. Grey has
	-- none to spend and stays grey.
	local grey = colour.stops("#767676 <->", "x")[2]
	eq(grey[1], grey[2])
	eq(grey[2], grey[3])
end)

test("band: a dark colour spreads upwards, which is the point of deriving both", function()
	-- The case the whole design turns on. `#0b3d91` has almost no room below
	-- the floor -- 0.39 in lightness against 0.35 -- so a band anchored at the
	-- colour and falling to the floor would be four hundredths wide and half
	-- its steps repeats. Taking the room above it instead spreads it from the
	-- floor to the ceiling, and every step is a colour of its own.
	local r = colour.ramp(colour.stops("#0b3d91 <->", "x"))
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
	-- Black used to be refused here, on the grounds that it has no lightness to
	-- scale and no hue to hold. With both ends fixed that stops being true of
	-- black in particular: a grey has no hue to hold at any lightness, and the
	-- band is drawn at the two the user asked for regardless. So the three
	-- greys furthest apart in sRGB all come out as the same band, and refusing
	-- one of the three would have been an exception with nothing behind it.
	local black = colour.stops("#000000 <->", "x")
	local mid = colour.stops("#767676 <->", "x")
	local white = colour.stops("#ffffff <->", "x")
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
	local up = colour.ramp(colour.stops("#0b3d91 <->", "x", { from = 0.35, to = 0.88 }))
	local down = colour.ramp(colour.stops("#0b3d91 <->", "x", { from = 0.88, to = 0.35 }))
	eq(#up, #down)
	for i = 1, #up do
		eq(down[i], up[#up + 1 - i], "step " .. i .. " is the other ramp's mirror")
	end
end)

test("bounds: the default is what a band gets when `setup` says nothing", function()
	local d = colour.bounds(nil, "x")
	eq(d.from, 0.35)
	eq(d.to, 0.88)
	-- And the default is what `stops` applies, so the two cannot drift.
	local implicit = colour.stops("#0b3d91 <->", "x")
	local explicit = colour.stops("#0b3d91 <->", "x", d)
	same_band(implicit, explicit)
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
	-- Why they are taken: sixty-four steps of one colour is what a flat `base`
	-- already is, so an equality test reads like the right refusal -- and it
	-- would catch this spelling and not the one beside it, which draws the
	-- identical column. Where flat stops being flat is a judgement, and the two
	-- ends are the writer's to make, degenerate ones included.
	local flat = colour.ramp(colour.stops("#0b3d91 <->", "x", { from = 0.5, to = 0.5 }))
	local near = colour.ramp(colour.stops("#0b3d91 <->", "x", { from = 0.5, to = 0.501 }))
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
