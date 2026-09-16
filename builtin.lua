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
---
--- **None of them writes a `style`.** A cell with no style of its own is drawn
--- in whatever colour the file row already carries, which is the flavor's, and
--- that is what Yazi's own linemodes do -- `preset/components/linemode.lua`
--- returns bare strings. A colour named here would be the terminal palette's
--- instead: measured on 26.9.1 under catppuccin-mocha, a column written
--- `style = "cyan"` emitted the 4-bit ANSI escape for cyan while the row around
--- it was `#cdd6f4`, so the two columns that carried one were the only things
--- on the screen the flavor did not reach. `permissions` is the exception and
--- reads the theme, a character at a time, rather than a colour of its own.
--- The rule is not left to this paragraph: `builtin_spec.lua`'s
--- `no built-in names a colour` walks the registry and refuses a `style` on
--- any definition in it, including one added after this was written.
---
--- What they do differ in is `stats`, and there the difference is
--- load-bearing: `column.lua` refuses a gradient on a column that declares none,
--- so declaring one is the whole of what lets a user write a gradient over
--- that column. `size` and the three time columns do. `count` does not, and
--- cannot honestly -- `entries` below answers `-` for a directory Yazi has
--- never listed, so a folder's extremes would depend on where the user had
--- already been, and the same listing would colour differently on a second
--- visit. The rest have no number to take extremes of at all.

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
	local folder = (cx.active --[[@as supaline.Tab]]):history(file.url)
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
	scale = "log",
	stats = extremes(function(file) return file:size() end),
	---@type supaline.Render
	render = function(file, ctx)
		local size = file:size()
		if size then
			return ya.readable_size(size), ctx.style_at(ctx.ratio(size))
		end
		-- An unevaluated directory, exactly as the preset `size` linemode does.
		return entries(file), ctx.style
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
		-- The one option any built-in reads off `ctx.opts`, and declaring it is
		-- what lets `fromat` be refused on a column that takes a `format`.
		options = { "format" },
		stats = extremes(get),
		refresh = refresh_year,
		---@type supaline.Render
		render = function(file, ctx)
			local time = get(file)
			if not time or time == 0 then
				return "", ctx.style
			end

			-- A format is `os.date`'s alone: supaline reserves no word out of
			-- it, so a string carrying no `%` draws itself. Leaving `format`
			-- out is the whole of how the preset is asked for, and a second
			-- spelling of that would have to be a word taken out of a
			-- namespace this plugin does not own.
			local fmt = ctx.opts.format
			local text = fmt and os.date(fmt, time) or smart(time)
			return text, ctx.style_at(ctx.ratio(time))
		end,
	})
end

register_time("mtime")
register_time("btime")
register_time("atime")

--- The `[status]` style Yazi draws each permission character in, and the one
--- everything else takes -- the type character, whatever letter it turns out
--- to be.
---
--- Keyed on the character rather than on the position, which is what Yazi
--- does: measured against the status bar of a real 26.9.1, the leading `-` of
--- a regular file draws in `perm_sep` like any other bit that is off, and a
--- type character reaches `perm_type` only by being none of the characters
--- below. `d`, `l`, `r`, `w`, `x`, `s`, `t`, `-` and `?` were each produced
--- and read back out of `tmux capture-pane -e`; `S` and `T` -- a setuid or
--- sticky bit with the execute bit off -- were not, and are the source's
--- rather than the screen's. `Status:perm()` in
--- `yazi-plugin/preset/components/status.lua` at 26.9.1 branches on the
--- character just as this does, with `x`, `s`, `S`, `t` and `T` in one arm,
--- so the table below is Yazi's mapping character for character rather than
--- one that agrees with it as far as the screen was read.
---
--- Which is also why a socket's leading `s` draws in `perm_exec` rather than
--- `perm_type`: `ChaMode::permissions` writes `s` for a socket, and keying on
--- the character sends it where every other `s` goes. That is Yazi's own
--- behaviour, in its status bar exactly as here, and not a divergence.
---
--- `?` is `perm_sep` beside `-`, and is a whole string rather than a stray
--- character: `cha:perm()` on a file Yazi has no metadata for answers a type
--- character and nine of them. A row like that is not exotic -- Yazi builds
--- one whenever a listed entry cannot be stat-ed, and `reveal` on a path that
--- does not exist yet draws one outright.
local PERM, PERM_TYPE = {}, nil

--- Re-read the permission styles. Declared as the column's `refresh` hook, so
--- main.lua runs it whenever a linemode is installed -- which is what a `theme`
--- event does -- and on every `cd`.
---
--- That hook is the whole of why this column can read the theme at all. A
--- `th.status` read while `init.lua` runs is Yazi's preset: 26.9.1 merges
--- `theme.toml` before any plugin code runs but not the flavor, which arrives
--- with an unasked `theme` event a few milliseconds later. `refresh` runs
--- after both, and again after every reload.
local function refresh_perms()
	local st = th.status or {}
	PERM_TYPE = st.perm_type
	PERM = {
		["-"] = st.perm_sep,
		["?"] = st.perm_sep,
		r = st.perm_read,
		w = st.perm_write,
		x = st.perm_exec,
		s = st.perm_exec,
		t = st.perm_exec,
		S = st.perm_exec,
		T = st.perm_exec,
	}
end

--- One span per character of `perm`.
---
--- Ten `ui.Span` allocations per row per frame, and no way around them: a
--- listing shows a handful of distinct permission strings over dozens of rows,
--- but **`ui.Line` consumes the spans it is given**, so a list built once and
--- kept cannot be drawn twice. Measured on 26.9.1 -- the second `ui.Line` over
--- the same table raises `expected a string, Span, Line, or a table of them`,
--- and a linemode that raises stops drawing the pane. The styles are what the
--- `refresh` hook is for; only the spans are rebuilt.
---
--- `over` is the column's own `ctx.style`, and it goes *over* each character
--- rather than under the lot of them, which is the only layering that keeps
--- the promise the rest of the plugin makes: the nearest layer that wrote a
--- key wins. Under, a `[status]` style that writes the same key wins instead,
--- so a flavor with `perm_read = { fg = ..., bold = true }` takes
--- `style = { bold = false }` away from the user who wrote it. Measured both
--- ways on the stub, against a `[status]` carrying a `bold` and a `bg`.
---
--- It cannot take the colours with it. This branch is reached only when
--- `ctx.fg_written` is false, and that is exactly the case where no layer
--- wrote an `fg` -- so the style being patched over has none to overwrite,
--- and a gradient never arrives either, since `permissions` declares no
--- `stats` and a gradient without one is refused where it is written.
---
--- Ten patches per row per frame, and no test against nil to skip them with:
--- `ctx.style` is a style whether or not anybody wrote one. A skip means a
--- second question on the `ctx` beside `fg_written`, which is a documented
--- field for every column to carry so that one of them can skip ten merges
--- beside the ten `ui.Span` allocations above -- and those are the floor
--- here anyway.
---@param perm string
---@param over unknown a ui.Style to put over each character's own
---@return table[] spans
local function perm_spans(perm, over)
	local spans = {}
	for i = 1, #perm do
		local c = perm:sub(i, i)
		local style = PERM[c] or PERM_TYPE
		spans[i] = ui.Span(c):style(style and style:patch(over) or over)
	end
	return spans
end

-- The only built-in column that paints its own cell at all, and it takes the
-- colours out of the *theme* by following Yazi's own status bar rather than by
-- inventing a mapping: a user whose flavor already says what a write bit looks
-- like sees the same thing in both places, with nothing to configure.
--
-- Which is why it steps aside the moment a colour is written for it. An `fg`
-- in the spec's `style` or in the `[supaline] permissions` field of the theme
-- is a flat colour for the whole cell -- `false` included, which is a colour
-- turned off -- and painting the characters over it would leave the written
-- colour visible nowhere and say nothing about why. `ctx.fg_written` is that
-- question and nothing else.
--
-- A `bold` or a `bg` is not a colour, so it does not make the column step
-- aside: it goes over the ten characters, which keep the theme's own reds and
-- greens because the style going over them carries no colour at all.
-- `perm_spans` says how.
column.register("permissions", {
	width = 10,
	align = "left",
	refresh = refresh_perms,
	---@type supaline.Render
	render = function(file, ctx)
		local perm = file.cha:perm() or ""
		if perm == "" or ctx.fg_written then
			return perm, ctx.style
		end
		return ui.Line(perm_spans(perm, ctx.style))
	end,
})

--- One half of a file's ownership, as text, or nothing at all on a platform
--- with no names to give, and the column that draws it.
---
--- A half at a time rather than the pair, because `render` runs for every
--- visible row on every frame: a `user` column that resolved the group as well
--- would look up a name and build a Lua string per row only to drop it, and
--- `group` beside it would do the same in the other direction. `owner` is the
--- only one that wants both, and asks for them itself.
---
--- `ya.user_name` and `ya.group_name` read the passwd and group databases of
--- the machine Yazi is running on, so a name they return only means anything
--- for a file that lives on it. An SFTP file's IDs were minted on the server,
--- where the same number is very likely a different account; resolving those
--- here puts a confident and wrong name on screen. Yazi's own `owner` linemode
--- resolves them unconditionally, so these columns deliberately differ from it.
---
--- `spec.is_virtual` is the exposed complement of Yazi's internal
--- `AuthKind::is_local()`: false for the `regular` and `search` kinds, true for
--- `mount`, `hub`, `scope` and `sftp`. Keying on it rather than on the `sftp`
--- scheme errs towards the numbers, so a remote scheme added in a later Yazi is
--- never given a name it has not earned. `file.url` and `.spec` are both cached
--- fields, so this is two field reads: measured at roughly twice a `cha.uid`
--- read on a real Yazi, which is far below anything worth hoisting.
---
--- `cha.uid` and `cha.gid` are `u32` in Yazi rather than `Option<u32>`, so Lua
--- is handed a number for every file on every platform and there is no "this
--- file has no owner" to ask about. On Windows that number is the `0` the
--- Rust filled in, which is why the column has to ask the *platform* instead:
--- `ya.user_name` and `ya.group_name` are `#[cfg(unix)]`, so their absence is
--- the question "does this build have names at all", and the answer there is
--- nothing rather than `0`. That is what `cha:perm()` already does for the
--- `permissions` column, and what Yazi's own `owner` linemode does not -- it
--- draws `0:0`. Read from the v26.9.1 source; no Windows machine was run.
---
--- The order is deliberate. A remote file's IDs come off the server -- an
--- SFTP `Cha` carries the attrs' `uid` and `gid` whatever the host is -- so
--- they are worth printing on a platform that could not have named them
--- anyway, and the virtual test comes first.
--- Registers the column that draws one half on its own, and hands the
--- resolution back for `owner` to reuse -- the shape `register_time` above
--- uses for the three time columns, which is why the width and the alignment
--- of a half are written once rather than once per column.
---
--- Eight is the traditional passwd limit rather than a measurement, and a
--- machine whose names run past it has `width = "auto"` like any column.
---@param name "user"|"group"
---@param field "uid"|"gid"
---@param lookup "user_name"|"group_name"
---@return fun(file: supaline.File): string?
local function register_half(name, field, lookup)
	local of = function(file)
		local id = file.cha[field]
		if file.url.spec.is_virtual then
			return tostring(id)
		end

		-- Read per row rather than captured when this file is loaded, and the
		-- reason is the test rather than the clock: `builtin_spec.lua` has no
		-- Windows machine, so it takes the two lookups off `ya` between renders
		-- and a captured upvalue would go on answering. The read itself is one
		-- table index, against a `ya` that resolves a utility once and keeps it.
		local found = ya[lookup]
		if not found then
			return nil
		end

		-- `tostring` only where the name is missing and the id has to stand in
		-- for it. A resolved name is already a string, and this runs per row.
		return found(id) or tostring(id)
	end

	column.register(name, {
		width = 8,
		align = "left",
		---@type supaline.Render
		render = function(file, ctx) return of(file) or "", ctx.style end,
	})
	return of
end

-- The two halves on their own, for a listing where only one of them is worth
-- the cells -- a home directory whose every file carries the same group, say.
local user_of = register_half("user", "uid", "user_name")
local group_of = register_half("group", "gid", "group_name")

-- ... and the pair, as the composition of the two rather than a third copy of
-- the rule they follow.
column.register("owner", {
	width = 12,
	align = "left",
	---@type supaline.Render
	render = function(file, ctx)
		local user = user_of(file)
		if not user then
			return "", ctx.style
		end
		-- No second guard: both halves ask the same platform the same question,
		-- so a build that answered one of them answers the other.
		return string.format("%s:%s", user, group_of(file)), ctx.style
	end,
})

column.register("count", {
	width = 5,
	align = "right",
	---@type supaline.Render
	render = function(file, ctx)
		if not file.cha.is_dir then
			return "", ctx.style
		end
		return entries(file), ctx.style
	end,
})

-- Yazi wraps every module in a state table, so a file that exists only for its
-- side effects still has to return one. There is nothing to export: a column
-- that caches something across rows says so with a `refresh` field on its own
-- definition, which is a user column's route as much as a built-in's.
return {}
