--- Boundaries introduced by the plan/appearance/runtime split. These tests use
--- retained callback contexts and observable calls, not private cache fields.
local colour = require(".colour")
local column = require(".column")
local config = require(".config")
local diagnostics = require(".diagnostics")
local runtime = require(".runtime")
local style = require(".style")

---@type supaline.Main
local main = require(".main")

local CFG = { separator = " ", order = 1400, band = {} }

local function folder(path, size) return stub.folder(path, { stub.file { name = "one", size = size } }) end

---@return supaline.Registry
local function registry()
	local r = column.new_registry()
	r.register("probe", { render = function(_, ctx) return tostring(ctx.stats), ctx.style end })
	return r
end

local function compile(opts, r)
	return config.compile(opts, r or registry(), function() return false end)
end

local function draw(name, at)
	cx.active.current = at
	return text_of(Linemode[name] { _file = at.files[1] })
end

test("registry: catalogues and registries have explicit independent lifetimes", function()
	local a, b = column.new_registry(), column.new_registry()
	local defs = require(".builtin").definitions()
	throws(function() a.compile("size", CFG) end, "unknown column `size`")
	for name, def in pairs(defs) do
		a.register(name, def)
	end
	eq(a.compile("size", CFG).name, "size")
	throws(function() b.compile("size", CFG) end, "unknown column `size`")
	local first = function() return "a" end
	local second = function() return "b" end
	a.register("mine", { render = first })
	b.register("mine", { render = second })
	eq(a.compile("mine", CFG).render, first)
	eq(b.compile("mine", CFG).render, second)
end)

test("plan: compilation neither reads a theme nor evaluates style callbacks", function()
	local calls = 0
	local opts = {
		separator = {
			"|",
			style = function()
				calls = calls + 1
				return "red"
			end,
		},
		linemodes = { detail = { {
			"probe",
			style = function()
				calls = calls + 1
				return "blue"
			end,
		} } },
	}
	local plan
	with(_G, "th", nil, function()
		with(_G, "ui", nil, function() plan = compile(opts) end)
	end)
	eq(calls, 0)
	eq(plan.columns[1].ctx, nil, "a plan has no bound context")
	eq(plan.columns[1].told, nil, "a plan has no notification state")
	style.resolve(plan, {})
	eq(calls, 2)
end)

test("plan: width policy has one explicit case", function()
	local policies = { { nil, "natural" }, { 5, "fixed" }, { "auto", "auto" }, { function() return 5 end, "computed" } }
	for _, policy in ipairs(policies) do
		local plan = compile { linemodes = { detail = { { "probe", width = policy[1] } } } }
		local col = plan.columns[1]
		eq(col.width.kind, policy[2])
		eq(rawget(col, "auto"), nil)
		eq(rawget(col, "fixed"), nil)
		eq(rawget(col, "width_of"), nil)
	end
end)

test("colour: arithmetic requires no Yazi globals", function()
	with(_G, "ui", nil, function()
		local pure = dofile(ROOT .. "/colour.lua")
		local stops = pure.band(assert(pure.rgb("#0b3d91")), { from = 0.35, to = 0.88 })
		local ramp = pure.ramp(stops)
		eq(#ramp, pure.STEPS)
		eq(table.concat(ramp), table.concat(colour.ramp(stops)))
	end)
end)

test("snapshot: a theme reload cannot change the setup's structural inputs", function()
	local definition = {
		width = 3,
		options = { "text", "state" },
		text = "old",
		state = { suffix = "" },
		style = { fg = "red" },
		render = function(_, ctx) return ctx.opts.text .. ctx.opts.state.suffix, ctx.style end,
	}
	main.column("snapshot", definition)
	local separator = { "|", style = { fg = "blue" } }
	local entry = { "snapshot", style = { bold = true } }
	local list = { entry, function() return "x" end }
	local opts = { separator = separator, linemodes = { snap = list } }
	main.setup(opts)
	local at = folder("/snapshot", 1)
	eq(draw("snap", at), "old|x")
	definition.width, definition.text, definition.style.fg = 8, "new", "green"
	entry.style.bold, separator[1], separator.style.fg = false, "/", "yellow"
	list[2] = function() return "y" end
	opts.linemodes.extra = { "size" }
	stub.fire("theme")
	eq(draw("snap", at), "old|x")
	local parts = stub.drawn_styles(Linemode.snap { _file = at.files[1] })
	eq(parts[1].fg, "red")
	eq(parts[1].bold, true)
	eq(parts[2].fg, "blue")
	eq(Linemode.extra, nil)
	-- Opaque option payloads are intentionally borrowed, not recursively cloned.
	definition.state.suffix = "!"
	eq(draw("snap", at), "ol…|x")
	definition.state.suffix = ""
	main.setup(opts)
	eq(draw("snap", at), "     new/y")
	eq(type(Linemode.extra), "function")
end)

test("snapshot: style tables with metatables are still framework records", function()
	local inherited = { fg = "red" }
	local written = setmetatable({ bold = true }, { __index = inherited })
	local plan
	with(_G, "ui", nil, function() plan = compile { linemodes = { detail = { { "probe", style = written } } } } end)
	inherited.fg, written.bold = "blue", false
	local paint = style.resolve(plan, {}).columns[plan.columns[1]]
	eq(paint.style:raw().fg, "Red")
	eq(paint.style:raw().bold, true)
	local opaque = ui.Style():fg("green")
	eq(style.snapshot(opaque), opaque)
	throws(
		function() style.resolve(compile { linemodes = { detail = { { "probe", style = ui.Style } } } }, {}) end,
		"constructor"
	)
end)

test("snapshot: pane lists, mode separators and named bands are owned by the plan", function()
	local band = { fg = { from = 0.35, to = 0.88 } }
	local sep = { ":", style = { fg = "cyan" } }
	---@type supaline.ColumnSpec[]
	local current = { { "size", style = "#0b3d91 <->" }, "mtime" }
	local spec = { current = current, separator = sep }
	main.setup { band = band, linemodes = { snap = spec } }
	local at = folder("/bands", 20)
	cx.active.current = at
	local before = stub.drawn_styles(Linemode.snap { _file = at.files[1] })
	band.fg.from, band.fg.to = 0.1, 0.2
	sep[1], sep.style.fg = "/", "red"
	spec.current = { "count" }
	current[1] = "permissions"
	stub.fire("theme")
	local after = stub.drawn_styles(Linemode.snap { _file = at.files[1] })
	eq(after[1].fg, before[1].fg)
	eq(after[2].fg, "cyan")
	eq(draw("snap", at):find(":", 1, true) ~= nil, true)
end)

test("context: alternating panes never rebind a retained context", function()
	local seen, stats_calls, styles, refreshes = {}, 0, 0, 0
	local shared = {
		{
			stats = function(files)
				stats_calls = stats_calls + 1
				return { min = 1, max = files[1]:size() }
			end,
			width = function(stats) return stats.max end,
			refresh = function() refreshes = refreshes + 1 end,
			style = function()
				styles = styles + 1
				return "red"
			end,
			render = function(file, ctx)
				seen[file:size()] = ctx
				return "x", ctx.style
			end,
		},
	}
	main.setup { linemodes = { panes = { current = shared, parent = shared, preview = shared } } }
	local current, parent, preview = folder("/p/current", 3), folder("/p", 5), folder("/p/current/preview", 7)
	parent.files[1].in_current, preview.files[1].in_current = false, false
	cx.active.current, cx.active.parent = current, parent
	cx.active.preview = { folder = preview, skip = 0 }
	cx.active.pref.linemode = "panes"
	local child = stub.children[1].fn
	for _ = 1, 3 do
		Linemode.panes { _file = current.files[1] }
		child { _file = parent.files[1] }
		child { _file = preview.files[1] }
	end
	eq(styles, 1)
	eq(refreshes, 1)
	eq(stats_calls, 3)
	eq(seen[3] == seen[5], false)
	eq(seen[5] == seen[7], false)
	for _, n in ipairs { 3, 5, 7 } do
		eq(seen[n].width, n)
		eq(seen[n].stats.max, n)
		eq(seen[n].ratio(n), 1)
		eq(seen[n]._lo, nil)
	end
	local saved = seen[3]
	Linemode.panes { _file = current.files[1] }
	eq(saved, seen[3], "rows in one cached folder share a context")
	stub.fire("cd")
	Linemode.panes { _file = current.files[1] }
	eq(refreshes, 2)
	eq(saved == seen[3], false)
	eq(saved.width, 3, "invalidating never mutates previously handed-out contexts")
end)

test("runtime: absent folders are distinct per mode and pane", function()
	local seen = {}
	local function entry(name, width)
		return {
			width = width,
			render = function(_, ctx)
				seen[name] = ctx
				return name
			end,
		}
	end
	local plan = compile { linemodes = { a = { parent = { entry("a", 2) } }, b = { parent = { entry("b", 4) } } } }
	local run = runtime.new(plan, style.resolve(plan, {}), diagnostics.new(function() error("unexpected report") end))
	local file = stub.file {}
	eq(text_of(run.render(plan.modes.a, "parent", file)), " a")
	eq(text_of(run.render(plan.modes.b, "parent", file)), "   b")
	eq(seen.a == seen.b, false)
	eq(seen.a.width, 2)
	eq(seen.b.width, 4)
end)

test("runtime: the ninth folder clears the eight-entry cache", function()
	local seen, passes = {}, 0
	main.setup {
		linemodes = {
			bounded = {
				{
					stats = function() passes = passes + 1 end,
					render = function(file, ctx)
						seen[file:size()] = ctx
						return "x"
					end,
				},
			},
		},
	}
	local first = folder("/cache/1", 1)
	draw("bounded", first)
	local saved = seen[1]
	for i = 2, 8 do
		draw("bounded", folder("/cache/" .. i, i))
	end
	draw("bounded", first)
	eq(seen[1], saved)
	eq(passes, 8)
	draw("bounded", folder("/cache/9", 9))
	draw("bounded", first)
	eq(passes, 10)
	eq(seen[1] == saved, false)
end)

test("theme: refreshed text invalidates auto width and preserves old contexts", function()
	local text, passes, callbacks = "old", 0, 0
	local seen ---@type supaline.Ctx?
	main.setup {
		linemodes = {
			themed = {
				{
					width = "auto",
					stats = function() passes = passes + 1 end,
					refresh = function() text = th.supaline and th.supaline.text or "old" end,
					style = function()
						callbacks = callbacks + 1
						return "red"
					end,
					render = function(_, ctx)
						seen = ctx
						return text, ctx.style
					end,
				},
			},
		},
	}
	local at = folder("/theme", 1)
	eq(draw("themed", at), "old")
	local old = assert(seen)
	for _ = 1, 10 do
		draw("themed", at)
		eq(seen, old)
	end
	eq(passes, 1)
	eq(callbacks, 1)
	with(stub.th, "supaline", { text = "longer" }, function()
		stub.fire("theme")
		eq(draw("themed", at), "longer")
		eq(assert(seen).width, 6)
	end)
	eq(old.width, 3)
	eq(old == seen, false)
	eq(passes, 2)
	eq(callbacks, 2)
end)

test("theme: a rejected appearance retains the previous runtime and cache", function()
	local bad, seen, passes = false, nil, 0
	main.setup {
		linemodes = {
			keep = {
				{
					stats = function() passes = passes + 1 end,
					style = function() return bad and "invalid-colour" or "red" end,
					render = function(_, ctx)
						seen = ctx
						return "ok", ctx.style
					end,
				},
			},
		},
	}
	local at = folder("/keep", 1)
	draw("keep", at)
	local old = assert(seen)
	bad = true
	local before = #stub.notified
	stub.fire("theme")
	eq(draw("keep", at), "ok")
	eq(seen, old)
	eq(passes, 1)
	eq(#stub.notified, before + 1)
	bad = false
	stub.fire("theme")
	draw("keep", at)
	eq(passes, 2)
end)

test("snapshot: re-registering a definition takes effect only on setup", function()
	main.column("replace", { render = function() return "old" end })
	local opts = { linemodes = { replace = { "replace" } } }
	main.setup(opts)
	main.column("replace", { render = function() return "new" end })
	stub.fire("theme")
	local at = folder("/replace", 1)
	eq(draw("replace", at), "old")
	main.setup(opts)
	eq(draw("replace", at), "new")
end)
