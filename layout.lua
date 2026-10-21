--- @since 26.9.1
--- One cell: what a column's `render` returned, measured, cut and padded to
--- the column's width.
---@class supaline.LayoutModule
local M = {}

--- Whether byte length is display width, which decides between Yazi's own
--- truncation and the cluster walk below.
---@param text string
---@return boolean
local function is_ascii(text) return not text:find("[\128-\255]") end

--- Display width of a plain string, and whether the byte length answered.
--- Sizes, dates and permission strings are ASCII, so they never ask Yazi.
---@param text string
---@return integer width
---@return boolean ascii
function M.text_width(text)
	if is_ascii(text) then
		return #text, true
	end
	return ui.width(text), false
end

-- The mark `ui.truncate` leaves behind, and the one cell it takes.
local ELLIPSIS = "…"

-- Zero-width joiner: whatever follows one belongs to the sequence it opened.
local ZWJ = "\226\128\141"

--- A skin-tone modifier, or one half of a flag: two cells alone and none
--- behind what they attach to, so neither can be told apart by measuring.
---@param ch string one UTF-8 character
---@return boolean
local function is_tone(ch) return ch:find("^\240\159\143[\187-\191]$") ~= nil end

---@param ch string one UTF-8 character
---@return boolean
local function is_flag(ch) return ch:find("^\240\159\135[\166-\191]$") ~= nil end

--- `text` split into grapheme clusters, as far as a cell needs: a base
--- character and everything that only means anything attached to it. A
--- cluster's width is not the sum of its characters': measured on 26.9.1,
--- `❤` is one cell and `❤️` two.
---@param text string
---@return table<integer, string>
local function clusters(text)
	local out, prev, half = {}, nil, false
	-- Not `%z`, which matches the letter `z` on the 5.5 Yazi runs.
	for ch in text:gmatch("[\0-\127\194-\244][\128-\191]*") do
		local join
		if #out == 0 then
			join = false
		elseif is_flag(ch) then
			join = half -- a flag is a pair of regional indicators, never a third
		else
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

--- Cut a string to `width` cells and add nothing, which `ui.truncate` cannot
--- do. `ascii` is passed in because every caller has already had to ask.
---@param text string
---@param width integer
---@param ascii boolean
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

--- Cut a string to `width` cells and mark the cut. Yazi's own is exact for
--- ASCII, but counts characters: measured on 26.9.1,
--- `ui.truncate("❤️abc", { max = 3 })` is four cells wide. So anything else is
--- cut here, on a cluster boundary, with the ellipsis's cell held back.
---@param text string
---@param width integer
---@param ascii boolean
---@return string
local function soft_cut(text, width, ascii)
	if ascii then
		return ui.truncate(text, { max = width })
	elseif width < 1 then
		return ""
	end
	return hard_cut(text, width - 1, false) .. ELLIPSIS
end

--- Fit a plain string into `limit` cells, and pad it to `pad` if the column
--- has a width. Either cut can come back short when a wide character
--- straddles the edge, so the result is measured again before padding.
---@param text string
---@param limit integer
---@param pad integer?
---@param align string
---@param overflow string
---@return string
local function fit(text, limit, pad, align, overflow)
	local w, ascii = M.text_width(text)
	if w > limit then
		if overflow == "grow" then
			return text
		elseif overflow == "clip" then
			text = hard_cut(text, limit, ascii)
		else
			text = soft_cut(text, limit, ascii)
		end
		w = M.text_width(text)
	end
	if pad and w < pad then
		local spare = string.rep(" ", pad - w)
		return align == "left" and text .. spare or spare .. text
	end
	return text
end

--- Cut a renderable to `width` cells. `Line:truncate` is the only way in, and
--- measured on 26.9.1 it differs from `Line:width` twice over.
---
--- A cluster wider than its characters can come back wider than `max`, so a
--- line is cut again with a smaller one until it fits. `max = 0` empties any
--- line, so the loop ends.
---
--- And with `ellipsis = ""` it still drops the character landing on `max`, so
--- a clip asks for one cell more. That alone leaves a line exactly one cell
--- over by its own count whole at `width + 1` and a character short at
--- `width`, and `❤️`, two cells and one character to it, puts a line back at
--- that length after its first cut. So every cut is of the line lengthened by
--- a cell. The cell stays on only when the line comes back whole, wider by it,
--- and only that lowers `max`: a cut that took something off goes again at
--- the same one, since what it took may have been a zero-width character
--- standing on `max` behind the one it belongs to. Putting a Line inside
--- another moves its style onto each of its spans, read off 26.9.1's
--- `yazi-binding/src/elements/line.rs`, so a style the line carries survives.
---
--- What no `max` steers around is that cut itself: a cluster across the edge
--- keeps its first character, so `❤️` there comes back as `❤`, drawn so by
--- 26.9.1 in a column of 12 for `abcdefghijk❤️l`.
---@param line supaline.Line
---@param width integer
---@param ellipsis string? `""` to cut without a mark, nil for Yazi's own
---@return supaline.Line
local function cut(line, width, ellipsis)
	if ellipsis ~= "" then
		for max = width, 0, -1 do
			-- Cast on each pass, for the loop limit `annotate-supaline` states.
			line = (line:truncate { max = max, ellipsis = ellipsis }) --[[@as supaline.Line]]
			if line:width() <= width then
				break
			end
		end
		return line
	end
	local max, w = width + 1, line:width()
	while w > width do
		line = (ui.Line { line, " " }) --[[@as supaline.Line]]
		line = line:truncate { max = max, ellipsis = "" }
		local now = line:width()
		if now > w then
			max = max - 1
		end
		w = now
	end
	return line
end

--- Render one column for one file, fitted to its width.
---
--- The width to pad to and the most the cell may be are one number wherever
--- there is a width, since `max_width` has already capped it. They part only
--- for a column whose `width` function failed: it draws unpadded, as its
--- report says, and a `max_width` the reader stated still cuts.
---@param col supaline.ColumnPlan
---@param ctx supaline.Ctx
---@param file supaline.File
---@return unknown an `AsLine`
function M.cell(col, ctx, file)
	local out, style = col.render(file, ctx)
	if out == nil then
		out = ""
	end
	local width = ctx.width
	local limit = width or col.max_width

	if type(out) == "string" then
		if limit then
			out = fit(out, limit, width, col.align, col.overflow)
		end
		return style and ui.Span(out):style(style) or out
	end

	-- A Line or Span came back; pad around it rather than inside it. A style
	-- beside it goes under its spans, so spans that styled themselves keep it.
	local line = ui.Line(out)
	if style then
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
		-- Cast here rather than where the line is made: `Line:style` returns
		-- `ui.Line`, which would drop the class again.
		line = cut(line --[[@as supaline.Line]], limit, col.overflow == "clip" and "" or nil)
		w = line:width()
	end

	if width and w < width then
		local pad = string.rep(" ", width - w)
		local padded = col.align == "left" and ui.Line { line, pad } or ui.Line { pad, line }
		-- Styled again so the pad is inside the style, as the string path's
		-- is. One style applied twice is safe where one span drawn twice is not.
		return style and padded:style(style) or padded
	end
	return line
end

--- The width of what a render returned. Renderables are consumed: measured
--- on 26.9.1, `ui.Line` takes what it is given, so nothing is drawn twice.
---@param out any
---@return integer
function M.measure(out)
	if out == nil then
		return 0
	elseif type(out) == "string" then
		return (M.text_width(out))
	end
	return ui.Line(out):width()
end

return M
