local supaline = require("supaline")

-- The ramp the colour linemodes below reach for when nothing else is the
-- point. It climbs in all three channels at once, which is what `e2e.py` reads
-- it for; `c_hue` is the one that deliberately does not.
local COOL = "#0b3d91 -> #7fd4ff"

-- The one that does not, for `c_hue`. Named rather than written twice: the two
-- columns there have to carry the *same* ramp for `e2e.py` to read a row's two
-- cells against each other, and two literals can drift where one cannot.
local HUE = "#0b3d91 -> #ffd400"

-- The band `c_band` draws, written with the marker even though a spec does not
-- need it: what the marker spreads is the same either way, and a reader
-- comparing this against `c_ramp` should see the spelling that put it there.
--
-- Spelled out in prose rather than quoted, and that is not a style point: the
-- second search below reads "a line with an arrow in it" as a ramp the first
-- one missed, and the marker has an arrow inside it. A comment here that
-- quoted one would stop the fixture building.
--
-- The same navy `COOL` starts from, which is the comparison worth having on
-- two keys. It is also the case the band exists for: `#0b3d91` has almost no
-- room below it and half again above, so a band anchored at the colour and
-- falling to the floor would be nearly flat, and this one is not.
local BAND = "#0b3d91 <->"

-- The same band, asked for by name rather than by the key it is written under.
-- `c_band`'s two columns then take one path each -- the name off the key, and
-- the name off the string -- and draw the identical ramp, so `e2e.py` reads
-- both of them with the check it already had, and a name that failed to
-- resolve is a refusal rather than a column that looks right.
--
-- `both` is defined below to the same pair as `fg` for exactly that reason. A
-- second pair here would test the name and lose the comparison.
local BAND_BY_NAME = "#0b3d91 <-> both"

-- The background `c_bg` puts under that ramp. Picked by measurement rather
-- than taste, because it has to answer to two things at once: the terminal
-- ground it is *seen* against, which is the reader's and unknown here, and the
-- ramp steps that have to stay *readable* on it.
--
-- In Oklab it sits 0.207 from the nearest of seven common terminal grounds --
-- black `#000000`, Catppuccin Mocha `#1e1e2e`, One Dark `#282c34`, Gruvbox
-- dark `#282828`, Solarized dark `#002b36`, white `#ffffff`, Solarized light
-- `#fdf6e3` -- 0.242 from the nearest of the sixty-four steps above, and 0.113
-- from the nearest colour this fixture draws elsewhere. The hexes are spelled
-- out because a distance taken against a list of names cannot be re-taken from
-- one: whoever checks this needs the colours, not the flavors.
--
-- The value that was here before, `#241a33`, was 0.02 from Mocha's `#1e1e2e`:
-- a correct background, drawn on every row, and invisible to anyone reading on
-- one.
--
-- A near-neutral colour cannot win that, whatever its lightness, because every
-- terminal ground is near-neutral too and the distance has to come from
-- somewhere. So the candidates were saturated ones, and this is the one whose
-- three numbers above were the largest.
local GROUND = "#8b0045"

-- The second ground, for the renderable column beside that one. Two of them
-- because the padding question is asked twice on the same row -- around a
-- string, and around a nested Line -- and telling which answer is which is
-- the first thing a reader does. They are 0.331 apart, further than either
-- sits from anything named above.
--
-- Against the same three sets: 0.276, 0.250, 0.243, each of them further than
-- `GROUND`'s own 0.207, 0.242 and 0.113. The search maximised the smallest of
-- the three over an RGB grid and refined at the top of it.
--
-- That third set is not decoration. The first search returned `#fe00fe`, and
-- this fixture draws `ext` in `magenta`: what a ground has to stand clear of
-- includes the palette on the same screen, not only the terminals the screen
-- might be read on.
local LINE_GROUND = "#007a00"

-- User columns, registered through the same entry point the built-ins use.
supaline.column("ext", {
	width = 5,
	align = "left",
	style = "magenta",
	render = function(file, ctx) return file.url.ext or "", ctx.style end,
})

-- A one-cell marker. Every built-in is 5 to 12 cells wide and the parent pane
-- is an eighth of the terminal, so none of them can demonstrate a pane there
-- without swallowing the file name; what fits at the edges is a marker.
supaline.column("mark", {
	width = 1,
	align = "left",
	style = "green",
	render = function(file, ctx) return file.cha.is_dir and "d" or "f", ctx.style end,
})

-- Names vary in length, which is what makes the overflow modes legible.
supaline.column("name", {
	width = 12,
	align = "left",
	render = function(file, ctx) return file.name, ctx.style end,
})

-- Where a row sits on the ramp, as a number, so a reader can name a row
-- instead of pointing at one. "The 0.50 row should look halfway between the
-- ends" is a judgement a person can make and report; "the middle one looks off"
-- is not, and that is the difference between a manual test and an impression.
--
-- Its own `stats`, over mtime, because `ctx` is per column: a column cannot
-- read the ratio of the one beside it, and this exists to say what the `mtime`
-- column next to it is doing. The two agree because the value and the scale
-- are the same, not because anything passes between them.
--
-- `supaline.extremes` rather than a loop written here, which is the whole
-- reason it is exported: `builtin.lua` is not a module a user column can
-- require, so without it the only way to get the min/max over a listing is to
-- write it again -- and a second copy drifts from the original, over the
-- flooring below.
--
-- The flooring stays the caller's, because both ends of it are: `builtin.lua`
-- floors an mtime on the way into `extremes` and again before `ctx.ratio`, so
-- this column has to do both too. `e2e.py` asks that a row's two cells land on
-- the same step; the two agree today only because `touch -t` leaves no
-- fractional part, and a fixture built any other way would report its own
-- rounding as a plugin that cannot place a row.
local function mtime_of(file)
	local t = file.cha.mtime
	return t and t > 0 and math.floor(t) or nil
end

supaline.column("ratio", {
	width = 4,
	align = "right",
	stats = supaline.extremes(mtime_of),
	render = function(file, ctx)
		local r = ctx.ratio(mtime_of(file))
		return r and string.format("%.2f", r) or "-", ctx.style_at(r)
	end,
})

-- The same name handed back as a renderable rather than a string, so the cut
-- goes through `Line:truncate` instead of `ui.truncate`. The two count
-- differently, and nothing else here takes that path.
supaline.column("name_line", {
	width = 12,
	align = "left",
	render = function(file, ctx) return ui.Line { ui.Span(file.name) }, ctx.style end,
})

-- --- columns that are wrong on purpose -------------------------------------
-- Every report a broken column can cause, which is six: the four functions a
-- column may write, each throwing, plus the two supaline words itself when a
-- `width` or a `stats` came back with something it cannot use. Not one of them
-- appears unless a column is written to cause it, and until these the only way
-- any had been read was a throwaway configuration written beside the code that
-- emits them -- which says nothing about how one reads against the columns a
-- reader actually has.
--
-- A seventh has no key here and is not a column's: `build` reports a
-- `[supaline]` value supaline refuses, from the `theme` handler, because the
-- user wrote it after `setup` had run. A theme file and a `c` key would reach
-- it, in the shape `c 1` to `c 3` already have.
--
-- They sit on a leader of their own, `b`, and `e2e.py` presses all of it --
-- in a second Yazi with a log of its own, started once the run that is meant
-- to be clean has been torn down. That shape is forced: `report` writes to
-- `yazi.log` as well as to the screen, and `e2e.py` fails the clean run for
-- logging an error at all, so these keys cannot be pressed in it. Two logs
-- rather than one exception.
--
-- Which columns that run expects is read out of *this file*, by a `sed` over
-- the `supaline.column("torn_` lines below. So a seventh registered here
-- turns the suite red until a key for it is pressed there too, and that is
-- the direction the list is meant to grow in. `MANUAL.md` says the same where
-- it says how to add a case.
--
-- One report per column per kind per session, which is the plugin rather than
-- the fixture: `told` marks a column against the kind it was told off for --
-- `stats`, `width`, or a throw from any of the four stages -- and drops every
-- later report of that kind from that column, which is what keeps a per-row
-- failure from redrawing itself once a second for ever. So each key here is
-- worth one look, and pressing it again draws the cells without the sentence.
-- Restart `manual.py` to see one a second time.
--
-- A column each rather than one column with six faults, and the reason is that
-- the throws share a kind rather than that the kinds share a column: `b r`,
-- `b s`, `b w` and `b f` are all "threw", so a column carrying two of them
-- would report whichever happened first and say nothing at all about the
-- other. `b g` and `b u` are their own kinds and would report beside it -- but
-- a column that is wrong in two ways is also one nobody can read a single
-- report against, which is the other half of why these are six.

-- `b r`. A `render` that throws, once per row. The only one of the four that
-- leaves anything on the line: the cell cannot be drawn, so `runtime`
-- fills its width with `!` rather than with spaces, and the columns either
-- side keep their places.
supaline.column("torn_render", {
	width = 6,
	align = "right",
	style = "red",
	render = function() error("this column cannot draw") end,
})

-- `b s`. A `stats` that throws, once per folder. Nothing on the line says so
-- -- the `render` below works and the cells come out as they would have
-- anyway -- which is the whole of why the report has to carry the column's
-- name.
supaline.column("torn_stats", {
	width = 6,
	align = "right",
	style = "red",
	stats = function() error("this column cannot measure a folder") end,
	render = function(file, ctx) return "ok", ctx.style end,
})

-- One function, shared by the two columns below, because what makes that pair
-- worth pressing in turn is that their cells are identical. Two copies of the
-- line would let an edit to one falsify that quietly.
local function dir_or_file(file, ctx) return file.cha.is_dir and "dir" or "file", ctx.style end

-- `b w`. A `width` function that throws. No width is invented in its place, so
-- the column draws unpadded and the row goes ragged: `dir` and `file` differ
-- by one cell, which is what makes that visible at all.
supaline.column("torn_width", {
	width = function() error("this column cannot measure itself") end,
	align = "right",
	style = "red",
	render = dir_or_file,
})

-- `b u`. A `width` function that returns a number nobody can use. The pair
-- worth reading beside `b w`, and why both are here: the cell is identical --
-- ragged, the same two words -- and the sentence is not. One says the reader's
-- function threw and the other says supaline refused what it handed back, and
-- nothing on the screen tells those apart.
supaline.column("torn_zero", {
	width = function() return 0 end,
	align = "right",
	style = "red",
	render = dir_or_file,
})

-- `b g`, read in `colour/ramp`. A `stats` that neither throws nor answers: it
-- comes back carrying no `min` and `max`, so there are no extremes to place a
-- row between and every row draws the ramp's low end. Beside the real `ratio`
-- column on the same ramp, one climbs and one does not -- which is the only
-- way one colour repeated sixty-four times is legible at all.
supaline.column("torn_range", {
	width = 4,
	align = "right",
	style = COOL,
	stats = function() return {} end,
	render = function(file, ctx)
		local r = ctx.ratio(mtime_of(file))
		-- Four dashes rather than one, which is what the real `ratio` column
		-- draws: with no extremes there is no ratio to format, and a single `-`
		-- would leave one cell of colour per row to judge a flat column by.
		return r and string.format("%.2f", r) or "----", ctx.style_at(r)
	end,
})

-- `b f`, armed by `g 6`. The fourth function a column may write, and the only
-- one supaline calls from outside the redraw.
--
-- Two columns, because the sentence that report carries has two halves and
-- neither is legible alone: every other column still refreshes, and this one
-- goes on drawing whatever it had cached. What they cache is a count of their
-- own refreshes, which is the one cached value a reader can check by eye.
--
-- The broken one goes first in the list on purpose. Before the containment
-- landed the throw stopped that loop where it stood and every hook behind it
-- went unrun, so the column worth watching here is the one that is not broken:
-- its count has to go on climbing.
local whole_ticks, torn_ticks = 0, 0

-- Armed by walking into `broken/`, and by nothing else. No linemode key can
-- reach this hook -- it runs at `setup` and again on every `cd`, whichever
-- linemode is showing -- so a hook that threw unconditionally would throw
-- during `e2e.py` as well, and that run fails on a Yazi that logged an error
-- at all. Nothing in it enters this folder.
--
-- `cx` is guarded rather than read outright because this hook also runs from
-- `install`, reached from `init.lua` before there is a manager to ask, and
-- from `fixture_spec.lua`, where the stub has no `current` at all.
local torn_armed = false

supaline.column("torn_tick", {
	width = 3,
	align = "right",
	style = "red",
	refresh = function()
		local cur = cx and cx.active and cx.active.current
		if cur and cur.cwd and tostring(cur.cwd):match("/broken$") then
			torn_armed = true
		end
		if torn_armed then
			error("this column cannot refresh")
		end
		torn_ticks = torn_ticks + 1
	end,
	render = function(file, ctx) return tostring(torn_ticks), ctx.style end,
})

supaline.column("whole_tick", {
	width = 3,
	align = "right",
	style = "green",
	refresh = function() whole_ticks = whole_ticks + 1 end,
	render = function(file, ctx) return tostring(whole_ticks), ctx.style end,
})

-- One list, handed to two panes below.
local EDGE = { "mark" }

supaline:setup {
	-- Every band this fixture draws, because supaline defines none: a marked
	-- colour with no band behind it is refused, so a fixture that said nothing
	-- here would not build. Both names are the pair `colour.lua` recommends,
	-- which is what every number `e2e.py` and `MANUAL.md` assert was measured
	-- at.
	--
	-- The marker is spelled out rather than quoted, for the reason the comment
	-- above `BAND` gives: the second search at the end of this file reads a
	-- line with an arrow in it as a ramp, and the marker has one inside it.
	band = {
		fg = { from = 0.35, to = 0.88 },
		both = { from = 0.35, to = 0.88 },
	},

	linemodes = {
		-- m0: one column, so `m s` is a fair comparison.
		plain = { "size" },

		-- m1: the everyday case, and the one the README opens with.
		default = { "size", "mtime" },

		-- m2: every built-in column at its own default width.
		everything = { "permissions", "owner", "user", "group", "size", "mtime", "count" },

		-- m3: the same value stated, measured, and measured with a cap. The
		-- stated width is deliberately wider than any size in the fixture, so the
		-- measured column beside it is visibly narrower from the first frame.
		widths = {
			{ "size", width = 10 },
			{ "size", width = "auto" },
			{ "owner", width = "auto", max_width = 8 },
		},

		-- m4: one name, four ways. Only the first should show "…", and the two
		-- clipped cells have to come out identical -- one is cut as a string and
		-- the other as a Line.
		overflow = {
			{ "name", overflow = "ellipsis" },
			{ "name", overflow = "clip" },
			{ "name_line", overflow = "clip" },
			{ "name", overflow = "grow" },
		},

		-- m5: the default separator, none at all, and one of your own -- the
		-- last of them in a colour. That is the half no plain-text assertion
		-- can see: the only way to tell a span of its own from a string that
		-- inherited the row's style is to read the escapes.
		seps = {
			{ "ext" },
			{ "size", separator = false },
			{ "mtime", separator = { "│", style = { fg = "#a6e3a1" } } },
		},

		-- m6 to m8: the panes. The difference shows in the left and right
		-- panes, never in the middle one.
		-- `mark`, not `size` and `mtime`: Yazi gives the linemode priority
		-- over the file name, and those two are 19 cells against a parent
		-- pane 21 wide, so the names vanish entirely. What fits at the edges
		-- is a marker, which is what these panes are for.
		pane_cur = { "mark" },
		pane_par = { current = EDGE, parent = EDGE },
		pane_prev = { current = EDGE, preview = EDGE },

		-- m e: the same two panes as m7, each carrying columns of its own.
		-- This is what the width table in the README is about -- the middle
		-- takes what it has room for, the parent takes the marker, and
		-- `preview` is named by nobody, which is how a pane is told to draw
		-- nothing.
		pane_each = {
			current = { "ext", "size" },
			parent = { "mark" },
		},

		-- m9: a registered user column, and an inline function.
		custom = {
			{ "ext" },
			{ "name", width = 8, overflow = "clip" },
			function(file, ctx) return file.cha.is_dir and "dir" or "file", ctx.style end,
		},

		-- The colour cases, `c r` to `c t`. Each is meant to be read in one of
		-- the folders under `colour/`, because the spread of values in the
		-- folder being drawn is what decides which part of a ramp reaches the
		-- screen; `MANUAL.md` says which goes with which.
		--
		-- Five of the six write their colours here rather than taking them
		-- from the theme, and that is the point: a colour written in the spec
		-- wins over `[supaline]`'s, so these hold still while `c 1` to `c 3`
		-- swap the theme underneath them. `c_theme` colours nothing in the spec
		-- and is the one that moves. Two code paths, told apart by pressing a
		-- key.

		-- c r, in `colour/ramp`: one row per ramp step. Both columns carry the
		-- same ramp, so the number and the date are drawn in the same step and
		-- a disagreement between them is visible rather than inferred.
		c_ramp = {
			{ "ratio", style = COOL },
			{ "mtime", style = COOL },
		},

		-- c h, in `colour/ramp`: the same rows, on a ramp that turns in hue.
		-- `e2e.py` reads a ramp per channel, which is a property of one that
		-- climbs in all three at once rather than of ramps in general -- navy to
		-- yellow drops the blue channel on the way through. So this is not
		-- merely a case nothing checks, it is the shape that check cannot be
		-- pointed at without going red on a correct gradient, and a reader is
		-- the only instrument left.
		c_hue = {
			{ "ratio", style = HUE },
			{ "mtime", style = HUE },
		},

		-- c b, in `colour/ramp`: the same rows again, on a ramp with no endpoints
		-- written anywhere -- both of them derived from the one colour in
		-- `BAND`. Beside `c r` it is the pair worth looking at: the same navy,
		-- spread by supaline rather than by hand, and the question a reader is
		-- the only instrument for is whether what it chose is worth drawing.
		c_band = {
			{ "ratio", style = BAND },
			{ "mtime", style = BAND_BY_NAME },
		},

		-- c g, in `colour/ramp`: a ramp over a ground carrying a background,
		-- beside the same ramp over no ground at all -- and `ratio`, which
		-- carries the ramp painted *as* the background, under the row's own
		-- text. `style.build` sets every step on the ground, so the `bg` is
		-- meant to survive under sixty-four colours that know nothing about it;
		-- and `bg` takes a gradient exactly as `fg` does, which is what `ratio`
		-- shows. A theme cannot ask for either -- `themes/bg.toml` is where
		-- that runs out.
		--
		-- An ungrounded column beside the grounded one because the question is
		-- whether the `bg` is still there, and against a single band the only
		-- reference a reader has is their own terminal's ground. That is
		-- unknown from here, and may be the very colour the `bg` carries.
		--
		-- Every stated width is wider than the text under it, so a band has to
		-- cover cells that carry no text. Left at its own width a column is
		-- exactly full on every row and that half of it could not be looked at:
		-- `mtime` is eleven wide in both of the formats it picks between, and
		-- every name in `colour/ramp` is eleven cells too.
		--
		-- `name_line` is here for the one reason nothing else can serve: it
		-- hands back a Line, which `cell` pads by the other of its two routes
		-- -- the comment on `M.cell` in `column.lua` is where those are written
		-- down -- and until this column carried a ground only one route was
		-- ever drawn on one. 16 rather than 14 so a glance can tell the two
		-- bands apart on screen, which is what `manual.py` is for; `e2e.py`
		-- reads each width off this file and does not need them to differ.
		--
		-- A ground and nothing else, where the column above it carries a ramp
		-- too. Not a choice: `name_line` has no `stats`, and `setup` refuses a
		-- gradient on a column that has none -- there would be no extremes to
		-- place a name between, and the ramp could only ever draw its low end.
		-- Watched, on 26.9.1, by writing `fg = COOL` here and reading the
		-- refusal off the screen. What that leaves is the row's own foreground
		-- over the ground, which is `ratio`'s question asked of a renderable.
		c_bg = {
			{ "mtime", style = COOL, width = 14 },
			{ "mtime", style = { fg = COOL, bg = GROUND }, width = 14 },
			{ "name_line", style = { bg = LINE_GROUND }, width = 16 },
			{ "ratio", style = { bg = COOL }, width = 6 },
		},

		-- c a, in `colour/ramp`: a bold over a colour the ramp chose. The same
		-- ratio twice on the same ramp, the left one bold, so the question is
		-- whether one column differs from the other in exactly one way -- which
		-- is a thing a reader can answer and a capture cannot.
		--
		-- `permissions` is the third because it is the only column that paints
		-- its own cell: its ten characters take their colours from the theme's
		-- `[status]` section, and a bold written for the column is patched into
		-- each of those styles rather than replacing any of them. Bold there
		-- with the theme's own reds and greens still on it is the whole claim.
		--
		-- `┊` for the same reason `c_scale` uses it: the two ratio columns hold
		-- the same number and would read as one, and `e2e.py` splits a capture
		-- on `│` to find the current pane.
		c_bold = {
			{ "ratio", style = { fg = COOL, bold = true } },
			{ "ratio", style = COOL, separator = "┊" },
			{ "permissions", style = { bold = true } },
		},

		-- c s, in `colour/scale`: the same size twice, log then linear, on one
		-- ramp. The sizes there double, so log spaces them evenly and linear
		-- collapses everything below the largest few onto the bottom step.
		--
		-- The separator is there because the two columns hold the same number
		-- and would otherwise read as one. It goes on the *second* of them: a
		-- separator is drawn before its own column, so one on the first would
		-- be a separator with nothing on its left, which `setup` refuses.
		--
		-- `┊` rather than the `│` that `m 5` uses, because `e2e.py` splits a
		-- capture line on U+2502 to find the current pane. Nothing reads this
		-- capture that way today; one drawn in a column would take the pane
		-- split with it, and the check would measure half a row without saying
		-- so.
		c_scale = {
			{ "size", scale = "log", style = COOL },
			{ "size", scale = "linear", style = COOL, separator = "┊" },
		},

		-- c e, in `colour/edge`: a ramp with nothing to spread over. Every value
		-- there is the same, so `ratio` answers 1 and every row with a value
		-- draws the *high* end -- not the low one, and not the flat ground.
		--
		-- `size` is in this one and not in `c_ramp` because it is the column
		-- that can have no value at all: a directory has no size, so both of
		-- them draw the *low* end while the files beside them are at the high
		-- one. Both rules on one screen, and no step in between anywhere, which
		-- is what the two of them look like when they are working.
		c_edge = {
			{ "size", style = COOL },
			{ "ratio", style = COOL },
			{ "mtime", style = COOL },
		},

		-- c t, in `data/`: nothing coloured in the spec, so all four take
		-- whatever `[supaline]` says. This is the mode `T` and `c 1` to `c 3`
		-- act on, and the only one that does.
		--
		-- `mtime` alone carries a bold, and no colour: the colour is the
		-- theme's ramp and the weight is the spec's, on the same cell, which is
		-- the case the layers exist for. The ramp moves under `c 1` to `c 3`;
		-- the bold stays.
		c_theme = { "size", { "mtime", style = { bold = true } }, "owner", "ext" },

		-- The broken columns, `b r` to `b f`. Each carries one column that is
		-- wrong on purpose between two that are not, because what has never been
		-- looked at is not the notification on its own -- that was read off a
		-- throwaway configuration while it was being written -- but how it, and
		-- the cell it leaves behind, read against the columns a reader has.
		b_render = { "size", "torn_render", "mtime" },
		b_stats = { "size", "torn_stats", "mtime" },
		b_width = { "size", "torn_width", "mtime" },
		b_zero = { "size", "torn_zero", "mtime" },

		-- Read in `colour/ramp`, where the real `ratio` beside it climbs through
		-- every step. A column stuck at one colour is not something anybody can
		-- see on its own.
		b_range = { { "ratio", style = COOL }, "torn_range", "mtime" },

		-- The broken hook first, so what is on show is the one behind it still
		-- running.
		b_tick = { "size", "torn_tick", "whole_tick", "mtime" },
	},
}
