--- @since 26.9.1
--- What is said when a column misbehaves while drawing, the gates that say it
--- once, and the one place the four functions a column draws with are called
--- from. A gate belongs to a `setup` and survives a theme change, so a report
--- is re-armed by a new configuration and not by a reload. No Yazi globals:
--- `main.lua` hands in the sink that writes the log and the screen.
---@class supaline.ReportModule
local M = {}

--- The first line of an error, for the screen. Measured on 26.9.1: what
--- `pcall` hands back from under Yazi is `runtime error: <chunk>:<line>:
--- <message>` and two tracebacks, and `ya.notify` draws every line of it. The
--- log keeps the whole; the `<chunk>:<line>:` stays, since it is where the
--- reader's own function threw.
---@param err any what `pcall` handed back
---@return string
function M.one_line(err) return (tostring(err):gsub("\nstack traceback:.*", ""):gsub("^runtime error: ", "")) end

--- Which of the four functions a column may write threw.
---@alias supaline.Stage "render"|"width"|"stats"|"refresh"

---@class supaline.Reporter
---@field call fun(col: supaline.ColumnPlan, stage: supaline.Stage, fn: function, ...: any): boolean, any, any
---@field stats fun(col: supaline.ColumnPlan)
---@field width fun(col: supaline.ColumnPlan, refused: string)

--- What a report calls a column: an inline one may have no name.
---@param col supaline.ColumnPlan
---@return string
local function name_of(col) return col.name or "?" end

-- What stands in for a cell that could not be drawn, one per cell the column
-- was given. A blank would read as a column nobody configured.
local BROKEN = "!"

-- How a column with no width draws. Shared by a `width` that threw and one
-- supaline would not take, because nothing on the screen tells them apart.
-- Measured on 26.9.1 at `b w` in the fixture: Yazi draws the linemode flush
-- right, so the columns after this one hold their place. An argument to
-- `string.format`, never part of a format string, so a `%` in it is harmless.
local UNPADDED = "this column draws unpadded: the line is drawn flush right, so the columns "
	.. "after it keep their place and the ones before it shift -- ragged rather than absent"

-- What a throw cost, per stage. Only `render` leaves a cell to fill with
-- `BROKEN`; a `stats` that threw usually leaves the line looking untouched, so
-- the column's name in the report is the whole of the signal; a `refresh` runs
-- before any row, so what is lost is whatever the column caches.
local COST = {
	render = string.format(
		"Everything else on the line goes on drawing, and a cell this column cannot draw at all is "
			.. "filled with `%s` so that the row keeps its shape",
		BROKEN
	),
	width = "Until it returns a width, " .. UNPADDED,
	stats = "Everything else on the line goes on drawing, and so does this column: a `stats` is read "
		.. "by the column's own `render`, so a line that looks untouched is one whose `render` needed "
		.. "nothing from it",
	refresh = "Every other column still refreshes, and this one goes on drawing with whatever it had "
		.. "cached before -- which the first time round is nothing at all",
}

M.BROKEN = BROKEN

--- A reporter over `sink`, which writes the whole of a report to the log and
--- its second argument, when there is one, to the screen.
---
--- Each column is told off once per kind: a throw from any of its four
--- functions is one kind, since the first thing that threw is where the reader
--- starts; `stats` with no extremes and a `width` supaline will not take are
--- two more, and one does not hide the other.
---@param sink fun(logged: any, shown: string?)
---@return supaline.Reporter
function M.new(sink)
	local gates = {} ---@type table<supaline.ColumnPlan, table<string, true>>
	local function told(col, kind)
		local gate = gates[col]
		if not gate then
			gate = {}
			gates[col] = gate
		end
		if gate[kind] then
			return true
		end
		gate[kind] = true
		return false
	end

	--- A column's `stats` came back with nothing its ramp can use. Knowable
	--- only inside a render, where an `error` would blank the screen, which
	--- costs far more than one column drawn in one colour. Measured on 26.9.1:
	--- `ya.notify` from inside a render reaches the screen, and the rows draw
	--- under it.
	---@param col supaline.ColumnPlan
	local function no_extremes(col)
		if told(col, "stats") then
			return
		end
		sink(
			string.format(
				"supaline: column `%s` draws a gradient, and its `stats` came back with no `min` and `max` "
					.. "numbers to place a row between -- so every row draws the ramp's low end and the column "
					.. "is one colour. `stats` is handed the folder's files and must return a table carrying "
					.. "both, and both have to be numbers",
				name_of(col)
			)
		)
	end

	--- A column threw from one of the four functions it may write, and the
	--- rest of the line goes on drawing. Measured on 26.9.1: an error raised
	--- under a linemode's render fails the whole `Root` component, on every
	--- frame, with nothing on screen and no log unless `YAZI_LOG` was set --
	--- worse than any mistake it could report. The screen gets the first line
	--- and the log the traceback, since a whole traceback in a notification
	--- pushes the line that names the column off the top of the pane.
	---@param col supaline.ColumnPlan
	---@param stage supaline.Stage which of the four threw
	---@param err any what it threw
	local function broke(col, stage, err)
		if told(col, "threw") then
			return
		end
		local said = tostring(err)
		sink(
			string.format(
				"supaline: column `%s` threw from its `%s`. %s. It threw: %s",
				name_of(col),
				stage,
				COST[stage],
				said
			),
			string.format(
				"column `%s` threw from its `%s`: %s (the traceback goes to the log)",
				name_of(col),
				stage,
				M.one_line(said)
			)
		)
	end

	--- A `width` function returned something that is not a count of cells.
	--- supaline's own refusal, returned rather than raised by `listing.width`
	--- so that it is not worded as the function throwing, which it did not.
	---@param col supaline.ColumnPlan
	---@param refused string what it returned, as written
	local function bad_width(col, refused)
		if told(col, "width") then
			return
		end
		sink(
			string.format(
				"supaline: the `width` function of column `%s` returned %s; it must return a whole number of "
					.. "cells, 1 or more. Until it does, %s",
				name_of(col),
				refused,
				UNPADDED
			)
		)
	end

	--- Call a column's own code -- one of its four functions, or supaline's own
	--- walking what one returned -- and report a throw as `stage`'s. Every
	--- call into one of the four is made through here. Measured on 26.9.1: an
	--- error raised under a linemode's render blanks the whole screen, on every
	--- frame, and `refresh` runs from places nobody can raise to. The arguments
	--- go through as they came and two results come back, so a call per cell
	--- per row allocates nothing.
	---
	--- A `style` written as a function is not among the four: it is
	--- configuration, and `appearance.lua` refuses its throw the way it refuses
	--- a value.
	---@param col supaline.ColumnPlan
	---@param stage supaline.Stage
	---@param fn function
	---@return boolean ok
	---@return any
	---@return any
	local function call(col, stage, fn, ...)
		local ok, a, b = pcall(fn, ...)
		if not ok then
			broke(col, stage, a)
		end
		return ok, a, b
	end

	return { call = call, stats = no_extremes, width = bad_width }
end

return M
