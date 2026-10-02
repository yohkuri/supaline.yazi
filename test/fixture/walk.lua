--- @since 26.9.1

--- The fixture's `walk` plugin, copied to `config/plugins/walk.yazi/main.lua`
--- by `test/setup.py`. `test/fixture/walk.toml` is the list it walks, and the
--- keys in `test/fixture/keymap.toml` run it:
---
---     plugin walk -- next      the next step, or the first
---     plugin walk -- back      the step before
---     plugin walk -- yes       record "looks right" and go on
---     plugin walk -- no        record "looks wrong" and go on
---
--- Async rather than `@sync`, because a verdict is written with `fs.write`,
--- which only an async context may call. Measured on 26.9.1: from a sync entry
--- it raises "attempt to yield from outside a coroutine" -- and has written
--- the file anyway, so the error is no proof that nothing happened. A `shell`
--- template could write it from a sync entry instead, and expands `%s` in what
--- it writes to the hovered path.
---
--- The step lives in the plugin's own state, which `ya.sync` hands each
--- callback as `st`. That is the same table `init.lua`'s `require` returns,
--- measured on 26.9.1, so the status bar child `setup` adds reads it directly.

-- Filled in by `setup.py` as every file it copies is.
local CASES = "@DIR@/config/plugins/case.yazi/cases.lua"

-- `dofile` rather than `require`, for the reason `case.lua` gives. Read in
-- both contexts the plugin runs in, `init.lua`'s and the entry's. The verdicts'
-- name is in it because `manual.py` reads them back from the name `setup.py`
-- spells, and a second spelling here would be the one that drifts.
local LISTED = dofile(CASES)
local STEPS = LISTED.steps
local VERDICTS = "@DIR@/" .. LISTED.verdicts

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
	local step = STEPS[st.i]
	ya.emit("plugin", { "case", "theme " .. step.theme })
	ya.emit("plugin", { "case", "show " .. step.case })
end

local move = ya.sync(go)

--- The step a verdict is about, or `nil` before the walk has begun, with the
--- verdict recorded where the status bar reads it and the walk already on to
--- the next step. Both in this one call rather than the move after the write,
--- because entries run concurrently and the write yields: measured on 26.9.1,
--- `W y W x` sent in one burst put both verdicts on one step, skipped the next,
--- and wrote them in the reverse order. What is left is which of the two
--- reaches this first, the order the entries happen to start in: the same
--- burst swaps them about half the time, and keys 5ms apart did not. A write
--- that then fails is told in a notification, with the walk moved on
--- regardless.
---@param said string
---@return integer?
local mark = ya.sync(function(st, said)
	local i = st.i
	if i then
		st.said = st.said or {}
		st.said[i] = said
		if i < #STEPS then
			go(st, 1)
		end
	end
	return i
end)

--- The status bar's part: the step, its key and its question, and the verdict
--- already given if there is one. Nothing at all before the walk begins, so a
--- run that never starts it draws the status bar Yazi would.
function M:setup()
	-- Yazi's component, which `types.yazi` declares no global for.
	---@diagnostic disable-next-line: undefined-global
	local status = Status
	status:children_add(function()
		local step = self.i and STEPS[self.i]
		if not step then
			return ui.Line("")
		end
		local said = self.said and self.said[self.i]
		return ui.Line(
			string.format(
				" walk %d/%d · %s · %s%s ",
				self.i,
				#STEPS,
				step.key,
				step.ask,
				said and (" [" .. said .. "]") or ""
			)
		)
	end, 500, status.RIGHT)
end

---@param job { args: string[] }
function M:entry(job)
	local verb = job.args[1]
	if verb == "next" then
		return move(1)
	elseif verb == "back" then
		return move(-1)
	end

	local said = (verb == "yes" or verb == "no") and verb
	if not said then
		return
	end
	local i = mark(said)
	if not i then
		return ya.notify { title = "walk", content = "W n starts the walk; there is no step yet", timeout = 5 }
	end

	-- Appended, so a step answered twice is two lines and the later one wins
	-- when the file is read, rather than the first answer vanishing.
	local step = STEPS[i]
	local fd, err = fs.access():append(true):create(true):open(Url(VERDICTS))
	local ok = false
	if fd then
		ok, err = fd:write_all(string.format("%d\t%s\t%s\t%s\n", i, step.case, step.theme, said))
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
