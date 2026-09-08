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
  where a misspelled key is not, the four places `types.yazi` disagrees with
  Yazi 26.9.1, and why a difference is declared by inheriting from Yazi's
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
`ctx.basee` are both refused, in a built-in column and in a spec alike. The
records the plugin passes around carry classes as well: a linemode, a column, a
folder and a bound entry. So does the configuration `setup` is given — the
plugin-wide options, a linemode spec, and the four shapes a column may be
written in — so `cfg.orderr`, `opts.linemodess` and `spec.paness` are refused
where they used to cost nothing.

That last one reaches only so far, and the limit is worth knowing before
trusting it. A wrong **value** in a spec is refused: `separator = 42` on a
linemode, `width = "wide"` on a column inside one. A misspelled **key** in the
same table is not — a table constructor passed as an argument is not checked
for keys its class does not declare, and marking those classes `(exact)` was
measured to change that at no site here. What a user writes wrong is still
`setup`'s to refuse at runtime, which is what all those errors are for.

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
neither `file.idx`, `file.in_current` nor `Url.spec`, and gives `Cha.perm` as a
string where 26.9.1 has a method — so `column.lua` declares the difference
itself, with the probe that established it written beside the classes. A newer
Yazi is a reason to run that probe again and correct them there, never to work
around them at the call site.

Those differences are declared by inheriting from Yazi's class, never by
re-opening it, which means a folder taken off `cx` is cast where it arrives.
The cast is the price of the subclass and it is worth paying: re-opening
`fs__File` and `Cha` to write the fields straight onto them removed the casts
and, in one arrangement, silently stopped refusing a misspelling — a check that
quietly does nothing is the failure mode this whole job exists to avoid.
