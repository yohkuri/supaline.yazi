--- Pins the truncation stubs in `stub.lua`.
---
--- `ui.truncate` is pinned to the assertions in Yazi's own test suite
--- (`yazi-plugin/src/ui/utils.rs`). `Line:truncate` has no upstream suite to
--- copy, so it is pinned to what a real Yazi drew in `test/e2e.sh` and to the
--- contract `column.cell` leans on: at most `max` cells, a character boundary,
--- and `ellipsis = ""` meaning a clean cut.
---
--- Everything the layout code believes about truncation rests on these, so if
--- either stub drifts the rest of the suite stops meaning anything.

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

-- --- Line:truncate ---------------------------------------------------------

local function lt(s, max, ellipsis) return stub.text_of(stub.Line(s):truncate { max = max, ellipsis = ellipsis }) end

test("Line:truncate: what a real Yazi drew", function()
	-- `test/e2e.sh` renders `exactly-1k.bin` (fourteen cells) through a column
	-- of twelve, three ways, and asserts these two on screen.
	eq(lt("exactly-1k.bin", 12), "exactly-1k.…")
	eq(lt("exactly-1k.bin", 12, ""), "exactly-1k.b")
end)

test("Line:truncate: an empty ellipsis is a clean cut", function()
	eq(lt("abcdefgh", 4, ""), "abcd")
	eq(lt("abcdefgh", 4), "abc…")
end)

test("Line:truncate: it fits, or it is left whole", function()
	eq(lt("abcd", 4), "abcd")
	eq(lt("abcd", 9), "abcd")
	eq(lt("abcdefgh", 0), "")
end)

test("Line:truncate: never more than max, and never mid character", function()
	-- The contract `column.cell` rests on: it may come back a cell short when a
	-- wide character straddles the edge, which is why the cell measures the
	-- result again and pads. It may never come back long, and it may never cut
	-- a character in half -- every byte of the result has to belong to a whole
	-- one of the three-byte characters it was given.
	for _, ellipsis in ipairs { "…", "" } do
		for max = 1, 12 do
			local out = lt("你好，世界", max, ellipsis)
			assert(stub.str_width(out) <= max, string.format("max=%d gave %q", max, out))
			eq(#out % 3, 0, string.format("max=%d cut mid character: %q", max, out))
		end
	end
	eq(lt("你好，世界", 4), "你…")
	eq(lt("你好，世界", 4, ""), "你好")
end)
