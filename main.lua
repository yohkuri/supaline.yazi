--- @since 26.9.1
--- supaline -- a column framework for Yazi's linemode.
---
--- `setup` turns each entry of `linemodes` into a real linemode, so
--- `mgr.linemode` and the `linemode` action switch between them exactly the way
--- they switch between Yazi's own.
---
--- Rendering runs for every visible row on every frame, so it does little but
--- read from tables: per-folder statistics and derived widths are computed once
--- per folder and cached here, then bound onto each column whenever the folder
--- being drawn changes.

-- Required for its side effects: loading it registers the built-in columns
-- through `column.register`, the same entry point a user column uses.
require(".builtin")
local colour = require(".colour")
local column = require(".column")

-- Yazi calls `Linemode` for three panes. `solo()` guards `in_current` itself,
-- so a linemode never reaches the other two; a child added with
-- `children_add` is called for all of them and has to decide for itself.
local PANES = { "current", "parent", "preview" }

---@type supaline.Cfg
local DEFAULTS = {
	-- The string a user writes, not the record `render` reads. Every separator
	-- in the plugin now becomes a record in the same place and on the same
	-- pass -- `compile` -- so the default is not the one that skips the reader,
	-- and there is no second shape for a future invariant to miss.
	separator = " ",
	-- Order of the parent/preview child among Linemode's children. Anything
	-- below `padding` (2000) keeps it inside the linemode block.
	order = 1400,
	-- No `scale` here, on purpose, and it is the only option that is missing
	-- one. The other two have nowhere else to come from; a scale can also be
	-- stated on a column's own definition -- `size` states `log`, because its
	-- values span orders of magnitude where a timestamp's do not -- so a
	-- default written here would have to outrank that definition or lose to it,
	-- and either way one of the two is unreachable.
	--
	-- Left nil instead, so `cfg.scale` means "the user wrote a scale in
	-- `setup`" and nothing else. `column.lua` resolves the three sources in
	-- order and holds the fallback for a column that gets none of them.
	--
	-- No band, and that one has no default anywhere rather than a default kept
	-- elsewhere. A band's two ends are lightnesses the ground it is drawn on
	-- decides; supaline cannot see that ground, so a pair written here would be
	-- a guess applied to everyone who never asked. `colour.lua` holds the pair
	-- it recommends, the refusals quote it, and a `<->` with no band behind it
	-- is refused rather than drawn.
	--
	-- Empty rather than absent, unlike `scale`: this is the namespace itself,
	-- not a band in it, and the field is what every `<->` is looked up in. It
	-- is also exactly what `colour.bands` returns for a `setup` that wrote no
	-- band, so the record before any `setup` and the record after an empty one
	-- are the same record, and a `<->` reaching either is refused by the same
	-- line.
	band = {},
}

--- The module table, as a spec sees it.
---
--- In this checkout and on the CI runner, `require(".main")` does not resolve
--- to this file. `types.yazi` ships a `main.lua` of its own -- 3,235 lines of
--- annotations, and no `return` -- and it sits on `workspace.library`, so the
--- name resolves there and every call a spec makes into the plugin is checked
--- against a module that exports nothing. Nothing says so:
--- `main.setup(42, ...)` and `main.columnn(...)` were both accepted before
--- this class existed.
---
--- Declaring the shape here and claiming it at the `require` is what puts those
--- calls back under the check, the same way `supaline.Stub` does for the stub.
--- Both entry points take a dot call and a colon call, and a `@field` carries
--- no `@overload`, so each is written as the union of its two shapes -- leave
--- one out and the spec that writes it that way is refused for no reason.
---
--- Which of the two files wins follows from the absolute path this tree sits
--- at, not from either name: a checkout sorting before
--- `~/.config/yazi/plugins/types.yazi/` reads `.main` from here instead. The
--- class is claimed at the `require` either way and stays right;
--- `annotate-supaline/references/main-collision.md` has the measurement and
--- the paths that flip it.
---@class supaline.Main
---@field setup fun(st: table, opts: supaline.Opts?)|fun(opts: supaline.Opts)
---@field column fun(name: string, def: supaline.ColumnDef)|fun(self: table, name: string, def: supaline.ColumnDef)
---@field extremes fun(get: fun(file: supaline.File): number?): fun(files: supaline.File[]): table?

local M = {}

--- What the user writes for one linemode: the columns in order, or a list of
--- columns under each pane that draws something, and the one option that
--- belongs to the linemode rather than to any column in it.
---
--- A pane is a key here rather than a value, so each of the three is a declared
--- field and `parent = 42` is refused by name. A key that is none of the four
--- names is past what the checker reaches into a table constructor, which is
--- what `OPTIONS` below is for.
---@class supaline.LinemodeSpec
---@field [integer] supaline.ColumnSpec
---@field current supaline.ColumnSpec[]? what the current pane draws, instead of the list above
---@field parent supaline.ColumnSpec[]? what the parent pane draws; nothing by default
---@field preview supaline.ColumnSpec[]? what the preview pane draws; nothing by default
---@field separator string|supaline.SepSpec|nil overrides the plugin-wide one

--- The table `setup` is handed. `linemodes` is the only field it cannot do
--- without and it is still optional here, because `setup` takes the dot call
--- as well as the colon call and has to look at what arrived before it can
--- say which one it was.
---@class supaline.Opts
---@field linemodes table<string, supaline.LinemodeSpec>?
---@field separator string|supaline.SepSpec|nil
---@field order integer?
---@field scale "linear"|"log"|nil
---@field band supaline.Bands? the bands a `<->` may name, by name

-- What `setup` itself takes, which is the only thing that refuses everything
-- else. The same reason `OPTIONS` above has, one level up: a key in the table
-- constructor `setup` is handed is past what `lua-language-server` checks
-- against `supaline.Opts` -- `(exact)` was measured not to change that -- so
-- `bnad`, `scal` and `seperator` reach this or they reach nobody. A `band`
-- written `bnad` defines no band at all, so the `<->`s that were to use it are
-- each refused for naming nothing -- loud, but pointed at the wrong table: the
-- reader is told to define `fg` while a whole `fg` sits three lines above,
-- spelled right, under a key nobody reads.
--
-- This is the outermost of the five tables a user writes. The other four -- a
-- linemode spec, a separator, a style, and a column spec or definition -- are
-- swept the same way, through `colour.unknown`.
local SETUP_KEYS = {
	band = true,
	linemodes = true,
	order = true,
	scale = true,
	separator = true,
}

local function claims_setup(key) return SETUP_KEYS[key] end

-- The keys above, in the order the message lists them. Sorted for the reason
-- `column.lua` sorts its own: `pairs` gives a set back in whatever order the
-- hash does, and a message that reorders itself between runs reads as a
-- different message.
local SETUP_KEY_LIST
do
	local names = {}
	for key in pairs(SETUP_KEYS) do
		names[#names + 1] = key
	end
	table.sort(names)
	SETUP_KEY_LIST = colour.key_list(names)
end

-- What a key that is none of them most likely meant. Both are mistakes about
-- where a thing goes rather than misspellings: one linemode written where the
-- table of them goes, and a linemode's columns written beside the table
-- instead of inside a linemode in it.
local SETUP_MEANT = {
	linemode = "`linemodes` is the spelling, and it is a table of them keyed by the name " .. "each one is switched to",
	columns = 'columns go inside a linemode -- `linemodes = { detail = { "size", "mtime" } }` '
		.. "-- rather than beside the table of them",
}

local SETUP_UNKNOWN = "supaline: %s. `setup` takes %s%s"

local cfg = DEFAULTS
local specs = {} ---@type table<string, supaline.LinemodeSpec> the user's linemode definitions

-- One record per linemode -- the class below -- rather than three tables keyed
-- by the same name. `render` and `child` then take one hash lookup per row
-- between them instead of three, and there is one thing to keep in step
-- instead of three.

--- One linemode in service. `compile` is the only thing that builds one, and
--- every field is read per row.
---@class supaline.Mode
---@field name string
---@field cols table<string, supaline.Column[]> what each pane draws, by pane name
---@field outer boolean whether it draws anywhere but the current pane
---@field sep supaline.Sep what goes between two columns

local linemodes = {} ---@type table<string, supaline.Mode>

-- The `refresh` hooks of every column in service, flattened. A column that
-- caches something across rows -- the current year, say -- declares one, and it
-- is run whenever a linemode is installed and on every `cd`.
local refreshers = {} ---@type table<integer, function>

-- Statistics and derived widths, keyed by linemode, folder and file count. The
-- count catches the common case of a file being added or removed; a write that
-- leaves it unchanged keeps stale extremes until the next file operation or
-- `cd`, which is the trade that keeps rendering O(1) per row.
local cache, cache_n = {}, 0 ---@type table<string, supaline.Entry[]>, integer

-- The pane last bound, held as its four parts rather than as the composed
-- key. `bind` runs for every visible row on every frame and almost always
-- finds nothing has changed, so the check it does first has to be cheap:
-- `tostring(cwd)` crosses into Rust to build a path string, and the key
-- concatenates three more. Comparing the parts is enough to decide.
--
-- `folder.cwd` is a cached field, so within a frame both sides of the `cwd`
-- test are the same userdata and Lua settles it by pointer without reaching
-- for `__eq` at all; across frames it falls back to one Rust-side path
-- comparison, which still allocates nothing.
local bound_name, bound_pane, bound_cwd, bound_n = nil, nil, nil, nil

-- Everything a previous `setup` put on `Linemode`, so the next one can take it
-- back off. Two names and a child id would each be their own special case, and
-- the one left without a case is the one that leaks: `Linemode[name]` was, and
-- a linemode dropped by a second `setup` stayed registered and drew nothing --
-- where Yazi draws an unregistered name as literal text.
--
-- `prev` holds what each name was bound to before, which is what lets an
-- override of one of Yazi's own linemodes be handed back.
local installed = { names = {}, prev = {}, child = nil } ---@type table

-- Yazi keeps the component's own machinery on the very table the linemodes are
-- looked up on, so a linemode named after any of it silently replaces the
-- machinery -- `new` takes out the constructor, `padding` takes out a child
-- every row draws.
--
-- The check asks `Linemode` what it holds rather than listing it: Yazi is on
-- CalVer and adds to the component between releases, and a name written down
-- here goes stale the moment it does. Only Yazi's own linemodes are exempt --
-- replacing `size` is a thing to want, replacing `redraw` is not. `none` is
-- deliberately not among them, because `solo()` returns before it could ever
-- dispatch to it.
local OVERRIDABLE = {
	size = true,
	permissions = true,
	btime = true,
	mtime = true,
	atime = true,
	owner = true,
}

-- Names supaline itself put on `Linemode`, so calling `setup` twice does not
-- refuse everything the first call registered.
local ours = {} ---@type table<string, boolean>

--- Whether `name` would replace something of Yazi's rather than sit alongside
--- it.
---@param name string
---@return boolean
local function is_yazis(name)
	if OVERRIDABLE[name] or ours[name] then
		return false
	end
	return Linemode[name] ~= nil or name:sub(1, 1) == "_"
end

-- Quoted by every refusal that is about the shape of a linemode. A message
-- that says what is wrong without saying what to write instead sends the
-- reader back to the README for the half it left out, which is why the one
-- below names the keys a linemode takes rather than only the key it got.
local PANES_HELP = "supaline: a linemode is a list of columns, drawn in the current pane -- "
	.. 'e.g. { "size", "mtime" } -- or a list of columns under each pane it draws in -- '
	.. 'e.g. { current = { "size" }, parent = { "count" } }'

-- What a linemode may carry besides its columns and its panes. Anything else
-- is refused rather than ignored, because nothing else refuses it: a key in a
-- table constructor is past what `lua-language-server` checks against the
-- class -- `(exact)` was measured not to change that -- so `separatorr` and
-- `parnet` reach here or they reach nobody.
local OPTIONS = { separator = true }

local OPTION_HELP = "supaline: besides its columns a linemode takes `current`, `parent`, "
	.. "`preview` and `separator`; got %s"

-- A separator is drawn before its column, so the first column of a pane's
-- list has nothing before it and `render` skips the separator there. Written
-- on that column anyway, a `separator` is drawn nowhere and says nothing --
-- the silence every other refusal in this file exists for.
--
-- The message names the pane, because a list is the pane's rather than the
-- linemode's: two panes of one linemode each have a first column, and only a
-- list written under both is the same one twice.
local FIRST_SEP = "supaline: the first column of `%s` on linemode `%s` was given a "
	.. "`separator`, which is drawn by nobody: a separator goes before its column, and "
	.. "the first column has nothing before it. Write it on the column it should "
	.. "precede, or drop it -- `separator = false` is accepted there, since it asks for "
	.. "nothing and gets nothing"

-- `PANES` as a set, so a key can be classified without walking it. Derived
-- rather than written out, because a list and a set of the same three names
-- are two things to keep in step.
local IS_PANE = {} ---@type table<string, boolean>
for _, pane in ipairs(PANES) do
	IS_PANE[pane] = true
end

-- What a linemode spec is entitled to: its columns at the numeric keys, a pane
-- name, or one of the options above.
local function claims_spec(key) return type(key) == "number" or IS_PANE[key] or OPTIONS[key] end

--- How many columns are written in `list`, counting the ones `ipairs` would
--- never reach. `compile` walks a column list with `ipairs`, so it stops at
--- the first missing index and anything past a gap draws nowhere -- the same
--- silence a key nobody claimed is refused for, arrived at by arithmetic
--- rather than by spelling.
---
--- `#list` is what `ipairs` will reach and this is what was written, so the
--- two differing is the whole of the test. `#` alone cannot make it: a list
--- that starts at index 2 has an entry in it and a `#` of 0.
---@param list table
---@return integer
local function entries_of(list)
	local n = 0
	for key in pairs(list) do
		if type(key) == "number" then
			n = n + 1
		end
	end
	return n
end

--- What each pane of a linemode draws, keyed by pane name, with a pane that
--- draws nothing absent rather than empty. One table answers both "which
--- panes" and "which columns", so there is one thing for `compile` to walk and
--- one thing per row to look up.
---
--- A linemode written as a bare list of columns draws them in the current pane
--- and nowhere else, which is all Yazi itself does. Naming a pane gives that
--- pane a list of its own, and is then the only place columns may be written:
--- a list left beside the pane keys would be drawn nowhere, and drawing
--- nothing without a word is the failure this refuses rather than ships.
---@param spec supaline.LinemodeSpec
---@return table<string, supaline.ColumnSpec[]> by pane
local function panes_of(spec)
	local sets = {}
	for _, pane in ipairs(PANES) do
		local list = spec[pane]
		if list ~= nil then
			if type(list) ~= "table" then
				error(string.format("%s; `%s` was given a %s rather than a list of columns", PANES_HELP, pane, type(list)))
			elseif #list == 0 then
				-- Leaving the pane out says exactly this and says it in one
				-- place, so an empty list is a second spelling of nothing.
				error(string.format("%s; `%s` was given an empty list -- leave the pane out instead", PANES_HELP, pane))
			end
			-- A pane takes columns and nothing else. The options live on the
			-- linemode, one level up, where they apply to every pane it draws
			-- in -- and a name written in here is not refused for being the
			-- wrong option but dropped for being somewhere `ipairs` never
			-- goes, which is the same silence again.
			for key in pairs(list) do
				if type(key) ~= "number" then
					error(
						string.format(
							"%s; `%s` takes a list of columns and nothing else, and was given "
								.. "`%s` beside them -- an option goes on the linemode itself",
							PANES_HELP,
							pane,
							tostring(key)
						)
					)
				end
			end
			if entries_of(list) ~= #list then
				error(string.format("%s; `%s` has a gap in its numbering", PANES_HELP, pane))
			end
			sets[pane] = list
		end
	end

	local _, unknown = colour.unknown(spec, claims_spec)
	if unknown then
		error(string.format(OPTION_HELP, unknown))
	end

	if next(sets) == nil then
		-- No pane was named, so the linemode's own list is what the current
		-- pane draws. An empty one draws nothing there, which is a thing to
		-- ask for and is pinned as one -- a gap in a list that has entries is
		-- not, and is refused here as it is under a pane.
		if entries_of(spec) ~= #spec then
			error(string.format("%s; this one has a gap in its numbering", PANES_HELP))
		end
		return { current = spec }
	-- Every column written on the linemode, not the ones `ipairs` would reach.
	-- A list starting at index 2 has a `#` of 0, so asking `#` here let a
	-- stray column through the moment a pane was named -- and refused the very
	-- same column when it sat at index 1.
	elseif entries_of(spec) > 0 then
		error(
			"supaline: a pane's columns are written under that pane's own name, so the "
				.. "columns beside them on the linemode would be drawn nowhere; move them "
				.. "under a pane"
		)
	end
	return sets
end

--- Which of the two panes outside the current one a row is in, and the folder
--- it belongs to. Statistics for such a row have to come from that pane's
--- folder, not from `cx.active.current`.
---
--- Only ever asked about a row already known not to be `in_current`, because
--- that is one free field read and this is not.
---
--- `in_preview` is not the counterpart of `in_current` its name suggests.
--- `in_current` is folder-wide -- Yazi compares the row's folder against the
--- tab's current one -- but `in_preview` is
---
---     me.idx == me.folder.cursor && tab.hovered() is this folder
---
--- so it is set on the previewed folder's *cursor row alone*. Every other
--- preview row reports false, and there is no `in_parent` to tell it apart
--- from a parent-pane row: both are simply "not current". Ask the preview
--- folder whether the row is one of its own instead.
---@param file supaline.File
---@return string pane, supaline.Folder? folder
local function pane_of(file)
	-- `idx` is the row's 1-based position in its own folder, so this is O(1).
	--
	-- Cast at the boundary, here and below: Yazi hands back a `tab__Folder`,
	-- and what makes it a `supaline.Folder` is the listing's element type,
	-- which is this plugin's claim about Yazi rather than Yazi's own.
	local folder = cx.active.preview.folder --[[@as supaline.Folder?]]
	local at = folder and folder.files[file.idx]
	if at and at.url == file.url then
		return "preview", folder
	end
	return "parent", cx.active.parent --[[@as supaline.Folder?]]
end

--- Put a report in the log in full and a short form of it on the screen.
---
--- Both halves, always, and that pairing is the whole of what this holds. A
--- notification times out and is gone; `yazi.log` is where a reader goes
--- afterwards, and where a traceback or a nested `CallbackError` is worth
--- keeping at whatever length it comes in. What the screen gets is cut to the
--- sentence that says what to change, because a notification long enough to
--- fill the preview pane pushes its own first line off the top of it --
--- measured twice, on `build`'s three stacked tracebacks and on `broke`'s.
---
--- The four callers word their own strings and share nothing else; what they
--- must not each decide is the level, the timeout and the title. Two of them
--- pass one string, which says the whole of it is already short enough for the
--- screen -- a refusal supaline worded itself, rather than something a
--- traceback came wrapped around.
---@param logged any the whole of it, error object or string
---@param shown string? the one sentence for the screen, if it is not the whole
local function report(logged, shown)
	ya.err(logged)
	ya.notify { title = "supaline", content = shown or logged, level = "error", timeout = 10 }
end

--- One line of what a `pcall` handed back, with Lua's wrapper off the front.
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
local function one_line(err) return (tostring(err):gsub("\nstack traceback:.*", ""):gsub("^runtime error: ", "")) end

--- Whether this column has already been told off for `what`, marking it told
--- if it has not.
---
--- Everything below reports from inside a render pass -- the folder pass for
--- two of them, a per-row path for the third -- so an ungated report is a
--- drip rather than a message. Measured on 26.9.1: ungated it is not even a
--- hang, the notification redraws, the redraw renders, the render notifies,
--- and the loop settles at about one a second and never stops.
---
--- Asked before each caller builds its message, never after, since building
--- one per row of every frame is the cost the gate exists to avoid.
---
--- Per column rather than per column and folder: a `stats` that came back
--- wrong is wrong about the column, and saying it again at every folder the
--- reader walks into would be the same drip more slowly. `setup` builds
--- fresh records, which re-arms all of it -- a reader who has just changed
--- the configuration is owed the message again.
---@param col supaline.Column
---@param what "stats"|"width"|"threw"
---@return boolean # true if it has been said already
local function told(col, what)
	if col.told[what] then
		return true
	end
	col.told[what] = true
	return false
end

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
---@param col supaline.Column
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

--- Say once that a column threw, and go on drawing everything else.
---
--- A column may write three functions -- `stats`, a `width` that is one, and
--- `render` -- and all three are called inside Yazi's redraw. **Measured on
--- 26.9.1**: an error raised anywhere under a linemode's render fails the
--- whole `Root` component, not the row and not the pane. The file list, the
--- header and the status bar all stop drawing, it happens again on every
--- frame for as long as that folder is open, and Yazi goes on taking keys
--- against a screen that is blank but for the preview's own placeholder. The
--- message reaches the log and nowhere else -- and there is no log at all
--- unless `YAZI_LOG` was set before Yazi started, which is not how anybody
--- runs it. So the reader is left with an empty terminal and nothing to read.
---
--- That is worse than any mistake it could be reporting, so the three calls
--- are made under `pcall` and this says what happened instead. It is the same
--- judgement `no_extremes` is, reached for the same reason and from the same
--- measurement; what is new here is that the throw need not be supaline's. A
--- reader's own `render` raising produced exactly the blank screen above, with
--- no part of this plugin involved in raising it.
---
--- One report across all three stages, not one each: what the reader has to
--- look at is the column, and the first thing of theirs it threw from is
--- where they will start. `told` holds that, and holds it hardest here --
--- this is the one of the three reached from a per-row path.
---
--- What it does **not** cover is a `width` function that came back with a
--- number nobody can use. That one is supaline's own refusal, `resolve_width`
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
---@param col supaline.Column
---@param stage string which of the three threw, named as the reader wrote it
---@param err any what it threw
local function broke(col, stage, err)
	if told(col, "threw") then
		return
	end

	local said = tostring(err)
	report(
		string.format(
			"supaline: column `%s` threw from its `%s`. Everything else on the line goes on "
				.. "drawing, and a cell this column cannot draw at all is filled with `%s` so "
				.. "that the row keeps its shape. It threw: %s",
			col.name or "?",
			stage,
			BROKEN,
			said
		),
		string.format(
			"column `%s` threw from its `%s`: %s (the traceback is in the log)",
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
--- why it arrives as a string from `resolve_width` instead of out of a
--- `pcall`: that function returns it so that this can be worded as what it
--- is. `broke` above has the other half of the argument.
---
--- What the reader sees instead of a width is the column unpadded -- it draws
--- whatever its `render` returns, at whatever width that is, so a listing of
--- uneven names comes out ragged. Ragged and readable is the right trade
--- against a stated `width = 0`, which `setup` refuses outright: that one is
--- knowable before anything draws, and this one is not knowable until the
--- folder it was handed exists.
---@param col supaline.Column
---@param why string the refusal, already worded by `column.lua`
local function bad_width(col, why)
	if told(col, "width") then
		return
	end

	local said = string.format(
		"%s. Until it does, this column draws unpadded: everything else on the line keeps its "
			.. "place and this one is ragged rather than absent",
		why
	)
	report(said)
end

--- Bind one folder's statistics and widths onto every column of a linemode.
--- Cheap and idempotent: it does nothing at all while the pane being drawn has
--- not changed.
---@param name string
---@param pane string the pane being drawn
---@param cols supaline.Column[] what that pane draws
---@param folder supaline.Folder?
local function bind(name, pane, cols, folder)
	if not folder then
		-- The pane is in this test for the same reason it is in the key below,
		-- and is insurance in the same way: only the parent pane can be
		-- without a folder, so the two panes it tells apart cannot both
		-- arrive here.
		if bound_name ~= false or bound_pane ~= pane then
			bound_name, bound_pane, bound_cwd, bound_n = false, pane, nil, nil
			for _, col in ipairs(cols) do
				column.bind(col, {})
			end
		end
		return
	end

	local files, cwd = folder.files, folder.cwd
	local n = #files
	if bound_name == name and bound_pane == pane and bound_n == n and bound_cwd == cwd then
		return
	end

	-- The pane is part of the identity because two panes of one linemode may
	-- draw different columns, and `entries` is positional. Nothing puts one
	-- folder in two panes at once -- the parent, the current and the hovered
	-- directory are three different folders -- so this is insurance rather
	-- than a case anyone has seen, and it costs one comparison on an interned
	-- string.
	local key = name .. "\0" .. pane .. "\0" .. tostring(cwd) .. "\0" .. n
	local entries = cache[key]
	if not entries then
		entries = {}
		for i, col in ipairs(cols) do
			local entry = {}
			if col.needs_pass then
				if col.stats then
					local ok, got = pcall(col.stats, files)
					if ok then
						entry.stats = got
					else
						broke(col, "stats", got)
					end
				end
				-- Here rather than in `column.bind`, which is handed an entry and
				-- cannot tell a `stats` that returned wrong from a column that has
				-- none: the no-folder path binds `{}` onto columns whose `stats`
				-- was never called. This is the line that called it.
				--
				-- `nil` is not a wrong answer and is not reported. It is what a
				-- `stats` says when the folder in front of it has nothing to
				-- measure, and `size` says it for a directory of directories --
				-- pinned by `builtin_spec.lua`'s "a folder with nothing to
				-- measure has no extremes". Reporting it would put a
				-- notification on the screen of anybody who walked into such a
				-- folder, about a built-in doing exactly what it is written to
				-- do. What the column does instead is draw its ramp's low end
				-- throughout, which is the honest answer to a listing with no
				-- range in it.
				--
				-- The same test covers a `stats` that threw. That one left
				-- `entry.stats` nil and `broke` has already named the column, so
				-- without it this would say a second and different thing about
				-- the same mistake -- and say the wrong one, since what came
				-- back was nothing at all rather than a table missing a pair.
				if col.ramped and entry.stats ~= nil and not column.has_extremes(entry.stats) then
					no_extremes(col)
				end
				-- The width pass renders every file, and those renders read
				-- `ctx.ratio`, so the extremes have to be in place first.
				column.bind(col, entry)
				-- Three outcomes, and the two that are not a width are different
				-- mistakes with different sentences. `ok` false is Lua raising:
				-- a `width` function that threw, or, under `width = "auto"`, a
				-- `render` that threw while it was being measured. `why` is
				-- supaline refusing what a `width` function handed back -- not a
				-- throw at all, which is why `resolve_width` returns it rather
				-- than raising it into the same `pcall` the throws come out of.
				local ok, got, why = pcall(column.resolve_width, col, files, entry.stats)
				-- Neither failure leaves a width the pass can stand behind, so
				-- none is invented and `entry.width` is left nil: the column
				-- draws unpadded. That is a ragged row, which is the thing a
				-- refused width of zero exists to prevent -- but a ragged row is
				-- readable, arrives with a notification naming the column, and
				-- leaves the rest of Yazi on screen, which the `error` this
				-- replaces did not.
				--
				-- Nil rather than `max_width`. The cap is not a width: padding
				-- every cell out to it is a fixed width the reader never asked
				-- for, and it would contradict the notification, which says this
				-- column draws unpadded. `column.cell` still cuts at the cap,
				-- which is the half of it that never needed the function that
				-- failed.
				if not ok then
					broke(col, "width", got)
				elseif why then
					bad_width(col, why --[[@as string]])
				else
					entry.width = got
				end
			end
			entries[i] = entry
		end

		if cache_n >= 8 then
			cache, cache_n = {}, 0
		end
		cache[key], cache_n = entries, cache_n + 1
	end

	for i, col in ipairs(cols) do
		column.bind(col, entries[i])
	end
	bound_name, bound_pane, bound_cwd, bound_n = name, pane, cwd, n
end

--- Draw one row. The caller has already looked the linemode up, resolved the
--- pane and taken that pane's columns off the mode, because all three had to:
--- `solo()` only dispatches for `in_current` rows, `child` has just asked
--- `pane_of`, and a pane with no columns is how both of them decide there is
--- nothing to draw at all. `folder` is nil for a pane that has none -- the
--- parent of the filesystem root -- which `bind` handles.
---@param mode supaline.Mode
---@param pane string the pane being drawn
---@param cols supaline.Column[] what that pane draws, already looked up
---@param file supaline.File
---@param folder supaline.Folder? the folder the row belongs to
---@return unknown an `AsLine`
local function render(mode, pane, cols, file, folder)
	bind(mode.name, pane, cols, folder)

	local sep, out = mode.sep, {}
	for i, col in ipairs(cols) do
		if i > 1 and col.sep ~= false then
			-- Whichever level wrote a separator supplies both halves of it, so
			-- this `or` is the whole of the inheritance and a nearer level
			-- never takes half of a farther one. A Span only where a style was
			-- written: `ui.Line` consumes what it is given, so one built here
			-- cannot be kept and drawn again on the next row, and an uncoloured
			-- separator stays the shared string it has always been.
			local one = col.sep or sep
			out[#out + 1] = one.style and ui.Span(one.text):style(one.style) or one.text
		end
		-- The third of the three, and the one called per row rather than per
		-- folder. A `pcall` here costs one per column per row -- five columns
		-- down forty rows is two hundred a frame, against a redraw that has
		-- just measured and styled every one of them -- and it is what keeps a
		-- column's own mistake inside that column's cells.
		local ok, cell = pcall(column.cell, col, file)
		if not ok then
			broke(col, "render", cell)
			cell = string.rep(BROKEN, col.ctx.width or #BROKEN)
		end
		out[#out + 1] = cell
	end
	return ui.Line(out)
end

--- Draw the active linemode in the parent and preview panes, for the linemodes
--- that ask for it. `solo()` has already drawn the current pane, so those rows
--- are skipped here.
---@param self table
---@return unknown an `AsLine`
local function child(self)
	-- Cast rather than annotated: `self` is Yazi's own linemode table, and the
	-- only thing this needs from it is what `_file` holds.
	local file = self._file --[[@as supaline.File]]
	-- Cheapest first. One child serves every linemode, so it is called for
	-- every parent and preview row even when the active linemode wants
	-- neither, and `pane_of` is far dearer than either of these tests.
	if file.in_current then
		return "" -- `solo()` has already drawn it
	end

	local name = cx.active.pref.linemode
	local mode = name and linemodes[name]
	if not mode or not mode.outer then
		return ""
	end

	local pane, folder = pane_of(file)
	local cols = mode.cols[pane]
	if not cols then
		return ""
	end

	-- `solo()` prepends a space to a line that has width; match it, so the two
	-- panes line up. A pane with nothing to draw is absent from `mode.cols`
	-- and was returned on above, so what arrives here is always a Line -- and
	-- one with no width of its own is handed back unwrapped, which is what
	-- `solo()` does with it too.
	local line = render(mode, pane, cols, file, folder)
	return line:visible() and ui.Line { " ", line } or line
end

--- A file operation can move a file between buckets, or change how wide the
--- widest cell is, so drop the cached pass and let the next frame redo it.
local function invalidate()
	cache, cache_n = {}, 0
	bound_name, bound_pane, bound_cwd, bound_n = nil, nil, nil, nil
end

--- Run every column's `refresh` hook. Subscribed to `cd` through `moved`,
--- which is the event that fires often enough to keep a value cached across
--- rows -- the current year -- from going stale in a session left open.
local function refresh()
	for i = 1, #refreshers do
		refreshers[i]()
	end
end

--- A `cd` is both of the above at once. The cached pass goes with it: the key
--- holds the folder and its file count, so a folder revisited after a write
--- that left the count alone -- one file grown, one timestamp touched -- would
--- otherwise be drawn with the extremes and the width measured on the way out.
--- That is what "until the next file operation or `cd`" means.
local function moved()
	invalidate()
	refresh()
end

--- Turn a set of specs into runtime linemodes. Pure, and the only place that
--- validates a spec: `column.normalize` and `panes_of` both raise, so a
--- configuration that does not compile never reaches module state.
---
--- One refusal is this function's own rather than either of theirs -- a
--- `separator` on the first column of a pane's list -- because it is the only
--- one that needs a column's position among its neighbours, which neither of
--- them has.
---@param from table<string, supaline.LinemodeSpec>
---@param with supaline.Cfg
---@return table<string, supaline.Mode> modes, function[] hooks, boolean outer whether any mode leaves the current pane
local function compile(from, with)
	local modes, hooks, outer = {}, {}, false
	-- Read here rather than in `setup`, which is what makes a `style` function
	-- under it follow the theme. `cfg` is stored once and handed to every
	-- later build, so a record resolved into it while `setup` ran would carry
	-- the colour the flavor had not supplied yet and carry it through every
	-- reload after -- the trap a column's `style` takes a function to escape,
	-- reappearing one level out. The linemode's and the column's were already
	-- read on this pass; measured, those two followed a reload and this one
	-- did not.
	--
	-- Once per compile rather than once per linemode: it is the same record
	-- for all of them, and `render` only ever reads it.
	--
	-- Never nil, so the reader's nil case is unreachable from here: `setup`
	-- falls back to `DEFAULTS.separator` and the `cfg` before any `setup` is
	-- `DEFAULTS` itself.
	local wide = column.separator(with.separator, "`separator` in `setup`") --[[@as supaline.Sep]]
	for name, spec in pairs(from) do
		local sets = panes_of(spec)
		-- Keyed by the list the user wrote rather than by the pane it was
		-- written under, so one list handed to two panes is compiled once and
		-- shared. Sharing is what keeps one `ctx` per column and one `refresh`
		-- per `cd`; only one pane is ever bound at a time, which is what makes
		-- it safe.
		local built, cols = {}, {}
		-- Walked in `PANES` order and not in the spec's, so a spec that
		-- refuses to compile names the same pane every time it is read.
		for _, pane in ipairs(PANES) do
			local list = sets[pane]
			local made = list and built[list]
			if list and not made then
				-- Against the spec alone, and not through `normalize`. `pick`
				-- reads `separator` off the definition as well, so refusing what a
				-- definition wrote would forbid a registered column from ever
				-- heading a linemode: one typo's cost, paid by every reuse of
				-- the column. What the user wrote here is what nobody draws.
				--
				-- `false` is falsy and passes, which is the one spelling that
				-- agrees with the outcome: it asks for nothing, and nothing is
				-- what index 1 gets. A list with no index 1 passes too -- a
				-- gap there is `panes_of`'s to refuse, and it does.
				local first = list[1]
				if type(first) == "table" and first.separator then
					error(string.format(FIRST_SEP, pane, name))
				end
				made = {}
				for i, entry in ipairs(list) do
					local col = column.normalize(entry, with)
					made[i] = col
					if col.refresh then
						hooks[#hooks + 1] = col.refresh
					end
				end
				built[list] = made
			end
			-- A pane that draws nothing is absent rather than empty, which is
			-- what lets both callers decide there is nothing to draw without
			-- asking how many columns there are. Only the current pane can
			-- land here: `panes_of` refuses an empty list under a pane name,
			-- and a linemode with no columns at all is the one that reaches
			-- this with an empty list of its own.
			if made and #made > 0 then
				cols[pane] = made
			end
		end

		local own = column.separator(spec.separator, string.format("`separator` on linemode `%s`", name))
		local reaches = cols.parent ~= nil or cols.preview ~= nil
		outer = outer or reaches
		modes[name] = {
			name = name,
			cols = cols,
			outer = reaches,
			sep = own or wide,
		}
	end
	return modes, hooks, outer
end

--- Put a compiled set of linemodes into service, dropping everything derived
--- from the last one.
local function install(modes, hooks)
	linemodes, refreshers = modes, hooks
	invalidate()
	refresh()
end

--- Take back everything the last `setup` put on `Linemode`. Names go back to
--- what they were bound to, so an override of one of Yazi's own linemodes is
--- handed back rather than left as a supaline one that draws nothing.
local function uninstall()
	for _, name in ipairs(installed.names) do
		Linemode[name] = installed.prev[name]
	end
	if installed.child then
		-- `Linemode:redraw()` calls every child it holds, so a second one
		-- would draw the parent and preview panes twice over.
		Linemode:children_remove(installed.child)
	end
	installed = { names = {}, prev = {}, child = nil }
end

--- Rebuild every linemode from the stored specs. Subscribed to `theme` for
--- two reasons, one of them at startup. `app:theme` re-reads `theme.toml`
--- from disk mid-run, so a colour resolved once at setup is the old one
--- from then on and nothing says so -- and 26.9.1 merges the flavor *after*
--- `init.lua` has run, announcing it with a `theme` event nobody asked for, so
--- a colour the flavor supplies is a preset's until this handler has run once.
--- Which panes a linemode wants cannot change under a theme reload, so the
--- third value is not wanted here.
---
--- The specs were compiled once already, inside `setup`, and nothing here has
--- touched them since -- but `compile` resolves colours, and on this path the
--- colours are the *theme's*. A `[supaline]` field that supaline refuses --
--- a colour Yazi will not parse, a gradient endpoint that is not `#rrggbb`, a
--- ramp on a column with no `stats` -- reaches this function and nowhere else,
--- because the user wrote it after `setup` had run.
---
--- So the message has to be delivered from here. There is nobody to raise to:
--- this runs from a `ps.sub` handler, and Yazi does not put an error out of one
--- in front of anyone. Editing `theme.toml` and pressing a key bound to
--- `app:theme` is the loop those messages were written for, and the failure
--- without this is a reload that changed nothing and said nothing -- exactly
--- what a plugin that ignored the event looks like.
---
--- Measured on 26.9.1: `ya.notify` from inside a sync `ps.sub` handler draws
--- the notification; it is not one of the calls that need an async context.
--- `ya.err` beside it, because a notification times out and `yazi.log` is
--- where a report of this comes from.
---
--- What is already installed is left alone. `install` is never reached, so the
--- last configuration that did compile keeps drawing -- the same rule `setup`
--- follows when it refuses a spec.
local function build()
	local ok, modes, hooks = pcall(compile, specs, cfg)
	if ok then
		return install(modes, hooks)
	end

	-- `ya.err` is handed the error itself rather than the trimmed string, and
	-- Yazi renders that as a nested `CallbackError` carrying all three
	-- tracebacks -- which is what a log is for and what a notification is not.
	--
	-- The source prefix goes too, which is the half `one_line` leaves on. The
	-- pattern is lazy so it takes the shortest one, which is the one Lua put
	-- there; the messages themselves open `supaline: ` and carry no
	-- `:<digits>: ` for it to stop at early. It reaches both spellings,
	-- `[string "supaline.colour"]:85: ` under Yazi and `./colour.lua:85: `
	-- under the unit suite.
	local why = one_line(modes):gsub("^.-:%d+: ", "")
	report(modes, why)
end

-- Subscribed at load rather than in `setup`, so calling `setup` twice cannot
-- subscribe twice and there is no flag to keep. Every handler reads module
-- state, which is empty and harmless until `setup` fills it.
--
-- `bulk-rename`, not `bulk`: the event was renamed without saying so, and
-- `ps.sub` accepts an unknown kind without complaining.
ps.sub("theme", build)
ps.sub("cd", moved)
for _, kind in ipairs { "rename", "bulk-rename", "move", "delete", "trash" } do
	ps.sub(kind, invalidate)
end

--- Register a reusable column, before `setup`, then refer to it by name from a
--- linemode spec. Accepts both `.column(name, def)` and `:column(name, def)`.
---
--- The colon call shifts every argument along by one, which one signature
--- cannot say; the `@overload` says it for callers. The dot form is tested
--- first so that the branch the parameters above describe is the branch that
--- reads them, and the casts sit in the colon branch, where the checker is
--- working from the overload rather than from the signature.
---@param a string the column's name
---@param b supaline.ColumnDef its definition
---@overload fun(self: table, name: string, def: supaline.ColumnDef)
function M.column(a, b, c)
	if type(a) == "string" then
		return column.register(a, b)
	end
	-- The colon call. Anything else lands here too and `register` refuses it
	-- by name, which is what it did before when `a` was neither.
	return column.register(b --[[@as string]], c --[[@as supaline.ColumnDef]])
end

--- The `stats` function the built-in ranged columns use, handed out so a
--- user-written one does not have to write the loop again. `get` reads the
--- value off a file, and is also where a timestamp is floored -- `render` has
--- to floor it the same way, or the two disagree about which step a row is on.
---
--- No colon form, because there is nothing here for `self` to shift: this takes
--- one argument and gives one back, so `supaline.extremes(...)` is the only
--- spelling and a `:` would swallow it.
---@param get fun(file: supaline.File): number?
---@return fun(files: supaline.File[]): table?
function M.extremes(get) return column.extremes(get) end

--- `_st` is Yazi's per-plugin state table. Nothing in this phase keeps state
--- across calls; the providers added later do, through `ya.sync` blocks
--- declared at the top level of this file.
---@param _st table plugin state, supplied by Yazi
---@param opts supaline.Opts?
---@overload fun(opts: supaline.Opts)
function M.setup(_st, opts)
	-- `.setup{...}` as well as `:setup{...}`, matching `M.column`. The dot form
	-- lands the options in the state parameter, which is Yazi's own table and
	-- never carries `linemodes`; without this the error names the one thing the
	-- user got right.
	if opts == nil and type(_st) == "table" and _st.linemodes ~= nil then
		opts = _st --[[@as supaline.Opts]]
	end
	opts = opts or {}

	-- Before a single key is read off it, and before anything is committed. A
	-- key this function does not know is not a value it would ever object to;
	-- it is a key nothing reads, which is the whole of what stands between
	-- `scal = "log"` and a plugin that quietly scales nothing.
	local _, _, subject, hints = colour.unknown(opts, claims_setup, "`setup`", SETUP_MEANT)
	if subject then
		error(string.format(SETUP_UNKNOWN, subject, SETUP_KEY_LIST, hints))
	end

	-- Kept as the user wrote it rather than read into a record here. `compile`
	-- below is what reads it, on this pass and on every later one, so a
	-- `style` written as a function is called again on each -- and because
	-- that call happens inside the `compile` this function already makes
	-- before it commits, a separator written wrong is still refused while
	-- `setup` runs rather than a session later.
	--
	-- An `if` rather than an `or`, because `false` is the one value `or`
	-- cannot pass through. It is meaningless on a plugin-wide separator and
	-- `column.separator` says so by name, which it never gets to do if the
	-- default quietly stands in for it first.
	local sep = opts.separator
	if sep == nil then
		sep = DEFAULTS.separator
	end

	-- Everything up to the commit below works on locals. A `setup` that is
	-- refused must leave the configuration already running untouched: the
	-- `theme` handler reads `specs`, so a rejected spec left there would make
	-- every later theme event throw instead of rebuilding.
	---@type supaline.Cfg
	local next_cfg = {
		separator = sep,
		order = opts.order or DEFAULTS.order,
		-- Not `or` a default: see `DEFAULTS`. Nil here is what lets a column
		-- definition's own scale through.
		--
		-- Refused here rather than left to `column.normalize`, which sees this
		-- value too: the mistake is in the table `setup` was handed, and a
		-- message reaching the reader through whichever column was normalised
		-- first would send them to a column they wrote correctly. Before the
		-- commit, like everything else in this record.
		scale = column.one_of("scale", opts.scale, "in `setup`"),
		-- Checked in `colour.lua`, where the two numbers mean something and
		-- where the pair the refusals recommend lives. Nothing falls back to
		-- it: a `setup` that wrote no band defines none, and the `<->` that
		-- wanted one is refused. Before the commit, so a band written wrong
		-- leaves the configuration already running alone.
		band = colour.bands(opts.band, "`band` in `setup`"),
	}

	local next_specs = opts.linemodes or {}
	if not next(next_specs) then
		error("supaline: `linemodes` is empty; there is nothing to render")
	end

	for name, spec in pairs(next_specs) do
		-- Yazi's limit is 1 to 20 *characters*; `#name` would refuse a CJK
		-- name of seven. `utf8.len` returns nil for a string that is not
		-- valid UTF-8, and such a name is Yazi's to refuse, not ours.
		local len = type(name) == "string" and (utf8.len(name) or #name) or nil
		if not len or len < 1 or len > 20 then
			error(string.format("supaline: a linemode name must be 1 to 20 characters, got `%s`", tostring(name)))
		elseif is_yazis(name) then
			error(
				string.format(
					"supaline: `%s` is part of Yazi's `Linemode` component; a linemode of "
						.. "that name would replace it. Overriding a built-in linemode "
						.. "(`size`, `mtime`, ...) is fine, replacing the component is not",
					name
				)
			)
		elseif type(spec) ~= "table" then
			error(string.format("%s; linemode `%s` is a %s", PANES_HELP, name, type(spec)))
		end
	end

	-- Compiling is what validates the columns and the panes, so it also has to
	-- happen before the commit -- and only once, rather than again inside
	-- `build`.
	local modes, hooks, wants_child = compile(next_specs, next_cfg)

	-- Committed. Nothing below here may raise on a configuration that got this
	-- far.
	cfg, specs = next_cfg, next_specs
	uninstall()
	install(modes, hooks)

	-- Registered whether or not the linemode draws in the current pane,
	-- because an unregistered name is not inert: `solo()` draws it as literal
	-- text. One that named the other panes alone draws nothing here instead.
	--
	-- `solo()` only dispatches for a row it has already found `in_current`, so
	-- the folder is the current one without asking.
	for name in pairs(specs) do
		ours[name] = true
		installed.names[#installed.names + 1] = name
		installed.prev[name] = Linemode[name]
		Linemode[name] = function(self)
			local mode = linemodes[name]
			local cols = mode and mode.cols.current
			if not cols then
				return ""
			end
			return render(mode, "current", cols, self._file, cx.active.current --[[@as supaline.Folder]])
		end
	end

	if wants_child then
		installed.child = Linemode:children_add(child, cfg.order)
	end
end

return M
