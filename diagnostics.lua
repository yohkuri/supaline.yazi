--- @since 26.9.1
--- Diagnostic vocabulary and setup-lifetime report gates. No Yazi globals:
--- the entry point supplies the paired log/notification sink.
---@class supaline.DiagnosticsModule
local M = {}

---@param names string[] at least two
---@param conj string? the word before the last name, `and` by default
---@return string
function M.key_list(names, conj)
	return string.format("`%s` %s `%s`", table.concat(names, "`, `", 1, #names - 1), conj or "and", names[#names])
end

--- The same over a key set rather than a list: every key of `set`, sorted.
---
--- Sorted for the reason `listed` gives below -- `pairs` walks a table in
--- whatever order the hash gives, so a message that names a set reorders
--- itself between runs and reads as a different message.
---
--- Here rather than beside each allow-list, because collecting and sorting is
--- the half of `key_list`'s own argument the list form cannot carry. The two
--- callers had written the same five lines, down to the comment explaining
--- the sort, and an allow-list added anywhere would have written a third.
---@param set table<string, any> the allow-list itself, read for its keys
---@param conj string? the word before the last name, `and` by default
---@return string
function M.key_list_of(set, conj)
	local names = {}
	for key in pairs(set) do
		names[#names + 1] = key
	end
	table.sort(names)
	return M.key_list(names, conj)
end

--- `names` backquoted and comma-joined, in whatever order they arrive in.
---
--- Exported because the quoting is shared with a caller that must *not* sort:
--- `column.lua` lists the options a definition declared, and those are read in
--- the order the definition wrote them. Without this the same expression is
--- spelled a third way -- `key_list` above carries the conjunction, `listed`
--- below carries the sort, and this is what the two of them have in common --
--- so a change to how a message quotes a name has three places to reach.
---@param names string[]
---@return string
function M.quoted(names) return "`" .. table.concat(names, "`, `") .. "`" end

--- Sorted quoted names, or nil when there are none.
---
--- Sorted because `pairs` walks a table in whatever order the hash gives, so a
--- message that names a set reorders itself between runs and reads as a
--- different message -- and, where the names are mistakes, costs a second run
--- to find the other half of them. Sorted in place: a caller that goes on to
--- read `names` gets the order the message used.
---@param names string[]
---@return string? quoted
local function listed(names)
	if #names == 0 then
		return nil
	end
	table.sort(names)
	return M.quoted(names)
end

--- The style a table written in a spec asks for.
---
--- Every key of `t` that `claims` does not answer for, sorted, and the same
--- names quoted and joined ready to drop into a message. Nil when every key
--- was claimed.
---
--- Every one of them rather than the first one found, and sorted, for the
--- reason `listed` gives.
---
--- What each caller has to say differs; what does not is the quoting, the
--- `is` or `are` that follows it, and the hint each name earns. Those three
--- drifted apart once already and are built here now, so a fifth allow-list
--- is a key set and a noun rather than a message assembled by hand.
---
--- Here because here is the only place all five callers can reach. This file
--- sits at the bottom of the require chain and knows nothing about `setup`'s
--- own options, a linemode spec or a separator; `column.lua` and `config.lua`
--- both require it, and neither requires the other in the direction that would
--- do. Spelled per caller it drifts in where the quoting happens -- one
--- quoting each name as it collects it, another at the join -- and every
--- further copy carries the drift on.
---@param t table
---@param claims fun(key: any): boolean? whether the table is entitled to that key
---@param noun string? what one of this table's keys is called, for `subject`
---@param meant table<string, string>? what a given misspelling most likely meant
---@return string[]? names sorted, for a caller that has something to say about each
---@return string? quoted the same names, backquoted and comma-joined
---@return string? subject the same names, and whether they is or are not a `noun` key
---@return string? hints what each of them probably meant, joined, or ""
function M.unknown(t, claims, noun, meant)
	local names = {}
	for k in pairs(t) do
		if not claims(k) then
			names[#names + 1] = tostring(k)
		end
	end
	local quoted = listed(names)
	if not quoted then
		return nil
	end
	local subject = noun
		and string.format("%s %s", quoted, #names == 1 and "is not a " .. noun .. " key" or "are not " .. noun .. " keys")
	local hints = {}
	for _, k in ipairs(names) do
		hints[#hints + 1] = meant and meant[k]
	end
	return names, quoted, subject, #hints > 0 and ". " .. table.concat(hints, "; ") or ""
end

-- What a style table is entitled to: the two colours, and an attribute under
-- whichever of its two spellings. Derived from `METHOD` rather than written
-- out, because a list and a set of the same names are two things to keep in

---
--- **Measured on 26.9.1**: what comes back is not the string `error` was
--- given. Yazi wraps it as `runtime error: <chunk>:<line>: <message>` and
--- appends two stack tracebacks, and `ya.notify` draws every line -- eleven
--- rows of it, with the one sentence that says what to change second. The log
--- is handed the error itself and keeps all three tracebacks, which is what a
--- log is for; this is what the screen gets.
---
--- What it leaves on is the `<chunk>:<line>: `, and that is the half the two
--- callers differ over rather than share. `build` strips it as well: the chunk
--- is one of supaline's own and the message already names the key. `broke`
--- keeps it, because there the chunk is the reader's and the line is where
--- their own function threw.
---@param err any what `pcall` handed back
---@return string
function M.one_line(err) return (tostring(err):gsub("\nstack traceback:.*", ""):gsub("^runtime error: ", "")) end

---@class supaline.Reporter
---@field threw fun(col: supaline.ColumnPlan, stage: string, err: any)
---@field stats fun(col: supaline.ColumnPlan)
---@field width fun(col: supaline.ColumnPlan, why: string)

---@param sink fun(logged: any, shown: string?)
---@return supaline.Reporter
function M.new(sink)
	local gates = {} ---@type table<supaline.ColumnPlan, table<string, true>>
	local function told(col, what)
		local gate = gates[col]
		if not gate then
			gate = {}
			gates[col] = gate
		end
		if gate[what] then
			return true
		end
		gate[what] = true
		return false
	end
	local report = sink
	local one_line = M.one_line
	--- Say once that a column's `stats` came back with nothing its ramp can use,
	--- and go on drawing.
	---
	--- What it returned is knowable only here, which is inside a render pass, and
	--- that is the whole of what decides the shape. An `error` from here takes the
	--- whole screen down -- see `broke` below for what that costs -- which is far
	--- worse than the thing it would be reporting, a column drawing in one colour
	--- instead of several. So: say it, and keep drawing.
	---
	--- Measured on 26.9.1, because until it was this had no shape at all.
	--- `ya.notify` from inside a linemode render reaches the screen; the rows draw
	--- under it and the pane is not disturbed. What keeps it from repeating is
	--- `told` above.
	---@param col supaline.ColumnPlan
	local function no_extremes(col)
		if told(col, "stats") then
			return
		end

		local why = string.format(
			"supaline: column `%s` draws a gradient, and its `stats` came back with no `min` and "
				.. "`max` numbers to place a row between -- so every row draws the ramp's low end "
				.. "and the column is one colour. `stats` is handed the folder's files and must "
				.. "return a table carrying both, and both have to be numbers",
			col.name or "?"
		)
		report(why)
	end

	-- What stands in for a cell that could not be drawn at all, one of these per
	-- cell the column was given. Loud on purpose: a broken column filled with
	-- spaces is a column that is not there, which is what `whole_cells` refuses a
	-- stated width of zero for, and a reader looking at a gap would be looking for
	-- the wrong fault.
	local BROKEN = "!"

	-- What a column with no width to pad to draws instead. One string rather than
	-- two because two reports end in it -- a `width` that threw, and a `width` that
	-- came back with a number supaline will not take -- and `MANUAL.md` sends a
	-- reader from `b w` straight to `b u` precisely because nothing on the screen
	-- tells those two apart. The sentences agreeing is the whole of that
	-- comparison, so they are not two sentences.
	--
	-- It says which side moves because only one of them does, and the earlier
	-- wording -- "everything else on the line keeps its place" -- was half right
	-- in a way that sent a reader to the wrong side. Measured on 26.9.1 at 170x40,
	-- at `b w` in the fixture, in display columns: `mtime`, after the ragged
	-- column, sits at 71 on every row, while `size`, before it, ends at 66 on the
	-- rows drawing `dir` and 65 on the rows drawing `file`. Yazi draws the
	-- linemode flush right, so the columns after this one are anchored and the
	-- ones before it take up the slack.
	--
	-- Both readers pass it to `string.format` as an argument rather than
	-- concatenating it into the format string, and that is a rule rather than a
	-- style: this is one string precisely so that it gets edited, and a `%` in it
	-- -- "keeps its place 100% of the time", an escape, a borrowed `%s` -- turns a
	-- format string carrying it into a raise. `bad_width`'s raise would be the
	-- expensive kind. It is called from the width pass, which sits outside the
	-- `pcall` around `runtime.width` and under a linemode's render, so the throw
	-- this file's longest docblock is written against would come from the line
	-- reporting a lesser one.
	local UNPADDED = "this column draws unpadded: the line is drawn flush right, so the columns "
		.. "after it keep their place and the ones before it shift -- ragged rather than absent"

	-- What the throw cost, worded per stage, for the middle of the sentence
	-- `broke` builds. A sentence each, because what a throw costs differs by
	-- stage and the screen says which.
	--
	-- `render` is the only one that leaves a cell nobody can fill. `BROKEN` is
	-- written at one site, under the per-row `pcall` alone, so that is the only
	-- stage a sentence may mention it in.
	--
	-- A `width` that threw leaves the column with no width, so it draws unpadded:
	-- `UNPADDED` above, which the report `bad_width` makes about that same screen
	-- ends in too.
	--
	-- A `stats` that threw usually leaves the line alone, since the reader's
	-- `render` is the only thing that reads a `stats` and one that needed none of
	-- it draws exactly as it would have. That is why this report has to carry the
	-- column's name: it is the whole of the signal. The sentence says which line
	-- is which rather than promising either, because a `render` that did need the
	-- result throws in its turn and `told` reports this one instead.
	--
	-- `refresh` runs before any row is drawn, so nothing on the line looks
	-- different; what was lost is whatever the column was going to cache, which
	-- the first time round is the whole of what it had.
	--
	-- `default` is what a stage nobody has worded gets, and it claims nothing
	-- about the cells. A shared sentence that did is the fault this table was
	-- carrying: three stages borrowed `render`'s, and two of them draw something
	-- else. Read on a screen, at `b r`, `b s` and `b w` in `manual.py`.
	local COST = {
		render = string.format(
			"Everything else on the line goes on drawing, and a cell this column cannot draw at all "
				.. "is filled with `%s` so that the row keeps its shape",
			BROKEN
		),
		width = "Until it returns a width, " .. UNPADDED,
		stats = "Everything else on the line goes on drawing, and so does this column: a `stats` is "
			.. "read by the column's own `render`, so a line that looks untouched is one whose "
			.. "`render` needed nothing from it",
		refresh = "Every other column still refreshes, and this one goes on drawing with whatever it "
			.. "had cached before -- which the first time round is nothing at all",
		default = "Everything else on the line goes on drawing",
	}

	--- Say once that a column threw, and go on drawing everything else.
	---
	--- A column may write four functions. Three of them -- `stats`, a `width`
	--- that is one, and `render` -- are called inside Yazi's redraw. **Measured on
	--- 26.9.1**: an error raised anywhere under a linemode's render fails the
	--- whole `Root` component, not the row and not the pane. The file list, the
	--- header and the status bar all stop drawing, it happens again on every
	--- frame for as long as that folder is open, and Yazi goes on taking keys
	--- against a screen that is blank but for the preview's own placeholder. The
	--- message reaches the log and nowhere else -- and there is no log at all
	--- unless `YAZI_LOG` was set before Yazi started, which is not how anybody
	--- runs it. So the reader is left with an empty terminal and nothing to read,
	--- and it is why the sentence below says the traceback *goes to* the log
	--- rather than that it is in one.
	---
	--- That is worse than any mistake it could be reporting, so those three calls
	--- are made under `pcall` and this says what happened instead. It is the same
	--- judgement `no_extremes` is, reached for the same reason and from the same
	--- measurement; what is new here is that the throw need not be supaline's. A
	--- reader's own `render` raising produced exactly the blank screen above, with
	--- no part of this plugin involved in raising it.
	---
	--- The fourth is `refresh`, which is contained for a different reason and
	--- said the same way -- `refresh` above carries that half of it. What the two
	--- reasons have in common is that neither caller has anybody to raise to.
	---
	--- One report across all four stages, not one each: what the reader has to
	--- look at is the column, and the first thing of theirs it threw from is
	--- where they will start. `told` holds that, and holds it hardest here --
	--- two of the four are reached from a path that runs again and again, a
	--- per-row one and a per-`cd` one.
	---
	--- What it does **not** cover is a `width` function that came back with a
	--- number nobody can use. That one is supaline's own refusal, `runtime.width`
	--- returns it rather than raising it for exactly this reason, and
	--- `bad_width` below words it as itself. A refusal raised into this wrapper
	--- would arrive here as "column `x` threw from its `width`" for a function
	--- that threw nothing at all.
	---
	--- The screen gets the first line of what was thrown and the log gets all of
	--- it. **Measured on 26.9.1**: what `pcall` hands back here carries a full Lua
	--- traceback, and the whole of it in a notification filled the preview pane
	--- top to bottom, pushing the one line that names the column and the mistake
	--- off the top. `report` is what holds those two halves together.
	---@param col supaline.ColumnPlan
	---@param stage string which of the four threw, named as the reader wrote it
	---@param err any what it threw
	local function broke(col, stage, err)
		if told(col, "threw") then
			return
		end

		local said = tostring(err)
		report(
			string.format(
				"supaline: column `%s` threw from its `%s`. %s. It threw: %s",
				col.name or "?",
				stage,
				COST[stage] or COST.default,
				said
			),
			string.format(
				"column `%s` threw from its `%s`: %s (the traceback goes to the log)",
				col.name or "?",
				stage,
				one_line(said)
			)
		)
	end

	--- Say once that a column's `width` function came back with something that is
	--- not a count of cells, and draw the column without one.
	---
	--- This is supaline's own refusal rather than a mistake of Lua's, which is
	--- why it arrives as a string from `runtime.width` instead of out of a
	--- `pcall`: that function returns it so that this can be worded as what it
	--- is. `broke` above has the other half of the argument.
	---
	--- What the reader sees instead of a width is the column unpadded -- it draws
	--- whatever its `render` returns, at whatever width that is, so a listing of
	--- uneven names comes out ragged. Ragged and readable is the right trade
	--- against a stated `width = 0`, which `setup` refuses outright: that one is
	--- knowable before anything draws, and this one is not knowable until the
	--- folder it was handed exists.
	---@param col supaline.ColumnPlan
	---@param why string the refusal, already worded by `runtime.lua`
	local function bad_width(col, why)
		if told(col, "width") then
			return
		end

		local said = string.format("%s. Until it does, %s", why, UNPADDED)
		report(said)
	end

	return { threw = broke, stats = no_extremes, width = bad_width }
end

return M
