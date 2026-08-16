--- @since 26.8.15
--- A chezmoi status column, plus the fetcher that feeds it.
---
--- chezmoi keeps three states: the *source* tree (~/.local/share/chezmoi, whose
--- filenames carry attribute prefixes like `dot_` and `private_`), the
--- *destination* tree (your home directory) and the *target* state computed
--- from the source. You browse both trees in practice, so this column resolves
--- either one.
---
--- Rather than reconstruct chezmoi's filename encoding -- which would rot the
--- moment chezmoi grows a new attribute -- we ask chezmoi itself:
---
---   chezmoi status  --path-style absolute         -> changes, by target path
---   chezmoi managed --path-style absolute         -> managed set, target side
---   chezmoi managed --path-style source-relative  -> managed set, source side
---   chezmoi source-path <targets...>              -> changes, by source path
---
--- Each of those runs in ~40ms, and only when the cache is stale or a file
--- operation has marked it dirty, so the cost never lands on a keystroke.

local column = require(".column")

---@enum CZ_CODES
local CODES = {
	script = 5, -- a script chezmoi will run
	deleted = 4,
	added = 3,
	modified = 2,
	managed = 1, -- tracked by chezmoi and up to date
	unmanaged = 0,
}

local function theme()
	local t = th.chezmoi or {}
	return {
		[CODES.script] = t.script or ui.Style():fg("magenta"),
		[CODES.deleted] = t.deleted or ui.Style():fg("red"),
		[CODES.added] = t.added or ui.Style():fg("green"),
		[CODES.modified] = t.modified or ui.Style():fg("yellow"),
		[CODES.managed] = t.managed or ui.Style():fg("darkgray"),
		[CODES.unmanaged] = t.unmanaged or ui.Style(),
	}, {
		[CODES.script] = t.script_sign or "!",
		[CODES.deleted] = t.deleted_sign or "-",
		[CODES.added] = t.added_sign or "+",
		[CODES.modified] = t.modified_sign or "~",
		[CODES.managed] = t.managed_sign or "",
		[CODES.unmanaged] = t.unmanaged_sign or "",
	}
end

--- The two status columns are "what changed behind chezmoi's back" and "what
--- `chezmoi apply` will do". The second is the actionable one; fall back to the
--- first when apply has nothing to say.
---@param sig string the leading two characters of a status line
---@return CZ_CODES?
local function code_of(sig)
	local c = sig:sub(2, 2)
	if c == " " or c == "" then
		c = sig:sub(1, 1)
	end

	if c == "R" then
		return CODES.script
	elseif c == "D" then
		return CODES.deleted
	elseif c == "A" then
		return CODES.added
	elseif c == "M" then
		return CODES.modified
	end
end

--- As in git.lua: real filesystem only, which also excludes `search://`.
---@param url Url
---@return boolean
local function is_local(url) return url.spec.is_regular end

--- Run chezmoi and return stdout, or nil if the binary is missing or errored.
---@param args string[]
---@return string?
local function run(args)
	local output = Command("chezmoi"):arg(args):output()
	if not output or not output.status.success then
		return nil
	end
	return output.stdout
end

---@param s string
---@return string[]
local function lines(s)
	local out = {}
	for line in s:gmatch("[^\r\n]+") do
		if line ~= "" then
			out[#out + 1] = line
		end
	end
	return out
end

--- Walk a change up to the tree root so directory rows inherit the worst state
--- of anything beneath them.
local function bubble_up(map, path, code, root)
	local url = Url(path).parent
	while url do
		local s = tostring(url)
		if #s < #root then
			break
		end
		if (map[s] or CODES.unmanaged) < code then
			map[s] = code
		end
		if s == root then
			break
		end
		url = url.parent
	end
end

-- State reducers. As in git.lua, these are left unwrapped: `ya.sync` binds to
-- the file it is called from, so main.lua wraps them next to `setup` and passes
-- the proxies into `fetch`.
local M = {}

--- Claim the right to refresh: returns the roots to work against, or nil when
--- another fetch is already in flight or the cache is still warm.
function M.reduce_claim(st, now, interval)
	local cz = st.cz
	if not cz or cz.ok == false or cz.busy then
		return nil
	elseif not cz.dirty and cz.at > 0 and now - cz.at < interval then
		return nil
	end

	cz.busy = true
	return { src = cz.src, dest = cz.dest }
end

function M.reduce_commit(st, status, managed, roots, now)
	local cz = st.cz
	cz.busy, cz.dirty, cz.at = false, false, now
	cz.status, cz.managed = status, managed
	cz.src, cz.dest = roots.src, roots.dest
	ui.render()
end

function M.reduce_abandon(st, ok)
	st.cz.busy = false
	st.cz.ok = ok
	if ok == false then
		st.cz.at = math.huge -- never retry a missing binary
	end
end

--- Register the "chezmoi" column, capturing the plugin state that the fetcher
--- writes into.
function M.setup(st, opts)
	opts = opts or {}
	st.cz = st.cz or { status = {}, managed = {}, at = 0, dirty = true }

	local styles, signs = theme()
	ps.sub("theme", function()
		styles, signs = theme()
	end)

	-- Any file operation can change what chezmoi has to say, so invalidate.
	-- On `bulk-rename` rather than `bulk`, for the reason main.lua gives.
	local dirty = function() st.cz.dirty = true end
	for _, kind in ipairs { "rename", "bulk-rename", "move", "delete", "trash" } do
		ps.sub(kind, dirty)
	end

	column.register("chezmoi", {
		width = opts.width or 1,
		align = "left",
		render = function(file, ctx)
			local cz = st.cz
			local path = tostring(file.url)

			local code = cz.status[path]
			if not code then
				code = cz.managed[path] and CODES.managed or CODES.unmanaged
			end

			local sign = signs[code]
			if sign == "" then
				return "", ctx.base
			elseif file.is_hovered then
				return sign
			end
			return sign, styles[code]
		end,
	})
end

---@param job table
---@param claim fun(now: number, interval: number): table? sync proxy from main.lua
---@param commit fun(status: table, managed: table, roots: table, now: number)
---@param abandon fun(ok: boolean)
---@return boolean
function M.fetch(job, claim, commit, abandon)
	local url = job.files[1].url
	if not is_local(url) then
		return true
	end

	local roots = claim(ya.time(), 3)
	if not roots then
		return true
	end

	-- One-time discovery of both tree roots.
	if not roots.src or not roots.dest then
		local src, dest = run { "source-path" }, run { "target-path" }
		if not src or not dest then
			abandon(false) -- chezmoi absent, or no source state yet
			return true
		end
		roots.src, roots.dest = lines(src)[1], lines(dest)[1]
		if not roots.src or not roots.dest then
			abandon(false)
			return true
		end
	end

	local raw = run { "status", "--path-style", "absolute" }
	if not raw then
		abandon(true) -- transient; try again on the next tick
		return true
	end

	-- Changes, keyed by target path.
	local status, targets = {}, {}
	for _, line in ipairs(lines(raw)) do
		local code, path = code_of(line:sub(1, 2)), line:sub(4)
		if code and path ~= "" then
			status[path] = code
			targets[#targets + 1] = path
		end
	end

	-- The same changes, keyed by source path. Every target here is managed by
	-- definition, so the batched output stays aligned with `targets`.
	if #targets > 0 then
		local argv = { "source-path" }
		for _, path in ipairs(targets) do
			argv[#argv + 1] = path
		end

		local mapped = run(argv)
		if mapped then
			local out = lines(mapped)
			for i, path in ipairs(out) do
				if targets[i] then
					status[path] = status[targets[i]]
				end
			end
		end
	end

	-- Managed sets for both trees.
	local managed = {}
	local target_side = run { "managed", "--path-style", "absolute" }
	if target_side then
		for _, path in ipairs(lines(target_side)) do
			managed[path] = true
		end
	end

	local source_side = run { "managed", "--path-style", "source-relative" }
	if source_side then
		local src = Url(roots.src)
		for _, rel in ipairs(lines(source_side)) do
			managed[tostring(src:join(rel))] = true
		end
	end

	-- Directories inherit the worst state below them, on both sides. Snapshot
	-- first: `bubble_up` writes into the very table we are walking.
	local leaves = {}
	for path, code in pairs(status) do
		leaves[#leaves + 1] = { path, code }
	end
	for _, leaf in ipairs(leaves) do
		local path, code = leaf[1], leaf[2]
		bubble_up(status, path, code, path:sub(1, #roots.src) == roots.src and roots.src or roots.dest)
	end

	commit(status, managed, roots, ya.time())
	return true
end

return M
