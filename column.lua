--- @since 26.8.15
--- Column registry, spec normalisation, and cell layout.
---
--- A column is written in one of four shapes, all of which collapse to the same
--- runtime object, so a built-in column and a user-written one are
--- indistinguishable to the renderer:
---
---   "size"                                  a registered column, by name
---   { "size", width = 9 }                   ... with its options overridden
---   function(file, ctx) return "..." end    render-only shorthand
---   { render = fn, stats = fn, width = 6 }  an inline definition
---
--- `render(file, ctx)` runs for every visible row on every frame and must stay
--- O(1). Anything that needs to look at the whole folder belongs in
--- `stats(files)`, which main.lua computes once per folder and caches.
---
--- `render` may return a single `AsLine`, or `text, style`. The latter skips
--- building an intermediate Line, which is what the built-in columns do.

local M = { _registry = {} }

--- Register a reusable column under `name`, so a linemode can refer to it as
--- `"name"` or `{ "name", ... }`.
---@param name string
---@param def table
function M.register(name, def)
	if type(name) ~= "string" or name == "" then
		error("supaline: a column needs a non-empty name")
	elseif type(def) ~= "table" or type(def.render) ~= "function" then
		error(string.format("supaline: column `%s` needs a `render` function", name))
	elseif def.fetch then
		-- `ya.sync` blocks are matched between the sync and async VMs by the
		-- position of the call, and a block registered from the user's
		-- `init.lua` is never replayed on the async side. A third-party column
		-- therefore cannot own asynchronous state; say so rather than letting it
		-- fail silently at render time.
		error(
			string.format(
				"supaline: column `%s` cannot define `fetch`; a column that needs "
					.. "asynchronous state has to be built into supaline itself",
				name
			)
		)
	end
	M._registry[name] = def
end

---@param name string
---@return table?
function M.get(name) return M._registry[name] end

--- Resolve a column's base colour: the spec first, then the `[supaline]` theme
--- section, then the definition's own default.
---
--- The theme section may hold either a style table or a plain string, so both
--- are accepted. This runs inside `build()`, never at setup: until the `theme`
--- event fires, `th.*` still holds preset values only.
---@param name string?
---@param opts table
---@param def table
---@return unknown? a colour string, or a ui.Style
local function base_of(name, opts, def)
	if opts.base then
		return opts.base
	end

	local section = name and th.supaline
	local themed = section and section[name]
	if themed ~= nil and themed ~= "" then
		return themed
	end
	return def.base
end

---@param base unknown? a colour string, or a ui.Style
---@return unknown a ui.Style
local function style_of(base)
	if base == nil then
		return ui.Style()
	elseif type(base) == "string" then
		return ui.Style():fg(base)
	end
	-- A style table straight out of the theme section.
	return base
end

--- Turn one entry of a linemode spec into a runtime column.
---@param spec string|table|function
---@param cfg table plugin-wide options
---@return table
function M.normalize(spec, cfg)
	local name, opts, def

	if type(spec) == "function" then
		name, opts, def = nil, {}, { render = spec }
	elseif type(spec) == "string" then
		name, opts = spec, {}
		def = M._registry[spec] or error(string.format("supaline: unknown column `%s`", spec))
	elseif type(spec) ~= "table" then
		error("supaline: a column must be a name, a function, or a table with `render`")
	elseif type(spec[1]) == "string" then
		name, opts = spec[1], spec
		def = M._registry[name] or error(string.format("supaline: unknown column `%s`", name))
	elseif type(spec[1]) == "function" then
		name, opts, def = nil, spec, { render = spec[1] }
	elseif type(spec.render) == "function" then
		name, opts, def = spec.name, spec, spec
	else
		error("supaline: a column must be a name, a function, or a table with `render`")
	end

	local pick = function(key) return opts[key] == nil and def[key] or opts[key] end

	local col = {
		name = name,
		align = pick("align") or "right",
		overflow = pick("overflow") or "ellipsis",
		max_width = pick("max_width"),
		sep = opts.sep,
		stats = pick("stats"),
		render = opts.render or def.render,
		scale = pick("scale") or cfg.scale,
	}

	local width = pick("width")
	if width == "auto" then
		col.auto = true
	elseif type(width) == "function" then
		col.width_of = width
	elseif type(width) == "number" then
		col.fixed = math.floor(width)
	elseif width ~= nil then
		error(string.format('supaline: `width` of column `%s` must be a number, "auto", or a function', name or "?"))
	end

	-- A folder-wide pass is only worth making when something actually consumes
	-- it: a gradient ramp, or a width that is derived from the listing.
	col.needs_pass = (col.stats ~= nil and cfg.gradient) or col.auto or col.width_of ~= nil

	-- One context table per column, reused across rows. main.lua rebinds
	-- `stats` and `width` whenever the folder being drawn changes, not per row.
	local ctx = { base = style_of(base_of(name, opts, def)), opts = opts, stats = nil, width = col.fixed }
	col.ctx = ctx

	--- Where `value` sits between the extremes of the current listing, 0 to 1.
	--- Returns nil when there is nothing to normalise against, which makes
	--- `ctx.style` fall back to the flat base colour.
	function ctx.ratio(value)
		local lo, hi = ctx._lo, ctx._hi
		if not value or not lo then
			return nil
		elseif hi == lo then
			return 1
		end

		local v = ctx._log and math.log(value + 1) or value
		local r = (v - lo) / (hi - lo)
		return r < 0 and 0 or r > 1 and 1 or r
	end

	--- Phase 2 replaces this with a lookup into a quantised Oklab ramp. Until
	--- then every column draws flat, in its base colour.
	function ctx.style(_) return ctx.base end

	return col
end

--- Bind one folder's precomputed statistics and width onto a column, and
--- prepare whatever `ctx.ratio` needs so that no work is repeated per row.
---@param col table
---@param entry table
function M.bind(col, entry)
	local ctx = col.ctx
	ctx.stats = entry.stats
	ctx.width = entry.width or col.fixed

	local st = entry.stats
	if type(st) ~= "table" or st.min == nil or st.max == nil then
		ctx._lo, ctx._hi, ctx._log = nil, nil, false
		return
	end

	if col.scale == "log" then
		ctx._lo, ctx._hi, ctx._log = math.log(st.min + 1), math.log(st.max + 1), true
	else
		ctx._lo, ctx._hi, ctx._log = st.min, st.max, false
	end
end

--- Display width of a plain string. Sizes, dates and permission strings are
--- ASCII, so the byte length is exact; anything else asks Yazi.
---@param text string
---@return integer
local function width_of(text)
	if not text:find("[\128-\255]") then
		return #text
	end
	return ui.width(text)
end

M.width_of = width_of

--- Cut a string to `width` display cells and add nothing. `ui.truncate` cannot
--- do this -- it always appends an ellipsis of its own -- so the general case
--- is walked here, one UTF-8 character at a time. Only ever reached by a cell
--- that overflows, and the ASCII path covers every built-in column.
---@param text string
---@param width integer
---@return string
local function hard_cut(text, width)
	if not text:find("[\128-\255]") then
		return text:sub(1, width)
	end

	local out, w = {}, 0
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		local cw = ui.width(ch)
		if w + cw > width then
			break
		end
		out[#out + 1], w = ch, w + cw
	end
	return table.concat(out)
end

--- Fit a plain string into `width`, padding or truncating as the column asks.
---
--- `ui.truncate` already appends its own ellipsis and returns *at most* `width`
--- cells -- it can come back short when a wide character straddles the
--- boundary -- so the result is measured again and padded.
---@return string
local function fit(text, width, align, overflow)
	local w = width_of(text)

	if w > width then
		if overflow == "grow" then
			return text
		elseif overflow == "clip" then
			text = hard_cut(text, width)
		else
			text = ui.truncate(text, { max = width })
		end
		w = width_of(text)
	end

	if w < width then
		local pad = string.rep(" ", width - w)
		return align == "left" and text .. pad or pad .. text
	end
	return text
end

--- Render one column for one file, fitted to its effective width.
---@param col table
---@param file table `fs::File`
---@return unknown an `AsLine`
function M.cell(col, file)
	local out, style = col.render(file, col.ctx)
	if out == nil then
		out = ""
	end

	local width = col.ctx.width
	if col.max_width and width and width > col.max_width then
		width = col.max_width
	end

	if type(out) == "string" then
		if width then
			out = fit(out, width, col.align, col.overflow)
		end
		return style and ui.Span(out):style(style) or out
	end

	-- A Line or Span came back; pad around it rather than inside it.
	local line = ui.Line(out)
	if not width then
		return line
	end

	local w = line:width()
	if w > width then
		if col.overflow == "grow" then
			return line
		elseif col.overflow == "clip" then
			-- An empty ellipsis is how `Line:truncate` is asked to cut cleanly;
			-- left to itself it inserts "…" like `ui.truncate` does.
			return line:truncate { max = width, ellipsis = "" }
		end
		return line:truncate { max = width }
	elseif w < width then
		local pad = string.rep(" ", width - w)
		return col.align == "left" and ui.Line { line, pad } or ui.Line { pad, line }
	end
	return line
end

--- The effective width of a column for one folder, for the two shapes that
--- derive it from the listing rather than stating it outright.
---@param col table
---@param files table
---@param stats any
---@return integer?
function M.resolve_width(col, files, stats)
	if col.width_of then
		local w = col.width_of(stats)
		return type(w) == "number" and math.floor(w) or nil
	elseif not col.auto then
		return col.fixed
	end

	-- "auto": render every file in the folder once and keep the widest result.
	-- O(n) per folder, cached by main.lua, and capped by `max_width`.
	local max, ctx = 0, col.ctx
	for i = 1, #files do
		local out = col.render(files[i], ctx)
		local w
		if out == nil then
			w = 0
		elseif type(out) == "string" then
			w = width_of(out)
		else
			w = ui.Line(out):width()
		end
		if w > max then
			max = w
		end
	end

	if col.max_width and max > col.max_width then
		max = col.max_width
	end
	return max
end

return M
