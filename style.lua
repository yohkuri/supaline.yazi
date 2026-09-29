--- @since 26.9.1
--- The style language: what one writer puts under `style`, read into a layer;
--- the slot that gathers every writer of one place; the layers merged key by
--- key; the `ui.Style` built out of the result; and a separator, which is text
--- and a slot of its own.
---
--- Every value here is read at `setup` except what a function returns and what
--- the theme holds, which are read again on every `theme` event.
local colour = require(".colour")
local paint = require(".paint")
local schema = require(".schema")

---@class supaline.StyleModule
local M = {}

-- The attribute keys, in the spelling `theme.toml` uses and in the order a
-- refusal lists them. The theme key is `reversed` where the method is
-- `reverse()`, and measured on 26.9.1, `reverse = true` in `[supaline]` is
-- ignored without a word -- which is why a spec's own spelling is refused.
local ATTRS = { "bold", "dim", "italic", "underline", "blink", "blink_rapid", "reversed", "hidden", "crossed" }

-- The keys that hold a colour rather than an attribute.
local COLOURS = { "fg", "bg" }

-- The `ui.Style` method behind each attribute key.
local METHOD = { reversed = "reverse" }
for _, k in ipairs(ATTRS) do
	METHOD[k] = METHOD[k] or k
end

-- Every key a style holds: the colours, then the attributes.
local KEYS = {}
for _, k in ipairs(COLOURS) do
	KEYS[#KEYS + 1] = k
end
for _, k in ipairs(ATTRS) do
	KEYS[#KEYS + 1] = k
end

local function known(k) return k == "fg" or k == "bg" or METHOD[k] ~= nil end

-- The spellings a reader arrives at honestly, pointed at the one that works.
local MEANT = {
	reverse = "`reversed` is the spelling, here and in `theme.toml`",
	strikethrough = "`crossed` is the spelling",
	reset = '`reset` is a colour rather than an attribute -- write `fg = "reset"`',
}

local STYLE_HELP = string.format(
	"A style table takes `fg` and `bg`, plus %s -- the spelling `theme.toml` uses, so a style is "
		.. "written the same way in both files",
	schema.key_list(ATTRS)
)

--- A style as a user writes it: the keys `theme.toml` takes. `fg` and `bg`
--- hold a colour, a gradient, a band, or `false` for none; an attribute holds
--- `true`, or `false` for the attribute taken off whatever is beneath.
---@class supaline.StyleTable
---@field fg string|false|nil
---@field bg string|false|nil
---@field bold boolean?
---@field dim boolean?
---@field italic boolean?
---@field underline boolean?
---@field blink boolean?
---@field blink_rapid boolean?
---@field reversed boolean?
---@field hidden boolean?
---@field crossed boolean?

--- What one writer may put under `style`: the table above, a colour string
--- standing for its `fg`, a `ui.Style`, or `false` for nothing at all --
--- neither a colour of its own nor whatever the writers beneath it said.
---@alias supaline.StyleValue string|supaline.StyleTable|ui.Style|false

--- ... or a function returning one of those, or nothing. Called on every
--- build, which is how a spec borrows a colour from a flavor that had not
--- landed while `init.lua` ran.
---@alias supaline.StyleSpec supaline.StyleValue|(fun(): supaline.StyleValue?)

--- One writer's say, read into the shape all three writers share. A key
--- nobody wrote is absent, which is what leaves the layer beneath showing.
--- `false` in place of a layer is a writer turning everything off: both
--- colours off, and the attributes left unwritten, since an attribute's
--- `false` would take the row's own away as well.
---@class supaline.Layer
---@field fg supaline.Paint?
---@field bg supaline.Paint?
---@field bold boolean?
---@field dim boolean?
---@field italic boolean?
---@field underline boolean?
---@field blink boolean?
---@field blink_rapid boolean?
---@field reversed boolean?
---@field hidden boolean?
---@field crossed boolean?

--- A style as configuration wrote it: a value, read at `setup`; a function,
--- called on every build; or the theme's field, looked up on every build.
---@class supaline.Source
---@field at supaline.Path where it was written
---@field layer supaline.Layer|false|nil a value, already read
---@field call function? a function to call for the value
---@field theme string? the `[supaline]` field to look up

--- How a value written in one slot is read into a layer, refusing what that
--- slot cannot draw.
---@alias supaline.Reader fun(value: any, at: supaline.Path): supaline.Layer|false

--- Who wrote each key of a merged style: where, and whether it was the
--- theme's field.
---@alias supaline.Writers table<string, { at: supaline.Path, theme: boolean }>

--- One place a style goes -- a column, or a separator -- with everything
--- written for it and how it is read. A value is read at `setup`, and what a
--- function returns or the theme holds is read on every build by the same
--- reader, so the two are refused alike. What only the merged style can show
--- is refused by `check`, on every build too.
---@class supaline.Slot
---@field sources supaline.Source[] farthest first
---@field read supaline.Reader
---@field check fun(resolved: supaline.Layer, from: supaline.Writers)?

--- Whether `value` is a `ui.Style`, by what it answers to. `getmetatable`
--- cannot tell: measured on 26.9.1, every Yazi userdata answers `false`, a
--- Span as much as a Style. `patch` is a Style's method and nothing else's.
---@param value any
---@return boolean
local function is_style(value)
	return value ~= nil and pcall(function() return value:patch(ui.Style()) end)
end

--- Read one writer's style into a layer, refusing anything that is not one:
--- `Span:style` takes a Style or nil, and measured on 26.9.1 any other value
--- survives `setup` and then blanks the screen.
---
--- A `ui.Style` is read through `raw()`, which answers with the same keys a
--- table has -- so a themed field, a spec's `ui.Style()` and a table written
--- out are one shape here, and merge key by key.
---@param value any
---@param at supaline.Path
---@param painter supaline.Painter what a colour, and a gradient, mean here
---@return supaline.Layer|false
function M.layer(value, at, painter)
	local t
	if value == nil then
		return {}
	elseif value == false then
		return false
	elseif type(value) == "string" then
		return { fg = painter(value, at, "fg") }
	elseif is_style(value) then
		t = (value --[[@as supaline.Style]]):raw()
	elseif type(value) ~= "table" then
		at:refuse(
			"must be a colour string, a table of style keys, a `ui.Style`, or `false`, got a %s -- "
				.. "anything else reaches Yazi as none of them, and the screen goes blank",
			type(value)
		)
	else
		-- Measured on 26.9.1: `type(ui.Style)` is `table` and `pairs` finds
		-- nothing on it, so the constructor with its call forgotten would
		-- otherwise read as a layer saying nothing.
		local mt = getmetatable(value)
		if type(mt) == "table" and mt.__call ~= nil then
			at:refuse(
				"is a table you can call rather than a style -- `ui.Style` is the constructor. Write "
					.. '`ui.Style()`, or `{ fg = "#ff8800", bold = true }` to say the same as a table'
			)
		elseif next(value) == nil then
			at:refuse(
				"is a style table with no keys in it, which says nothing at all. Write the keys you "
					.. 'mean, as `{ fg = "#ff8800", bold = true }`, or `false` to turn every key off'
			)
		end
		t = value
	end

	schema.sweep(t, at, known, "style", STYLE_HELP, MEANT)
	local layer = {}
	for _, k in ipairs(COLOURS) do
		local v = t[k]
		if v == false then
			layer[k] = false
		elseif v ~= nil then
			layer[k] = painter(v, at:key(k), k)
		end
	end
	for _, k in ipairs(ATTRS) do
		local v = t[k]
		if v ~= nil and type(v) ~= "boolean" then
			at:key(k):refuse("must be true or false, got a %s -- it is an attribute rather than a colour", type(v))
		end
		layer[k] = v
	end
	return layer
end

--- How a column's style is read: a gradient resolved against the bands
--- `setup` defined, anything else a colour Yazi takes.
---@param bands supaline.Bands
---@return supaline.Reader
function M.reader(bands)
	local painter = paint.painter(bands)
	return function(value, at) return M.layer(value, at, painter) end
end

--- A style as configuration wrote it, read as far as it can be before a theme
--- exists.
---@param value any
---@param at supaline.Path
---@param read supaline.Reader
---@return supaline.Source?
function M.source(value, at, read)
	if value == nil then
		return nil
	elseif type(value) == "function" then
		return { at = at, call = value }
	end
	return { at = at, layer = read(value, at) }
end

--- Stack the layers, farthest first, giving each key to the nearest layer
--- that wrote it; `from` says which, for the refusal that has to name a file
--- and for the column that asks who wrote its `fg`.
---@param layers { values: supaline.Layer|false, source: any }[]
---@return supaline.Layer resolved
---@return table<string, any> from the source of each key
function M.merge(layers)
	local out, from = {}, {}
	for _, record in ipairs(layers) do
		local layer, source = record.values, record.source
		if layer == false then
			out, from = { fg = false, bg = false }, { fg = source, bg = source }
		else
			for _, k in ipairs(KEYS) do
				local v = layer[k]
				if v ~= nil then
					out[k], from[k] = v, source
				end
			end
		end
	end
	return out, from
end

--- Which colour key of a merged layer holds a gradient, if either does.
---@param resolved supaline.Layer
---@return string?
function M.gradient_in(resolved)
	for _, k in ipairs(COLOURS) do
		if type(resolved[k]) == "table" then
			return k
		end
	end
	return nil
end

--- What a row is drawn in: one style, or `colour.STEPS` of them when a colour
--- key holds a gradient, each set on the ground everything else built.
---
--- An attribute method takes a removal flag rather than the value --
--- `bold(true)` takes bold off -- so a layer's `false` goes in as `true`.
--- Measured through `raw()` on 26.9.1; `checked-traps.md` has it.
---@param resolved supaline.Layer
---@return unknown ground a ui.Style holding every key but a gradient
---@return unknown[]? steps ratio 0 first, when there is a gradient
function M.build(resolved)
	local ground = ui.Style()
	for _, k in ipairs(ATTRS) do
		local v = resolved[k]
		if v ~= nil then
			ground = ground[METHOD[k]](ground, not v)
		end
	end
	local ramps
	for _, k in ipairs(COLOURS) do
		local v = resolved[k]
		if type(v) == "string" then
			ground = ground[k](ground, v)
		elseif type(v) == "table" then
			ramps = ramps or {}
			ramps[k] = colour.ramp(v)
		end
	end
	if not ramps then
		return ground, nil
	end
	local steps = {}
	for i = 1, colour.STEPS do
		local step = ground
		for k, hexes in pairs(ramps) do
			step = step[k](step, hexes[i])
		end
		steps[i] = step
	end
	return ground, steps
end

--- A separator as it is written: the text first, the style beside it, which
--- reads the way `{ "size", style = ... }` does.
---@class supaline.SepSpec
---@field [1] string what to draw
---@field style supaline.StyleSpec?

--- A separator as a plan holds it: the text, and the slot its style is
--- resolved in, when one was written.
---@class supaline.Sep
---@field text string
---@field slot supaline.Slot?

local SEP_KEYS = { [1] = true, style = true }
local function sep_key(k) return SEP_KEYS[k] end

--- How a separator's style is read. A separator is drawn between two columns
--- rather than on a file, so a gradient is refused by the painter; `false` and
--- a style on `""` are refused here. The same reader takes what a function
--- returns, so the two are refused the same way.
---@param text string
---@return supaline.Reader
local function separator_reader(text)
	return function(value, at)
		if value == false then
			at:refuse(
				"is `false`, and there is nothing here to turn off. A column's `style = false` drops what its "
					.. "theme or its definition would otherwise supply; a separator has neither behind it, so "
					.. "leaving `style` out is how one goes uncoloured"
			)
		elseif value ~= nil and text == "" then
			at:refuse(
				'colours `""`, which draws nothing: a span of no cells shows no style. Write `""` on its own '
					.. "to put nothing between two columns, or give the separator something to draw"
			)
		end
		return M.layer(value, at, paint.flat)
	end
end

--- Read a separator, in either shape. `false` is not one: it drops the
--- separator before a column, and only a column may write it -- the caller
--- takes it before this is reached. Unrefused, `separator = 42` reaches Yazi
--- and empties the pane.
---@param value any
---@param at supaline.Path
---@return supaline.Sep
function M.separator(value, at)
	if type(value) == "string" then
		return { text = value }
	elseif type(value) ~= "table" then
		at:refuse(
			'must be a string or a table, got a %s -- `" | "` draws that between two columns, `{ " | ", '
				.. 'style = ... }` draws it in a colour, and `""` draws nothing at all. `false` drops the '
				.. "separator before a column and is a column's `separator`, never a linemode's",
			type(value)
		)
	end
	schema.sweep(
		value,
		at,
		sep_key,
		"separator",
		'A separator table takes what to draw as `[1]` and `style` beside it -- `{ " | ", style = { fg = "#585b70" } }`'
	)
	local text = value[1]
	if type(text) ~= "string" then
		at:key(1):refuse(
			'must be the text to draw, as `{ " | ", style = ... }`, got %s -- a separator with no text '
				.. "reaches Yazi as a span of nothing and the linemode stops drawing",
			text == nil and "nothing" or "a " .. type(text)
		)
	end
	if value.style == nil then
		-- The table form with the colour left out says what the bare string
		-- says; it does not inherit a style from the level above.
		return { text = text }
	end
	local read = separator_reader(text)
	return { text = text, slot = { sources = { M.source(value.style, at:key("style"), read) }, read = read } }
end

return M
