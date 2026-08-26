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
#!/usr/bin/env nutshell

use shebang::diagnostics

finding_block "version moved on a feature branch"
finding_note  "A version moves on a release. If this PR is one, say so."
findings_verdict
```

Modules are separated by `::` the whole way down, and `lib.nut` is what says which name maps to
which file. Vendoring the repository and sourcing a file directly also works: a checkout at
`lib/shebang/` is sourced as `. "${0%/*}/lib/shebang/libs/diagnostics.sh"`.

Every library errors immediately if nutshell has not been initialised, naming the setup step rather
than failing later on an undefined function.

## diagnostics

`diagnostics` records severity-tagged findings, through `finding_block` and `finding_judge` with
`finding_note` for continuation lines, and renders a verdict whose exit code a caller can branch on:
0 when nothing was found, 1 when something blocking was, and 3 when something needs judgement.

## tui

Twelve modules for a terminal interface, taken on their own like everything else here. Written for a
bootable maintenance tool, which set the constraints.

`tui/term` enters and leaves a full-screen session and puts the terminal back however the run ends.
Two ideas carry it. There may be no terminal at all, so every entry point is safe with nothing
attached and simply does less: a pipe full of escape sequences is a corrupted file rather than a
styled one. And whatever is changed gets restored on every exit path including the ones nobody
plans for, because raw mode belongs to the terminal rather than the process and a crash otherwise
leaves a shell that does not echo. It also carries the palette every other module colours by, named
for what a colour means rather than for the colour.

`tui/key` names a keypress, so nothing above it ever matches an escape sequence. Arrows, vi keys and
the emacs pairs fold to the same four names.

`tui/menu` is a list with headings the cursor skips and a viewport that keeps the cursor in view.
The cursor is a ring: up from the first row is the last. `[` and `]` move by section, and so does a
modifier with an arrow.

Three things arrange it, and they are three different questions. `g` groups by the section a row was
declared under, by its kind, or not at all, making its own headings when the cut is not the declared
one. `s` orders by the caller's own order, by name, or by state with what can be run at the top,
inside a group and never across it, so the sections do not move when the ordering does. `f` cycles
the filters a caller registered, which are predicates over a row rather than text: "the ones I can
run" is not a word that appears in any row.

`/` searches, over the notes and the ids as well as the titles, which is the other half of that
distinction. It is a mode rather than type-to-filter because every letter worth searching for is
already a key that means something, and `chroot` would quit at the `h`.

A run of movement is absorbed before it draws. A wheel event becomes a run of arrow keys and a
velocity scroll becomes a long one, so a list that redraws per key keeps painting for seconds after
the hand stopped.

`tui/confirm` asks in three strengths: yes or no, a word typed back, and a name typed back. The
third exists because the failure it defends against is not "did not mean to say yes", it is "meant
yes about a different disk", and no amount of shouting catches that. All three refuse by default
when there is no terminal to ask at.

`tui/modal` draws a question inside the interface instead of at the bottom of the terminal, which is
where a confirmation lands if nothing places it.

`tui/frame` is a bordered region with a title, and `tui/progress` a bar that redraws in place.
`tui/report` renders a run's outcome: a mark per line, a state column that lines up rather than
trailing off the end of each sentence, and indentation for the steps inside a step.

`tui/layout` divides one axis by counts, shares and floors, with a priority deciding what goes when
there is not enough room. `tui/table` puts columns across a width through it, borders optional, and
takes `--at ROW COL` and `--height N` so it can be drawn inside a box something else worked out.

`tui/plan` is the two-dimensional one: panels fitted around the main region, each naming the shapes
it can take, so a tall sidebar becomes a row of short columns underneath when it will not fit
beside. It fills lines and wraps, weighing each shape by how many of the panels after it still fit.
It does not promise the arrangement that drops the fewest, which is bin packing; it promises that
the same inputs give the same arrangement, that a panel is only ever placed at a size it declared,
and that nothing overlaps or leaves the screen.

`tui/run` hands the screen to something that owns it, a package manager, a chroot, fsck, and states
the result rather than leaving it implicit. Boxing such a thing inside the interface costs its
colours, its progress and the user's real scrollback to gain a border.

## Tests

```bash
./test
./test tests/tui_term_test.sh
```

`test` resolves nutshell itself through `lib/find-nutshell`, pinned at `dev`.
That file is a byte for byte copy of nutshell's own resolver, because a project
cannot use the resolver to find the resolver. It is kept in step by
`tests/find_nutshell_copy_test.sh`, which compares the two and fails when they
have moved apart; a stale one is otherwise quiet, resolving what it understood
when it was copied and not knowing a pin shape added since.
`SHEBANG_NUTSHELL_REF` names another. There is nothing to initialise: a copy of
nutshell in the tree is a second version that drifts from the machine's in
silence, so this carries the resolver and not the interpreter.

```bash
./check
```

## License

See `LICENSE`.
