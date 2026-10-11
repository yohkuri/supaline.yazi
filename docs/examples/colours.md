# Colours

What a column can be coloured with: a colour your terminal names, a gradient
from the smallest value in the folder to the largest, and the attributes a
terminal draws — written in `init.lua`, in `theme.toml`, or in both. How the
pictures are drawn is in [the index](README.md).

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

<!-- drawn on every ground -->
![The same columns on seven terminal colour schemes](images/named-colours.svg)

`permissions` takes its colours from your theme's `[status]` section, and
Yazi's preset theme writes those by name as well.

Every way to write a colour is under [`style`](../styles.md#style), and what
`permissions` draws under [Built-in columns](../configuration.md#built-in-columns).

## A gradient on size

A colour can run from the smallest value in the folder to the largest. From
blue to red, the small files are cool and the large ones hot.
`size` places a file by the magnitude of its size, so kilobytes and gigabytes
in one folder still spread across the whole gradient; a directory, which has
no size to place, takes the low end.

```lua
-- ~/.config/yazi/init.lua
require("supaline"):setup {
  linemodes = {
    detail = {
      { "size", style = "#3b82f6 -> #ef4444" },
      "mtime",
    },
  },
}
```

![size from blue to red](images/size-gradient.svg)

How a gradient is written and where a file lands on it are under
[A gradient](../styles.md#a-gradient), and placing by magnitude under
[`scale`](../styles.md#scale).

## A gradient on age

The same on `mtime` draws what changed recently hot, and what has sat
untouched for months cool.

```lua
-- ~/.config/yazi/init.lua
require("supaline"):setup {
  linemodes = {
    detail = {
      "size",
      { "mtime", style = "#3b82f6 -> #ef4444" },
    },
  },
}
```

![mtime from blue to red](images/mtime-gradient.svg)

A timestamp is placed on a linear scale rather than by magnitude;
[`scale`](../styles.md#scale) says why.

## Three stops

A gradient may pass through more colours than two. Blue and red sit far apart
in hue, and the colours between them meet near grey; a purple between the two
keeps the middle of the gradient as vivid as its ends.

```lua
-- ~/.config/yazi/init.lua
require("supaline"):setup {
  linemodes = {
    detail = {
      { "size", style = "#3b82f6 -> #a855f7 -> #ef4444" },
      "mtime",
    },
  },
}
```

![size from blue through purple to red](images/three-stops.svg)

Each stop is a `#rrggbb`, with an arrow between each pair; see
[A gradient](../styles.md#a-gradient).

## Log against linear

`size` places a file by the magnitude of its size. Placed by the size itself,
on a linear scale, the largest file takes the top of the gradient and almost
everything else lands near the bottom. The same column twice, the second
linear:

```lua
-- ~/.config/yazi/init.lua
require("supaline"):setup {
  linemodes = {
    detail = {
      { "size", style = "#3b82f6 -> #ef4444" },
      { "size", style = "#3b82f6 -> #ef4444", scale = "linear" },
    },
  },
}
```

![size on a log scale and on a linear one](images/log-and-linear.svg)

Where `scale` may be written, and which place wins, is under
[`scale`](../styles.md#scale).

## A gradient behind the text

A gradient under `bg` colours the cell rather than the text, and an `fg`
beside it is drawn on every step. These two are darker than the blue and red
above, so white reads on both ends.

```lua
-- ~/.config/yazi/init.lua
require("supaline"):setup {
  linemodes = {
    detail = {
      { "size", style = { bg = "#2563eb -> #dc2626", fg = "#ffffff" } },
      "mtime",
    },
  },
}
```

![size on a background from blue to red](images/background-gradient.svg)

`fg` and `bg` both take a gradient, together or apart; see
[A gradient](../styles.md#a-gradient).

## Attributes

Bold, italic, underline and the rest go in a style table, with a colour or
without one:

```lua
-- ~/.config/yazi/init.lua
require("supaline"):setup {
  linemodes = {
    detail = {
      { "owner", style = { bold = true } },
      { "size", style = { underline = true } },
      { "mtime", style = { fg = "blue", italic = true } },
    },
  },
}
```

![owner in bold, size underlined, mtime in blue italics](images/attributes.svg)

A column given no colour is drawn in the file row's own, as the bold `owner`
is here.

Every key a style table takes, and what `false` under one means, is under
[`style`](../styles.md#style).

## From your theme

The same styles can be written in `theme.toml`, under a `[supaline]` section
whose fields are named after the columns, so a flavor can ship them. The
linemode itself then names no colour:

```lua
-- ~/.config/yazi/init.lua
require("supaline"):setup {
  linemodes = {
    detail = { "size", "mtime" },
  },
}
```

```toml
# ~/.config/yazi/theme.toml
[supaline]
size  = "#3b82f6 -> #ef4444"
mtime = { fg = "blue", italic = true }
```

![size and mtime styled from the theme](images/from-the-theme.svg)

A gradient in a theme is the whole value, never a table's `fg`, which Yazi
would fail to parse; see [From the theme](../styles.md#from-the-theme).

## The theme and the linemode together

When both write a column's style, each key goes to the one nearer the column,
and a key only one of them wrote is kept. With the theme above, `bold` is
added to the gradient, and `fg = false` takes the blue off `mtime` while the
italics stay:

```lua
-- ~/.config/yazi/init.lua
require("supaline"):setup {
  linemodes = {
    detail = {
      { "size", style = { bold = true } },
      { "mtime", style = { fg = false } },
    },
  },
}
```

```toml
# ~/.config/yazi/theme.toml
[supaline]
size  = "#3b82f6 -> #ef4444"
mtime = { fg = "blue", italic = true }
```

![size as a bold gradient, mtime in italics and the row's colour](images/theme-and-linemode.svg)

The column's own definition is the third place a style can come from; how
the three combine is under
[How the three combine](../styles.md#how-the-three-combine).

## Permissions

`permissions` colours each character from your theme. A bold or a background
goes over those colours, and a colour of your own replaces them with one for
the whole cell:

```lua
-- ~/.config/yazi/init.lua
require("supaline"):setup {
  linemodes = {
    detail = {
      { "permissions", style = { bold = true } },
      { "permissions", style = "cyan" },
    },
  },
}
```

![permissions in bold over the theme's colours, and in cyan alone](images/permissions.svg)

Which `[status]` style each character is drawn in is under
[Built-in columns](../configuration.md#built-in-columns).
