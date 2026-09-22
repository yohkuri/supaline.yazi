<!--
CI checks everything about this change that can be checked, so there is no
checklist here repeating it. What is below is the part no check on this
repository can see. CONTRIBUTING.md has the rest, including what to run
before pushing.
-->

## What this changes

<!-- And why. A line is enough, and a linked issue instead of one is fine. -->

## What CI cannot see

CI never starts a Yazi. `test/e2e.py` and `test/manual.py` are the only things
that do, and a broken fetcher shows up neither on the screen nor in any check
here -- so a green pull request says nothing about either.

- Yazi version:
- `test/e2e.py`:

If this adds or edits a claim about how Yazi behaves, say what you ran to
establish it, and say where the measurement stops rather than rounding it off:
a variant you never managed to produce is written down as never observed.

<!--
Delete the section above if nothing here can reach a running Yazi -- a
document, a workflow, or a test that never loads the plugin.
-->
