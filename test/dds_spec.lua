--- The stub's DDS kind list, pinned against Yazi's own.
---
--- Yazi's `ps.sub` takes any string and returns without complaining, so a
--- stale kind is a subscription that never fires -- no error, no warning, and
--- nothing on screen to notice. Yazi renamed `bulk` to `bulk-rename`
--- without saying so, which is how the plugin came to have a subscription
--- worth pinning.
---
--- The names live in `pub_after!` in `yazi-dds/src/pubsub.rs`, plus one that
--- does not: `bulk-rename` is published by a hand-written
--- `pub_after_bulk_rename` beside the macro, which is exactly why reading the
--- macro alone misses it.

test("DDS: every kind Yazi publishes, and no others", function()
	local want = {
		"tab",
		"cd",
		"load",
		"hover",
		"rename",
		"@yank",
		"duplicate",
		"move",
		"trash",
		"delete",
		"download",
		"input",
		"mount",
		"theme",
		"bulk-rename",
	}
	local n = 0
	for _ in pairs(stub.DDS_KINDS) do
		n = n + 1
	end
	eq(n, #want, "fifteen kinds")
	for _, kind in ipairs(want) do
		assert(stub.DDS_KINDS[kind], "missing DDS kind: " .. kind)
	end
end)

test("DDS: the renamed one is `bulk-rename`, and `bulk` is gone", function()
	assert(stub.DDS_KINDS["bulk-rename"], "Yazi publishes `bulk-rename`")
	eq(stub.DDS_KINDS["bulk"], nil, "`bulk` was the name before it, and fires nothing now")
end)

test("DDS: an unknown kind is refused, not taken in silence", function()
	throws(function()
		ps.sub("bulk", function() end)
	end, "no such DDS kind")
end)

test("DDS: every kind the plugin subscribes to is one Yazi publishes", function()
	-- The subscriptions are made when `main.lua` loads, so this is really an
	-- assertion that the require above did not throw. Counting them says so out
	-- loud, and catches a subscription silently dropped as well as a bad name.
	require(".main")
	local n = 0
	for kind in pairs(stub.subs) do
		assert(stub.DDS_KINDS[kind], "not a published kind: " .. kind)
		n = n + 1
	end
	eq(n, 7, "theme, cd, and the five that invalidate")
end)
