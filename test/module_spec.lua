---@diagnostic disable: inject-field

--- Yazi wraps every module it loads in a state table, so a file that ends
--- `return true` fails with "error converting Lua boolean to table" and the
--- plugin does not load at all.
---
--- Nothing else here would say so. `require` hands the boolean straight back,
--- and the failure lands wherever the result is first indexed -- in another
--- module, under a message naming the wrong file.
---
--- The second test here is about a module's shape rather than its type, and is
--- in this file for that reason.

--- Every tracked plugin file, asked for rather than listed. A module added
--- later is the one this test exists for, and a hand-written list would not
--- have it. `git ls-files` for the same reason the `@since` CI job uses it: a
--- glob of the root would miss one added in a subdirectory.
local function plugin_files()
	local pipe = assert(io.popen("git -C '" .. ROOT .. "' ls-files '*.lua' ':!:test/*'"))
	local out = pipe:read("a")
	pipe:close()

	local names = {}
	for path in out:gmatch("[^\n]+") do
		local name = path:match("^([^/]+)%.lua$")
		assert(name, "plugin file in a subdirectory: " .. path .. " -- teach this spec Yazi's require form for it")
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
local MAIN_EXPORTS = { "column", "setup" }

test("modules: `supaline.Main` names what main.lua exports", function()
	local names = {}
	for name in pairs(require(".main")) do
		names[#names + 1] = name
	end
	table.sort(names)

	eq(
		table.concat(names, ", "),
		table.concat(MAIN_EXPORTS, ", "),
		"main.lua's exports moved; update `supaline.Main` beside them and this list"
	)
end)
