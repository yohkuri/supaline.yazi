-- Parsing of `git status --porcelain -z`.
--
-- Both halves of this are places supaline knowingly departs from git.yazi, so
-- they are pinned here: conflict states must not read as ordinary changes, and
-- paths must survive verbatim.

return function(t)
	local git = t.module("git")
	local CODES, match, entries = git._CODES, git._match, git._entries

	local NAME = {}
	for k, v in pairs(CODES) do
		NAME[v] = k
	end

	local function code_of(signs)
		local code = match(signs .. " some-file.txt")
		return code and NAME[code] or nil
	end

	-- git calls an entry unmerged when its two-letter code is one of these.
	t.group("unmerged states are conflicts, not ordinary changes")
	for _, signs in ipairs { "DD", "AU", "UD", "UA", "DU", "AA", "UU" } do
		t.check(signs .. " -> updated", code_of(signs) == "updated", code_of(signs))
	end

	t.group("ordinary states keep git.yazi's classification")
	local ordinary = {
		{ "??", "untracked" },
		{ "!!", "ignored" },
		{ " M", "modified" },
		{ "M ", "modified" },
		{ "MM", "modified" },
		{ "T ", "modified" },
		{ "AM", "modified" }, -- added then modified: the worktree change wins
		{ "A ", "added" },
		{ "C ", "added" },
		{ "AD", "added" }, -- added to the index, gone from the worktree; not a conflict
		{ "D ", "deleted" },
		{ " D", "deleted" },
	}
	for _, case in ipairs(ordinary) do
		local signs, want = case[1], case[2]
		t.check(string.format("%q -> %s", signs, want), code_of(signs) == want, code_of(signs))
	end

	t.group("paths survive verbatim")
	do
		local _, path = match([[?? back\slash.txt]])
		t.check("a backslash is not an escape", path == [[back\slash.txt]], path)

		local _, quoted = match([[?? quote"name.txt]])
		t.check("a quote is not a delimiter", quoted == [[quote"name.txt]], quoted)

		local _, unicode = match("?? 日本語.txt")
		t.check("non-ASCII is untouched", unicode == "日本語.txt", unicode)

		local _, spaced = match("?? two words.txt")
		t.check("spaces are kept", spaced == "two words.txt", spaced)
	end

	t.group("directories")
	do
		local code, path = match("!! build/")
		t.check("an ignored directory becomes excluded", code == CODES.excluded, code)
		t.check("its trailing slash is stripped", path == "build", path)

		local ucode, upath = match("?? vendor/")
		t.check("an untracked directory keeps its code", ucode == CODES.untracked, ucode)
		t.check("its trailing slash is stripped too", upath == "vendor", upath)
	end

	t.group("malformed input")
	do
		t.check("an unknown code yields nothing", match("ZZ file.txt") == nil)
		t.check("a status with no path yields nothing", match("?? ") == nil)
		t.check("an empty record yields nothing", match("") == nil)
	end

	t.group("NUL-separated records")
	do
		local got = entries("?? a.txt\0 M b.txt\0")
		t.check("split on NUL", #got == 2 and got[1] == "?? a.txt" and got[2] == " M b.txt", #got)

		t.check("a missing final NUL is tolerated", #entries("?? a.txt\0 M b.txt") == 2)
		t.check("empty records are skipped", #entries("\0\0?? a.txt\0\0") == 1)
		t.check("empty input yields nothing", #entries("") == 0)

		local newline = entries("?? has\nnewline.txt\0")
		t.check("a newline inside a path is not a separator", #newline == 1, #newline)
	end
end
