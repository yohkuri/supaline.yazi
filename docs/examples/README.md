# Examples

The pages listed below hold the examples, a page to a subject. Each example
is a configuration and what it draws. Every picture is rendered by running the
configuration above it in Yazi 26.9.1, so the two say the same thing; Yazi's
file icons are switched off for the pictures, since an image cannot rely on its
viewer having a Nerd Font.

## Layout

[Layout](layout.md): the columns a linemode draws, from the quick start to an
`ls -l`, with their widths, what happens to a cell too long for its column,
and the separators between them.

[![permissions, user, size and mtime](images/ls-l.svg)](layout.md#like-ls--l)

## Styles

[Styles](styles.md): a colour your terminal names, drawn on five colour
schemes and on xterm; gradients on `size` and on `mtime`, with three stops, on
a linear scale and behind the text; one colour across a lightness range, on
a dark terminal and on a light one; attributes; styles written in `theme.toml`;
and the colours `permissions` takes from your theme.

[![size from blue to red](images/size-gradient.svg)](styles.md#a-gradient-on-size)

## Columns of your own

[Columns of your own](custom-columns.md): a column of file extensions, one on
a gradient of its own, and one taking an option of its own.

[![the length of each name, from blue for the shortest to red for the longest](images/name-length.svg)](custom-columns.md#a-gradient-of-your-own)

## Panes and keys

[Panes and keys](panes.md): columns of their own in the parent and preview
panes, a key that shows the columns and hides them, and supaline beside
git.yazi's sign, lined up and hidden from a key of its own.

[![size and mtime in the file list, a red dot from dark to light by mtime in the parent pane, and size in the preview pane](images/per-pane.svg)](panes.md#different-columns-per-pane)
