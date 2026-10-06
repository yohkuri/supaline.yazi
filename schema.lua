--- @since 26.9.1
--- Where a value was written, the refusal that says so, and the few parsers
--- every table a user writes is read with.
---
--- A refusal names the path that was being read rather than a phrase each
--- caller words for itself, and it is a string raised at level 0, so no
--- position in a file of supaline's is put in front of it.
---
--- A string rather than a table, because nothing else survives the trip.
--- Measured on 26.9.1 with a probe plugin: an error raised in a function one
--- module exports and caught by `pcall` in another arrives as Yazi's own error
--- userdata, `runtime error: ` and the `tostring` of what was raised, then two
--- tracebacks -- a table's identity is gone, a string's text is kept. A
--- closure handed back by an export, and a call within one module, are not
--- wrapped, so the harness, which wraps nothing, would not have said so.
---@class supaline.SchemaModule
local M = {}

-- Lua's keywords: names a key may hold and a path may not spell bare.
local KEYWORD = {}
for word in
	(
		"and break do else elseif end false for function goto if in local "
		.. "nil not or repeat return then true until while"
	):gmatch("%a+")
do
	KEYWORD[word] = true
end

--- `name` as Lua source spells it as a key: bare where that parses, and
--- `["..."]` where a keyword or a leading digit would not.
---@param name any
---@return string
function M.as_key(name)
	if type(name) == "string" and name:find("^[%a_][%w_]*$") and not KEYWORD[name] then
		return name
	end
	return string.format("[%q]", tostring(name))
end

--- What was written, for the end of a message that names it back: a string or
--- a number as written, anything else by its type. An empty string is named,
--- since quoted it is a pair of backticks that read as nothing.
---@param value any
---@return string
function M.as_written(value)
	local t = type(value)
	if value == "" then
		return "an empty string"
	elseif t == "string" or t == "number" then
		return string.format("`%s`", tostring(value))
	end
	return "a " .. t
end

--- "`a`, `b`", in the order given.
---@param names string[]
---@return string
function M.quoted(names) return "`" .. table.concat(names, "`, `") .. "`" end

--- "`a`, `b` and `c`", or "... or `c`" for a set of values to choose from.
---@param names string[]
---@param conj string? `and` by default
---@return string
function M.key_list(names, conj)
	if #names < 2 then
		return M.quoted(names)
	end
	return string.format("`%s` %s `%s`", table.concat(names, "`, `", 1, #names - 1), conj or "and", names[#names])
end

--- Where a value was written: `setup.linemodes.detail[2].align`,
--- `column("mark").style`, `theme [supaline].size`. `()` marks what a
--- function written there returned.
---@class supaline.Path
---@field s string
local Path = {}
Path.__index = Path
function Path.__tostring(p) return p.s end

---@param root string
---@return supaline.Path
function M.path(root) return setmetatable({ s = root }, Path) end

---@param key any
---@return supaline.Path
function Path:key(key)
	if type(key) == "number" then
		return M.path(string.format("%s[%s]", self.s, key))
	end
	local bare = M.as_key(key)
	return M.path(self.s .. (bare:sub(1, 1) == "[" and bare or "." .. bare))
end

---@return supaline.Path
function Path:call() return M.path(self.s .. "()") end

--- Refuse the value at this path: what is wrong with it, and what to write
--- instead. The location that matters is this path, not the line of this
--- file that noticed.
---@param fmt string
---@param ... any
function Path:refuse(fmt, ...) error(string.format("supaline: %s: %s", self.s, string.format(fmt, ...)), 0) end

--- Refuse every key of `t` that `known` does not claim, all of them at once
--- and sorted: `pairs` order would reword the message between runs, and naming
--- only the first costs a second run to find the rest.
---
--- This is what a misspelled key meets and nothing else does: a key in a table
--- constructor is past what `lua-language-server` checks against a class, and
--- `(exact)` was measured not to change that.
---@param t table
---@param at supaline.Path
---@param known fun(key: any): boolean?
---@param noun string what one of these tables is called, as in "not a `noun` key"
---@param help string what such a table does take
---@param meant table<string, string>? what a stray key most likely meant
function M.sweep(t, at, known, noun, help, meant)
	local names = {}
	for key in pairs(t) do
		if not known(key) then
			names[#names + 1] = tostring(key)
		end
	end
	if #names == 0 then
		return
	end
	table.sort(names)
	local hints = {}
	for _, name in ipairs(names) do
		hints[#hints + 1] = meant and meant[name]
	end
	at:refuse(
		"%s %s. %s%s",
		M.quoted(names),
		#names == 1 and "is not a " .. noun .. " key" or "are not " .. noun .. " keys",
		help,
		#hints > 0 and ". " .. table.concat(hints, "; ") or ""
	)
end

---@alias supaline.Parser fun(value: any, at: supaline.Path): any

---@param a any
---@param b any
---@return boolean
local function by_name(a, b) return tostring(a) < tostring(b) end

--- The keys of `t`, sorted by how they print, so that a message listing them,
--- or reading them in turn, says the same thing on every run.
---@param t table
---@return any[]
function M.sorted_keys(t)
	local keys = {}
	for key in pairs(t) do
		keys[#keys + 1] = key
	end
	table.sort(keys, by_name)
	return keys
end

--- A parser for a table of named fields: the keys it may hold, each read by
--- its own parser into a fresh table. A key nobody wrote is not read, so what
--- comes back holds exactly the keys that were written.
---
--- Fields are read in the order of their names, so a table wrong in two
--- places names the same one first on every run.
---@param fields table<any, supaline.Parser>
---@param noun string
---@param help string
---@param meant table<string, string>?
---@return fun(t: table, at: supaline.Path): table
function M.record(fields, noun, help, meant)
	local order = M.sorted_keys(fields)
	local function known(key) return fields[key] ~= nil end
	return function(t, at)
		M.sweep(t, at, known, noun, help, meant)
		local out = {}
		for _, key in ipairs(order) do
			local v = t[key]
			if v ~= nil then
				out[key] = fields[key](v, at:key(key))
			end
		end
		return out
	end
end

--- Whatever was written, unread: an option only its column interprets.
---@type supaline.Parser
function M.any(value) return value end

--- One of `values`, and nothing else. A value no key takes used to be taken by
--- being ignored, which is the quieter half of a misspelled key.
---@param values string[] in the order the message lists them
---@return supaline.Parser
function M.enum(values)
	local list = M.key_list(values, "or")
	return function(value, at)
		for _, ok in ipairs(values) do
			if value == ok then
				return value
			end
		end
		at:refuse("must be %s, got %s", list, M.as_written(value))
	end
end

--- A function. Refused while `setup` can still say so, rather than at the
--- first row, as a column throwing from a function nobody wrote.
---@type supaline.Parser
function M.fn(value, at)
	if type(value) ~= "function" then
		at:refuse(
			"must be a function, got %s -- it is called rather than read, so anything else would "
				.. "surface at the first row as this column throwing",
			M.as_written(value)
		)
	end
	return value
end

--- A whole number, or nil. `type` is asked before `math.tointeger`, which on
--- 5.5 turns the string "3" into 3.
---@param value any
---@return integer?
local function integer(value) return type(value) == "number" and math.tointeger(value) or nil end

--- A width as a count of cells, or nil for anything that is not one. The
--- floor is here rather than at each caller because every source of a width
--- empties the column the same way with a 0.
---@param value any
---@return integer?
function M.cells_of(value)
	local n = integer(value)
	return n and n >= 1 and n or nil
end

--- A whole number of cells, 1 or more. Not floored: `2.5` is a mistake
--- wherever it came from, and `3.0` is 3.
---@type supaline.Parser
function M.cells(value, at)
	local n = M.cells_of(value)
	if not n then
		at:refuse(
			"must be a whole number of cells, 1 or more, got %s -- a column of no cells draws as the "
				.. "empty string on every row, which reads as a column that is not there",
			M.as_written(value)
		)
	end
	return n
end

--- A whole number.
---@type supaline.Parser
function M.whole(value, at)
	local n = integer(value)
	if not n then
		at:refuse("must be a whole number, got %s", M.as_written(value))
	end
	return n
end

--- The keys of `t` that are not numbers, sorted, whether its numbered keys
--- run from 1 without a gap, and how many there are. `#t` alone cannot say: a
--- table with a gap has whichever border Lua finds, and `ipairs` stops at the
--- first one.
---@param t table
---@return string[] others
---@return boolean dense
---@return integer numbered
function M.shape(t)
	local others, n = {}, 0
	for key in pairs(t) do
		if type(key) == "number" then
			n = n + 1
		else
			others[#others + 1] = tostring(key)
		end
	end
	table.sort(others)
	return others, n == #t, n
end

return M
