---@diagnostic disable: inject-field

--- The stub's `AuthKind` table, pinned against Yazi's own.
---
--- `yazi-shared/src/auth/kind.rs` has six variants and two predicates over
--- them, and `yazi-shared/src/spec/lua.rs` exposes three of the flags to Lua.
--- The stub reproduces that partition, so it is worth as much as its fidelity
--- and no more -- the same reason `truncate_spec.lua` exists.
---
---     pub fn is_local(self) -> bool {
---       match self { Regular | Search => true, Mount | Hub | Scope | Sftp => false }
---     }
---
--- `is_local` is not bound to Lua; `is_virtual` is its exact complement, which
--- is why the plugin keys on that.

test("AuthKind: every variant Yazi has, and no others", function()
	local want = { "regular", "search", "mount", "hub", "scope", "sftp" }
	local n = 0
	for _ in pairs(stub.AUTH_KINDS) do
		n = n + 1
	end
	eq(n, #want, "six variants")
	for _, kind in ipairs(want) do
		assert(stub.AUTH_KINDS[kind], "missing AuthKind: " .. kind)
	end
end)

test("AuthKind: is_virtual is the complement of Yazi's is_local", function()
	for _, kind in ipairs { "regular", "search" } do
		eq(stub.spec_of(kind).is_virtual, false, kind .. " is local")
	end
	for _, kind in ipairs { "mount", "hub", "scope", "sftp" } do
		eq(stub.spec_of(kind).is_virtual, true, kind .. " is not local")
	end
end)

test("AuthKind: is_regular holds for one variant, is_search for one", function()
	-- The trap this table exists to expose: a search result is a local file
	-- with `is_regular = false`, so a check written as `not is_regular`
	-- demotes every search hit along with the remote ones.
	eq(stub.spec_of("regular").is_regular, true)
	eq(stub.spec_of("search").is_regular, false)
	eq(stub.spec_of("search").is_search, true)
	eq(stub.spec_of("sftp").is_search, false)
end)

test("AuthKind: an unknown kind is refused, not guessed", function()
	throws(function() stub.spec_of("regualr") end, "no such AuthKind")
end)
