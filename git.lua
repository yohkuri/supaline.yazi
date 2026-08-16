--- @since 26.8.15
--- A Git status column, plus the fetcher that feeds it.
---
--- This is the *optional* provider. The default arrangement is to keep using
--- the official git.yazi alongside supaline -- it renders as its own Linemode
--- child and needs nothing from us. Include the "git" column here instead when
--- you want the status sign aligned with supaline's other columns.
---
--- Status parsing, the worktree probe and the bubble-up/propagate-down handling
--- are derived from git.yazi in yazi-rs/plugins, Copyright (c) 2023 yazi-rs,
--- MIT licensed — see the third-party notices in LICENSE. The theme keys are
--- deliberately the same `[git]` ones, so existing flavours style this column
--- for free.
---
--- Two knowing departures, both pinned by test/git_spec.lua: unmerged states
--- are classified before ordinary ones, and `-z` is used so that paths are not
--- C-quoted.

local column = require(".column")

local WINDOWS = ya.target_family() == "windows"

-- Higher wins when a directory contains a mix of states.
---@enum GIT_CODES
local CODES = {
	unknown = 100, -- not determined yet
	excluded = 99, -- an ignored directory
	ignored = 6,
	untracked = 5,
	modified = 4,
	added = 3,
	deleted = 2,
	updated = 1,
	clean = 0,
}

-- Order matters: the first match wins.
--
-- The unmerged (conflict) states come first, because they are spelled with the
-- same letters as ordinary changes and would otherwise be swallowed by them.
-- git calls an entry unmerged when its code is DD, AU, UD, UA, DU, AA or UU, so
-- `U` anywhere covers five of them and DD/AA are named outright.
--
-- This is a deliberate departure from git.yazi, whose `[AD][AD]` rule sits
-- after `[AC]` and `D` and is therefore unreachable: there, AA reads as added,
-- DD and UD as deleted, AU and UA as added. See test/git_spec.lua.
local PATTERNS = {
	{ "!$", CODES.ignored },
	{ "?$", CODES.untracked },
	{ "U", CODES.updated },
	{ "^DD$", CODES.updated },
	{ "^AA$", CODES.updated },
	{ "[MT]", CODES.modified },
	{ "[AC]", CODES.added },
	{ "D", CODES.deleted },
}

local function theme()
	local t = th.git or {}
	return {
		[CODES.unknown] = t.unknown or ui.Style(),
		[CODES.ignored] = t.ignored or ui.Style():fg("darkgray"),
		[CODES.untracked] = t.untracked or ui.Style():fg("magenta"),
		[CODES.modified] = t.modified or ui.Style():fg("yellow"),
		[CODES.added] = t.added or ui.Style():fg("green"),
		[CODES.deleted] = t.deleted or ui.Style():fg("red"),
		[CODES.updated] = t.updated or ui.Style():fg("yellow"),
		[CODES.clean] = t.clean or ui.Style(),
	}, {
		[CODES.unknown] = t.unknown_sign or "",
		[CODES.ignored] = t.ignored_sign or "",
		[CODES.untracked] = t.untracked_sign or "?",
		[CODES.modified] = t.modified_sign or "",
		[CODES.added] = t.added_sign or "",
		[CODES.deleted] = t.deleted_sign or "",
		[CODES.updated] = t.updated_sign or "",
		[CODES.clean] = t.clean_sign or "",
	}
end

--- Split the NUL-separated output of `git status --porcelain -z`.
---
--- `--porcelain` on its own C-quotes any path containing a backslash, a quote
--- or a control character, so `back\slash.txt` arrives as `"back\\slash.txt"`
--- and never matches the real path. `-z` emits paths verbatim instead, which is
--- why this reads NUL-separated records rather than lines.
---@param s string
---@return string[]
local function entries(s)
	local out, pos = {}, 1
	while pos <= #s do
		local i = s:find("\0", pos, true)
		local entry = i and s:sub(pos, i - 1) or s:sub(pos)
		if entry ~= "" then
			out[#out + 1] = entry
		end
		pos = (i or #s) + 1
	end
	return out
end

---@param entry string one record of `git status --porcelain -z`, `XY <path>`
---@return GIT_CODES?
---@return string?
local function match(entry)
	local signs = entry:sub(1, 2)
	for _, p in ipairs(PATTERNS) do
		local path, pattern, code = nil, p[1], p[2]
		if signs:find(pattern) then
			path = entry:sub(4)
			path = WINDOWS and path:gsub("/", "\\") or path
		end

		if not path then -- keep looking
		elseif path == "" then
			return -- a status with no path; nothing to attribute it to
		elseif path:find("[/\\]$") then
			-- An ignored *directory*; mark it so propagate_down can expand it.
			return code == CODES.ignored and CODES.excluded or code, path:sub(1, -2)
		else
			return code, path
		end
	end
end

---@param cwd Url
---@return string?
local function root(cwd)
	local is_worktree = function(url)
		local file, head = io.open(tostring(url)), nil
		if file then
			head = file:read(8)
			file:close()
		end
		return head == "gitdir: "
	end

	repeat
		local next = cwd:join(".git")
		local cha = fs.cha(next)
		if cha and (cha.is_dir or is_worktree(next)) then
			return tostring(cwd)
		end
		cwd = cwd.parent
	until not cwd
end

--- Roll each change up through its ancestors so directory rows show the worst
--- state of anything beneath them.
local function bubble_up(changed)
	local new, empty = {}, Url("")
	for path, code in pairs(changed) do
		if code ~= CODES.ignored then
			local url = Url(path).parent
			while url and url ~= empty do
				local s = tostring(url)
				new[s] = (new[s] or CODES.clean) > code and new[s] or code
				url = url.parent
			end
		end
	end
	return new
end

--- Expand ignored directories into the one level we actually draw.
local function propagate_down(excluded, cwd, repo)
	local new, rel = {}, cwd:strip_prefix(repo)
	for _, path in ipairs(excluded) do
		if rel:starts_with(path) then
			new[tostring(cwd)] = CODES.excluded
		elseif cwd == repo:join(path).parent then
			new[path] = CODES.ignored
		end
	end
	return new
end

-- State reducers. These run in the sync context but are deliberately *not*
-- wrapped in `ya.sync` here: a plugin's sync state is scoped to the file the
-- `ya.sync` call sits in, so a closure created in this file would land in a
-- different state than the one `setup` populates. main.lua does the wrapping,
-- next to its own `setup`, and hands the proxies back to `fetch`.
local M = {}

function M.reduce_add(st, cwd, repo, changed)
	st.git = st.git or { dirs = {}, repos = {} }
	st.git.dirs[cwd] = repo
	st.git.repos[repo] = st.git.repos[repo] or {}

	for path, code in pairs(changed) do
		if code == CODES.clean then
			st.git.repos[repo][path] = nil
		elseif code == CODES.excluded then
			st.git.dirs[path] = CODES.excluded
		else
			st.git.repos[repo][path] = code
		end
	end
	ui.render()
end

function M.reduce_remove(st, cwd)
	st.git = st.git or { dirs = {}, repos = {} }

	local repo = st.git.dirs[cwd]
	if not repo then
		return
	end

	ui.render()
	st.git.dirs[cwd] = nil
	if not st.git.repos[repo] then
		return
	end

	for _, r in pairs(st.git.dirs) do
		if r == repo then
			return -- still in use by another directory
		end
	end
	st.git.repos[repo] = nil
end

--- Only shell out for files that live on the real filesystem; a virtual URL
--- (sftp://, trash://, ...) has no local `git` to ask. Note this is
--- `is_virtual`, not `is_regular`: a `search://` URL is neither, and its files
--- are real ones that git can perfectly well be asked about.
---@param url Url
---@return boolean
local function is_local(url) return not url.spec.is_virtual end

--- Flatten a URL to the plain local path underneath it.
---
--- A `search://` URL stringifies with its scheme and query attached
--- (`search://txt:1:1/home/me/x`), which git would not accept as a pathspec and
--- which would not match anything the fetcher stored. Converting once at each
--- boundary keeps every path below here unaware that search listings exist.
--- A regular URL is returned as-is, so the render path allocates nothing.
---@param url Url
---@return Url
local function local_url(url) return url.spec.is_regular and url or Url(url.path) end

--- Register the "git" column. Called by main.lua with the plugin state so the
--- render closure can read what the fetcher wrote.
function M.setup(st, opts)
	st.git = st.git or { dirs = {}, repos = {} }

	local styles, signs = theme()
	ps.sub("theme", function()
		styles, signs = theme()
	end)

	column.register("git", {
		width = opts and opts.width or 1,
		align = "left",
		render = function(file, ctx)
			-- Take `.base` before flattening, not after: in a search listing
			-- `.base` is the search root, which is the key the fetcher stored,
			-- whereas flattening first would yield the file's own directory.
			local url = file.url
			local repo = st.git.dirs[tostring(local_url(url.base or url.parent))]

			local code = CODES.unknown
			if repo == CODES.excluded then
				code = CODES.ignored
			elseif repo then
				code = st.git.repos[repo][tostring(local_url(url)):sub(#repo + 2)] or CODES.clean
			end

			local sign = signs[code]
			if sign == "" then
				return "", ctx.base
			elseif file.is_hovered then
				return sign -- unstyled, so the cursor highlight shows through
			end
			return sign, styles[code]
		end,
	})
end

---@param job table
---@param add fun(cwd: string, repo: string, changed: table) sync proxy from main.lua
---@param remove fun(cwd: string) sync proxy from main.lua
---@return boolean
---@return unknown?
function M.fetch(job, add, remove)
	local url = job.files[1].url
	if not is_local(url) then
		return true
	end

	-- In a search listing `.base` is the search root: one directory covering
	-- every hit, which is exactly the one `git status` wants to run in.
	local cwd = local_url(url.base or url.parent)
	local repo = root(cwd)
	if not repo then
		remove(tostring(cwd))
		return true
	end

	local paths = {}
	for _, file in ipairs(job.files) do
		paths[#paths + 1] = tostring(local_url(file.url))
	end

	-- `-z` supersedes `core.quotePath`: it turns off path quoting entirely.
	-- stylua: ignore
	local output, err = Command("git")
		:cwd(tostring(cwd))
		:arg({ "--no-optional-locks", "status", "--porcelain", "-z", "-unormal", "--no-renames", "--ignored=matching" })
		:arg(paths)
		:output()
	if not output then
		return true, Err("Cannot spawn `git`, error: %s", err)
	elseif not output.status.success then
		-- A non-zero exit means we have no idea what the state is. Returning
		-- here leaves the previous state alone; carrying on would parse the
		-- empty stdout and wipe every path in `paths` to `clean`.
		return true, Err("`git status` failed: %s", output.stderr)
	end

	local changed, excluded = {}, {}
	for _, entry in ipairs(entries(output.stdout)) do
		local code, path = match(entry)
		if code == CODES.excluded then
			excluded[#excluded + 1] = path
		elseif code and path then
			changed[path] = code
		end
	end

	if job.files[1].cha.is_dir then
		ya.dict_merge(changed, bubble_up(changed))
	end
	ya.dict_merge(changed, propagate_down(excluded, cwd, Url(repo)))

	-- Anything git didn't mention is clean; recording that clears stale state.
	for _, path in ipairs(paths) do
		local s = path:sub(#repo + 2)
		changed[s] = changed[s] or CODES.clean
	end

	add(tostring(cwd), repo, changed)
	return false
end

-- Exposed for test/git_spec.lua; not part of the plugin's interface.
M._CODES = CODES
M._entries = entries
M._match = match

return M
