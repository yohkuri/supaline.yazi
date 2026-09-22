<!--
Thanks for the pull request! Two short questions below — CI covers
everything else, so there's no checklist to work through.
CONTRIBUTING.md has the details, including what to run before pushing.
-->

## What does this change?

<!-- A sentence is plenty, and linking an issue instead is fine. -->

## Did you watch it run?

CI never opens a real Yazi. `test/e2e.py` and `test/manual.py` are the only
things that do, so a green pull request says nothing about whether the
plugin actually draws anything.

- Yazi version:
- `test/e2e.py`:

If you're adding or changing a claim about how Yazi behaves, it helps a lot
to say what you ran to find out — and where you stopped looking.

<!--
Delete this second section if your change can't reach a running Yazi — docs,
workflows, or a test that never loads the plugin.
-->
