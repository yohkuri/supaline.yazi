---@diagnostic disable: lowercase-global
-- (`install` assigns Yazi's globals on purpose.)
--
-- Stand-ins for the globals Yazi injects, so the pure logic (colour maths,
-- column normalisation, padding, the stats contract) can be exercised by a
-- plain `lua` binary.
--
-- These are only as faithful as the tests need. Anything that depends on real
-- Yazi behaviour -- rendering, fetchers, `ya.sync` state -- belongs in
-- test/e2e.sh, which drives an actual Yazi.

local M = {}

--- Display width of a stubbed renderable.
function M.width_of(x)
	if type(x) == "string" then
		return #x
	elseif x.kind == "span" then
		return #x.text
	elseif x.kind == "line" then
		local n = 0
		for _, p in ipairs(x.parts) do
			n = n + M.width_of(p)
		end
		return n
	end
	return 0
end

--- Flatten a stubbed renderable back to plain text.
function M.text_of(x)
	if type(x) == "string" then
		return x
	elseif x.kind == "span" then
		return x.text
	elseif x.kind == "line" then
		local out = {}
		for _, p in ipairs(x.parts) do
			out[#out + 1] = M.text_of(p)
		end
		return table.concat(out)
	end
	return ""
end

--- A minimal `fs::File`.
function M.file(name, size, mtime, is_dir)
	return {
		name = name,
		url = name,
		is_hovered = false,
		cha = { len = size, mtime = mtime, is_dir = is_dir or false, uid = 501, gid = 20, nlink = 1 },
		size = function() return is_dir and nil or size end,
	}
end

function M.install()
	ui = {
		Style = function()
			local s = { kind = "style" }
			s.fg = function(self, c)
				self.color = c
				return self
			end
			return s
		end,
		Span = function(t)
			local s = { kind = "span", text = t }
			s.style = function(self, st)
				self.st = st
				return self
			end
			return s
		end,
		Line = function(x)
			if type(x) ~= "table" or x.kind then
				x = { x }
			end
			local l = { kind = "line", parts = x }
			l.width = function(self) return M.width_of(self) end
			return l
		end,
	}

	th = { supaline = {} }

	ya = {
		-- Close enough in shape to the real one for the assertions we make.
		readable_size = function(n)
			if n < 1024 then
				return string.format("%d B", n)
			elseif n < 1024 * 1024 then
				return string.format("%.1f K", n / 1024)
			elseif n < 1024 * 1024 * 1024 then
				return string.format("%.1f M", n / 1024 / 1024)
			end
			return string.format("%.1f G", n / 1024 / 1024 / 1024)
		end,
		user_name = function(uid) return "user" .. tostring(uid) end,
		group_name = function(gid) return "grp" .. tostring(gid) end,
		time = function() return os.time() end,
		target_family = function() return "unix" end,
	}

	cx = { active = { history = function() return nil end } }
end

return M
