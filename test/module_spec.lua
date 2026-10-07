--- Yazi wraps every module it loads in a state table, so a file that ends
--- `return true` fails with "error converting Lua boolean to table" and the
--- plugin does not load at all.
---
--- Nothing else here would say so. `require` hands the boolean straight back,
--- and the failure lands wherever the result is first indexed -- in another
--- module, under a message naming the wrong file.
---
--- The other tests here are about a module's shape rather than its type, and
--- are in this file for that reason.

--- Every plugin file, including additions not staged yet, asked for rather than
--- listed. A module added later is the one this test exists for, and a
--- hand-written list would not have it. Git excludes personal ignored files,
--- as the CI checks do; a glob of the root would miss one added in a
--- subdirectory, which is the other thing this refuses.
---
--- A plugin is one flat directory of files named in `[0-9a-z-]` alone, and
--- there is no require form that reaches past it. Read off the v26.9.1 source
--- rather than run: `require(".x")` names `<plugin>.x`, and the loader splits
--- that at its first dot and refuses an entry holding any other character --
--- `.src.column` and `.src/column` alike -- before it reads
--- `plugins/<plugin>.yazi/<entry>.lua` (`explode_name_parts`, in
--- `yazi-runner/src/loader/loader.rs`). `ya pkg` deploys only the `*.lua`
--- directly in the plugin's directory whose names pass the same test
--- (`plugin_files`, in `yazi-cli/src/package/dependency.rs`), so a module under
--- `src/`, or a `foo_bar.lua`, never reaches an installed copy either. The
--- stub's `require` knows neither rule and loads both, so nothing else here
--- would say so.
local function plugin_files()
	local pipe =
		assert(io.popen("git -C '" .. ROOT .. "' ls-files --cached --others --exclude-standard '*.lua' ':!:test/*'"))
	local out = pipe:read("a")
	pipe:close()

	local names = {}
	for path in out:gmatch("[^\n]+") do
		local name = path:match("^([0-9a-z-]+)%.lua$")
		assert(
			name,
			path
				.. " cannot be a module: Yazi loads a plugin's modules from its own directory, by names of "
				.. "lowercase letters, digits and `-`, and `ya pkg` installs nothing else. Move it to the "
				.. "root, named that way"
		)
		names[#names + 1] = "." .. name
	end
	-- An empty result means git said nothing, not that the plugin has no
	-- modules; passing on that would be the quietest failure of all.
	assert(#names > 0, "no plugin files found; is git on PATH?")
	return names
end

test("modules: every one returns a table, not a boolean", function()
	-- No count assertion here on purpose. Pinning the number would put the
	-- hand-written list back, one indirection along, and a module added later
	-- is exactly the one this test is for.
	for _, name in ipairs(plugin_files()) do
		eq(type(require(name)), "table", name .. " returns a table")
	end
end)

--- What `main.lua` exports, in the order `table.sort` puts them.
---
--- `supaline.Main` is written by hand, because in this checkout and on the CI
--- runner `require(".main")` resolves to `types.yazi` rather than to this tree
--- and the specs are checked against that class instead of against the module.
--- Nothing otherwise keeps the two in step, and the drift is silent in the
--- direction that matters.
---
--- That is the type checker's resolution, and which of the two wins is a
--- property of the absolute path the tree sits at, measured in
--- `annotate-supaline/references/main-collision.md`. The `require` below is
--- Lua's own and reaches this tree wherever it sits, which is what lets this
--- test read the exports at all.
---
--- This catches one direction: an export the class does not name, which is the
--- one a spec would then be refused for. A changed *signature* is past
--- anything Lua can see at runtime, and is still read by eye.
local MAIN_EXPORTS = { "column", "entry", "extremes", "setup" }

test("modules: `supaline.Main` names what main.lua exports", function()
	-- Off the module rather than what `require` hands back, which in Yazi and
	-- the stub alike is a proxy whose only key is `__mod`.
	local names = {}
	for name in pairs(rawget(require(".main"), "__mod")) do
		names[#names + 1] = name
	end
	table.sort(names)

	eq(
		table.concat(names, ", "),
		table.concat(MAIN_EXPORTS, ", "),
		"main.lua's exports moved; update `supaline.Main` beside them and this list"
	)
end)

--- The annotations Yazi reads off the top of a plugin's `main.lua`, by the
--- rules `Chunk::analyze` in 26.9.1's `yazi-runner/src/loader/chunk.rs`
--- reads them by: blank lines skipped, every other line `---` and then a word,
--- and the scan over at the first line that is neither an annotation nor
--- blank. A port rather than a pattern, because what it decides is where the
--- scan stops, and a pattern for the line would pass on wherever the line was.
---@param body string
---@return table<string, string> # each annotation it reached, by its word
local function annotations(body)
	local found = {}
	for line in (body .. "\n"):gmatch("([^\n]*)\n") do
		local trimmed = line:match("^%s*(.-)%s*$")
		if trimmed ~= "" then
			local rest = line:match("^%-%-%-(.*)$")
			if not rest then
				break
			end
			local word, value = rest:match("^%s*(%S+)[ \t]+(.-)%s*$")
			if not word or value == "" or not word:match("^@.") then
				break
			end
			found[word] = value
		end
	end
	return found
end

test("modules: Yazi reads `@sync entry` off main.lua, where a key needs it", function()
	-- A key that runs `entry` in a Lua state of its own would find no `setup`
	-- there, and every `toggle` would be refused as made before it. Yazi takes
	-- `@sync` only from the top of the file and stops at the first line of
	-- prose, so the same annotation one line too low is read by nobody.
	local f = assert(io.open(ROOT .. "/main.lua"))
	local body = f:read("a")
	f:close()
	local found = annotations(body)
	eq(found["@since"], "26.9.1", "this port reads the annotation every file carries")
	eq(found["@sync"], "entry", "main.lua's entry is sync, and Yazi reads it so")

	-- And the port stops where Yazi does.
	eq(annotations("--- @since 26.9.1\n--- Prose.\n--- @sync entry\n")["@sync"], nil, "below a line of prose")
end)
