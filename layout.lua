--- @since 26.9.1
--- Cell measurement and layout; no registry, configuration inheritance or cache.
---@class supaline.LayoutModule
local M = {}

--- A Line, with the method `cut` below calls on one. `types.yazi` declares
--- `ui.truncate` and nothing for `Line:truncate`, which 26.9.1 has and
--- `test/truncate_spec.lua` pins the behaviour of, so the checker refuses the
--- call on a value it has typed. Taking the line as `unknown` gets past that
--- and costs the rest: nothing else called on the same value is checked
--- either.
---
--- The cast is at the call to `cut` rather than on the `ui.Line` it is handed:
--- `Line:style` is declared returning `self`, which resolves to `ui.Line`, so
--- a line cast where it is made loses the class again at the first `:style`.
---
--- The two options are the ones this plugin passes and `truncate_spec.lua`
--- pins, not a claim about everything 26.9.1 accepts -- `ui.truncate` also
--- takes `rtl`, and whether the method does was never measured. Nothing rests
--- on it either way: a constructor's keys are not checked against this shape.
---@class supaline.Line : ui.Line
---@field truncate fun(self: self, opts: { max: integer, ellipsis: string? }): supaline.Line

--- Whether byte length is display width and the ASCII truncation path is safe.
---
--- Named because it is load-bearing in three places rather than an
--- optimisation in three places. In `soft_cut` it is the branch between
--- `ui.truncate` and the cluster walk the `❤️` measurement exists for, so a
--- typo in the byte class there reads as a performance choice and cuts a cell
--- too wide.
---@param text string
---@return boolean
local function is_ascii(text) return not text:find("[\128-\255]") end

--- Display width of a plain string. Sizes, dates and permission strings are
--- ASCII, so the byte length is exact; anything else asks Yazi.
---
--- The answer to `is_ascii` comes back beside the width, because measuring is
--- where it is asked and cutting is where it is wanted again. A caller with no
--- cut ahead of it ignores the second value and pays nothing for it.
---@param text string
---@return integer width
---@return boolean ascii whether the byte length was what answered
function M.text_width(text)
	if is_ascii(text) then
		return #text, true
	end
	return ui.width(text), false
end

-- The mark `ui.truncate` leaves behind, and the one cell it takes.
local ELLIPSIS = "…"

-- Zero-width joiner. Whatever follows one belongs to the sequence it opened,
-- however wide that character measures on its own.
local ZWJ = "\226\128\141"

--- Whether `ch` is a skin-tone modifier, or one half of a flag. Both are two
--- cells alone and none at all behind what they attach to, so neither can be
--- told from a base character by measuring it.
---@param ch string one UTF-8 character
---@return boolean
local function is_tone(ch) return ch:find("^\240\159\143[\187-\191]$") ~= nil end

---@param ch string one UTF-8 character
---@return boolean
local function is_flag(ch) return ch:find("^\240\159\135[\166-\191]$") ~= nil end

--- Split `text` into grapheme clusters -- as much of that rule as a cell
--- needs: a base character, plus everything after it that only means anything
--- attached to it.
---
--- Necessary rather than tidy, because the width of a cluster is not the sum
--- of its characters' widths. Measured on 26.9.1: `❤` is one cell and the
--- variation selector after it is none, but `❤️` is two. A cut that counted
--- characters would hand back a cell more than the column asked for, and every
--- column after it would shift.
---@param text string
---@return table<integer, string>
local function clusters(text)
	local out, prev, half = {}, nil, false
	-- `[\0-\127\194-\244]` rather than `[%z...]`: `%z` stopped meaning the NUL
	-- byte after Lua 5.1 and matches the letter `z` on the 5.5 Yazi runs.
	for ch in text:gmatch("[\0-\127\194-\244][\128-\191]*") do
		local join
		if #out == 0 then
			join = false
		elseif is_flag(ch) then
			join = half -- a flag is a pair of regional indicators, never a third
		else
			-- Zero width covers the combining marks, the variation selectors and
			-- the joiner itself.
			join = ui.width(ch) == 0 or is_tone(ch) or prev == ZWJ
		end

		if join then
			out[#out] = out[#out] .. ch
		else
			out[#out + 1] = ch
		end
		prev, half = ch, is_flag(ch) and not join
	end
	return out
end

--- Cut a string to `width` display cells and add nothing. `ui.truncate` cannot
--- do this -- it always appends an ellipsis of its own -- so the general case
--- is walked here, one cluster at a time. Only ever reached by a cell that
--- overflows, and the ASCII path covers every built-in column.
---
--- `ascii` is passed in rather than asked, because every caller has already
--- had to ask: `fit` measured the string before it knew the cell overflowed,
--- and `soft_cut` chose this path by the same answer. Asked here as well, the
--- same bytes were scanned twice on the way to one cut and three times on the
--- way through `fit`.
---@param text string
---@param width integer
---@param ascii boolean whether `text` is all ASCII
---@return string
local function hard_cut(text, width, ascii)
	if width < 1 then
		return ""
	elseif ascii then
		return text:sub(1, width)
	end

	local out, w = {}, 0
	for _, cluster in ipairs(clusters(text)) do
		local cw = ui.width(cluster)
		if w + cw > width then
			break
		end
		out[#out + 1], w = cluster, w + cw
	end
	return table.concat(out)
end

--- Cut a string to `width` cells and mark the cut, as `ui.truncate` does.
---
--- Yazi's own is exact for ASCII, which is every built-in column, so that is
--- still what an ASCII cell goes through. It counts one character at a time,
--- though, and a cluster wider than its characters slips past: measured on
--- 26.9.1, `ui.truncate("❤️abc", { max = 3 })` is `❤️a…`, four cells wide.
--- So anything carrying a byte over 127 is cut here instead, on a cluster
--- boundary and with the ellipsis's own cell held back.
---@param text string
---@param width integer
---@param ascii boolean whether `text` is all ASCII; see `hard_cut`
---@return string
local function soft_cut(text, width, ascii)
	if ascii then
		return ui.truncate(text, { max = width })
	elseif width < 1 then
		return ""
	end
	return hard_cut(text, width - 1, false) .. ELLIPSIS
end

--- Fit a plain string into `limit` cells, padding it out to `pad` cells if the
--- column has a width to pad to.
---
--- Either cut returns *at most* `limit` cells, and either can come back short
--- when a wide character straddles the boundary, so the result is measured
--- again and padded.
---
--- The two numbers are the same one wherever a column has a width at all --
--- folder preparation has already applied `max_width`. They part company on the one
--- path that leaves a column without a width, which is `M.cell` below.
---@param text string
---@param limit integer the most it may be
---@param pad integer? what to pad it out to, if anything
---@param align string
---@param overflow string
---@return string
local function fit(text, limit, pad, align, overflow)
	-- Taken off the measurement and handed to whichever cut is chosen. Measuring
	-- had to ask already, and both cuts ask the same question of the same bytes
	-- -- so left to each of them the class was scanned three times over for
	-- every cell that overflows, on every row of every frame.
	local w, ascii = M.text_width(text)

	if w > limit then
		if overflow == "grow" then
			return text
		elseif overflow == "clip" then
			text = hard_cut(text, limit, ascii)
		else
			text = soft_cut(text, limit, ascii)
		end
		-- Measured again rather than assumed: either cut returns *at most*
		-- `limit`, and a cut that dropped a wide cluster comes back shorter --
		-- and no longer necessarily non-ASCII, so this asks afresh.
		w = M.text_width(text)
	end

	if pad and w < pad then
		local spare = string.rep(" ", pad - w)
		return align == "left" and text .. spare or spare .. text
	end
	return text
end

--- Cut a renderable to `width` cells.
---
--- `Line:truncate` is the only way in -- a Line's spans cannot be read back
--- from Lua -- and it measures the line differently from `Line:width`, in two
--- ways that have to be corrected from out here. Both were measured on 26.9.1
--- and both come from one place: it counts one character at a time, and drops
--- the character that lands exactly on `max` to make room for the ellipsis.
---
---   * With `ellipsis = ""` there is nothing to make room for, but the drop
---     happens anyway: `{ max = 4 }` returns three cells of `abcdefgh`, where
---     the same string cut as a string returns four. Asking for one cell more
---     than the column has cancels it out exactly.
---   * A cluster wider than its characters -- `❤️` is two cells and its two
---     characters are one and none -- is left alone when it does not fit, so
---     what comes back can be *wider* than `max`. No `max` cuts that to the
---     cell, so cut again with a smaller one until it fits, and let it come
---     back short: short is padded below, long shifts every column after it.
---
--- Yazi's truncate mutates the line it is given and hands it back, so each
--- pass cuts the previous result further. `max = 0` empties a line whatever it
--- held, so the loop always ends.
---@param line supaline.Line
---@param width integer
---@param ellipsis string? `""` to cut without a mark, nil for Yazi's own
---@return supaline.Line
local function cut(line, width, ellipsis)
	local max = ellipsis == "" and width + 1 or width
	while max >= 0 do
		line = line:truncate { max = max, ellipsis = ellipsis }
		if line:width() <= width then
			break
		end
		max = max - 1
	end
	return line
end

--- Render one column for one file, fitted to its effective width.
---@param col supaline.ColumnPlan
---@param ctx supaline.Ctx
---@param file supaline.File
---@return unknown an `AsLine`
function M.cell(col, ctx, file)
	local out, style = col.render(file, ctx)
	if out == nil then
		out = ""
	end

	-- The width to pad out to, and the most the cell may be. They are the same
	-- number wherever there is one: folder preparation has already capped `ctx.width` by
	-- `max_width`.
	--
	-- They part company on the one path that leaves a column with no width at
	-- all -- a `width` function that threw, or that came back with a number
	-- supaline will not take. That column draws unpadded, which is what its
	-- notification says and what a ragged row looks like; a `max_width` the
	-- reader stated is still theirs, and is the one half of the arithmetic
	-- that never depended on the function that failed. Handing the cap over as
	-- the width instead would pad every cell out to it, which is a fixed width
	-- nobody asked for wearing a cap's name.
	local width = ctx.width
	local limit = width or col.max_width

	if type(out) == "string" then
		if limit then
			out = fit(out, limit, width, col.align, col.overflow)
		end
		return style and ui.Span(out):style(style) or out
	end

	-- A Line or Span came back; pad around it rather than inside it.
	local line = ui.Line(out)
	if style then
		-- `render` may hand back a style alongside a renderable as well as
		-- alongside a string, and dropping it here would lose the colour
		-- silently. A Line's style sits under its spans, so one that styled
		-- its own keeps them.
		line = line:style(style)
	end
	if not limit then
		return line
	end

	local w = line:width()
	if w > limit then
		if col.overflow == "grow" then
			return line
		end
		-- An empty ellipsis is how `Line:truncate` is asked to cut cleanly; left
		-- to itself it inserts "…" like `ui.truncate` does.
		line = cut(line --[[@as supaline.Line]], limit, col.overflow == "clip" and "" or nil)
		-- `cut` returns *at most* `limit`: a wide character straddling the edge
		-- comes back one cell short, and an unpadded cell drags every column
		-- after it out of line.
		w = line:width()
	end

	if width and w < width then
		local pad = string.rep(" ", width - w)
		local padded = col.align == "left" and ui.Line { line, pad } or ui.Line { pad, line }
		-- Styled a second time, around the pad. The string path pads in `fit`
		-- and styles what came back, so its spare cells are inside the style
		-- for free; here the pad cannot be built until the line has been
		-- measured, which is after `line` was styled. A Line's style sits
		-- under its spans, so this reaches the bare pad and leaves both the
		-- text and whatever the render styled its own spans with.
		--
		-- Applying one style twice is safe where applying one *span* twice is
		-- not: `ctx.style` is reused on every row of every column already, by
		-- the string path a few lines above.
		return style and padded:style(style) or padded
	end
	return line
end

--- Measure the value a render returned. Renderables are consumed, never cached.
---@param out any
---@return integer
function M.measure(out)
	if out == nil then
		return 0
	end
	if type(out) == "string" then
		return (M.text_width(out))
	end
	return ui.Line(out):width()
end

return M
