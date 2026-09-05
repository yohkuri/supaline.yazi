--- Pins the truncation stubs in `stub.lua`.
---
--- `ui.truncate` is pinned to the assertions in Yazi's own test suite
--- (`yazi-plugin/src/ui/utils.rs`). `Line:truncate` has no upstream suite to
--- copy, so it is pinned to a table measured against a real Yazi 26.9.1: six
--- strings -- ASCII, CJK, and one each carrying a variation selector, a
--- joiner, a skin-tone modifier and a flag -- cut at every `max` from 0 to 8,
--- with and without an ellipsis. The stub reproduces all of it.
---
--- The two cuts do not agree, and the tests below say where. `column.cell` is
--- what closes the gap, so a stub that quietly closed it here would let the
--- correction be deleted with the suite still green.

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

test("width: East Asian characters take two cells", function()
	eq(stub.str_width("你好"), 4)
	eq(stub.str_width("Hello"), 5)
	eq(stub.str_width("日本語のファイル名.txt"), 22)
end)

test("width: an emoji takes two cells, like an East Asian character", function()
	-- `unicode-width`, which Yazi uses, gives emoji presentation two cells. The
	-- fixture carries `絵文字🎨のなまえ.txt` precisely because of it, so a stub
	-- that measured one would disagree with the harness built to check the same
	-- names.
	eq(stub.str_width("🎨"), 2)
	eq(stub.str_width("絵文字🎨のなまえ.txt"), 20)
end)

test("width: a cluster is not the sum of its characters", function()
	-- Measured on Yazi 26.9.1, and the reason `column.lua` cuts on cluster
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

	-- `test/e2e.sh` renders `exactly-1k.bin` (fourteen cells) through columns
	-- of twelve, and has one that hands back a Line rather than a string
	-- precisely so this cell is on screen to be checked.
	eq(lt("exactly-1k.bin", 12), "exactly-1k.…")
	eq(lt("exactly-1k.bin", 12, ""), "exactly-1k.")
end)

test("Line:truncate: it counts characters, and can come back wider than max", function()
	-- The other half of the gap. `❤️` is one character of one cell and one of
	-- none, and two cells on screen; `Line:truncate` adds the characters up,
	-- decides a five-cell line fits in four, and hands it back untouched.
	-- Measured on Yazi 26.9.1 -- and there is no `max` that cuts this line to
	-- exactly four, which is why `column.cell` cuts again rather than once.
	eq(stub.Line("\u{2764}\u{FE0F}abc"):truncate({ max = 4, ellipsis = "" }):width(), 5)
	eq(lt("\u{2764}\u{FE0F}abc", 3, ""), "\u{2764}\u{FE0F}a")
end)

test("Line:truncate: it fits, or it is left whole", function()
	eq(lt("abcd", 4), "abcd")
	eq(lt("abcd", 9), "abcd")
	eq(lt("abcdefgh", 0), "")
end)

test("Line:truncate: a character it can measure is never overrun", function()
	-- Where its own count agrees with the screen -- everything but the clusters
	-- above -- it comes back at most `max` cells and on a character boundary.
	-- It may come back short when a wide character straddles the edge, which is
	-- why the cell measures the result again and pads. Every byte of the result
	-- has to belong to a whole one of the three-byte characters it was given.
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
