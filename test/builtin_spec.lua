---@diagnostic disable: inject-field, need-check-nil

--- `builtin.lua`: the formatters, and the fallbacks each column takes when the
--- value it wants is not there.

local column = require(".column")
require(".builtin")

local CFG = { scale = "linear" }

--- Run `fn` with `cx.active:history` answering `folder`, and put the stub's own
--- back afterwards: left reassigned, it reaches every test after this one and
--- the failure points at the wrong one.
---@param folder table?
---@param fn function
local function with_history(folder, fn)
	local before = cx.active.history
	-- Yazi's parameters, for the reason `stub.lua` gives beside its own.
	cx.active.history = function(_, _url) return folder end
	local ok, err = pcall(fn)
	cx.active.history = before
	if not ok then
		error(err, 0)
	end
end

--- Render one built-in column for one file, returning plain text.
---@param name string
---@param file table
---@param opts table?
---@return string
local function render(name, file, opts)
	local spec = { name }
	for k, v in pairs(opts or {}) do
		spec[k] = v
	end
	return text_of(column.cell(column.normalize(spec, CFG), file))
end

-- --- size ------------------------------------------------------------------

test("size: human-readable, right-aligned in 7 cells", function()
	eq(render("size", stub.file { size = 0 }), "     0B")
	eq(render("size", stub.file { size = 900 }), "   900B")
	eq(render("size", stub.file { size = 819200 }), "   800K")
	eq(render("size", stub.file { size = 92160000 }), "  87.9M")
end)

test("size: the widest readable size still fits the column", function()
	-- `ya.readable_size` keeps the mantissa in (1, 1024] and strips a trailing
	-- ".0", so "1023.9K" is as wide as it gets.
	eq(#ya.readable_size(1023.9 * 1024), 7)
end)

test("size: a directory falls back to its entry count", function()
	with_history(
		{ files = { 1, 2, 3 } },
		function() eq(render("size", stub.file { name = "d", is_dir = true }), "      3") end
	)
end)

test("size: a directory Yazi has never listed shows a dash", function()
	with_history(nil, function() eq(render("size", stub.file { name = "d", is_dir = true }), "      -") end)
end)

-- --- times -----------------------------------------------------------------

local THIS_YEAR = os.date("*t").year
local RECENT = os.time { year = THIS_YEAR, month = 3, day = 4, hour = 5, min = 6, sec = 0 }
local OLD = os.time { year = 2020, month = 12, day = 25, hour = 1, min = 2, sec = 0 }

test(
	"mtime: time of day within the current year",
	function() eq(render("mtime", stub.file { mtime = RECENT }), "03/04 05:06") end
)

test(
	"mtime: the year itself for anything older",
	function() eq(render("mtime", stub.file { mtime = OLD }), "12/25  2020") end
)

test(
	"mtime: both forms are the same width",
	function() eq(#render("mtime", stub.file { mtime = RECENT }), #render("mtime", stub.file { mtime = OLD })) end
)

test("mtime: a missing or zero time is blank", function()
	eq(render("mtime", stub.file {}), "           ")
	eq(render("mtime", stub.file { mtime = 0 }), "           ")
end)

test(
	"mtime: `format` takes an os.date format",
	function() eq(render("mtime", stub.file { mtime = OLD }, { format = "%Y-%m-%d", width = 10 }), "2020-12-25") end
)

test("btime and atime read their own fields", function()
	eq(render("btime", stub.file { btime = OLD, mtime = RECENT }), "12/25  2020")
	eq(render("atime", stub.file { atime = OLD, mtime = RECENT }), "12/25  2020")
end)

-- --- the rest --------------------------------------------------------------

test("permissions: left-aligned, blank when the platform has none", function()
	eq(render("permissions", stub.file { perm = "drwxr-xr-x" }), "drwxr-xr-x")
	eq(render("permissions", stub.file {}), "          ")
end)

test("owner: user:group, blank without a uid", function()
	eq(render("owner", stub.file { uid = 1, gid = 2 }), "user1:group2")
	eq(render("owner", stub.file {}), "            ")
end)

test("owner: a name longer than the column is truncated, not allowed to push", function()
	-- Yazi sizes the file name against whatever the linemode takes, so a cell
	-- that overflowed would eat the name instead.
	eq(render("owner", stub.file { uid = 501, gid = 20 }), "user501:gro…")
end)

test("owner: a remote file keeps its numbers, a local one gets names", function()
	-- `ya.user_name` resolves against this machine, so a name is only right
	-- for a file that lives on it. A search result does, an SFTP one does not.
	eq(render("owner", stub.file { uid = 501, gid = 20, url_kind = "search" }), "user501:gro…")
	eq(render("owner", stub.file { uid = 501, gid = 20, url_kind = "sftp" }), "501:20      ")
	eq(render("owner", stub.file { uid = 501, gid = 20, url_kind = "mount" }), "501:20      ")
end)

test("count: directories only", function()
	with_history({ files = { 1, 2 } }, function()
		eq(render("count", stub.file { name = "d", is_dir = true }), "    2")
		eq(render("count", stub.file { name = "f.txt" }), "     ")
	end)
end)

-- --- statistics ------------------------------------------------------------

test("stats: extremes skip the values that are not there", function()
	local def = column.get("size")
	local st = def.stats {
		stub.file { size = 100 },
		stub.file { size = nil }, -- an unevaluated directory
		stub.file { size = 0 }, -- an empty file must not drag the floor down
		stub.file { size = 5000 },
	}
	eq(st.min, 100)
	eq(st.max, 5000)
end)

test(
	"stats: a folder with nothing to measure has no extremes",
	function() eq(column.get("size").stats { stub.file { size = nil } }, nil) end
)
