--- Pins the `ui.truncate` port in `stub.lua` to the assertions in Yazi's own
--- test suite (`yazi-plugin/src/ui/utils.rs`). Everything the layout code
--- believes about truncation rests on these, so if the port drifts the rest of
--- the suite stops meaning anything.

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
