# the-whole-shebang

> Bash libraries built on nutshell, each one taken on its own.

Built on [nutshell](https://github.com/orgrinrt/nutshell), but the arrangement is the
opposite one. nutshell is a single thing you take whole: source `init`, `use` what you
need, and every module comes along in the same install. The libraries here are meant to
be picked apart. A script that wants findings and a verdict takes `diagnostics` and
nothing else, and never has to learn that the rest is even here.

That is the whole idea, so if you find a library in here reaching for another one for no
good reason, that's a bug and I'd like to hear about it.

## Status

First release. The api hasn't settled yet and breaking changes should be expected,
though I'll try to keep them documented. The tui half especially is young: it was
written for one bootable maintenance tool and the shapes it has are the shapes that tool
needed, so there are almost certainly gaps that only show up once somebody uses it for
something else.

---

## Installation

Declare it in `nut.toml` and let nutshell resolve it:

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

`ref` takes a branch or a tag. `main` follows the releases, `dev` follows whatever I am
doing today, and a tag like `0.1.0` is the one to use if you want the thing to stay
exactly where you left it.

Modules separate with `::` the whole way down, and `lib.nut` is the file that says which
name maps to where. Vendoring the repository works too and sources a file directly: a
checkout at `lib/shebang/` is reached as
`. "${0%/*}/lib/shebang/libs/diagnostics.sh"`.

Every library here stops immediately if nutshell has not been initialised, and names the
setup step, rather than letting you find out later on some undefined function.

## diagnostics

Records severity-tagged findings through `finding_block` and `finding_judge`, with
`finding_note` for continuation lines, and renders a verdict whose exit code a caller can
branch on: 0 when nothing was found, 1 when something blocking was, and 3 when something
needs a human to look at it.

## tui

Twelve modules for a terminal interface, taken on their own like everything else here.
Written for a bootable maintenance tool, which is what set the constraints.

`tui/term` enters and leaves a full-screen session and puts the terminal back however the
run ends. Two ideas carry it. There may be no terminal at all, so every entry point is
safe with nothing attached and simply does less: a pipe full of escape sequences is a
corrupted file rather than a styled one. And whatever gets changed is restored on every
exit path including the ones nobody plans for, because raw mode belongs to the terminal
rather than to the process, and a crash otherwise leaves you with a shell that does not
echo. It also carries the palette every other module colours by, named for what a colour
means rather than for the colour itself.

`tui/key` names a keypress, so nothing above it ever has to match an escape sequence.
Arrows, vi keys and the emacs pairs all fold to the same four names.

`tui/menu` is a list with headings the cursor skips over, and a viewport that keeps the
cursor in view. The cursor is a ring: up from the first row is the last one. `[` and `]`
move by section, and so does a modifier with an arrow.

Three things arrange it, and they are three different questions. `g` groups by the
section a row was declared under, by its kind, or not at all, making its own headings
when the cut is not the declared one. `s` orders by the caller's own order, by name, or
by state with what can be run at the top, inside a group and never across it, so the
sections do not move around when the ordering does. `f` cycles the filters a caller
registered, which are predicates over a row rather than text: "the ones I can run" is not
a word that appears in any row.

`/` searches, over the notes and the ids as well as the titles, which is the other half
of that same distinction. It is a mode rather than type-to-filter because every letter
worth searching for is already a key that means something, and `chroot` would quit at
the `h`.

A run of movement gets absorbed before it draws. A wheel event becomes a run of arrow
keys and a velocity scroll becomes a long one, so a list that redraws per key keeps
painting for seconds after the hand already stopped.

`tui/confirm` asks in three strengths: yes or no, a word typed back, and a name typed
back. The third one is there because the failure it defends against is not "did not mean
to say yes", it is "meant yes about a different disk", and no amount of shouting catches
that one. All three refuse by default when there is no terminal to ask at.

`tui/modal` draws a question inside the interface instead of at the bottom of the
terminal, which is where a confirmation lands if nothing places it.

`tui/frame` is a bordered region with a title, and `tui/progress` a bar that redraws in
place. `tui/report` renders a run's outcome: a mark per line, a state column that lines
up rather than trailing off the end of each sentence, and indentation for the steps
inside a step.

`tui/layout` divides one axis by counts, shares and floors, with a priority deciding what
goes when there is not enough room. `tui/table` puts columns across a width through it,
borders optional, and takes `--at ROW COL` and `--height N` so it can be drawn inside a
box that something else worked out.

`tui/plan` is the two-dimensional one: panels fitted around the main region, each naming
the shapes it can take, so a tall sidebar becomes a row of short columns underneath when
it will not fit beside. It fills lines and wraps, weighing each shape by how many of the
panels after it still fit. It does not promise the arrangement that drops the fewest,
which is bin packing and a different problem; it promises that the same inputs give the
same arrangement, that a panel is only ever placed at a size it declared, and that
nothing overlaps or leaves the screen.

`tui/run` hands the screen over to something that owns it, a package manager, a chroot,
fsck, and states the result afterwards rather than leaving it implicit. Boxing such a
thing inside the interface costs you its colours, its progress and your real scrollback,
and all you get back is a border.

## Tests

```bash
./test
./test tests/tui_term_test.sh
./check
```

`test` and `check` resolve nutshell themselves through `lib/find-nutshell`,
pinned at the released `0.4.1` so the suite runs against the same interpreter
you would get. `SHEBANG_NUTSHELL_REF` names another one, a tag or a branch. There is nothing to initialise first: a copy of
nutshell in the tree is a second version that drifts from the machine's one in silence,
so this carries the resolver and not the interpreter.

That resolver is a byte for byte copy of nutshell's own, because a project cannot use the
resolver to find the resolver. `tests/find_nutshell_copy_test.sh` compares the two and
fails when they have moved apart. A stale one is otherwise quiet about it, resolving what
it understood back when it was copied and knowing nothing of a pin shape added since.

## Support

Whether you use this project, have learned something from it, or just like it, please consider supporting it by buying me a coffee, so I can dedicate more time on open-source projects like this :)

<a href="https://buymeacoffee.com/orgrinrt" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Coffee" style="height: auto !important;width: auto !important;" ></a>

## License

> The project is licensed under the **Mozilla Public License 2.0**.

`SPDX-License-Identifier: MPL-2.0`

> You can check out the full license [here](https://github.com/orgrinrt/the-whole-shebang/blob/main/LICENSE)
