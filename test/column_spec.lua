-- Column normalisation, padding, the stats/ratio contract, and the built-ins.

return function(t)
	local column = t.module("column")
	local file, text_of, width_of = t.stub.file, t.stub.text_of, t.stub.width_of

	local CFG = {
		separator = " ",
		gradient = { mode = "relative", colors = "truecolor", scale = "linear", steps = 24, min_luminance = 50 },
	}

	local any = file("f", 1, 1)

	t.group("normalize: accepted shapes")
	do
		local by_name = column.normalize("size", CFG)
		t.check("string name", by_name.name == "size" and by_name.width == 9)

		local with_opts = column.normalize({ "size", width = 12, align = "left" }, CFG)
		t.check("name + opts", with_opts.width == 12 and with_opts.align == "left")

		local fn = column.normalize(function() return "x" end, CFG)
		t.check("bare function", fn.render ~= nil and fn.width == nil)

		local wrapped = column.normalize({ function() return "x" end, width = 4 }, CFG)
		t.check("function + opts", wrapped.width == 4)

		local inline = column.normalize({ render = function() return "y" end, width = 3, align = "left" }, CFG)
		t.check("inline table", inline.width == 3 and inline.align == "left")
	end

	t.group("normalize: rejected shapes")
	do
		t.check("unknown name errors", not pcall(column.normalize, "nope", CFG))
		t.check("number errors", not pcall(column.normalize, 42, CFG))
		t.check("empty table errors", not pcall(column.normalize, {}, CFG))
	end

	t.group("padding")
	do
		local right = column.normalize({ render = function() return "ab" end, width = 5, align = "right" }, CFG)
		t.check("right-aligned", text_of(column.cell(right, any)) == "   ab")

		local left = column.normalize({ render = function() return "ab" end, width = 5, align = "left" }, CFG)
		t.check("left-aligned", text_of(column.cell(left, any)) == "ab   ")

		local over = column.normalize({ render = function() return "abcdefgh" end, width = 3 }, CFG)
		t.check("overflow is not truncated", text_of(column.cell(over, any)) == "abcdefgh")

		local none = column.normalize({ render = function() return "ab" end }, CFG)
		t.check("no width, no padding", text_of(column.cell(none, any)) == "ab")

		local empty = column.normalize({ render = function() return "" end, width = 4 }, CFG)
		t.check("empty still occupies its width", width_of(column.cell(empty, any)) == 4)

		local wide = column.normalize({ render = function() return "あ" end, width = 4 }, CFG)
		t.check(
			"multibyte measured by display width",
			width_of(column.cell(wide, any)) == 4,
			width_of(column.cell(wide, any))
		)

		local nilled = column.normalize({ render = function() return nil end, width = 3 }, CFG)
		t.check("nil render is safe", text_of(column.cell(nilled, any)) == "   ")
	end

	t.group("stats and ratio")
	do
		local col = column.normalize("size", CFG)
		local files = { file("a", 100), file("b", 5000), file("c", 900000), file("d", nil, nil, true) }
		local stats = col.stats(files)
		t.check(
			"directories excluded from the extremes",
			stats.min == 100 and stats.max == 900000,
			string.format("%s..%s", tostring(stats.min), tostring(stats.max))
		)

		col.ctx.stats = stats
		t.check("min -> 0", col.ctx.ratio(100) == 0)
		t.check("max -> 1", col.ctx.ratio(900000) == 1)
		t.check("below range clamps", col.ctx.ratio(1) == 0)
		t.check("above range clamps", col.ctx.ratio(99999999) == 1)
		t.check("nil value -> nil ratio", col.ctx.ratio(nil) == nil)

		col.ctx.stats = nil
		t.check("no stats -> nil ratio", col.ctx.ratio(500) == nil)

		col.ctx.stats = { min = 42, max = 42 }
		t.check("degenerate range -> 1", col.ctx.ratio(42) == 1)
	end

	t.group("log scale")
	do
		local lin = column.normalize({ "size" }, CFG)
		local logc = column.normalize({ "size", scale = "log" }, CFG)
		local stats = { min = 1024, max = 1024 * 1024 * 1024 }
		lin.ctx.stats, logc.ctx.stats = stats, stats

		local mid = 1024 * 1024 -- 1 MiB, the geometric middle of the range
		t.check("linear pins 1 MiB to the dark end", lin.ctx.ratio(mid) < 0.01, lin.ctx.ratio(mid))
		t.check("log puts 1 MiB near the middle", math.abs(logc.ctx.ratio(mid) - 0.5) < 0.05, logc.ctx.ratio(mid))
	end

	t.group("gradient wiring")
	do
		local col = column.normalize({ "size" }, CFG)
		col.ctx.stats = { min = 0, max = 100 }
		t.check("ramp endpoints differ", col.ctx.style(0).color ~= col.ctx.style(1).color)

		local off = column.normalize({ "size", gradient = "off" }, CFG)
		t.check("gradient=off falls back to the base", off.ctx.style(0) == off.ctx.style(1))

		local nocolor = {
			separator = " ",
			gradient = { mode = "relative", colors = "off", scale = "linear", steps = 24, min_luminance = 50 },
		}
		local flat = column.normalize({ "size" }, nocolor)
		t.check("colors=off falls back to the base", flat.ctx.style(0) == flat.ctx.style(1))
	end

	t.group("theme override")
	do
		th.supaline = { size_base = "#ff0000" }
		local col = column.normalize({ "size" }, CFG)
		col.ctx.stats = { min = 0, max = 10 }
		local hex = col.ctx.style(1).color
		t.check("[supaline] size_base is honoured", tonumber(hex:sub(2, 3), 16) > tonumber(hex:sub(4, 5), 16), hex)

		local explicit = column.normalize({ "size", base = "#00ff00" }, CFG)
		explicit.ctx.stats = { min = 0, max = 10 }
		local hex2 = explicit.ctx.style(1).color
		t.check("a per-column base wins over the theme", tonumber(hex2:sub(4, 5), 16) > tonumber(hex2:sub(2, 3), 16), hex2)
		th.supaline = {}
	end

	t.group("built-in columns")
	do
		local size = column.normalize("size", CFG)
		size.ctx.stats = { min = 100, max = 900000 }
		t.check(
			"size renders human bytes",
			text_of(column.cell(size, file("a", 5000))):find("4.9 K") ~= nil,
			text_of(column.cell(size, file("a", 5000)))
		)
		t.check(
			"an unevaluated directory renders a dash",
			text_of(column.cell(size, file("d", nil, nil, true))):find("-") ~= nil
		)

		local mtime = column.normalize("mtime", CFG)
		local now = os.time()
		mtime.ctx.stats = { min = now - 100000, max = now }

		local this_year = text_of(column.cell(mtime, file("a", 1, now)))
		t.check("mtime shows the time of day for this year", this_year:find("%d%d:%d%d") ~= nil, this_year)

		local long_ago = os.time { year = tonumber(os.date("%Y")) - 3, month = 6, day = 1, hour = 12 }
		local older = text_of(column.cell(mtime, file("b", 1, long_ago)))
		t.check("mtime shows the year for older files", older:find(tostring(tonumber(os.date("%Y")) - 3)) ~= nil, older)

		local zero = text_of(column.cell(mtime, file("c", 1, 0)))
		t.check("mtime tolerates a zero timestamp", zero:gsub(" ", "") == "", "[" .. zero .. "]")

		local custom = column.normalize({ "mtime", format = "%Y-%m-%d" }, CFG)
		custom.ctx.stats = { min = now - 1, max = now }
		local formatted = text_of(column.cell(custom, file("a", 1, now)))
		t.check("a custom format is honoured", formatted:find("^%s*%d%d%d%d%-%d%d%-%d%d$") ~= nil, formatted)

		local owner = column.normalize("owner", CFG)
		t.check("owner renders user:group", text_of(column.cell(owner, file("a", 1, now))):find("user501:grp20") ~= nil)
	end
end
