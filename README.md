# the-whole-shebang

> A collection of bash libraries built on nutshell, each sourceable on its own.

A collection of libraries built on [nutshell](https://github.com/orgrinrt/nutshell), each one
sourceable on its own.

That independence is the arrangement rather than an accident. nutshell is one thing you take whole:
source `init`, `use` what you need, and every module is part of the same install. The libraries here
are the opposite shape. A script that wants findings and a verdict takes `diagnostics` and nothing
else, and never learns that the rest exists.

## Using one

Declare the dependency in `nut.toml` and let nutshell resolve it:

```toml
[deps.shebang]
git = "https://github.com/orgrinrt/the-whole-shebang.git"
ref = "main"
```

```bash
#!/usr/bin/env bash
. "${0%/*}/lib/nutshell/init"

use shebang::diagnostics/diagnostics

finding_block "version moved on a feature branch"
finding_note  "A version moves on a release. If this PR is one, say so."
findings_verdict
```

Vendoring the repository and sourcing a file directly also works. The libraries
live under `libs/`, so a checkout at `lib/shebang/` is sourced as
`. "${0%/*}/lib/shebang/libs/diagnostics/diagnostics.sh"`.

Every library errors immediately if nutshell has not been initialised, naming the setup step rather
than failing later on an undefined function.

## The libraries

One library so far. `diagnostics` records severity-tagged findings, through
`finding_block` and `finding_judge` with `finding_note` for continuation lines,
and renders a verdict whose exit code a caller can branch on: 0 when nothing was
found, 1 when something blocking was, and 3 when something needs judgement.

## tui

Eight modules for a terminal interface, taken on their own like everything else
here. Written for a bootable maintenance tool, which set the constraints.

`tui/term` enters and leaves a full-screen session and puts the terminal back
however the run ends. Two ideas carry it. There may be no terminal at all, so
every entry point is safe with nothing attached and simply does less: a pipe
full of escape sequences is a corrupted file rather than a styled one. And
whatever is changed gets restored on every exit path including the ones nobody
plans for, because raw mode belongs to the terminal rather than the process and
a crash otherwise leaves a shell that does not echo.

`tui/key` names a keypress, so nothing above it ever matches an escape
sequence. Arrows, vi keys and the emacs pairs fold to the same four names.

`tui/menu` is a list with headings the cursor skips and a viewport that keeps
the cursor in view. `/` searches, over the notes as well as the titles. It is a
mode rather than type-to-filter because every letter worth searching for is
already a key that means something, and `chroot` would quit at the `h`.

`tui/confirm` asks in three strengths: yes or no, a word typed back, and a name
typed back. The third exists because the failure it defends against is not
"did not mean to say yes", it is "meant yes about a different disk", and no
amount of shouting catches that. All three refuse by default when there is no
terminal to ask at.

`tui/run` hands the screen to something that owns it -- a package manager, a
chroot, fsck -- and states the result rather than leaving it implicit. Boxing
such a thing inside the interface costs its colours, its progress and the
user's real scrollback to gain a border.

## Tests

```bash
git submodule update --init
./test
./test tests/tui_term_test.sh
```

## License

See `LICENSE`.
