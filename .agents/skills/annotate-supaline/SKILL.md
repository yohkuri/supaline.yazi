---
name: annotate-supaline
description: >-
  How far `lua-language-server --check .` reaches into this plugin, and the
  rules for the classes it reads. Read before declaring or changing a class or
  a field annotation in the plugin's own Lua, or a cast where one of those
  values arrives -- not for running the check, which AGENTS.md lists and which
  needs nothing from here, not for a spec or a stub, which `verify-supaline`
  covers, and not for a rename or a format string. Covers what carries a type
  and what does not, why a wrong value in a configuration table is refused
  where a misspelled key is not, the eight places `types.yazi` disagrees with
  Yazi 26.9.1 -- seven where it declares less than Yazi has and one where it
  declares more -- and why a difference is declared by inheriting from Yazi's
  class rather than re-opening it. The collision that makes `supaline.Main`
  necessary is summarised here and measured in
  references/main-collision.md.
---

# Writing the type annotations

`AGENTS.md` lists `lua-language-server --check .` and says what it needs
installed to compare the plugin against anything. This is what it reaches once
it runs.

## What the check reaches

What the check reaches is what carries a type. `cx`, `ya` and a `Url` are
declared classes, so a misspelled field or a wrong arity on one is refused, and
`column.lua` declares `supaline.File` and `supaline.Ctx` for the two values a
`render` is handed, so the columns are read too — `file.cha.is_dirr` and
`ctx.stlye` are both refused, in a built-in column and in a spec alike. The
records the plugin passes around carry classes as well: a linemode, a column, a
folder and a bound entry. So does the configuration `setup` is given — the
plugin-wide options, a linemode spec, and the four shapes a column may be
written in — so `cfg.orderr`, `opts.linemodess` and `spec.separatorr` are
refused.

That last one reaches only so far, and the limit is worth knowing before
trusting it. A wrong **value** in a spec is refused: `separator = 42` on a
linemode, `width = "wide"` on a column inside one. A misspelled **key** in the
same table is not — a table constructor passed as an argument is not checked
for keys its class does not declare, and marking those classes `(exact)` was
measured to change that at no site here. What a user writes wrong is still
`setup`'s to refuse at runtime, which is what all those errors are for.

A value reassigned from its own method inside a loop is a second limit, and
this one is the tool's rather than an annotation's: measured with
lua-language-server 3.19.1, the version CI pins, a local written as
`line = line:truncate {...}` inside a `while` keeps its class for that call and
loses it for the rest of the loop body — `line:widthh()` on the next line is
not refused, where the same typo after the loop ends, or outside one, is. `cut`
in `column.lua` is that shape, so what covers the `line:width()` inside its
loop is `column_spec.lua` at runtime and nothing at check time.

The specs are inside that reach only because `main.lua` declares
`supaline.Main` for them to claim. Here and on the CI runner `require(".main")`
resolves to `types.yazi` rather than to this tree, so without that class every
call a spec makes into the plugin is checked against a module exporting
nothing, with the job green throughout. That "here" is not a redundancy: which
of the two `main.lua` files wins is a property of the absolute path the tree
sits at, not of either name. `references/main-collision.md` has the mechanism,
what was measured and what was not, the places the collision is stated,
and how to re-take it — worth opening when a checkout moves, when the pinned
annotations revision moves, or when the CI step `None of them shadow this
plugin's own modules` fires.

A module table carries no class of its own for free. `require(".column")`
resolves to this tree and that module's signatures are read normally, yet a
misspelled `column.normalizze` costs nothing unless the table `column.lua`
returns carries a class of its own. It carries `supaline.ColumnModule` — the
shape `supaline.Stub` uses too. Declared on the table rather than written out,
its fields are whatever the file assigns, so nothing has to pin them.
`supaline.Main` is by hand only because there is no table here for the checker
to read it off.

## Where types.yazi and Yazi disagree

Yazi's own annotations are not the last word on Yazi. `types.yazi` describes
neither `file.idx`, `file.in_current` nor `Url.spec`, gives `Cha.perm` as a
string where 26.9.1 has a method, declares `ui.truncate` but nothing for
`Line:truncate`, which 26.9.1 has, describes no `Tab:history`, which
`builtin.lua` asks a directory for its entry count, and no `Style:raw`, which
`colour.lua` reads every `ui.Style` it is handed through — so `column.lua` and
`colour.lua` declare the difference themselves, with the evidence written
beside the classes: a probe for the four read off `cx`,
`test/truncate_spec.lua` for the one method, which pins what it does, and
`colour_spec.lua` against `yazi-platform-traps/references/probes.md` for the
other. A newer Yazi is a reason to run those again and correct them there,
never to work around them at the call site.

Declaring the fifth is what keeps the call checked, and the difference is
worth planting once: with `cut` taking its line as `unknown`, `line:truncatee`
inside it passes the check, and with `supaline.Line` the same typo comes back
as an `undefined-field` warning. Getting one call past the checker is all
`unknown` buys, and it pays with every other call on the same value.

What it buys is the name, not the argument. `max = "wide"` passes either way —
the limit on a table constructor above holds here too, and naming a class for
the options was measured not to change it — so the call being checked means
the method exists and takes an options table, and no more.

The sixth is worth knowing about for how it hid rather than for what it
declares. `cx.active:history(url)` checked out for months without a class,
because a spec swapping the method for its own assigned the field under a
file-wide `inject-field` disable and injected it workspace-wide; the plugin's
call was being blessed by a line in a test. Rewriting that spec's swap through
a shared helper indexed the field instead of assigning it, and the plugin went
red — which is the good outcome, and worth expecting whenever a check goes red
at a change that could not have touched it. `tab__Tab` is `(exact)`, so
nothing the harness builds can declare a field on one.

Those differences are declared by inheriting from Yazi's class, never by
re-opening it, which means a folder taken off `cx` is cast where it arrives.
The cast is the price of the subclass and it is worth paying: re-opening
`fs__File` and `Cha` to write the fields straight onto them removed the casts
and, in one arrangement, silently stopped refusing a misspelling — a check that
quietly does nothing is the failure mode this whole job exists to avoid.

All seven of those are `types.yazi` describing **less** than Yazi has, and the
difference runs the other way too — which is the worse direction, because the
check blesses the call and the screen refuses it. `ui.Style:reset()` is one:
declared on the `ui.Style` class the annotations mark `(exact)`, and
`attempt to call a nil value (method 'reset')` on 26.9.1, measured in a
detached tmux. Nothing here calls it, and the colour `"reset"` is a different
thing that works. Take it as the limit on what a green check means: it says
the annotations agree with the call, and the annotations are not the platform.
