-- The colour maths: parsing, the Oklab ramp, and quantised lookup.

return function(t)
	local gradient = t.module("gradient")

	-- A ramp holds `ui.Style`s; the stub records the colour it was given.
	local function hex(style) return style.color end

	local function rgb(style)
		local h = hex(style)
		return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16)
	end

	-- Perceived brightness, only to assert the ramp runs the right way.
	local function luma(style)
		local r, g, b = rgb(style)
		return 0.2126 * r + 0.7152 * g + 0.0722 * b
	end

	t.group("parse")
	t.check("hex accepted", gradient.ramp("#89b4fa", 4, 0.5) ~= nil)
	t.check("name accepted", gradient.ramp("cyan", 4, 0.5) ~= nil)
	t.check("garbage rejected", gradient.ramp("not-a-colour", 4, 0.5) == nil)
	t.check("short hex rejected", gradient.ramp("#abc", 4, 0.5) == nil)

	t.group("ramp shape")
	for _, base in ipairs { "#89b4fa", "cyan", "red", "#f38ba8", "#a6e3a1" } do
		local ramp = gradient.ramp(base, 24, 0.5)
		t.check(base .. ": 24 steps", #ramp == 24, #ramp)

		local monotonic = true
		for i = 2, #ramp do
			if luma(ramp[i]) < luma(ramp[i - 1]) - 0.5 then
				monotonic = false
			end
		end
		t.check(base .. ": brightness increases", monotonic)
		t.check(base .. ": in gamut", hex(ramp[#ramp]):match("^#%x%x%x%x%x%x$") ~= nil, hex(ramp[#ramp]))
	end

	t.group("hue survives the ramp")
	local reds = gradient.ramp("#f38ba8", 24, 0.5)
	local r1, g1, b1 = rgb(reds[20])
	t.check("red stays reddest", r1 > g1 and r1 > b1, hex(reds[20]))

	local greens = gradient.ramp("#a6e3a1", 24, 0.5)
	local r2, g2, b2 = rgb(greens[20])
	t.check("green stays greenest", g2 > r2 and g2 > b2, hex(greens[20]))

	local blues = gradient.ramp("#89b4fa", 24, 0.5)
	local r3, g3, b3 = rgb(blues[20])
	t.check("blue stays bluest", b3 > r3 and b3 > g3, hex(blues[20]))

	t.group("min_luminance")
	local dim = gradient.ramp("#89b4fa", 24, 0.2)
	local bright = gradient.ramp("#89b4fa", 24, 0.8)
	t.check(
		"a lower floor is darker at the bottom",
		luma(dim[1]) < luma(bright[1]),
		string.format("%s vs %s", hex(dim[1]), hex(bright[1]))
	)
	t.check(
		"both reach the same top",
		math.abs(luma(dim[24]) - luma(bright[24])) < 1,
		string.format("%s vs %s", hex(dim[24]), hex(bright[24]))
	)

	t.group("pick")
	local ramp = gradient.ramp("#89b4fa", 24, 0.5)
	t.check("ratio 0 -> first", gradient.pick(ramp, 0) == ramp[1])
	t.check("ratio 1 -> last", gradient.pick(ramp, 1) == ramp[24])
	t.check("nil -> last", gradient.pick(ramp, nil) == ramp[24])
	t.check("NaN -> last", gradient.pick(ramp, 0 / 0) == ramp[24])
	t.check("below range clamps", gradient.pick(ramp, -5) == ramp[1])
	t.check("above range clamps", gradient.pick(ramp, 5) == ramp[24])
end
