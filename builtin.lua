--- @since 26.8.15
--- The columns that ship with supaline.
---
--- Every one of these goes through `column.register()`, the same entry point a
--- user column uses -- there is no privileged internal path.

local column = require(".column")

-- Sizes and timestamps both take their extremes from the current listing, the
-- way `eza --color-scale-mode=gradient` does. Directories whose size has not
-- been evaluated stay out of the range, matching eza's `Size::Some` filter.
---@param get fun(file: table): number?
---@return fun(files: table): table?
local function extremes(get)
	return function(files)
		local min, max
		for i = 1, #files do
			local v = get(files[i])
			if v and v > 0 then
				if not min or v < min then
					min = v
				end
				if not max or v > max then
					max = v
				end
			end
		end
		return min and { min = min, max = max } or nil
	end
end

local function file_size(file) return file:size() end

column.register("size", {
	width = 9,
	align = "right",
	base = "cyan",
	stats = extremes(file_size),
	render = function(file, ctx)
		local size = file:size()
		if size then
			return ya.readable_size(size), ctx.style(ctx.ratio(size))
		end

		-- An unevaluated directory: fall back to the entry count, if the folder
		-- has already been visited, exactly as the preset `size` linemode does.
		local folder = cx.active:history(file.url)
		return folder and tostring(#folder.files) or "-", ctx.base
	end,
})

--- Yazi's preset formatting: time-of-day for the current year, the year itself
--- for anything older, so the column keeps a stable width either way.
local function smart(time)
	if os.date("%Y", time) == os.date("%Y") then
		return os.date("%m/%d %H:%M", time)
	end
	return os.date("%m/%d  %Y", time)
end

---@param field "mtime"|"btime"|"atime"
local function register_time(field)
	local get = function(file)
		local t = file.cha[field]
		return t and math.floor(t) or nil
	end

	column.register(field, {
		width = 11,
		align = "right",
		base = "blue",
		stats = extremes(get),
		render = function(file, ctx)
			local time = get(file)
			if not time or time == 0 then
				return "", ctx.base
			end

			local fmt = ctx.opts and ctx.opts.format
			local text = (not fmt or fmt == "smart") and smart(time) or os.date(fmt, time)
			return text, ctx.style(ctx.ratio(time))
		end,
	})
end

register_time("mtime")
register_time("btime")
register_time("atime")

column.register("permissions", {
	width = 10,
	align = "left",
	render = function(file, ctx) return file.cha:perm() or "", ctx.base end,
})

column.register("owner", {
	width = 12,
	align = "right",
	render = function(file, ctx)
		local cha = file.cha
		if not cha.uid then
			return "", ctx.base
		end

		local user = ya.user_name and ya.user_name(cha.uid) or cha.uid
		local group = ya.group_name and ya.group_name(cha.gid) or cha.gid
		return string.format("%s:%s", user, group), ctx.base
	end,
})

column.register("count", {
	width = 5,
	align = "right",
	render = function(file, ctx)
		if not file.cha.is_dir then
			return "", ctx.base
		end

		local folder = cx.active:history(file.url)
		return folder and tostring(#folder.files) or "-", ctx.base
	end,
})

-- Yazi's `require` wraps every module in a state table, so entries must return
-- a table even when, as here, they exist purely for their side effects.
return {}
