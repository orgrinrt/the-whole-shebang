# the-whole-shebang

> The whole shebang. Complete bash library for serious scripting.

A collection of libraries built on [nutshell](https://github.com/orgrinrt/nutshell), each one
sourceable on its own.

That independence is the arrangement rather than an accident. nutshell is one thing you take whole:
source `init`, `use` what you need, and every module is part of the same install. The libraries here
are the opposite shape. A script that wants findings and a verdict takes `diagnostics` and nothing
else, and never learns that the rest exists.

## Using one

Initialise nutshell, then source the library:

```bash
#!/usr/bin/env bash
. "${0%/*}/lib/nutshell/init"
. "${0%/*}/lib/shebang/diagnostics/findings.sh"

finding_block "version moved on a feature branch"
finding_note  "A version moves on a release. If this PR is one, say so."
findings_verdict
```

Every library errors immediately if nutshell has not been initialised, naming the setup step rather
than failing later on an undefined function.

## The libraries

| Library | What it is for |
|---|---|
| `diagnostics/findings` | Recording severity-tagged findings and rendering a verdict, with an exit code a caller can branch on. |
| `tui/term` | Entering and leaving a full-screen terminal session, and putting the terminal back however the run ends. |
| `tui/key` | Reading a keypress and naming it, so nothing above ever matches on an escape sequence. |
| `tui/menu` | A list you choose from, with headings the cursor skips and a viewport that keeps the cursor in view. |
| `tui/confirm` | Asking before something irreversible, in three strengths, refusing by default when it cannot ask. |

## Tests

```bash
git submodule update --init      # nutshell, for the harness
./test                           # everything
./test tests/tui_term_test.sh    # one file
```

## License

See `LICENSE`.
