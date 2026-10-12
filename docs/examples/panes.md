# Panes and keys

The columns in the parent and preview panes beside the file list, a key that
shows them and hides them, and supaline beside git.yazi's sign. How the
pictures are drawn is in [the index](README.md).

## Different columns per pane

A linemode that names a pane draws columns there, and a pane it leaves out
draws none. Under Yazi's own `ratio` the parent pane is an eighth of the
terminal, so how many cells a column there can take depends on how wide the
terminal is: 15 at the 120 columns drawn here, 21 at 170. Whatever the columns
take comes out of the names. Here the parent pane has a column of your own, a
dot for when each entry was last modified, spread across one colour's
lightness the way
[a built-in can be](styles.md#one-colour-across-a-lightness-range): the most
recent is the lightest. The preview pane shows the hovered directory with the
sizes in it:

```lua
-- ~/.config/yazi/init.lua
local supaline = require("supaline")

local function mtime(file) return file.cha.mtime or 0 end

supaline.column("mark", {
  width = 1,
  style = "#ef4444 <->",
  stats = supaline.extremes(mtime),
  render = function(file, ctx)
    return "●", ctx.style_at(ctx.ratio(mtime(file)))
  end,
})

supaline:setup {
  lightness = { fg = { from = 0.40, to = 0.90 } },
  linemodes = {
    detail = {
      current = { "size", "mtime" },
      parent  = { "mark" },
      preview = { "size" },
    },
  },
}
```

```toml
# ~/.config/yazi/yazi.toml
[mgr]
linemode = "detail"
```

<!-- drawn on the dark ground -->
<!-- drawn 120 columns wide -->
![size and mtime in the file list, a red dot from dark to light by mtime in the parent pane, and size in the preview pane](images/per-pane.svg)

## A key that shows the columns and hides them

`plugin supaline -- toggle` switches to a linemode, or back to `none` when it
is the one showing, so one key does both:

```lua
-- ~/.config/yazi/init.lua
require("supaline"):setup {
  linemodes = {
    detail = { "size", "mtime" },
  },
}
```

```toml
# ~/.config/yazi/keymap.toml
[[mgr.prepend_keymap]]
on   = [ "m", "d" ]
run  = "plugin supaline -- toggle detail"
desc = "Toggle supaline's columns"
```

<!-- drawn on the dark ground -->
<!-- drawn before and after pressing m d -->
![size and mtime, and then no columns at all once m d is pressed](images/toggle.svg)
