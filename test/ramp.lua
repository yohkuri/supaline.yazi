--- Print a ramp to the terminal, the way `colour.lua` builds it.
---
---     lua test/ramp.lua "#0b3d91 -> #7fd4ff"
---     lua test/ramp.lua "#111 -> #222" "#0b3d91 -> #ffd400 -> #7fd4ff"
---     lua test/ramp.lua --band 0.90,0.35 "#0b3d91 <->"
---
--- `--band` is one band of `setup`'s own option, `from` first, and it is here
--- because the two numbers cannot be settled any other way: one end of the
--- recommended pair was measured against five terminal backgrounds and the
--- other was chosen by looking at exactly this output. Every user has to do
--- the same, since supaline applies that pair to nobody, and the alternative
--- is editing `init.lua` and restarting Yazi per guess.
---
--- Omitting it draws the recommended pair, which is what the refusal a band
--- with no definition earns tells the reader to paste -- so what they see here
--- first is what they were just told to write.
---
--- `manual.sh` runs this before it opens Yazi, over every ramp the fixture can
--- draw, so the whole of each one is on screen at once and in the terminal the
--- colours are about to be judged in.
---
--- A linemode can only ever show the steps some folder's values happen to land
--- on -- `colour/ramp` is built to land on all of them, and even there you
--- scroll. This shows every step side by side, which is how a band, or a
--- stretch where several steps read as one colour, becomes obvious rather than
--- suspected.
---
--- What it cannot say is whether supaline puts a row on the right step: it
--- never asks the plugin, only the arithmetic underneath it. That half is
--- `e2e.sh`'s, and the two look at different halves deliberately.

local HERE = (arg[0] or "test/ramp.lua"):match("^(.*)[/\\]") or "."

-- `colour.lua` answers a `#rrggbb` straight out of a pattern, and reaches for
-- Yazi only to ask whether it takes one of the *other* spellings -- a name, a
-- 256-colour index -- by trying to build a style out of one. There is no Yazi
-- here, so this stands in for it.
--
-- Permissive rather than strict, which is the opposite of what a stub in this
-- harness usually owes Yazi, and for a reason that only holds here: nothing but
-- `#rrggbb` can be drawn either way, because `colour.stops` needs numbers at
-- both ends and refuses everything else on the next line. So the only thing
-- this choice decides is which refusal a reader gets. Accepting sends `cyan` to
-- the message about why an endpoint cannot be a palette name -- the true one,
-- and the one a real Yazi gives. Refusing sends it to "not a colour Yazi
-- accepts", which goes on to recommend writing `cyan`.
---@diagnostic disable-next-line: lowercase-global
ui = {
	Style = function()
		return { fg = function(self) return self end }
	end,
}

local colour = dofile(HERE .. "/../colour.lua")

local ESC = string.char(27)

--- One line of the ramp, `cell(i)` drawn in step `i`'s colour.
---
--- One escape per step and a single reset at the end, so what a terminal is
--- handed is as close to what a linemode hands it as this can get.
---@param ramp string[]
---@param cell fun(i: integer): string
---@return string
local function strip(ramp, cell)
	local out = {}
	for i, hex in ipairs(ramp) do
		-- `colour.colour` rather than a pattern of our own: the hex spelling is
		-- the plugin's to define, and a second copy here would answer nil the
		-- day it widens. `pcall` in `show` would then report that as a ramp the
		-- reader wrote wrong.
		local rgb = colour.colour(hex, "test/ramp.lua") --[[@as integer[] ]]
		out[#out + 1] = string.format("%s[38;2;%d;%d;%dm%s", ESC, rgb[1], rgb[2], rgb[3], cell(i))
	end
	return table.concat(out) .. ESC .. "[0m"
end

--- Two lines per ramp, because they answer different questions.
---
--- The solid one is about the gradient: a band, a reversal, a stretch of steps
--- that read as one colour. The digits are about the column -- every step has
--- to carry *text* legibly against the terminal's own background, and a ramp
--- whose low end is as dark as the terminal is a correct gradient and an
--- unreadable column. Counting in tens is what lets a reader say which step
--- stopped being readable rather than "somewhere near the bottom".
---@param value string
---@param band supaline.Band
local function show(value, band)
	-- One band under every name a `<->` here could ask for. This tool draws the
	-- pair it was given, so which name a string happens to write is not a
	-- question it has any business asking -- where a user's `setup` has exactly
	-- the names they wrote and a `<->` naming another is the refusal they want.
	local bands = setmetatable({}, { __index = function() return band end })
	local ramp = colour.ramp(colour.stops(value, "test/ramp.lua", bands, "fg"))
	print("")
	print(string.format("  %s    %d steps, %s to %s", value, #ramp, ramp[1], ramp[#ramp]))
	print("  " .. strip(ramp, function() return "█" end))
	print("  " .. strip(ramp, function(i) return tostring((i - 1) % 10) end))
end

-- `--band` taken out of the list first, so the loop below stays a loop over
-- ramps, and taken wherever it appears: a reader iterating on the bounds is as
-- likely to append the flag as to lead with it, and a positional rule would
-- answer that by refusing the ramp as a colour. The pair goes through
-- `colour.bounds` rather than being checked here, which is the point of that
-- function living in `colour.lua`: what this prints for `--band 0,1` is what a
-- user's `init.lua` would have said.
local values, band = {}, colour.recommended()
local i = 1
while arg[i] do
	if arg[i] == "--band" then
		local pair = arg[i + 1]
		local from, to = (pair or ""):match("^%s*([^,%s]+)%s*,%s*([^,%s]+)%s*$")
		if not from then
			io.stderr:write("test/ramp.lua: --band takes two lightnesses, as `--band 0.35,0.88`\n")
			os.exit(2)
		end
		-- The unparsed string rather than the nil it becomes, so a `--band a,b`
		-- is refused in the words the user typed.
		band = colour.bounds({ from = tonumber(from) or from, to = tonumber(to) or to }, "`--band`")
		i = i + 2
	else
		values[#values + 1] = arg[i]
		i = i + 1
	end
end

if not values[1] then
	io.stderr:write('usage: lua test/ramp.lua [--band FROM,TO] "#0b3d91 -> #7fd4ff" [...]\n')
	os.exit(2)
end

local failed = false
for n = 1, #values do
	-- Each ramp on its own, so one that cannot resolve does not take the rest
	-- of the screen with it. The message is the plugin's, and it is the same
	-- one a user gets from a `theme.toml` that says the same thing.
	local ok, err = pcall(show, values[n], band)
	if not ok then
		io.stderr:write(tostring(err):gsub("^.-:%d+: ", "") .. "\n")
		failed = true
	end
end

print("")
os.exit(failed and 1 or 0)
