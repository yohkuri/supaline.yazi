--- `colour.lua`, `paint.lua` and `style.lua`: what a colour value may be, how
--- one writer's style is read and the three are merged and built, and the ramp
--- built from one.
---
--- The stub's `ui.Style():fg` refuses what a real 26.9.1 refuses, from a
--- measured table, which is what lets the "not a colour" path be tested at all
--- -- the plugin asks Yazi's parser rather than carrying a list of its own.

local colour = require(".colour")
local paint = require(".paint")
local schema = require(".schema")
local style = require(".style")

-- Where a value under test was written, for the refusals that name it.
local X = schema.path("x")

--- A stop as the colour it is, so a mismatch reads as two colours rather than
--- as two channel numbers.
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

--- `style.merge` over one layer per writer, nearest last.
local function merge(values)
	local sources = { "definition", "theme", "spec" }
	local layers = {}
	for i, value in ipairs(values) do
		layers[i] = { values = value, source = sources[i] }
	end
	return style.merge(layers)
end

--- The nine attributes, each under the `ui.Style` method that drives it.
---
--- Written out here as well as in `style.lua` and the stub, because the stub
--- stands in for Yazi and must not require the plugin. This table is what holds
--- the three together, read on the way in by `layer` and on the way out by
--- `build`.
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

--- The pair `paint.recommended` hands a reader to paste, which is what every
--- band measured below was measured at. Written out rather than taken from
--- that function, so a change to the recommendation fails these tests rather
--- than moving them along with it.
---@type supaline.Band
local REC = { from = 0.35, to = 0.88 }

---@type supaline.Bands
local BANDS = { fg = REC, bg = REC }

--- `#0b3d91` as `colour.band` takes it.
---@type integer[]
local NAVY = { 0x0b, 0x3d, 0x91 }

--- `paint.stops` for `value` against `bands` -- `REC` as `fg` unless given --
--- under the `fg` key.
---@param value any
---@param bands supaline.Bands?
---@return integer[][]
local function stops(value, bands) return paint.stops(value, X, bands or { fg = REC }, "fg") end

-- --- one colour ------------------------------------------------------------

test("colour: a hex triple comes back with its channels", function()
	local rgb = assert(paint.colour("#0b3d91", X), "a hex colour has channels")
	eq(hex(rgb), "#0b3d91")
	eq(assert(paint.colour("#FF8800", X))[1], 255, "case is Yazi's business, not a second spelling")
end)

test("colour: a name and an index are colours with no channels to give", function()
	eq(paint.colour("cyan", X), nil, "what `cyan` is on screen is the terminal's palette, not ours")
	eq(paint.colour("129", X), nil)
	eq(paint.colour("reset", X), nil)
end)

test("colour: what Yazi's parser refuses is refused here, and named in the error", function()
	throws(
		function() paint.colour("#f80", schema.path("setup.linemodes.detail[1].style")) end,
		"setup.linemodes.detail[1].style: ",
		"`#f80`"
	)
	throws(function() paint.colour("nosuchcolour", X) end, "not a colour Yazi accepts")
	throws(function() paint.colour("256", X) end, "not a colour Yazi accepts")
	throws(function() paint.colour(42, X) end, "must be a colour string")
	-- `fg(nil)` and `fg(true)` return nil on a real Yazi instead of raising, so
	-- neither may reach it: the caller would be told the colour was fine.
	throws(function() paint.colour(nil, X) end, "got a nil")
	throws(function() paint.colour(true, X) end, "got a boolean")
end)

test("colour: the arithmetic needs no Yazi at all", function()
	-- So `test/ramp.lua` can draw a ramp without one, and so nothing in the
	-- arithmetic can come to depend on Yazi's parser.
	_G.ui = nil
	local pure = dofile(ROOT .. "/colour.lua")
	local ramp = pure.ramp(pure.band(assert(pure.rgb("#0b3d91")), REC))
	eq(#ramp, pure.STEPS)
	eq(table.concat(ramp), table.concat(colour.ramp(colour.band(NAVY, REC))))
end)

-- --- one writer's layer ----------------------------------------------------

--- A layer read from `value` with the painter a column's style is read with.
--- Never `false` here: that is the one input `style.layer` answers with itself,
--- and the test that plants it asserts on the value directly.
---@param value any
---@param bands supaline.Bands? `BANDS` when omitted
---@return supaline.Layer
local function layer(value, bands)
	local got = style.layer(value, X, paint.painter(bands or BANDS))
	if not got then
		error("a layer rather than `false`")
	end
	return got
end

test("layer: nothing written is an empty layer, and `false` is the layer itself", function()
	eq(next(layer(nil)), nil)
	-- Not a layer of eleven `false`s. An attribute's `false` is the attribute
	-- taken off, where `style = false` asks for a cell drawn in whatever the row
	-- already carries. `merge` is what reads it, so it is handed on as it is.
	eq(style.layer(false, X, paint.painter(BANDS)), false)
end)

test("layer: a string is the `fg`, flat or a gradient", function()
	eq(layer("#0b3d91").fg, "#0b3d91")
	eq(layer("cyan").fg, "cyan", "a name is Yazi's to resolve, not ours")

	-- A gradient is kept as its stops, parsed on the way in so that a bad
	-- endpoint is refused while the layer is read rather than while it draws.
	eq(#layer("#0b3d91 -> #7fd4ff").fg, 2)
	eq(#layer("#7fd4ff <->").fg, 2, "a band derives both of its ends")

	throws(function() layer("#gg0000") end, "is not a colour Yazi accepts")
	throws(function() layer("cyan -> #7fd4ff") end, "cannot be a gradient endpoint")
end)

test("layer: a table is the theme's spelling, read key by key", function()
	-- A layer has to know which keys were written, because a key nobody wrote
	-- is what leaves the one beneath showing.
	local got = layer { fg = "#ff8800", bg = "#7a2d00", bold = true, reversed = true }
	eq(got.fg, "#ff8800")
	eq(got.bg, "#7a2d00")
	eq(got.bold, true)
	eq(got.reversed, true, "`reversed`, the theme's key; `reverse()` is the method's business")
	eq(got.italic, nil, "a key nobody wrote is not in the layer")

	eq(layer({ fg = false }).fg, false)
	eq(layer({ bg = false }).bg, false)
	eq(type(layer({ bg = "#0b3d91 -> #7fd4ff" }).bg), "table")
	eq(type(layer({ bg = "#0b3d91 <->" }).bg), "table")
end)

test("layer: every attribute a theme can write is read under its own name", function()
	-- `false` is the attribute taken off, which is what the same line means in
	-- a theme, and not the same as nothing said.
	for key in pairs(ATTRS) do
		eq(layer({ [key] = true })[key], true, key)
		eq(layer({ [key] = false })[key], false, key .. " = false")
		eq(layer({ fg = "cyan" })[key], nil, key .. " unsaid")
	end
end)

test("layer: a `ui.Style` is read through `raw()`, so its keys are the same keys", function()
	-- A themed table field arrives as the `Style` Yazi parsed, in Yazi's own
	-- spelling of the colours, which `fg()` takes back.
	local got = layer(ui.Style():fg("#ff8800"):bg("cyan"):bold():reverse())
	eq(got.fg, "#FF8800")
	eq(got.bg, "Cyan")
	eq(got.bold, true)
	eq(got.reversed, true, "the theme's key, which is the layer's")
	-- `types.yazi` declares `bold` without the removal flag 26.9.1's takes.
	---@diagnostic disable-next-line: redundant-parameter
	eq(layer(ui.Style():bold(true)).bold, false, "a removal, the shape a theme's `bold = false` arrives in")
	eq(next(layer(ui.Style())), nil, "an empty `[supaline]` field says nothing, and is not refused")
end)

test("layer: a key Yazi would have dropped is refused by name", function()
	-- The whole of what the table form buys over the theme's: Yazi drops a key
	-- it does not know before `th.supaline` exists -- measured on 26.9.1,
	-- `strikethrough = true` in `[supaline]` said nothing -- while a spec
	-- reaches this file verbatim.
	throws(function() layer { fg = "cyan", strikethru = true } end, "`strikethru` is not a style key")
	throws(function() layer { zebra = true, apple = true } end, "`apple`, `zebra` are not style keys")
	-- The three a reader arrives at honestly are pointed at what works.
	throws(function() layer { reverse = true } end, "`reversed` is the spelling")
	throws(function() layer { strikethrough = true } end, "`crossed` is the spelling")
	throws(function() layer { reset = true } end, 'write `fg = "reset"`')
	-- The list spelling of a gradient is not taken, and nothing guesses it.
	throws(function() layer { "#aabbcc", "#ff8800" } end, "`1`, `2` are not style keys")
end)

test("layer: a colour is a colour and an attribute a boolean", function()
	throws(function() layer { fg = "#gg0000" } end, "x.fg: `#gg0000` is not a colour Yazi accepts")
	throws(function() layer { bg = 42 } end, "x.bg: must be a colour string, got a number")
	throws(function() layer { fg = { "#aabbcc", "#ff8800" } } end, "x.fg: must be a colour string, got a table")
	throws(function() layer { bold = "yes" } end, "must be true or false")
end)

test("layer: what is not a style at all is refused", function()
	-- `ui.Style` with the call forgotten. Measured on 26.9.1: `type(ui.Style)`
	-- is `table` and `pairs` over it finds nothing, so it would otherwise read
	-- as a layer saying nothing.
	throws(function() layer(ui.Style) end, "is the constructor")
	throws(function() layer {} end, "no keys in it")
	throws(function() layer(42) end, "got a number")
	throws(function() layer(true) end, "got a boolean")

	-- `Span:style` takes a Style or nil, and a value that is neither survives
	-- `setup` and then empties the screen. Told apart by what it answers to:
	-- mlua gives all of Yazi's userdata `__metatable = false`, measured on
	-- 26.9.1, so `getmetatable` cannot tell a Span from a Style.
	throws(
		function() style.layer(ui.Span("x"), schema.path("setup.linemodes.detail[1].style"), paint.painter(BANDS)) end,
		"setup.linemodes.detail[1].style: "
	)
	-- The harness's renderable is a Lua table where Yazi's is userdata, so it
	-- is refused as a style table whose keys are nothing of the sort.
	throws(function() layer(ui.Line {}) end, "`_parts` is not a style key")
end)

-- --- the three layers, merged ----------------------------------------------

test("merge: each key goes to the nearest layer that wrote it", function()
	local resolved, from = merge {
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
	eq(from.fg, "theme")
	eq(from.bg, "definition")
	eq(from.bold, "spec")
	eq(from.italic, "theme")
	eq(from.dim, nil)
end)

test("merge: `false` is written, so the layer beneath does not show through", function()
	local resolved, from = merge { { fg = "red", bold = true }, { fg = false } }
	eq(resolved.fg, false)
	eq(from.fg, "theme")
	eq(resolved.bold, true, "and a key the nearer layer left alone is still the farther one's")

	eq(next((merge { {}, {}, {} })), nil, "three layers saying nothing say nothing")
end)

test("merge: a layer that is `false` whole starts the stack over", function()
	-- Both colours off and on record as off, so the column that asks who wrote
	-- its `fg` is told; every attribute unwritten rather than taken off, so the
	-- row keeps its own.
	local resolved, from = merge { { fg = "red", bg = "blue", bold = true }, false }
	eq(resolved.fg, false)
	eq(resolved.bg, false)
	eq(resolved.bold, nil)
	eq(from.fg, "theme")
	eq(from.bold, nil)

	local again = merge { { bold = true }, false, { fg = "green" } }
	eq(again.fg, "green", "and a layer above it writes over that as over anything")
	eq(again.bg, false)
	eq(again.bold, nil)
end)

-- --- what the merged layer builds -----------------------------------------

test("build: a flat layer is one style, and `false` on a colour is no colour", function()
	local ground, steps = style.build { fg = "#ff8800", bg = "#7a2d00", bold = true }
	eq(ground.fg, "#ff8800")
	eq(ground.bg, "#7a2d00")
	eq(ground.bold, true)
	eq(steps, nil, "nothing to quantise")

	local off = style.build { fg = false, bold = true }
	eq(rawget(off, "fg"), nil)
	eq(off.bold, true)

	eq(next(style.build {}), nil, "nothing written builds an empty style")
end)

test("build: every attribute reaches its method, added or taken off", function()
	-- Yazi's `bold(true)` takes bold off, so a `false` in the layer has to
	-- arrive as `bold(true)` and not as a second `bold()`. `rawget`, because a
	-- style carrying nothing under a key answers with the method.
	for key, method in pairs(ATTRS) do
		eq(rawget(style.build { [key] = true }, method), true, key)
		eq(rawget(style.build { [key] = false }, method), false, key .. " = false")
	end
end)

test("build: a gradient under `fg` is the quantisation's worth of styles, each on the ground", function()
	local ground, steps = style.build(layer { fg = "#0b3d91 -> #7fd4ff", bold = true, bg = "#1e1e2e" })
	steps = assert(steps, "a gradient builds steps")
	eq(#steps, 64)
	eq(steps[1].fg, "#0b3d91")
	eq(steps[64].fg, "#7fd4ff")
	-- Both ends, because the ground is what every step is set on.
	for _, i in ipairs { 1, 64 } do
		eq(steps[i].bold, true)
		eq(steps[i].bg, "#1e1e2e")
	end
	eq(rawget(ground, "fg"), nil, "the ground carries everything but the gradient")
end)

test("build: a gradient under `bg` paints the ground, and both keys may carry one", function()
	local _, steps = style.build(layer { bg = "#0b3d91 -> #7fd4ff", fg = "#ffffff" })
	steps = assert(steps, "a gradient builds steps")
	eq(steps[1].bg, "#0b3d91")
	eq(steps[64].bg, "#7fd4ff")
	eq(steps[32].fg, "#ffffff", "a flat colour beside it is on every step")

	local _, both = style.build(layer { fg = "#000000 -> #ffffff", bg = "#0b3d91 -> #7fd4ff" })
	both = assert(both, "a gradient builds steps")
	eq(both[1].fg .. both[1].bg, "#000000#0b3d91", "two gradients land on the same step at the same ratio")
	eq(both[64].fg .. both[64].bg, "#ffffff#7fd4ff")
end)

-- --- one style, for a separator ---------------------------------------------

--- A separator's style, read with the painter a separator's slot reads with.
---@param value any
---@return unknown
local function flat(value)
	local layer = style.layer(value, X, paint.flat) --[[@as supaline.Layer]]
	return (style.build(layer))
end

test("flat: a separator's style is one layer built on its own, and takes no gradient", function()
	eq(flat("#ff8800").fg, "#ff8800")
	eq(flat({ bold = true }).bold, true)
	eq(flat(ui.Style():fg("cyan")).fg, "Cyan")

	-- A separator is drawn between two columns rather than on a file, so there
	-- is no value to place on a gradient. Every spelling of one is refused with
	-- the one message, naming the value rather than whichever part of it a
	-- parser would have tripped over first -- `cyan <->` included.
	local SAME = "is a gradient, and there is no value here to place"
	for _, value in ipairs { "#0b3d91 -> #7fd4ff", "#0b3d91 <->", "#0b3d91 <-> nosuch", "cyan <->" } do
		throws(function() flat(value) end, "`" .. value .. "` " .. SAME)
	end
	throws(function() flat { bg = "#0b3d91 <->" } end, "x.bg: `#0b3d91 <->` " .. SAME)
end)

-- --- what a style answers `raw()` with ------------------------------------

--- `raw()` off a style, cast the way `style.lua` casts: `types.yazi` declares
--- no `raw` on its `(exact)` `ui.Style`.
---@param style unknown
---@return table
local function raw(style)
	return (style --[[@as supaline.Style]]):raw()
end

test("raw: a style answers with its keys, in Yazi's own spelling", function()
	-- The stub's `raw()` against a run of 26.9.1 -- `probes.md`, "A colour
	-- read back out of a style". `style.lua` reads every `ui.Style` through
	-- this, so a stub that answered any other way would let the theme specs
	-- prove nothing about the theme.
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

	---@diagnostic disable-next-line: redundant-parameter
	eq(raw(ui.Style():bold(true)).bold, false, "a removal is `false`, the shape a theme's `bold = false` arrives in")
	eq(next(raw(ui.Style())), nil, "an empty style answers an empty table")

	-- And what comes back goes back in, on a real Yazi and here.
	for _, name in ipairs { "Reset", "LightRed", "DarkGray", "Cyan", "#FF8800" } do
		eq(raw(ui.Style():fg(name)).fg, name)
	end
end)

-- --- telling a ramp from a flat colour -------------------------------------

test("is_ramp: the arrow is what a flat colour can never contain", function()
	eq(paint.is_ramp("#0b3d91 -> #7fd4ff"), true)
	eq(paint.is_ramp("#0b3d91 <->"), true, "`<->` carries the arrow inside it")
	eq(paint.is_ramp("#0b3d91"), false)
	eq(paint.is_ramp("cyan"), false)
	eq(paint.is_ramp(nil), false)
	eq(paint.is_ramp {}, false)
	-- A style out of the theme is userdata on a real Yazi and a table behind a
	-- metatable here, so an implementation reaching for a field on it before
	-- testing the type would pass a bare table and fail on both of those.
	eq(paint.is_ramp(ui.Style():fg("red"):bold()), false)
end)

-- --- endpoints -------------------------------------------------------------

test("stops: a string splits on the arrow, whitespace and all", function()
	local got = stops("  #0b3d91   ->#ffffff->   #7fd4ff  ")
	eq(#got, 3)
	eq(hex(got[1]) .. hex(got[2]) .. hex(got[3]), "#0b3d91#ffffff#7fd4ff")
end)

test("stops: a name cannot anchor a ramp", function()
	-- A good flat colour, refused here alone: interpolating from it means
	-- guessing what the terminal draws it as.
	throws(function() stops("cyan -> #7fd4ff") end, "cannot be a gradient endpoint")
	throws(function() stops("129 -> #7fd4ff") end, "cannot be a gradient endpoint")
end)

test("stops: one colour is a band with the marker, and a refusal without it", function()
	-- Under `fg` a bare colour is a flat colour and has to go on meaning one,
	-- so the marker is the only spelling of a band.
	same_band(stops("#7fd4ff <->"), colour.band({ 0x7f, 0xd4, 0xff }, REC))
	throws(
		function() stops("#7fd4ff") end,
		"is one colour, and a gradient needs two ends",
		"`#7fd4ff <->` to spread the one colour"
	)
	throws(function() stops { "#0b3d91", "#7fd4ff" } end, "must be a string like")
end)

test("stops: `<->` spreads one colour and says so when handed two", function()
	throws(function() stops("#0b3d91 <-> #7fd4ff") end, "is not a band")
	throws(function() stops("<->") end, "is not a band")
	-- Only the marker is removed, so what is left gets the message a bad
	-- colour gets.
	throws(function() stops("cyan <->") end, "cannot be a gradient endpoint")
end)

-- --- a band ----------------------------------------------------------------

test("band: both ends are fixed, whatever the colour's own lightness", function()
	-- Every value below is from the arithmetic in `colour.lua`; the same
	-- numbers come out of the derivation by hand. `#e8f4ff` sits at 0.96 and
	-- `#0b1a2f` at 0.22, outside the band either way, and neither appears on
	-- it: what the colour supplies is the hue.
	local light = stops("#e8f4ff <->")
	eq(hex(light[1]) .. " " .. hex(light[2]), "#383b3e #ced9e3")
	local dark = stops("#0b1a2f <->")
	eq(hex(dark[1]) .. " " .. hex(dark[2]), "#1f3b61 #bfdaff")
end)

test("band: past the exposure's reach, lightness is bought with chroma", function()
	-- The exposure alone stops where the strongest channel hits 255: `#0b3d91`
	-- reaches 0.59 and no further. Above it the hue is held and the chroma
	-- spent, which is the only thing that can be given up without turning the
	-- colour.
	eq(hex(stops("#0b3d91 <->")[2]), "#c2d9ff")
	-- A channel already at 255 cannot be exposed at all, and 0.83 is below the
	-- ceiling, so this one buys the rest with chroma too -- the reason the
	-- ceiling is 0.88.
	eq(hex(stops("#7fd4ff <->")[2]), "#a8e1ff")
	-- Never more chroma than the exposure would have reached: grey stays grey.
	local grey = stops("#767676 <->")[2]
	eq(grey[1], grey[2])
	eq(grey[2], grey[3])
end)

test("band: a dark colour spreads upwards, every step a colour of its own", function()
	-- `#0b3d91` has almost no room below the floor -- 0.39 against 0.35 -- so a
	-- band anchored at the colour would be four hundredths wide and half its
	-- steps repeats. Taking the room above it spreads it floor to ceiling.
	local r = colour.ramp(stops("#0b3d91 <->"))
	local seen, n = {}, 0
	for _, step in ipairs(r) do
		if not seen[step] then
			seen[step], n = true, n + 1
		end
	end
	eq(n, #r, "every step distinct")
	eq(r[1], "#08347f")
	eq(r[#r], "#c2d9ff")
end)

test("band: black is a grey band rather than a refusal", function()
	-- A grey has no hue to hold at any lightness, and the band is drawn at the
	-- two the user asked for regardless, so the three greys furthest apart in
	-- sRGB come out as the same band and none of them is a special case.
	local black = stops("#000000 <->")
	same_band(black, stops("#767676 <->"), "black against a mid grey")
	same_band(black, stops("#ffffff <->"), "black against white")
	eq(hex(black[1]) .. " " .. hex(black[2]), "#3a3a3a #d7d7d7")
end)

test("band: the pair is directed, so writing it backwards inverts the ramp", function()
	-- What a light terminal needs, and the reason the two numbers are `from`
	-- and `to` rather than a floor and a ceiling with a boolean beside them.
	local up = colour.ramp(stops("#0b3d91 <->", { fg = { from = 0.35, to = 0.88 } }))
	local down = colour.ramp(stops("#0b3d91 <->", { fg = { from = 0.88, to = 0.35 } }))
	eq(#up, #down)
	for i = 1, #up do
		eq(down[i], up[#up + 1 - i], "step " .. i .. " is the other ramp's mirror")
	end
end)

test("recommended: a fresh table, so two callers cannot write to one band", function()
	local a, b = paint.recommended(), paint.recommended()
	eq(a.from .. " " .. a.to, REC.from .. " " .. REC.to)
	a.from = 0.1
	eq(b.from, REC.from, "the second copy did not move with the first")
	eq(paint.recommended().from, REC.from, "and neither did the next one")
end)

-- --- bands by name ---------------------------------------------------------

test("bands: a `setup` that named no band defines none", function()
	-- There is no name a band can be asked for by that answers without the
	-- user having said so, which is the whole of what "no default" means.
	local none = paint.bands(nil, X)
	eq(next(none), nil)
	throws(function() stops("#0b3d91 <->", none) end, "nothing defines `fg`")
end)

test("bands: the refusal carries the pair to paste and says nothing is defined", function()
	-- This message is the feature's front door: what a reader meets the first
	-- time they write `<->`. So it carries the two numbers, the name the key
	-- asked for, and the fact that supaline is not withholding a better answer.
	throws(
		function() stops("#0b3d91 <->", {}) end,
		"{ from = 0.35, to = 0.88 }",
		"band = { fg = ",
		"cannot see that ground",
		"No band is defined yet"
	)
end)

test("bands: the refusal lists what is defined, which is where a typo shows up", function()
	-- No sweep can refuse `bgg`, because every name is a name somebody may have
	-- meant; this list, read at the use site, stands in for one.
	local defined = paint.bands({ fg = REC, bgg = REC }, X)
	throws(function() paint.stops("#0b3d91 <->", X, defined, "bg") end, "Defined: `bgg`, `fg`")
end)

test("bands: a band is asked for by its key, or by the name after the marker", function()
	local dark, dim = { from = 0.1, to = 0.3 }, { from = 0.2, to = 0.45 }
	local bands = paint.bands({ fg = REC, bg = dark, dim = dim }, X)
	-- A `supaline.Paint` is a flat colour or a ramp's stops; the key it was read
	-- off is what narrows it to a band here.
	local both = layer({ fg = "#0b3d91 <->", bg = "#0b3d91 <->" }, bands)
	same_band(both.fg --[[@as integer[][] ]], colour.band(NAVY, REC))
	same_band(both.bg --[[@as integer[][] ]], colour.band(NAVY, dark))
	same_band(layer("#0b3d91 <->", bands).fg --[[@as integer[][] ]], colour.band(NAVY, REC), "a bare string is `fg`")
	same_band(
		layer({ bg = "#0b3d91 <-> dim" }, bands).bg --[[@as integer[][] ]],
		colour.band(NAVY, dim),
		"and a name after the marker wins over the key"
	)
end)

test("bands: what follows the marker is a name, and a colour there says so", function()
	local one = { fg = REC }
	throws(function() stops("#0b3d91 <-> #7fd4ff", one) end, "is not a band name", "write them with `->`")
	throws(function() stops("#0b3d91 <-> 0.4", one) end, "is not a band name")
	throws(function() stops("#0b3d91 <-> My_Band", one) end, "is not a band name")
	-- `from` and `to` pass the name shape and `bands` refuses to define them,
	-- so the undefined-band refusal would tell the reader to write what
	-- `setup` turns away. Caught first, in the words `setup` uses.
	throws(function() stops("#0b3d91 <-> from", one) end, "one of a band's own two keys")
	throws(function() stops("#0b3d91 <-> to", one) end, "Call the band something else", "`to`")
end)

test("bands: a name Lua will not take bare is quoted where the refusal says to write it", function()
	-- `end` and `2x` are names `setup` defines when bracketed, and a refusal a
	-- reader pastes has to be a setting: `band = { end = ... }` is a syntax
	-- error. An ordinary name stays bare, so the common message does not read
	-- as the awkward case.
	for _, name in ipairs { "end", "2x" } do
		local defined = paint.bands({ [name] = REC }, X)
		eq(next(defined), name, "`setup` takes " .. name)
		same_band(stops("#0b3d91 <-> " .. name, defined), colour.band(NAVY, REC), name .. " draws")
		throws(function() stops("#0b3d91 <-> " .. name, {}) end, 'band = { ["' .. name .. '"] = ')
	end
	throws(function() stops("#0b3d91 <-> dim", {}) end, "band = { dim = ")
	throws(function() stops("#0b3d91 <-> _x", {}) end, "band = { _x = ")
end)

test("bands: a band's name is a column's rule, without the cap that is Yazi's", function()
	-- The two `NAME` literals live apart on purpose -- a column's is Yazi's
	-- theme rule and a band's is this plugin's own -- and nothing but this says
	-- they have come apart.
	local registry = require(".column").new_registry()
	for _, name in ipairs { "2x", "_x", "x_", "my_band2" } do
		registry.register(name, { render = function() return "x" end })
		eq(next(paint.bands({ [name] = REC }, X)), name, name .. " names both a column and a band")
	end
	for _, name in ipairs { "my-band", "MyBand" } do
		throws(function() paint.bands({ [name] = REC }, X) end, "is not a band name")
	end
	throws(function() paint.bands({ [1] = REC }, X) end, "is not a band name")

	-- A column name is capped at 20 because a `[supaline]` field is; nothing
	-- parses a band name, so nothing caps it.
	local long = string.rep("b", 21)
	throws(function()
		registry.register(long, { render = function() return "x" end })
	end, "cannot be a column name")
	eq(next(paint.bands({ [long] = REC }, X)), long, "a band of 21 characters is defined")
end)

test("bands: a band's own keys are not a band, nor a band's name", function()
	-- The flat pair written where a table of bands goes is what a reader writes
	-- who takes `band` for one band. Refused rather than read as `fg`, and the
	-- message names the replacement.
	throws(
		function() paint.bands({ from = 0.35, to = 0.88 }, X) end,
		"are a band's own keys",
		"band = { fg = { from = 0.35, to = 0.88 } }"
	)
	throws(function() paint.bands({ from = 0.35 }, X) end, "are a band's own keys")
	-- A table under `to` is not the flat pair, and is refused for its own
	-- reason.
	throws(function() paint.bands({ to = REC }, X) end, "cannot also be a band's name")
	throws(function() paint.bands({ from = REC }, X) end, "cannot also be a band's name")
end)

test("bands: each band is checked, named, and in the same order every run", function()
	throws(
		function() paint.bands({ fg = { from = 0, to = 0.88 } }, schema.path("setup.band")) end,
		"setup.band.fg.from: ",
		"must be above 0"
	)
	throws(function() paint.bands({ dim = "dark" }, X) end, "x.dim: must be a table")
	-- Read in the order of their names, so fixing the one named does not reveal
	-- a different one first on the next run.
	for _ = 1, 8 do
		throws(function() paint.bands({ fg = { from = 0 }, bg = "dark" }, X) end, "x.bg: must be a table")
	end
end)

test("bounds: an end outside `(0, 1]` is refused, NaN included", function()
	-- 0 is black at every hue, so a band with an end there has one no colour
	-- reaches; above 1 is off the end of the space. A NaN answers false to both
	-- comparisons, which is why the check is written `not (v > 0 and v <= 1)`.
	for _, band in ipairs {
		{ from = 0, to = 0.88 },
		{ from = 0.35, to = 1.2 },
		{ from = -0.1, to = 0.88 },
		{ from = 0 / 0, to = 0.88 },
	} do
		throws(function() paint.bounds(band, X) end, "must be above 0")
	end
	throws(function() paint.bounds({ from = 2, to = 0.5 }, schema.path("setup.band.fg")) end, "setup.band.fg.from: ")
end)

test("bounds: a band that is not two numbers is refused", function()
	throws(function() paint.bounds({ to = 0.88 }, X) end, "x.from: must be an Oklab lightness")
	throws(function() paint.bounds({ from = 0.35 }, X) end, "x.to: must be an Oklab lightness")
	throws(function() paint.bounds({ from = "dark", to = 0.88 }, X) end, "x.from: must be an Oklab lightness")
	-- Nothing falls back to the recommended pair, so nil here is a caller that
	-- read a name nobody defined.
	throws(function() paint.bounds("dark", X) end, "must be a table of two lightnesses")
	throws(function() paint.bounds(nil, X) end, "must be a table of two lightnesses")
end)

test("bounds: two ends at one lightness are taken rather than refused", function()
	local band = paint.bounds({ from = 0.6, to = 0.6 }, X)
	eq(band.from .. " " .. band.to, "0.6 0.6")
	-- An equality test reads like the right refusal and would catch this
	-- spelling and not the one beside it, which draws the identical column.
	-- Where flat stops being flat is the writer's judgement.
	local same = colour.ramp(stops("#0b3d91 <->", { fg = { from = 0.5, to = 0.5 } }))
	local near = colour.ramp(stops("#0b3d91 <->", { fg = { from = 0.5, to = 0.501 } }))
	for i = 1, 64 do
		eq(same[i], "#155ace")
		eq(near[i], same[i])
	end
end)

-- --- the ramp --------------------------------------------------------------

test("ramp: as many colours as the quantisation says, endpoints exact", function()
	local r = colour.ramp(stops("#0b3d91 -> #7fd4ff"))
	-- Stated rather than read off the module, so changing the quantisation
	-- fails here instead of agreeing with itself.
	eq(#r, 64)
	-- The conversion is a round trip, so every endpoint comes back to the byte.
	eq(r[1], "#0b3d91")
	eq(r[#r], "#7fd4ff")
end)

test("ramp: it interpolates in Oklab, not in sRGB", function()
	-- Navy to yellow is where the two part company: halfway along, sRGB gives
	-- `#808040` and Oklab a far lighter, less muddy `#688e83`.
	local r = colour.ramp(stops("#000080 -> #ffff00"))
	eq(r[32], "#688e83")
	eq(r[33], "#6c9183")
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

test("ramp: one stop is refused rather than indexed past the end", function()
	-- `ramp` is exported beside `stops`, and a caller that built its endpoints
	-- another way would otherwise get "attempt to index a nil value".
	throws(function() colour.ramp { { 0, 0, 0 } } end, "at least two colours")
end)
