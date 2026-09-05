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

for _, key in ipairs { "fg", "bg" } do
	Style[key] = function(self, value)
		local s = new_style(self)
		s[key] = value
		return s
	end
end
for _, key in ipairs { "bold", "italic", "underline", "dim", "reverse" } do
	Style[key] = function(self, value)
		local s = new_style(self)
		s[key] = value == nil or value
		return s
	end
end

local Span = {}
Span.__index = Span
function Span:style(s)
	self._style = s
	return self
end

local Line = {}
Line.__index = Line

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

function Line:width() return str_width(text_of(self)) end
function Line:visible() return self:width() > 0 end
function Line:style(s)
	self._style = s
	return self
end

--- A port of `Line::truncate` from `yazi-binding/src/elements/line.rs`, its
--- two surprises included, because `column.cell` exists to correct them:
---
---   * it holds back the ellipsis's width and then drops the character that
---     lands exactly on `max` as well, so an empty ellipsis still costs an
---     ASCII line one cell;
---   * it counts characters while `Line:width` measures the string, so a line
---     it thinks fits can come back wider than `max`.
---
--- Reproduced rather than repaired: a stub that quietly did the right thing
--- would let the correction be deleted with every test still green.
function Line:truncate(opts)
	local max = opts.max
	if max < 1 then
		return M.Line("")
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
		return M.Line(ellipsis)
	elseif adv <= max then
		return self -- it fits, by its own reckoning
	end

	-- The character the cut lands on is kept, unless it ends exactly on `max`.
	local len = fits == max and 0 or #char_at(text, at)
	return M.Line(text:sub(1, at + len) .. ellipsis)
end

function M.Line(x)
	if getmetatable(x) == Line then
		return x
	end
	local parts = x
	if type(x) ~= "table" or getmetatable(x) == Span then
		parts = { x }
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
			uid = t.uid,
			gid = t.gid,
			perm = function() return t.perm end,
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
		Style = function() return new_style {} end,
		truncate = truncate,
		width = function(x) return str_width(text_of(x)) end,
		render = function() end,
	}

	-- One table, because 26.9.1 has one state: the user's `theme.toml` and
	-- flavor are merged before any plugin code runs, so `th.supaline` and a
	-- `[mgr]` override alike are readable from the first line of `init.lua`.
	-- Measured, not assumed -- a `[mgr] cwd` captured at load time paints the
	-- user's colour, and a `Style` read out of `th` is a value frozen at that
	-- moment, not a handle that follows later reloads.
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
	}

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
	-- `history` is declared with the parameters Yazi's takes, and reads
	-- neither. `types.yazi` does not describe `Tab:history` at all, so this
	-- line is the only declaration a language server has for it, and a nullary
	-- one makes the plugin's own `cx.active:history(url)` the thing that looks
	-- wrong.
	_G.cx = { active = { pref = {}, preview = {}, history = function(_, _url) return nil end } }

	local loaded = {}
	_G.require = function(name)
		if name:sub(1, 1) ~= "." then
			return REAL_REQUIRE(name)
		end
		if loaded[name] == nil then
			local chunk = assert(loadfile(root .. "/" .. name:sub(2) .. ".lua"))
			loaded[name] = chunk() or {}
		end
		return loaded[name]
	end
end

return M
