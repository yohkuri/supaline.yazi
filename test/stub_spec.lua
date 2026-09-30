--- Pins `stub.lua` against Yazi, because a stub is worth exactly its fidelity.
---
--- `ui.truncate` is pinned to the assertions in Yazi's own test suite
--- (`yazi-plugin/src/ui/utils.rs`). `Line:truncate` has no upstream suite to
--- copy, so it is pinned to a table measured against a real Yazi 26.9.1: six
--- strings -- ASCII, CJK, and one each carrying a variation selector, a
--- joiner, a skin-tone modifier and a flag -- cut at every `max` from 0 to 8,
--- with and without an ellipsis. The stub reproduces all of it.
---
--- The two cuts do not agree, and the tests below say where. `layout.cell` is
--- what closes the gap, so a stub that quietly closed it here would let the
--- correction be deleted with the suite still green.
---
--- The rest pins where the stub is deliberately louder than Yazi: a value Yazi
--- would take in silence, or could never have produced, is refused here.

local function t(s, max, rtl) return stub.truncate(s, { max = max, rtl = rtl }) end

test("truncate: shorter than one cell", function()
	eq(t("你好，world", 0), "")
	eq(t("你好，world", 1), "…")
	eq(t("你好，world", 2), "…")
end)

test("truncate: appends its own ellipsis", function()
	eq(t("你好，世界", 3), "你…")
	eq(t("你好，世界", 4), "你…")
	eq(t("你好，世界", 5), "你好…")
	eq(t("Hello, world", 5), "Hell…")
	eq(t("Ni好，世界", 3), "Ni…")
end)

test("truncate: off by one", function()
	eq(t("Hello, world", 11), "Hello, wor…")
	eq(t("你好，世界", 9), "你好，世…")
	eq(t("你好，世Jie", 9), "你好，世…")
end)

test("truncate: exact fit is returned whole", function()
	eq(t("Hello, world", 12), "Hello, world")
	eq(t("你好，世界", 10), "你好，世界")
	eq(t("Hello, world", 13), "Hello, world")
	eq(t("你好，世界", 11), "你好，世界")
end)

test("truncate: right to left", function()
	eq(t("world，你好", 0, true), "")
	eq(t("world，你好", 1, true), "…")
	eq(t("你好，世界", 3, true), "…界")
	eq(t("你好，世界", 4, true), "…界")
	eq(t("你好，世界", 5, true), "…世界")
	eq(t("Hello, world", 5, true), "…orld")
	eq(t("你好，Shi界", 3, true), "…界")
	eq(t("Hello, world", 11, true), "…llo, world")
	eq(t("你好，世界", 9, true), "…好，世界")
	eq(t("Ni好，世界", 9, true), "…好，世界")
end)

test("truncate: a wide character straddling the edge comes back short", function()
	-- The reason `fit` measures again and pads: asking for 4 cells of a wide
	-- string can only yield 3.
	eq(stub.str_width(t("你好，世界", 4)), 3)
end)

test("width: East Asian characters and emoji take two cells", function()
	-- `unicode-width`, which Yazi uses, gives emoji presentation two cells, and
	-- the fixture carries `絵文字🎨のなまえ.txt` for that reason.
	eq(stub.str_width("你好"), 4)
	eq(stub.str_width("Hello"), 5)
	eq(stub.str_width("日本語のファイル名.txt"), 22)
	eq(stub.str_width("🎨"), 2)
	eq(stub.str_width("絵文字🎨のなまえ.txt"), 20)
end)

test("width: a cluster is not the sum of its characters", function()
	-- Measured on Yazi 26.9.1, and the reason `layout.lua` cuts on cluster
	-- boundaries: `str_width` is what `ui.width` and `Line:width` return, and
	-- `cp_width` is what both truncations count. Every line here is a pair that
	-- disagrees, in one direction or the other.
	eq(stub.str_width("\u{2764}\u{FE0F}"), 2, "a variation selector widens what it follows")
	eq(stub.cp_width("\u{2764}\u{FE0F}"), 1)
	eq(stub.str_width("\u{1F469}\u{200D}\u{1F4BB}"), 2, "a joined pair is one two-cell character")
	eq(stub.cp_width("\u{1F469}\u{200D}\u{1F4BB}"), 4)
	eq(stub.str_width("\u{1F44D}\u{1F3FB}"), 2, "a skin-tone modifier adds nothing")
	eq(stub.cp_width("\u{1F44D}\u{1F3FB}"), 4)
	eq(stub.str_width("\u{1F1EF}\u{1F1F5}"), 2, "a flag is two one-cell halves")
	eq(stub.str_width("e\u{0301}"), 1, "a combining mark adds nothing")
end)

-- --- Line:truncate ---------------------------------------------------------

local function lt(s, max, ellipsis) return stub.text_of(stub.Line(s):truncate { max = max, ellipsis = ellipsis }) end

test("Line:truncate: an empty ellipsis still costs a cell", function()
	-- Where the two cuts part company. Yazi holds back the ellipsis's width and
	-- then drops the character that lands exactly on `max` as well, and an
	-- empty ellipsis does nothing about the second half: the same eight cells
	-- cut to four come back as four from `ui.truncate` and three from here.
	eq(lt("abcdefgh", 4, ""), "abc")
	eq(t("abcdefgh", 4), "abc…")
	eq(lt("abcdefgh", 4), "abc…")

	-- `test/e2e.py` renders `exactly-1k.bin` (fourteen cells) through columns
	-- of twelve, and has one that hands back a Line so this cell is on screen.
	eq(lt("exactly-1k.bin", 12), "exactly-1k.…")
	eq(lt("exactly-1k.bin", 12, ""), "exactly-1k.")
end)

test("Line:truncate: it counts characters, and can come back wider than max", function()
	-- `❤️` is one character of one cell and one of none, and two cells on
	-- screen; `Line:truncate` adds the characters up, decides a five-cell line
	-- fits in four, and hands it back untouched. Measured on Yazi 26.9.1 -- and
	-- no `max` cuts this line to exactly four, which is why `layout.cell` cuts
	-- again rather than once.
	eq(stub.Line("\u{2764}\u{FE0F}abc"):truncate({ max = 4, ellipsis = "" }):width(), 5)
	eq(lt("\u{2764}\u{FE0F}abc", 3, ""), "\u{2764}\u{FE0F}a")
end)

test("Line:truncate: it fits, or it is left whole", function()
	eq(lt("abcd", 4), "abcd")
	eq(lt("abcd", 9), "abcd")
	eq(lt("abcdefgh", 0), "")
end)

test("Line:truncate: a character it can measure is never overrun", function()
	-- Where its own count agrees with the screen it comes back at most `max`
	-- cells and on a character boundary, possibly short when a wide character
	-- straddles the edge.
	for _, ellipsis in ipairs { "…", "" } do
		for max = 1, 12 do
			local out = lt("你好，世界", max, ellipsis)
			assert(stub.str_width(out) <= max, string.format("max=%d gave %q", max, out))
			eq(#out % 3, 0, string.format("max=%d cut mid character: %q", max, out))
		end
	end
	eq(lt("你好，世界", 4), "你…")
	eq(lt("你好，世界", 4, ""), "你")
end)

test("Line:width: the parts are measured one by one, not joined up", function()
	-- Measured on Yazi 26.9.1: a heart and the variation selector after it are
	-- one cell as separate parts and two inside a single part.
	local heart, vs = "\u{2764}", "\u{FE0F}"
	eq(stub.Line({ stub.Span(heart), stub.Span(vs) }):width(), 1)
	eq(stub.Line({ stub.Span(heart .. vs) }):width(), 2)
	eq(stub.Line({ heart, vs }):width(), 1, "a plain string is a part like any other")
	eq(stub.Line({ stub.Line { stub.Span("ab") }, stub.Span("cd") }):width(), 4, "and so is a nested Line")
end)

test("Line:truncate: it modifies the line it was given and hands that back", function()
	-- Measured on Yazi 26.9.1, where the receiver came back four cells wide
	-- from eight and `rawequal` held. `cut` in `layout.lua` relies on it.
	local line = stub.Line { stub.Span("abcdefgh") }
	local out = line:truncate { max = 4 }
	eq(rawequal(out, line), true, "the same line comes back")
	eq(line:width(), 4, "and it has been cut where it stands")

	local fits = stub.Line { stub.Span("ab") }
	eq(rawequal(fits:truncate { max = 4 }, fits), true, "one that fits is the same line too")
	eq(fits:width(), 2)

	local none = stub.Line { stub.Span("abcd") }
	none:truncate { max = 0, ellipsis = "" }
	eq(none:width(), 0, "a `max` below one empties it")
end)

test("Line:truncate: the cut keeps the part boundaries", function()
	-- Measured on Yazi 26.9.1: the same characters cut at the same `max` come
	-- out a cell apart depending on how they were split up.
	local heart, vs = "\u{2764}", "\u{FE0F}"
	local many = stub.Line { stub.Span(heart), stub.Span(vs), stub.Span("abcdef") }
	many:truncate { max = 4, ellipsis = "" }
	eq(many:width(), 3)

	local one = stub.Line { stub.Span(heart .. vs .. "abcdef") }
	one:truncate { max = 4, ellipsis = "" }
	eq(one:width(), 4)
end)

test("Line:truncate: every span keeps its own style through the cut", function()
	-- Measured on Yazi 26.9.1 by reading the colours back off the screen with
	-- `tmux capture-pane -e`: a red "aaa" and a green "bbbbb" cut to six drew
	-- "aaabb" with both colours still on screen.
	local red, green = ui.Style():fg("#ff0000"), ui.Style():fg("#00ff00")
	-- `stub.Line` rather than `ui.Line`: `types.yazi` declares nothing for
	-- `Line:truncate`, so the checker refuses the call on a value it has typed.
	local line = stub.Line {
		stub.Span("aaa"):style(red),
		stub.Span("bbbbb"):style(green),
	}
	line:truncate { max = 6, ellipsis = "" }
	eq(stub.text_of(line), "aaabb", "the same five cells Yazi drew")

	local got = stub.drawn_styles(line)
	eq(got[1], red, "the span that survived whole keeps its style")
	eq(got[2], green, "and so does the one the cut landed inside")
end)

-- --- AuthKind --------------------------------------------------------------

test("AuthKind: each variant's three flags, as Yazi sets them", function()
	-- `is_virtual` is the complement of Yazi's `is_local`, and `is_regular` and
	-- `is_search` each hold for one variant. A search result is local with
	-- `is_regular = false`, which is the trap these flags expose.
	for kind, virtual in pairs { regular = false, search = false, mount = true, hub = true, scope = true, sftp = true } do
		local spec = stub.spec_of(kind)
		eq(spec.is_virtual, virtual, kind .. ".is_virtual")
		eq(spec.is_regular, kind == "regular", kind .. ".is_regular")
		eq(spec.is_search, kind == "search", kind .. ".is_search")
	end
end)

-- --- require ---------------------------------------------------------------

test("require: a proxy over the module, as Yazi hands back", function()
	-- Measured on 26.9.1 with a probe plugin reading its own module this way,
	-- every assertion below included. `table`, because what is probed here is
	-- the proxy and not the module's declared shape.
	local proxy = require(".schema") --[[@as table]]
	local again = require(".schema")
	local mod = rawget(proxy, "__mod")
	eq(proxy == again, false, "each require is a table of its own")
	eq(rawget(again, "__mod"), mod, "over the one module")

	local keys = {}
	for k in pairs(proxy) do
		keys[#keys + 1] = k
	end
	eq(table.concat(keys, ","), "__mod", "and it holds nothing else")

	local before = stub.wrappers
	eq(proxy.any == proxy.any, false, "a function field is a new wrapper on every read")
	eq(proxy.any == mod.any, false, "and never the function itself")
	eq(stub.wrappers - before, 3, "each read counted")
	do
		local kept = proxy.any
		before = stub.wrappers
		kept()
		kept()
		eq(stub.wrappers - before, 2, "and each call through one")
	end
	eq(require(".report").BROKEN, rawget(require(".report"), "__mod").BROKEN, "any other field is itself")

	local t = {}
	eq(proxy.any(t), t, "a table argument goes through")
	eq(proxy:any(), mod, "a proxy in first place arrives as its module")
	eq(proxy.any(mod.any), mod.any, "and what a call returns is not wrapped")
	local fake = { __mod = 7 }
	eq(proxy.any(fake), fake, "a table whose `__mod` is no module goes through as it is")

	-- Written as a second function further down, which the checker would call
	-- a duplicate field.
	---@diagnostic disable-next-line: duplicate-set-field
	proxy.probe = function(...) return select("#", ...) end
	eq(rawget(mod, "probe") ~= nil, true, "a write lands on the module")
	eq(rawget(proxy, "probe"), nil, "and not on the proxy")
	eq(proxy.probe(), 0, "a call with no argument is handed none")
	eq(proxy.probe(nil), 1, "and one with a nil is handed the nil")

	local kept = proxy.probe
	---@diagnostic disable-next-line: duplicate-set-field
	proxy.probe = function() return "replaced" end
	eq(kept(), "replaced", "a kept wrapper calls whatever the name holds when it is called")

	local report = rawget(require(".report"), "__mod")
	report.probe = function() return "report" end
	eq(proxy.probe(require(".report")), "report", "on the module of a proxy passed first")
	report.probe, proxy.probe = nil, nil
end)

-- --- what the stub refuses and Yazi would not ------------------------------

test("refused: an `AuthKind` Yazi does not have", function()
	throws(function() stub.spec_of("regualr") end, "no such AuthKind")
end)

test("refused: a write to `th`", function()
	-- Yazi takes one without a word. Here `th` reads through to `stub.th`, so a
	-- write that landed would shadow every theme a spec plants after it.
	throws(function() rawget(_G, "th").supaline = {} end, "write to `stub.th`")
end)

test("refused: a DDS kind Yazi does not publish", function()
	-- `bulk` is what Yazi published before `bulk-rename`, and a subscription
	-- to it would never fire.
	throws(function()
		ps.sub("bulk", function() end)
	end, "no such DDS kind")
end)

test("refused: a permission string Yazi could not have produced", function()
	throws(function() stub.file { perm = "nope" } end, "ten-character")
	throws(function() stub.file { perm = "drwxr-xr-" } end, "ten-character")
	throws(function() stub.file { perm = "?rwxr-xr-x" } end, "type character from `dlbcsp-`")
	-- `ChaMode::permissions` returns on the dummy before it writes a single
	-- bit, so `?` is all nine or none.
	throws(function() stub.file { perm = "drwxr-x???" } end, "nine `?`")
	throws(function() stub.file { perm = "dswxr-xr-x" } end, "per position")

	-- Left out is the platform, not the file: `Cha:perm` is nil on Windows.
	eq(stub.file({}).cha:perm(), nil)
	eq(stub.file({ perm = "-?????????" }).cha:perm(), "-?????????")
end)

test("refused: an owner id Yazi could not have produced", function()
	throws(function() stub.file { uid = "root" } end, "`uid` is a `u32`")
	throws(function() stub.file { gid = -1 } end, "`gid` is a `u32`")
	throws(function() stub.file { uid = 1.5 } end, "whole number")

	-- Left out is the `0` Yazi fills in where the platform has no owner.
	eq(stub.file({}).cha.uid, 0)
	eq(stub.file({}).cha.gid, 0)
end)
