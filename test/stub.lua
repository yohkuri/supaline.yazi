--- Stubs for the Yazi globals the plugin touches, so the pure logic can run
--- under a plain Lua interpreter.
---
--- These are only worth anything if they behave like the real thing.
--- `ui.truncate` in particular is a line-by-line port of Yazi's own, because
--- the layout code leans on two of its habits: it appends an ellipsis of its
--- own, and it returns *at most* `max` cells. `truncate_spec.lua` pins the port
--- against the assertions in Yazi's own test suite, and pins `Line:truncate`
--- -- which has no upstream test suite to copy -- against what a real Yazi put
--- on screen and against the contract `column.cell` relies on.
---
--- What the stubs cannot cover is exactly what `test/e2e.sh` is for: rendering,
--- fetchers, and `ya.sync`.

-- The stubs deliberately implement only what the plugin touches, so LuaLS
-- comparing them against the full types.yazi declarations is noise.
---@diagnostic disable: missing-fields, missing-return

--- Named so `run.lua` can hand the specs something typed: a global reached
--- through `dofile` is `unknown`, and a spec is then free to read a field off a
--- stub that Yazi has no such field for.
---@class supaline.Stub
local M = {}

-- Captured here rather than inside `install`: that runs once per spec file,
-- and taking `require` from the global there would capture the previous
-- wrapper and nest one more level on every call.
local REAL_REQUIRE = require

-- --- Unicode ---------------------------------------------------------------

--- Iterate the UTF-8 characters of `s` as (byte index, character), the byte
--- index being 0-based to mirror the Rust this mirrors.
---@param s string
---@return function
local function chars(s)
	local i = 1
	return function()
		if i > #s then
			return nil
		end
		local ch = s:match("^[^\128-\191][\128-\191]*", i)
		local at = i - 1
		i = i + #ch
		return at, ch
	end
end

---@param ch string one UTF-8 character
---@return integer
local function codepoint(ch)
	local b1 = ch:byte(1)
	if #ch == 1 then
		return b1
	elseif #ch == 2 then
		return (b1 - 192) * 64 + (ch:byte(2) - 128)
	elseif #ch == 3 then
		return (b1 - 224) * 4096 + (ch:byte(2) - 128) * 64 + (ch:byte(3) - 128)
	end
	return (b1 - 240) * 262144 + (ch:byte(2) - 128) * 4096 + (ch:byte(3) - 128) * 64 + (ch:byte(4) - 128)
end

-- The East Asian Wide and Fullwidth blocks, plus emoji presentation, which is
-- as much of `unicode-width` as anything here needs. The emoji spans are
-- coarser than the real property -- a handful of text-presentation symbols
-- inside them are one cell -- but a file name that carries an emoji carries a
-- two-cell one, and the fixture has such a name on purpose.
local WIDE = {
	{ 0x1100, 0x115F },
	{ 0x2E80, 0x303E },
	{ 0x3041, 0x33FF },
	{ 0x3400, 0x4DBF },
	{ 0x4E00, 0x9FFF },
	{ 0xA000, 0xA4CF },
	{ 0xAC00, 0xD7A3 },
	{ 0xF900, 0xFAFF },
	{ 0xFE30, 0xFE6F },
	{ 0xFF00, 0xFF60 },
	{ 0xFFE0, 0xFFE6 },
	{ 0x20000, 0x3FFFD },
	{ 0x1F004, 0x1F004 },
	{ 0x1F0CF, 0x1F0CF },
	{ 0x1F18E, 0x1F18E },
	{ 0x1F191, 0x1F19A },
	{ 0x1F200, 0x1F2FF },
	{ 0x1F300, 0x1F64F },
	{ 0x1F680, 0x1F6FF },
	{ 0x1F7E0, 0x1F7EB },
	{ 0x1F900, 0x1F9FF },
	{ 0x1FA70, 0x1FAFF },
}

-- The combining marks, the zero-width characters -- the joiner among them --
-- and the variation selectors. `unicode-width` gives each of them no cells of
-- its own, which is the half of the rule that makes a cluster wider than the
-- characters in it.
local ZERO = {
	{ 0x0300, 0x036F },
	{ 0x200B, 0x200F },
	{ 0xFE00, 0xFE0F },
}

local ZWJ, VS16 = 0x200D, 0xFE0F

---@param cp integer
---@param ranges table
---@return boolean
local function within(cp, ranges)
	for _, range in ipairs(ranges) do
		if cp >= range[1] and cp <= range[2] then
			return true
		end
	end
	return false
end

--- The width of one character on its own -- `char.width()` in Rust, which is
--- what both of Yazi's truncations count with, one character at a time.
---@param ch string
---@return integer
local function char_width(ch)
	local cp = codepoint(ch)
	if within(cp, ZERO) then
		return 0
	elseif within(cp, WIDE) then
		return 2
	end
	return 1
end

--- What the truncations count: the characters' own widths, added up.
---@param s string
---@return integer
local function cp_width(s)
	local w = 0
	for _, ch in chars(s) do
		w = w + char_width(ch)
	end
	return w
end

--- What `ui.width` and `Line:width` return: the width of the *string*, which
--- is not the sum above. A variation selector widens the character before it,
--- and a joiner or a skin-tone modifier folds what follows into it. Measured
--- on Yazi 26.9.1: `❤` is one cell, the selector after it is none, and `❤️` is
--- two; `👩‍💻` and `👍🏽` are two apiece where their characters add up to four.
---
--- The two disagreeing is not a detail of the model. It is the reason
--- `column.lua` cuts on cluster boundaries, and a stub that added characters
--- up here would let that be deleted with the suite still green.
---@param s string
---@return integer
local function str_width(s)
	local w, prev, joined = 0, nil, false
	for _, ch in chars(s) do
		local cp = codepoint(ch)
		if cp == VS16 then
			-- Emoji presentation: the character before it takes a second cell.
			w = w + (prev and char_width(prev) == 1 and 1 or 0)
		elseif cp == ZWJ then
			joined = true
		elseif joined then
			-- Only an emoji folds into the one the joiner came from. `👩‍💻` is one
			-- two-cell character; `👩‍…`, which is what a truncation right after a
			-- joiner leaves, is three cells.
			joined = false
			w = w + (cp >= 0x1F000 and char_width(ch) == 2 and 0 or char_width(ch))
		elseif prev and cp >= 0x1F3FB and cp <= 0x1F3FF then
			-- A skin-tone modifier, behind the emoji it recolours.
		else
			w = w + char_width(ch)
		end
		prev = ch
	end
	return w
end

M.cp_width = cp_width
M.str_width = str_width

-- --- ui.truncate -----------------------------------------------------------

---@param s string
---@param at integer 0-based byte index
---@return string
local function char_at(s, at) return s:match("^[^\128-\191][\128-\191]*", at + 1) end

--- A port of `Utils::truncate` from `yazi-plugin/src/ui/utils.rs`.
---@param s string
---@param opts table `{ max: integer, rtl: boolean? }`
---@return string
local function truncate(s, opts)
	local max = opts.max
	if #s == 0 then
		return s
	elseif #s <= max then
		return s
	elseif max < 1 then
		return ""
	end

	local seq = {}
	for at, ch in chars(s) do
		seq[#seq + 1] = { at, ch }
	end
	if opts.rtl then
		for i = 1, math.floor(#seq / 2) do
			seq[i], seq[#seq - i + 1] = seq[#seq - i + 1], seq[i]
		end
	end

	-- `take_while` evaluates its predicate on the first failing element too, so
	-- `last` advances one step further than `idx` does.
	local adv, last, idx = 0, 0, nil
	for _, c in ipairs(seq) do
		last, adv = adv, adv + char_width(c[2])
		if adv > max then
			break
		end
		idx = c[1]
	end

	if idx == nil then
		return "…"
	elseif adv <= max then
		return s
	end

	if not opts.rtl then
		if last == max then
			return s:sub(1, idx) .. "…"
		end
		return s:sub(1, idx + #char_at(s, idx)) .. "…"
	elseif last == max then
		return "…" .. s:sub(idx + #char_at(s, idx) + 1)
	end
	return "…" .. s:sub(idx + 1)
end

M.truncate = truncate

-- --- ui elements -----------------------------------------------------------

local Style = {}
Style.__index = Style

--- Immutable, as Yazi's has been since 26.5.6: every setter returns a new one.
local function new_style(t)
	local s = setmetatable({}, Style)
	for k, v in pairs(t or {}) do
		s[k] = v
	end
	return s
end

-- What a real `ui.Style():fg` took on 26.9.1, measured by handing it every
-- combination below and reading back which raised `Failed to parse Colors`.
--
-- Ten names, each also spelled `light`, `light-`, `bright` and `bright-`; a
-- `dark` prefix for the greys **only**, so `darkgray` resolves and `darkred`
-- does not; `reset`, but neither `default` nor `none`; no `purple` in any
-- form; and the whole lookup case-insensitive, so `RED` is a colour. Beside
-- the names: `#rrggbb`, and a decimal index from "0" to "255" -- while `#rgb`,
-- `#rrggbbaa`, `""`, `"256"`, `rgb(1,2,3)` and `indexed(5)` are all refused.
--
-- Refused here rather than waved through, because the plugin now decides what
-- a colour is before Yazi sees it: a stub that took anything would let a spec
-- assert an error message the plugin never had to produce.
local NAMED = { reset = true }
for _, name in ipairs { "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white", "gray", "grey" } do
	for _, form in ipairs { "%s", "light%s", "light-%s", "bright%s", "bright-%s" } do
		NAMED[form:format(name)] = true
	end
end
NAMED.darkgray, NAMED["dark-gray"], NAMED.darkgrey, NAMED["dark-grey"] = true, true, true, true

--- What Yazi's own parser takes. A colour it refuses raises there, so it raises
--- here.
---@param value any
---@return boolean
local function is_colour(value)
	if type(value) ~= "string" then
		return false
	elseif value:find("^#%x%x%x%x%x%x$") then
		return true
	elseif NAMED[value:lower()] then
		return true
	end
	local n = value:match("^%d+$") and tonumber(value)
	return n ~= nil and n <= 255
end

for _, key in ipairs { "fg", "bg" } do
	Style[key] = function(self, value)
		-- Yazi returns nil for `fg(nil)` and `fg(true)` rather than raising --
		-- measured -- and the caller then indexes nil somewhere else entirely.
		-- One of the silences the stub is here to break.
		if not is_colour(value) then
			error(string.format("stub: `%s` is not a colour Yazi would accept: %s", key, tostring(value)))
		end
		local s = new_style(self)
		s[key] = value
		return s
	end
end

--- Merge `other` over a copy of this style. Measured on 26.9.1 by drawing all
--- four combinations through a linemode and reading the SGR back out of
--- `tmux capture-pane -e`: what `other` sets wins, what it leaves alone is kept
--- -- `fg red + bold` patched with `bg green + italic` draws bold, italic, red
--- on green -- an empty patch changes nothing, and the receiver is not
--- modified.
function Style:patch(other)
	if other ~= nil and getmetatable(other) ~= Style then
		error("stub: `patch` takes a Style or nil, as Yazi's does")
	end
	local s = new_style(self)
	for k, v in pairs(other or {}) do
		s[k] = v
	end
	return s
end
-- Every attribute 26.9.1's `ui.Style` has, named as the API names them --
-- `reverse`, where the theme key for the same effect is `reversed`. A stub
-- missing one would refuse a style the plugin is entitled to build, and it
-- would refuse it as `attempt to call a nil value`.
--
-- The argument is `remove`, not the value: `bold()` and `bold(false)` both add
-- the attribute and `bold(true)` takes it off. Read off
-- `yazi-binding/src/style/style.rs` and measured through `Style:raw()` on
-- 26.9.1 -- `ui.Style():bold(true)` comes back `{ bold = false }`. So the
-- field holds the three states `StyleFlat` holds: nil where nothing was said,
-- `true` for the attribute added, `false` for it removed. A stub that stored
-- the argument itself would read `bold(true)` as bold and let a plugin
-- building a removal pass while a real Yazi stripped the attribute instead.
local ATTRS = {
	"bold",
	"dim",
	"italic",
	"underline",
	"blink",
	"blink_rapid",
	"reverse",
	"hidden",
	"crossed",
}
for _, key in ipairs(ATTRS) do
	Style[key] = function(self, remove)
		local s = new_style(self)
		s[key] = not remove
		return s
	end
end

-- How Yazi spells a colour it hands back. `raw()` serialises the colour
-- through ratatui's `Display`, which capitalises a name and uppercases a hex,
-- and `fg()` parses it back through `FromStr`, which lowercases, strips
-- spaces, hyphens and underscores, and folds `bright` into `light`, `grey`
-- into `gray`, `light black` into `dark gray` and `light white` into `white`
-- -- so every spelling that goes in comes out as one of these, and every one
-- of these goes back in. Measured on 26.9.1 for `reset`, `cyan`, `bright-red`,
-- `darkgray`, `bright-black`, `bright-white` and `light-blue`, the hex
-- `#ff8800` and the index `129`; the rest of the table is read off
-- `ratatui-core/src/style/color.rs` at the revision Yazi 26.9.1 builds
-- against. `probes.md` holds the run.
local DISPLAY = {
	reset = "Reset",
	black = "Black",
	red = "Red",
	green = "Green",
	yellow = "Yellow",
	blue = "Blue",
	magenta = "Magenta",
	cyan = "Cyan",
	gray = "Gray",
	darkgray = "DarkGray",
	lightred = "LightRed",
	lightgreen = "LightGreen",
	lightyellow = "LightYellow",
	lightblue = "LightBlue",
	lightmagenta = "LightMagenta",
	lightcyan = "LightCyan",
	white = "White",
}

---@param colour string as it was handed to `fg` or `bg`
---@return string as `raw()` hands it back
local function display_of(colour)
	if colour:find("^#") then
		return colour:upper()
	elseif colour:find("^%d+$") then
		return colour
	end
	local key = colour:lower():gsub("[ %-_]", ""):gsub("bright", "light"):gsub("grey", "gray")
	key = key:gsub("^lightblack$", "darkgray"):gsub("^lightwhite$", "white"):gsub("^lightgray$", "white")
	return DISPLAY[key] or error("stub: no Display spelling for the colour " .. colour)
end

--- The plain table Yazi's `raw()` answers with: `fg` and `bg` as the strings
--- above, each attribute under the *theme's* key -- `reversed`, where the
--- method is `reverse` -- as the boolean the field holds, and nothing at all
--- for a key nobody set. `ui.Style()` answers `{}`. Measured on 26.9.1 and
--- pinned by `colour_spec.lua`, because `colour.lua` reads a themed style
--- through this and nothing else could tell it what the keys are.
---@return table
function Style:raw()
	local out = {}
	-- `rawget`: `Style.fg` is the setter, so a style holding no colour answers
	-- `self.fg` with a function.
	for _, key in ipairs { "fg", "bg" } do
		local v = rawget(self, key)
		if v ~= nil then
			out[key] = display_of(v)
		end
	end
	for _, key in ipairs(ATTRS) do
		local v = rawget(self, key)
		if v ~= nil then
			out[key == "reverse" and "reversed" or key] = v
		end
	end
	return out
end

local Span = {}
Span.__index = Span
function Span:style(s)
	self._style = s
	return self
end

local Line = {}
Line.__index = Line

--- Every Span and Line already handed to a `ui.Line`, weakly held so a row
--- that has been drawn and dropped does not keep its spans alive.
local taken = setmetatable({}, { __mode = "k" })

--- The plain text of anything renderable, which is all the assertions need.
---@param x any
---@return string
local function text_of(x)
	if x == nil then
		return ""
	elseif type(x) == "string" then
		return x
	elseif getmetatable(x) == Span then
		return x._text
	elseif getmetatable(x) == Line then
		local out = {}
		for _, part in ipairs(x._parts) do
			out[#out + 1] = text_of(part)
		end
		return table.concat(out)
	end
	error("not renderable: " .. type(x))
end

M.text_of = text_of

--- The style attached to a Span, so a test can check what colour a column
--- asked for.
---@param x any
---@return table?
function M.style_of(x) return getmetatable(x) == Span and x._style or nil end

--- The style each leaf of a renderable is drawn in, in order -- a Span's own
--- patched over every Line's around it, `false` where nothing styles it.
---
--- The order is Yazi's: a Line's style sits *under* its spans, so a span's
--- `fg` wins and a `bold` the Line carries reaches every span that did not
--- say otherwise. Read off `yazi-binding/src/elements/line.rs` at 26.9.1,
--- where a Line taken into another has `line.style.patch(s.style)` set on
--- each of its spans, and off ratatui's `Cell::set_style`, which patches a
--- span's style over what the line put in the cell. `test/e2e.sh` sees it on
--- screen: a bold written for `permissions` opens a run of characters in
--- colours of their own.
---@param x any
---@return table[]
function M.drawn_styles(x)
	local out = {}
	local function walk(part, under)
		if getmetatable(part) == Line then
			local base = under
			if part._style then
				base = base and base:patch(part._style) or part._style
			end
			for _, sub in ipairs(part._parts) do
				walk(sub, base)
			end
		elseif getmetatable(part) == Span then
			local own = part._style
			if under then
				own = own and under:patch(own) or under
			end
			out[#out + 1] = own or false
		else
			out[#out + 1] = under or false
		end
	end
	walk(x, nil)
	return out
end

--- The first style found anywhere inside a renderable, for asserting on what a
--- linemode came back with without unpicking its structure.
---@param x any
---@return table?
function M.first_style(x)
	local own = M.style_of(x)
	if own then
		return own
	elseif type(x) == "table" and x._parts then
		for _, part in ipairs(x._parts) do
			local found = M.first_style(part)
			if found then
				return found
			end
		end
	end
	return nil
end

--- Measured part by part and added up, the way Yazi's own does, rather than
--- over the parts joined into one string. The two disagree wherever a cluster
--- straddles a part boundary: measured on 26.9.1,
--- `ui.Line { ui.Span("\u{2764}"), ui.Span("\u{FE0F}") }` is **one** cell --
--- a heart, plus a variation selector that measures nothing on its own --
--- where the joined string is two. A column handing back several spans would
--- otherwise have its width and its padding checked against a number the
--- screen never shows.
local function part_width(part)
	if getmetatable(part) ~= Line then
		return str_width(text_of(part))
	end
	local w = 0
	for _, sub in ipairs(part._parts) do
		w = w + part_width(sub)
	end
	return w
end

function Line:width() return part_width(self) end
function Line:visible() return self:width() > 0 end
function Line:style(s)
	self._style = s
	return self
end

--- Keep the first `bytes` bytes of a part list, part boundaries intact. Only
--- the part the cut lands inside is rebuilt; the ones before it are kept by
--- reference, and a Span keeps its style.
---@param parts table
---@param bytes integer
---@return table
local function keep_bytes(parts, bytes)
	local out = {}
	for _, part in ipairs(parts) do
		if bytes <= 0 then
			break
		end
		local text = text_of(part)
		if #text <= bytes then
			out[#out + 1] = part
			bytes = bytes - #text
		elseif getmetatable(part) == Line then
			out[#out + 1] = setmetatable({ _parts = keep_bytes(part._parts, bytes), _style = part._style }, Line)
			bytes = 0
		elseif getmetatable(part) == Span then
			out[#out + 1] = setmetatable({ _text = text:sub(1, bytes), _style = part._style }, Span)
			bytes = 0
		else
			out[#out + 1] = text:sub(1, bytes)
			bytes = 0
		end
	end
	return out
end

--- A port of `Line::truncate` from `yazi-binding/src/elements/line.rs`, its
--- three surprises included, because `column.cell` exists to correct the first
--- two:
---
---   * it holds back the ellipsis's width and then drops the character that
---     lands exactly on `max` as well, so an empty ellipsis still costs an
---     ASCII line one cell;
---   * it counts characters while the width is counted in cells, so a line it
---     thinks fits can come back wider than `max`;
---   * it **modifies the line it was given** and hands that same line back,
---     rather than building a new one. `cut` in `column.lua` says so and
---     relies on it; a column holding on to a renderable across rows would
---     find it cut down by the first row that overflowed.
---
--- Reproduced rather than repaired: a stub that quietly did the right thing
--- would let the correction be deleted with every test still green.
---
--- The cut keeps the part boundaries, which is what makes the width above come
--- out right afterwards: measured on 26.9.1,
--- `ui.Line { ui.Span("\u{2764}"), ui.Span("\u{FE0F}"), ui.Span("abcdef") }`
--- cut to four is three cells, and the same characters in one span are four.
--- Each part keeps its own style through the cut, the one the cut lands inside
--- included -- measured by drawing a two-colour line and reading the colours
--- back off the screen, since two lines of equal width cannot be told apart
--- any other way.
function Line:truncate(opts)
	local max = opts.max
	if max < 1 then
		self._parts = {}
		return self
	end

	local ellipsis = opts.ellipsis == nil and "…" or opts.ellipsis
	local text = text_of(self)
	-- Yazi truncates the ellipsis to `max` first and reserves what is left of
	-- it, so an ellipsis wider than the column cannot reserve more than one.
	local threshold = max - math.min(cp_width(ellipsis), max)

	-- `at` is the last position whose running width still fits the threshold,
	-- and `fits` its width there.
	local adv, at, fits = 0, nil, nil
	for i, ch in chars(text) do
		adv = adv + char_width(ch)
		if adv <= threshold then
			at, fits = i, adv
		elseif adv > max then
			break
		end
	end

	if at == nil then
		self._parts = { ellipsis }
		return self
	elseif adv <= max then
		return self -- it fits, by its own reckoning, and is left alone
	end

	-- The character the cut lands on is kept, unless it ends exactly on `max`.
	local len = fits == max and 0 or #char_at(text, at)
	local kept = keep_bytes(self._parts, at + len)
	if ellipsis ~= "" then
		kept[#kept + 1] = ellipsis
	end
	self._parts = kept
	return self
end

--- Yazi **moves** a Span or a Line into the Line it is put in, so the value is
--- gone from Lua's side and handing it over a second time raises
--- `bad argument #2: expected a string, Span, Line, or a table of them`.
--- Measured on 26.9.1 for a span and a line alike, in a table and bare;
--- `Span:style` does not consume, and the same span can be styled twice.
---
--- Loud here for the reason every other divergence in this file is loud.
--- Yazi's own message reaches nobody -- a linemode that raises stops drawing
--- the pane, and the traceback goes to `yazi.log` alone -- while a stub that
--- let one span be drawn twice would make caching a built list of them look
--- correct, and that cache is exactly what a column drawing a character at a
--- time invites.
---@param part any
---@return any
local function take(part)
	local mt = getmetatable(part)
	if mt ~= Span and mt ~= Line then
		return part
	elseif taken[part] then
		error(
			string.format(
				"stub: this %s has already been put in a Line. Yazi moves it rather than copying "
					.. "it, so build the spans fresh for each row and cache the styles instead",
				mt == Span and "Span" or "Line"
			)
		)
	end
	taken[part] = true
	return part
end

--- A Line that is handed a Line is not given it back: measured on 26.9.1,
--- `ui.Line(line)` succeeds once and the same line offered a second time
--- raises `expected a string, Span, Line, or a table of them`, the refusal a
--- reused Span gets. So a bare Line is consumed and wrapped like any other
--- part, and the wrapper that comes back is a Line of its own, which a further
--- `ui.Line` may consume in turn -- also measured.
---
--- Handing it straight back is what this did until a review caught it, and the
--- cost was the whole point of the check: `column.cell` calls `ui.Line(out)`
--- on whatever a render returns, so a column caching one finished Line was
--- green here and blanked the pane on the second row.
function M.Line(x)
	local mt = getmetatable(x)
	local parts = x
	if type(x) ~= "table" or mt == Span or mt == Line then
		parts = { x }
	end
	for _, part in ipairs(parts) do
		take(part)
	end
	return setmetatable({ _parts = parts }, Line)
end

function M.Span(text) return setmetatable({ _text = text }, Span) end

-- --- fixtures --------------------------------------------------------------

-- Yazi's `AuthKind`, and which side of `is_local()` each variant falls on.
-- Written out rather than derived from a pair of comparisons, because the
-- partition is the claim being made about Yazi: a typo in a spec's `url_kind`
-- would otherwise pass as virtual and make a test succeed for the wrong
-- reason. `auth_spec.lua` pins all six.

--- Every DDS kind Yazi publishes, and so every kind `ps.sub` can be given
--- that will ever fire.
---
--- The names come from `pub_after!` in `yazi-dds/src/pubsub.rs`, plus one that
--- does not: `bulk-rename` is published by a hand-written
--- `pub_after_bulk_rename` beside the macro, so reading the macro alone misses
--- it. A `@` name is a static event -- `@yank` is the only one.
M.DDS_KINDS = {}
for _, kind in ipairs {
	"tab",
	"cd",
	"load",
	"hover",
	"rename",
	"@yank",
	"duplicate",
	"move",
	"trash",
	"delete",
	"download",
	"input",
	"mount",
	"theme",
	"bulk-rename",
} do
	M.DDS_KINDS[kind] = true
end

M.AUTH_KINDS = {
	regular = { is_regular = true, is_search = false, is_virtual = false },
	search = { is_regular = false, is_search = true, is_virtual = false },
	mount = { is_regular = false, is_search = false, is_virtual = true },
	hub = { is_regular = false, is_search = false, is_virtual = true },
	scope = { is_regular = false, is_search = false, is_virtual = true },
	sftp = { is_regular = false, is_search = false, is_virtual = true },
}

--- The `Url.spec` of a file whose URL has the given `AuthKind`.
---@param kind string
---@return table
function M.spec_of(kind)
	local flags = M.AUTH_KINDS[kind] or error("stub: no such AuthKind: " .. tostring(kind))
	return {
		kind = kind,
		is_regular = flags.is_regular,
		is_search = flags.is_search,
		is_virtual = flags.is_virtual,
	}
end

--- One of `Cha`'s two owner ids, as Yazi would have handed it over -- or a
--- refusal, for a value Yazi cannot produce.
---
--- Numbers, always. Yazi's `Cha` carries `uid` and `gid` as `u32` rather than
--- `Option<u32>`, filling them with the `0` of `unix_either!(m.uid(), 0)` on a
--- platform that has neither, so Lua is never handed a nil here and a column
--- cannot ask "does this file have an owner". A stub that left them nil let a
--- `not cha.uid` guard look like the Windows case while Yazi was reaching the
--- branch below it and drawing `0:0`.
---
--- `nil or 0` was the whole of it until this raised as well, which is half a
--- stub: it stopped a spec seeing a nil, and passed anything else through
--- untouched. `uid = "root"` reached `ya.user_name` and came back `userroot`,
--- green, describing a file no Yazi has ever produced -- the silence this
--- harness is supposed to break rather than reproduce.
---@param t table
---@param field "uid"|"gid"
---@return integer
local function id_of(t, field)
	local v = t[field]
	if v == nil then
		return 0
	elseif math.type(v) ~= "integer" or v < 0 or v > 0xffffffff then
		error(
			string.format(
				"stub: `%s` is a `u32` in Yazi's `Cha`, so it takes a whole number in "
					.. "[0, 2^32); got %s. Leave it out for the `0` Yazi fills in where a "
					.. "platform has no owner.",
				field,
				tostring(v)
			)
		)
	end
	return v
end

--- The ten positions `ChaMode::permissions` writes, and the dummy it leaves
--- alone. Read off `yazi-fs/src/cha/mode.rs` at 26.9.1, which starts from a
--- fixed `-?????????` and overwrites it: a type character from `dlbcsp-`, then
--- `r` and `w` where the bit is set, and an execute bit that carries the
--- setuid, setgid or sticky bit folded into it as `s`, `S`, `t` or `T`. Where
--- the `Cha` was never stat-ed the function returns after the type character,
--- so the nine `?` are the whole of the rest and never mixed in among letters.
local PERM_REAL = "^[dlbcsp%-][r%-][w%-][xsS%-][r%-][w%-][xsS%-][r%-][w%-][xtT%-]$"
local PERM_DUMMY = "^[dlbcsp%-]" .. ("%?"):rep(9) .. "$"

--- A file's permission string, as Yazi would have handed it over -- or a
--- refusal, for a string Yazi cannot produce.
---
--- nil is the one value that is not an error, and is the platform rather than
--- the file: `Cha:perm` is `Ok(Value::Nil)` under `#[cfg(windows)]` and ten
--- bytes under `#[cfg(unix)]`, never an empty string and never a short one. So
--- leaving the field out is how a spec asks for a build with no permissions to
--- name, which is what `builtin.lua` spells `cha:perm() or ""`.
---
--- Everything else is gated because the column will not notice. `perm_spans`
--- walks the string a character at a time and falls back to `PERM_TYPE` for
--- anything it does not know, so `perm = "nope"` renders four spans and a spec
--- asserting on them passes, describing a file no Yazi has ever produced --
--- the same silence `id_of` above was written to break, one field over.
---@param t table
---@return string?
local function perm_of(t)
	local v = t.perm
	if v == nil then
		return nil
	elseif type(v) ~= "string" or not (v:match(PERM_REAL) or v:match(PERM_DUMMY)) then
		error(
			string.format(
				"stub: `perm` is what `Cha:perm` answers, so it takes a ten-character "
					.. "string -- a type character from `dlbcsp-`, then either nine `?` for "
					.. "a `Cha` Yazi could not stat or `rwx` per position, with `s`, `S`, "
					.. "`t` or `T` where a bit is folded into the execute one; got %s. Leave "
					.. "it out for the nil Yazi answers where a platform has no permissions.",
				type(v) == "string" and string.format("%q", v) or tostring(v)
			)
		)
	end
	return v
end

--- A stand-in for `fs::File`. Everything the built-in columns read is either
--- passed in or defaulted to something harmless.
---
--- Claiming `supaline.File` rather than `table` is what puts the specs under
--- the same type check the plugin is under: a spec reaching for a field Yazi
--- does not have is refused here too. It says nothing about the stub itself --
--- the class is not `(exact)`, so the table below is accepted however little
--- of it is filled in -- and fidelity is still read against a running Yazi.
---@param t table
---@return supaline.File
function M.file(t)
	local name = t.name or "file.txt"
	--- The `AuthKind` of the file's URL: `regular`, `search`, `mount`, `hub`,
	--- `scope` or `sftp`.
	local kind = t.url_kind or "regular"
	-- Read now rather than inside the closure below, so a string Yazi could
	-- not have produced is refused at the `stub.file` that wrote it rather
	-- than at whichever render first reaches for it.
	local perm = perm_of(t)
	local file = {
		name = name,
		in_current = t.in_current == nil and true or t.in_current,
		is_hovered = t.is_hovered or false,
		-- `idx` is the row's 1-based position in its own folder. `M.folder`
		-- overwrites it, so a file placed in one always agrees with it.
		idx = t.idx or 1,
		-- `in_preview` is deliberately absent here and computed below: Yazi
		-- derives it per read, and a stub that stored a flag would let the
		-- plugin trust it.
		url = {
			ext = name:match("%.([^.]+)$"),
			-- Yazi's `Url.spec`, from the `AuthKind` table above rather than
			-- from a flag the caller hands in: `regular` and `search` are
			-- local and everything else is virtual, so a search result keeps
			-- its owner names and an `sftp` file does not. A stub that took
			-- the flag directly would let a column key on `is_regular` --
			-- which is false for a search result too -- and still pass.
			spec = M.spec_of(kind),
		},
		cha = {
			is_dir = t.is_dir or false,
			mtime = t.mtime,
			btime = t.btime,
			atime = t.atime,
			uid = id_of(t, "uid"),
			gid = id_of(t, "gid"),
			perm = function() return perm end,
		},
		size = function() return t.size end,
	}
	setmetatable(file.url, { __tostring = function() return "/tmp/" .. name end })
	-- Yazi computes `in_preview` on every read as
	--
	--     me.idx == me.folder.cursor && tab.hovered() is this folder
	--
	-- so it is true for the previewed folder's cursor row and false for every
	-- other row of the same pane. Reproduce that exactly: a stub that instead
	-- flagged the whole pane would let the plugin read it as the counterpart
	-- of `in_current`, which is the bug this fidelity exists to catch.
	setmetatable(file, {
		__index = function(_, k)
			if k ~= "in_preview" then
				return nil
			end
			local folder = cx.active.preview and cx.active.preview.folder
			return folder ~= nil and folder.files[folder.cursor] == file
		end,
	})
	return file
end

--- Fire every handler subscribed to a DDS event, in subscription order. One
--- way to say it, rather than reaching into `M.subs` by index -- which quietly
--- does nothing the day the subscription order changes.
---@param kind string
function M.fire(kind)
	for _, fn in ipairs(M.subs[kind] or {}) do
		fn()
	end
end

--- A stand-in for a folder, with a `cwd` that stringifies and a file list.
---
--- Claims `supaline.Folder` for the reason `M.file` claims `supaline.File`:
--- it is what puts a spec's reads under the same check the plugin's are.
---@param cwd string
---@param files supaline.File[]
---@param cursor integer? the hovered row, 1-based; the first by default
---@return supaline.Folder
function M.folder(cwd, files, cursor)
	for i = 1, #files do
		files[i].idx = i
	end
	return {
		cwd = setmetatable({}, { __tostring = function() return cwd end }),
		files = files,
		cursor = cursor or 1,
	}
end

-- --- installation ----------------------------------------------------------

--- Put the stubs in place as globals, and teach `require` Yazi's relative
--- form so `require(".column")` finds `column.lua` next to it.
---@param root string repository root
function M.install(root)
	_G.ui = {
		Line = M.Line,
		Span = M.Span,
		-- A callable table rather than a function, because that is what Yazi
		-- has: measured on 26.9.1, `type(ui.Style)` is `table` and only
		-- `ui.Style()` is userdata. It matters now that `base` branches on
		-- `type`: written as a plain function here, a `base = ui.Style` with
		-- the call forgotten would be called for its colour and come back an
		-- empty style, where Yazi refuses the table outright.
		Style = setmetatable({}, { __call = function() return new_style {} end }),
		truncate = truncate,
		width = function(x) return str_width(text_of(x)) end,
		render = function() end,
	}

	-- One table, because 26.9.1 has one state by the time the plugin draws
	-- anything. `theme.toml` is merged before any plugin code runs, so
	-- `th.supaline` and a `[mgr]` override alike are readable from the first
	-- line of `init.lua`. Measured, not assumed -- a `[mgr] cwd` captured at
	-- load time paints the user's colour, and a `Style` read out of `th` is a
	-- value frozen at that moment, not a handle that follows later reloads.
	--
	-- The flavor is *not* there that early: a field only the flavor supplies
	-- holds Yazi's preset while `init.lua` runs and reaches its real value with
	-- an unasked `theme` event a few milliseconds later. One table is still
	-- right, because nothing here models a startup -- a spec that cares writes
	-- the preset, then writes the flavor's value and calls `fire("theme")`.
	--
	-- What a test writes here is what the plugin can already see.
	--
	-- What survives is the reload: `app:theme` re-reads `theme.toml` from disk
	-- mid-run, so a colour resolved once and cached goes stale with nothing to
	-- say so. Write the new section here and `fire("theme")` to reproduce it.
	M.th = {}
	_G.th = setmetatable({}, {
		__index = function(_, k) return M.th[k] end,
		__newindex = function(_, k) error("stub: write to `stub.th`, not `th." .. tostring(k) .. "`") end,
	})
	_G.ya = {
		readable_size = function(size)
			local units = { "B", "K", "M", "G", "T", "P", "E", "Z", "Y", "R", "Q" }
			local i = 1
			while size > 1024 and i < #units do
				size = size / 1024
				i = i + 1
			end
			local s = string.format("%.1f%s", size, units[i]):gsub("[.,]0", "", 1)
			return s
		end,
		user_name = function(uid) return "user" .. tostring(uid) end,
		group_name = function(gid) return "group" .. tostring(gid) end,
		dbg = function() end,
		err = function() end,
		-- Recorded rather than dropped, because this is the plugin's only way
		-- to put anything in front of a user from a `ps.sub` handler -- there
		-- is nobody to raise to there -- and a spec has to be able to say the
		-- message was delivered. `title` and `content` are asserted on;
		-- `timeout` and `level` are Yazi's to draw.
		--
		-- Refused when it is not shaped the way 26.9.1 wants it. Yazi takes one
		-- table and reads four fields off it, and a call written as
		-- `ya.notify(title, body)` would go through a stub that only stored its
		-- first argument.
		notify = function(opts)
			if type(opts) ~= "table" or type(opts.title) ~= "string" or type(opts.content) ~= "string" then
				error("stub: `ya.notify` takes one table with `title` and `content`, as Yazi's does")
			end
			table.insert(M.notified, opts)
		end,
	}
	M.notified = {}

	M.subs = {}
	_G.ps = {
		-- Yazi's own `ps.sub` takes any string and returns without
		-- complaining, so a stale kind is a subscription that simply never
		-- fires: no error, no warning, nothing on screen. This one refuses
		-- instead. It is the same deliberate divergence `spec_of` makes for
		-- `AuthKind` -- a stub that reproduces a silent failure lets a test
		-- pass while the plugin is dead.
		sub = function(kind, fn)
			if not M.DDS_KINDS[kind] then
				error("stub: no such DDS kind: " .. tostring(kind))
			end
			M.subs[kind] = M.subs[kind] or {}
			table.insert(M.subs[kind], fn)
		end,
	}

	-- Shaped like Yazi's own: the component keeps its machinery on the very
	-- table the linemodes are looked up on, which is why a linemode may not be
	-- named after any of it.
	M.children = {}
	_G.Linemode = {
		_inc = 1000,
		_children = { { "solo", id = 1, order = 1000 }, { "padding", id = 2, order = 2000 } },
		new = function(self, file) return setmetatable({ _file = file }, { __index = self }) end,
		solo = function() return "" end,
		redraw = function() return M.Line("") end,
		padding = function() return " " end,
		-- Yazi's own: the id comes from `_inc` rather than the position, so it
		-- stays valid once something before it has been removed.
		children_add = function(self, fn, order)
			self._inc = self._inc + 1
			table.insert(M.children, { fn = fn, order = order, id = self._inc })
			return self._inc
		end,
		children_remove = function(_, id)
			for i, c in ipairs(M.children) do
				if c.id == id then
					table.remove(M.children, i)
					break
				end
			end
		end,
	}
	-- Yazi's own linemodes sit on that same table, which is the whole reason
	-- the plugin cannot simply refuse every name already on it.
	for _, name in ipairs { "none", "size", "permissions", "btime", "mtime", "owner" } do
		_G.Linemode[name] = function() return "" end
	end

	-- `preview` is always a table: Yazi has one whether or not a folder is
	-- being previewed, and the plugin reads `preview.folder` on every row that
	-- is not in the current pane.
	--
	-- `history` is written with the parameters Yazi's takes, and reads
	-- neither: a nullary one here would make the plugin's own
	-- `cx.active:history(url)` the thing that looks wrong when a spec swaps it
	-- out. It declares nothing, though -- `tab__Tab` is `(exact)`, so a field
	-- this table adds is the stub's alone. The type `types.yazi` leaves out is
	-- `supaline.Tab` in `column.lua`, beside the rest of the disagreements.
	_G.cx = { active = { pref = {}, preview = {}, history = function(_, _url) return nil end } }

	-- Whatever the module returned, handed back exactly as it came. This used
	-- to read `chunk() or {}`, which turned the one value Yazi refuses --
	-- Yazi wraps every module in a state table, so `false` fails the load with
	-- "error converting Lua boolean to table" -- into the one it wants.
	-- `module_spec.lua` is written to catch that and could not: a `builtin.lua`
	-- ending `return false` passed all 110 tests while a real Yazi would not
	-- load the plugin at all.
	--
	-- Whether a module has been loaded is kept apart from what it returned, so
	-- that a module returning `false` or nothing is loaded once rather than on
	-- every require -- registering its columns again each time.
	local loaded = {}
	_G.require = function(name)
		if name:sub(1, 1) ~= "." then
			return REAL_REQUIRE(name)
		end
		if not loaded[name] then
			local chunk = assert(loadfile(root .. "/" .. name:sub(2) .. ".lua"))
			loaded[name] = { chunk() }
		end
		return loaded[name][1]
	end
end

return M
