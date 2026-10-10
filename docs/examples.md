# Examples

Each example is a configuration and what it draws. Every picture here is
rendered by running the configuration above it in Yazi 26.9.1, so the two say
the same thing; Yazi's file icons are switched off for the pictures, since an
image cannot rely on its viewer having a Nerd Font.

## On any terminal

A colour written by name — `blue`, `magenta` — is drawn from your terminal's
own palette, the same way Yazi draws a directory or an executable. One capture
of this configuration, drawn in the colours of seven terminal schemes:

```lua
-- ~/.config/yazi/init.lua
require("supaline"):setup {
  linemodes = {
    detail = {
      "permissions",
      { "size", style = "magenta" },
      { "mtime", style = "blue" },
    },
  },
}
```

![The same columns on seven terminal colour schemes](examples/named-colours.svg)

`permissions` takes its colours from your theme's `[status]` section, and
Yazi's preset theme writes those by name as well.
