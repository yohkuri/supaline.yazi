--- @since 26.9.1

--- The fixture's `walk` plugin, copied to `config/plugins/walk.yazi/main.lua`
--- by `test/setup.py`. `test/fixture/walk.toml` is the list it walks, and the
--- keys in `test/fixture/keymap.toml` run it:
---
---     plugin walk -- next      the next step, or the first
---     plugin walk -- back      the step before
---     plugin walk -- yes       record "looks right" and go on
---     plugin walk -- no        ask what looks wrong, record it and go on
---     plugin walk -- more      the step's section of `MANUAL.md`, in `less`
---     plugin walk -- hide      put the guide away, or bring it back
---
--- Async rather than `@sync`, because a verdict is written with `fs.write`,
--- which only an async context may call. Measured on 26.9.1: from a sync entry
--- it raises "attempt to yield from outside a coroutine" -- and has written
--- the file anyway, so the error is no proof that nothing happened. A `shell`
--- template could write it from a sync entry instead, and expands `%s` in what
--- it writes to the hovered path. `ya.input` and `ui.hide` are async-only too.
---
--- The step lives in the plugin's own state, which `ya.sync` hands each
--- callback as `st`. That is the same table `init.lua`'s `require` returns,
--- measured on 26.9.1, so the guide `setup` adds reads it directly.

-- Filled in by `setup.py` as every file it copies is.
local CASES = "@DIR@/config/plugins/case.yazi/cases.lua"

-- `dofile` rather than `require`, for the reason `case.lua` gives. Read in
-- both contexts the plugin runs in, `init.lua`'s and the entry's. The verdicts'
-- name is in it because `manual.py` reads them back from the name `setup.py`
-- spells, and a second spelling here would be the one that drifts.
local LISTED = dofile(CASES)
local STEPS = LISTED.steps
local VERDICTS = "@DIR@/" .. LISTED.verdicts

--- The guide takes a third of the screen and never more than twelve rows,
--- because what it sits under is what is being judged: `c r` is sixty-four
--- rows of one ramp, and every row the guide takes is one fewer of those.
local SHARE, TALLEST = 3, 12

--- Below this many rows the guide is its heading and the question, with no
--- room for what to look at under it.
local SHORTEST = 4

--- The cells the heading keeps for the step's title before it gives up the
--- marks, and then the count, on its right.
local TITLED = 24

--- What the last row of the guide says, at every step, and the same keys bare
--- where the screen is too narrow for that.
local KEYS = "W y looks right · W x looks wrong · W n next · W p back · W d more · W h hide"
local BARE = "W y · W x · W n · W p · W d · W h"

local M = {}

--- The step `st.i` is on, moved by `by` and held to the list, and Yazi put in
--- its state. The theme goes in at every step rather than only when it
--- changes, because a theme key pressed by hand changes it behind the walk's
--- back. Both go through the `case` plugin, which is what knows how to show a
--- case and where a theme's script is.
---@param st table
---@param by integer
local function go(st, by)
	st.i = math.max(1, math.min(#STEPS, (st.i or 0) + by))
	st.said = st.said or {}
	local step = STEPS[st.i]
	ya.emit("plugin", { "case", "theme " .. step.theme })
	ya.emit("plugin", { "case", "show " .. step.case })
	-- Each step's guide is its own height. A layout drawn from Lua changes
	-- nothing Yazi scrolls by until a resize, read off 26.9.1's
	-- `yazi-actor/src/app/resize.rs`, so a pane the guide shrank would leave
	-- the hovered row below its last.
	ya.emit("app:resize", {})
end

local move = ya.sync(go)

--- The step a verdict is about, with the verdict recorded where the guide
--- reads it and the walk already on to the next step. Both in this one call
--- rather than the move after the write, because entries run concurrently and
--- the write yields: measured on 26.9.1, `W y W x` sent in one burst put both
--- verdicts on one step, skipped the next, and wrote them in the reverse
--- order. What is left is which of the two reaches this first, the order the
--- entries happen to start in: the same burst swaps them about half the time,
--- and keys 5ms apart did not. A write that then fails is told in a
--- notification, with the walk moved on regardless.
---@param said string
---@return integer
local mark = ya.sync(function(st, said)
	local i = st.i
	st.said[i] = said
	if i < #STEPS then
		go(st, 1)
	end
	-- On the last step nothing else draws the mark it just got.
	ui.render()
	return i
end)

--- The step the walk is on, or `nil` before it has begun.
---@return integer?
local current = ya.sync(function(st) return st.i end)

local toggle = ya.sync(function(st)
	st.hidden = not st.hidden
	ya.emit("app:resize", {})
end)

--- The heading row: where the walk is on its left, and on its right how many
--- steps were answered each way and a mark per step -- `✓` looks right, `✗`
--- looks wrong, `·` not answered -- with the step on show reversed. One line
--- padded between the two, because two lines drawn over one row do not share
--- a background. Where the row is too narrow for all of it, the marks go
--- first and then the count, and the title is cut to what is left.
---@param st table
---@param width integer
---@return ui.Line
local function heading(st, width)
	local said = st.said[st.i]
	local chip = string.format(" walk %d/%d ", st.i, #STEPS)
	local title = " " .. STEPS[st.i].title .. " " .. (said and ("[" .. said .. "] ") or "")

	local marks, yes, no = {}, 0, 0
	for i = 1, #STEPS do
		local s = st.said[i]
		yes, no = yes + (s == "yes" and 1 or 0), no + (s == "no" and 1 or 0)
		marks[i] = s == "yes" and "✓" or s == "no" and "✗" or "·"
	end
	local left = #STEPS - yes - no
	local count = left == 0 and string.format("all answered: %d yes, %d no  ", yes, no)
		or string.format("%d yes · %d no · %d to go  ", yes, no, left)

	-- Measured as strings: a `Line` takes the spans it is given, so one built
	-- only to be measured leaves nothing to draw.
	local room = width - ui.width(chip)
	local function right() return ui.width(count .. table.concat(marks) .. " ") end
	if room - right() < TITLED then
		marks = {}
	end
	if room - right() < TITLED then
		count = ""
	end
	room = room - right()
	-- A cell short, so a title that was cut still has a space after it.
	title = ui.truncate(title, { max = math.max(0, room - 1) })

	local spans = {
		ui.Span(chip):style(th.mode.normal_main),
		ui.Span(title),
		ui.Span(string.rep(" ", room - ui.width(title)) .. count),
	}
	for i, mark in ipairs(marks) do
		spans[#spans + 1] = i == st.i and ui.Span(mark):reverse() or ui.Span(mark)
	end
	spans[#spans + 1] = ui.Span(" ")
	return ui.Line(spans):style(th.mode.normal_alt)
end

--- `text` broken between words into lines no wider than `width` cells. A word
--- wider than that has a line to itself, and is cut where it is drawn.
--- Here rather than by `ui.Text:wrap` as it is drawn, because `measure` sizes
--- the guide by these rows before anything is.
---@param text string
---@param width integer
---@return string[]
local function wrap(text, width)
	local lines, line = {}, nil
	for word in text:gmatch("%S+") do
		if line and ui.width(line .. " " .. word) <= width then
			line = line .. " " .. word
		else
			lines[#lines + 1] = line
			line = word
		end
	end
	lines[#lines + 1] = line
	return lines
end

--- A guide row: its text, and whether it is drawn bold.
---@alias walk.Row { [1]: string, [2]: boolean }

--- The guide's rows between its heading and its keys, wrapped to `width`: the
--- question in bold, then what to look at, each item hanging under its dash.
--- Kept as text, because `measure` counts them before `draw` draws them.
---@param i integer
---@param width integer
---@return walk.Row[]
local function body(i, width)
	local step, rows = STEPS[i], {}
	for _, line in ipairs(wrap(step.ask, width)) do
		rows[#rows + 1] = { line, true }
	end
	for _, item in ipairs(step.look) do
		for n, line in ipairs(wrap(item, width - 2)) do
			rows[#rows + 1] = { (n == 1 and "- " or "  ") .. line, false }
		end
	end
	return rows
end

--- The guide's height in `area`: nothing before the walk has begun or while
--- it is put away, its heading and the question where the screen is short,
--- and otherwise as much of what to look at as fits.
---@param st table
---@param area ui.Rect
---@return integer
local function measure(st, area)
	if not st.i or st.hidden then
		return 0
	end
	local room = math.min(TALLEST, area.h // SHARE)
	if room < SHORTEST then
		return math.max(1, math.min(2, room))
	end
	return math.min(room, #body(st.i, area.w - 2) + 2)
end

--- The guide, as Yazi's components are: a table with an `_id`, an area, and
--- the elements it draws in it.
local Guide = { _id = "walk" }

---@param area ui.Rect
---@param st table
function Guide:new(area, st) return setmetatable({ _area = area, _st = st }, { __index = self }) end

function Guide:reflow() return { self } end

--- Guarded, because an error raised here fails the whole `Root` rather than
--- the guide -- the file list and the status bar stop drawing on every frame.
--- What it raised is drawn in the guide's place instead.
function Guide:redraw()
	local ok, drawn = pcall(self.draw, self)
	if ok then
		return drawn
	end
	ya.err("walk: the guide could not be drawn: " .. tostring(drawn))
	return { ui.Line("walk: the guide could not be drawn: " .. tostring(drawn)):area(self._area) }
end

--- Its heading, and then either the question alone where `measure` left no
--- room for more -- the only height under three it gives -- or the rows that
--- fit and the keys.
function Guide:draw()
	local a, st = self._area, self._st
	local function row(y) return ui.Rect { x = a.x, y = a.y + y, w = a.w, h = 1 } end

	-- `area` is declared to answer a `Rect` as well, so this is any element.
	---@type any[]
	local drawn = { heading(st, a.w):area(row(0)) }
	if a.h < 3 then
		if a.h == 2 then
			drawn[2] = ui.Line(" " .. STEPS[st.i].ask):bold():area(row(1))
		end
		return drawn
	end

	local rows, room, shown = body(st.i, a.w - 2), a.h - 2, {}
	for i = 1, math.min(#rows, room) do
		local text, bold = table.unpack(rows[i])
		shown[i] = bold and ui.Line(text):bold() or ui.Line(text)
	end
	if #rows > room then
		shown[room] = ui.Line("… W d reads the section"):dim()
	end
	drawn[#drawn + 1] = ui.Text(shown):area(ui.Rect { x = a.x + 1, y = a.y + 1, w = a.w - 2, h = room })
	local keys = ui.width(KEYS) + 2 <= a.w and KEYS or BARE
	drawn[#drawn + 1] = ui.Line(" " .. keys):dim():area(row(a.h - 1))
	return drawn
end

--- The guide, between the file list and the status bar, and a compact line
--- in the status bar while it is put away. Both are added here, at load,
--- because a `require` from inside a component raises until the plugin has
--- been loaded -- on every frame, measured on 26.9.1 -- and one that raises
--- there takes the whole screen with it. Before `W n` neither draws, so
--- `e2e.py` reads the screen Yazi would.
---
--- Below rather than beside the panes, because the columns are what is being
--- judged and a guide beside them would narrow every pane it sits next to.
--- Wrapped around 26.9.1's own `Root:layout` and `Root:build` rather than
--- written over them, so all this leans on is the tab being the third chunk
--- and the modal the last child, read off its `components/root.lua`.
function M:setup()
	local st = self
	-- Yazi's components, which `types.yazi` declares no global for.
	---@diagnostic disable-next-line: undefined-global
	local root, status = Root, Status
	local layout, build = root.layout, root.build

	function root:layout()
		layout(self)
		local ok, height = pcall(measure, st, self._area)
		if not ok then
			ya.err("walk: the guide could not be measured: " .. tostring(height))
		end
		self._guide = nil
		if ok and height > 0 then
			-- In 26.9.1 and missing from `types.yazi`.
			---@diagnostic disable-next-line: undefined-field
			local vertical = ui.Layout.VERTICAL
			local split = ui.Layout()
				:direction(vertical)
				:constraints({ ui.Constraint.Fill(1), ui.Constraint.Length(height) })
				:split(self._chunks[3])
			self._chunks[3], self._guide = split[1], split[2]
		end
	end

	function root:build()
		build(self)
		if self._guide then
			table.insert(self._children, #self._children, Guide:new(self._guide, st))
		end
	end

	status:children_add(function()
		local step = st.hidden and st.i and STEPS[st.i]
		if not step then
			return ui.Line("")
		end
		return ui.Line(string.format(" walk %d/%d · %s · W h shows the guide ", st.i, #STEPS, step.key))
	end, 500, status.RIGHT)
end

--- The step's section of `MANUAL.md`, whole, in `less` -- why each thing the
--- guide names is worth looking at -- with Yazi put away until it quits.
--- With `LESSOPEN` emptied, since a preprocessor that reformats Markdown
--- moves the heading off the line `setup.py` read it on.
---@param i integer
local function more(i)
	local permit = ui.hide()
	local done, err = Command("less")
		:arg({ "+" .. STEPS[i].line .. "g", LISTED.manual })
		:env("LESSOPEN", "")
		:stdin(Command.INHERIT)
		:stdout(Command.INHERIT)
		:stderr(Command.INHERIT)
		:status()
	-- `types.yazi` declares the permit and not the method that gives it back.
	---@diagnostic disable-next-line: undefined-field
	permit:drop()
	if not done or not done.success then
		ya.notify {
			title = "walk",
			content = "less could not show " .. LISTED.manual .. ": " .. tostring(err or (done and done.code)),
			timeout = 10,
			level = "error",
		}
	end
end

---@param job { args: string[] }
function M:entry(job)
	local verb = job.args[1]
	if verb == "next" then
		return move(1)
	elseif verb == "back" then
		return move(-1)
	elseif verb ~= "yes" and verb ~= "no" and verb ~= "more" and verb ~= "hide" then
		return
	end

	local on = current()
	if not on then
		return ya.notify { title = "walk", content = "W n starts the walk; there is no step yet", timeout = 5 }
	elseif verb == "more" then
		return more(on)
	elseif verb == "hide" then
		return toggle()
	end

	-- What looks wrong, in the reader's words, kept beside the verdict. Escape
	-- gives no verdict at all, so a `W x` pressed by mistake costs nothing.
	local note = ""
	if verb == "no" then
		local value, event =
			ya.input { title = "What looks wrong? (Enter alone to say nothing)", pos = { "center", w = 60 } }
		if event ~= 1 then
			return
		end
		note = tostring(value or ""):gsub("[%c]", " ")
	end

	-- Appended, so a step answered twice is two lines and the later one wins
	-- when the file is read, rather than the first answer vanishing.
	local i = mark(verb)
	local step = STEPS[i]
	local line = string.format("%d\t%s\t%s\t%s", i, step.case, step.theme, verb)
	if note ~= "" then
		line = line .. "\t" .. note
	end
	local fd, err = fs.access():append(true):create(true):open(Url(VERDICTS))
	local ok = false
	if fd then
		ok, err = fd:write_all(line .. "\n")
		if ok then
			ok, err = fd:flush()
		end
	end
	if not ok then
		return ya.notify {
			title = "walk",
			content = "the verdict was not written to " .. VERDICTS .. ": " .. tostring(err),
			timeout = 10,
			level = "error",
		}
	end
	if i == #STEPS then
		ya.notify { title = "walk", content = "the last step; every verdict is in " .. VERDICTS, timeout = 10 }
	end
end

return M
