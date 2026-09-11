--- @since 26.9.1
--- The columns that ship with supaline.
---
--- Every one of these goes through `column.register()`, the same entry point a
--- user column uses; there is no privileged internal path.
---
--- Their widths are stated outright rather than measured. Measuring means
--- rendering every file in the folder on each `cd`, which is the right trade
--- only when the user asks for it -- `width = "auto"` is available on any
--- column, these included.

local column = require(".column")

-- Extremes of the current listing, the way `eza --color-scale-mode=gradient`
-- takes them. In `column.lua` rather than here, because a user-written ranged
-- column wants the same loop and cannot require this file.
local extremes = column.extremes

--- The entry count of an already-visited directory. Yazi keeps folders it has
--- listed in the tab's history; one it has never opened has no count to show.
---@param file supaline.File
---@return string
local function entries(file)
	local folder = cx.active:history(file.url)
	return folder and tostring(#folder.files) or "-"
end

-- `ya.readable_size` keeps the mantissa in (1, 1024] and strips a trailing
-- ".0", so the widest result it can produce is "1023.9K".
-- `scale = "log"` on the definition, where the fallback is linear and is right
-- for a timestamp.
--
-- A listing's sizes span orders of magnitude and its extremes are almost always
-- one huge file and one tiny one, so a linear ratio puts everything but the
-- largest file on the floor: measured over the harness fixture, 1B to 88M, a
-- 300K file lands at 0.003 linear and 0.68 log. eza colours sizes on a linear
-- ratio and this is exactly how it looks -- every file below the biggest draws
-- the same colour.
--
-- A default, not a decision taken out of the user's hands: a `scale` written
-- in `setup` outranks this, and one written in the spec outranks that.
-- `column.lua` resolves the three.
column.register("size", {
	width = 7,
	align = "right",
	base = "cyan",
	scale = "log",
	stats = extremes(function(file) return file:size() end),
	---@type supaline.Render
	render = function(file, ctx)
		local size = file:size()
		if size then
			return ya.readable_size(size), ctx.style(ctx.ratio(size))
		end
		-- An unevaluated directory, exactly as the preset `size` linemode does.
		return entries(file), ctx.base
	end,
})

-- The current year as an epoch range, so `smart` decides which format to use
-- with an integer comparison. Asking `os.date("%Y", time)` per row would mean
-- a `localtime`, a `strftime` and a fresh string for every timestamp cell on
-- every frame, only to pick a branch.
--
-- `os.time` reads its table as local time, so the bounds follow the same
-- offset -- and the same DST -- that `os.date` would have applied.
local YEAR_FROM, YEAR_TO = 0, 0

--- Re-read the year. Declared as the `refresh` hook of every time column, so
--- main.lua runs it whenever a linemode is installed and on every `cd`. A
--- session left open across New Year and never navigated still shows the old
--- year's formatting until something moves.
local function refresh_year()
	local y = tonumber(os.date("%Y")) --[[@as integer]]
	YEAR_FROM = os.time { year = y, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
	YEAR_TO = os.time { year = y + 1, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
end

refresh_year()

--- Yazi's preset formatting: time of day within the current year, the year
--- itself for anything older, so the column keeps one width either way.
---@param time integer
---@return string
local function smart(time)
	if time >= YEAR_FROM and time < YEAR_TO then
		return os.date("%m/%d %H:%M", time) --[[@as string]]
	end
	return os.date("%m/%d  %Y", time) --[[@as string]]
end

---@param field "mtime"|"btime"|"atime"
local function register_time(field)
	---@param file supaline.File
	local get = function(file)
		local t = file.cha[field]
		return t and math.floor(t) or nil
	end

	column.register(field, {
		width = 11,
		align = "right",
		base = "blue",
		stats = extremes(get),
		refresh = refresh_year,
		---@type supaline.Render
		render = function(file, ctx)
			local time = get(file)
			if not time or time == 0 then
				return "", ctx.base
			end

			local fmt = ctx.opts.format
			local text = (not fmt or fmt == "smart") and smart(time) or os.date(fmt, time)
			return text, ctx.style(ctx.ratio(time))
		end,
	})
end

register_time("mtime")
register_time("btime")
register_time("atime")

column.register("permissions", {
	width = 10,
	align = "left",
	---@type supaline.Render
	render = function(file, ctx) return file.cha:perm() or "", ctx.base end,
})

column.register("owner", {
	width = 12,
	align = "left",
	---@type supaline.Render
	render = function(file, ctx)
		local cha = file.cha
		if not cha.uid then
			return "", ctx.base
		end

		-- `ya.user_name` and `ya.group_name` read the passwd and group
		-- databases of the machine Yazi is running on, so a name they return
		-- only means anything for a file that lives on it. An SFTP file's IDs
		-- were minted on the server, where the same number is very likely a
		-- different account; resolving those here puts a confident and wrong
		-- name on screen. Yazi's own `owner` linemode resolves them
		-- unconditionally, so this column deliberately differs from it.
		--
		-- `spec.is_virtual` is the exposed complement of Yazi's internal
		-- `AuthKind::is_local()`: false for the `regular` and `search` kinds,
		-- true for `mount`, `hub`, `scope` and `sftp`. Keying on it rather
		-- than on the `sftp` scheme errs towards the numbers, so a remote
		-- scheme added in a later Yazi is never given a name it has not
		-- earned. `file.url` and `.spec` are both cached fields, so this is
		-- two field reads: measured at roughly twice a `cha.uid` read on a
		-- real Yazi, which is far below anything worth hoisting.
		if file.url.spec.is_virtual then
			return string.format("%s:%s", cha.uid, cha.gid), ctx.base
		end

		local user = ya.user_name and ya.user_name(cha.uid) or cha.uid
		local group = ya.group_name and ya.group_name(cha.gid) or cha.gid
		return string.format("%s:%s", user, group), ctx.base
	end,
})

column.register("count", {
	width = 5,
	align = "right",
	---@type supaline.Render
	render = function(file, ctx)
		if not file.cha.is_dir then
			return "", ctx.base
		end
		return entries(file), ctx.base
	end,
})

-- Yazi wraps every module in a state table, so a file that exists only for its
-- side effects still has to return one. There is nothing to export: a column
-- that caches something across rows says so with a `refresh` field on its own
-- definition, which is a user column's route as much as a built-in's.
return {}
