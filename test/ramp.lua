--- Print a ramp to the terminal, the way `colour.lua` builds it.
---
---     lua test/ramp.lua "#0b3d91 -> #7fd4ff"
---     lua test/ramp.lua "#111 -> #222" "#0b3d91 -> #ffd400 -> #7fd4ff"
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
		local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
		out[#out + 1] =
			string.format("%s[38;2;%d;%d;%dm%s", ESC, tonumber(r, 16), tonumber(g, 16), tonumber(b, 16), cell(i))
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
local function show(value)
	local ramp = colour.ramp(colour.stops(value, "test/ramp.lua"))
	print("")
	print(string.format("  %s    %d steps, %s to %s", value, #ramp, ramp[1], ramp[#ramp]))
	print("  " .. strip(ramp, function() return "█" end))
	print("  " .. strip(ramp, function(i) return tostring((i - 1) % 10) end))
end

if not arg or not arg[1] then
	io.stderr:write('usage: lua test/ramp.lua "#0b3d91 -> #7fd4ff" [...]\n')
	os.exit(2)
end

local failed = false
for i = 1, #arg do
	-- Each ramp on its own, so one that cannot resolve does not take the rest
	-- of the screen with it. The message is the plugin's, and it is the same
	-- one a user gets from a `theme.toml` that says the same thing.
	local ok, err = pcall(show, arg[i])
	if not ok then
		io.stderr:write(tostring(err):gsub("^.-:%d+: ", "") .. "\n")
		failed = true
	end
end

print("")
os.exit(failed and 1 or 0)
