# the-whole-shebang

> Bash libraries built on nutshell, each one taken on its own.

Built on [nutshell](https://github.com/orgrinrt/nutshell), but the arrangement is the
opposite one. nutshell is a single thing you take whole: source `init`, `use` what you
need, and every module comes along in the same install. The libraries here are meant to
be picked apart. A script that wants findings and a verdict takes `diagnostics::findings`
and nothing else, and never has to learn that the rest is even here.

That is the whole idea, so if you find a library in here reaching for another one for no
good reason, that's a bug and I'd like to hear about it.

## What it needs

nutshell, and a recent one. `libs/tui/report.sh` and `libs/tui/menu/draw.sh`
both use `list`, which arrived in nutshell 0.7.0, so the entry points here state
that floor and refuse under it rather than failing later on a missing function.

`nut.toml` pins `nutshell_branch = "dev"` rather than a version, because this
and nutshell are developed together. That means what this does can change when
nutshell's dev moves, including after a release here is tagged. It is the right
trade while the two move together and it will not always be.

## Status

Second release. The api hasn't settled yet and breaking changes should be expected,
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

use shebang::diagnostics::findings

finding_block "version moved on a feature branch"
finding_note  "A version moves on a release. If this PR is one, say so."
findings_verdict
```

`ref` takes a branch or a tag. `main` follows the releases, `dev` follows whatever I am
doing today, and a tag like `0.1.0` is the one to use if you want the thing to stay
exactly where you left it.

Modules separate with `::` the whole way down, and `lib.nut` is the file that says which
name maps to where. There is no vendored path and there should not be one: a copy in your
tree is a second version of this that goes quietly out of date, and the whole point of the
manifest is that you say which one you want and the launcher fetches it.

Every library here stops immediately if nutshell has not been initialised, and names the
setup step, rather than letting you find out later on some undefined function.

## diagnostics::findings

Records severity-tagged findings through `finding_block` and `finding_judge`, with
`finding_note` for continuation lines, and renders a verdict whose exit code a caller can
branch on: 0 when nothing was found, 1 when something blocking was, and 3 when something
needs a human to look at it.

## tui

Fifteen modules for a terminal interface, taken on their own like everything else here.
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

`tui/action` holds what an interface can do, as data rather than as a `case` over
characters. An action carries an id, a label, which keys reach it and where it applies,
so the key line, the help screen and the palette are all reads of one register instead of
three lists that drift. A binding is named, `bracket-left` and not `[`, which is what
lets a config file point at it and what makes it rebindable on a layout that cannot
produce the character: on a Finnish keyboard `[` is AltGr+8 and a bare console does not
deliver it at all.

`tui/screen` writes only the rows that changed. A whole-screen redraw on every keypress
is imperceptible under a terminal emulator with a gpu behind it and close to a second on
a bare console, which is the machine a maintenance tool tends to run on, so a frame is
built as rows and the flush compares them against the ones already up there. A cursor
step costs two rows and a filter keystroke costs most of them, and neither case has to be
recognised for that to come out right.

`tui/palette` is the other way to reach an action, for when a key is a thing you would
have had to already know. Type a few letters of what you want and pick it off the list,
and the keys that reach it are printed beside it, which is mostly how anybody finds out
one exists. It searches the whole register, so an action with no key at all is as
reachable as any other, and it picks rather than runs: the caller decides what to do with
what came back.

`tui/menu` is a list with headings the cursor skips over, and a viewport that keeps the
cursor in view. The cursor is a ring: up from the first row is the last one. `[` and `]`
move by section, and so do ctrl and alt with an arrow, since a terminal can swallow the
modified arrow and a layout can withhold the bracket. Every key it answers to sits in the
register above, so all of them can be moved.

A row can also say it does not know yet. Working out whether a task is already true is
often the slow part, slow enough that doing all of it before the first frame means a blank
terminal for several seconds and the first thing anybody learns about the tool is that it
hangs on start. So the rows go up unresolved, and `TUI_MENU_IDLE` names a function the
menu calls whenever nothing is being typed, which fills them in a slice at a time. A key
that is already waiting wins over a slice, since answering the person in front of it
matters more than finishing the list.

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

`test` and `check` run through the `nutshell` launcher, which reads the pin in
`nut.toml` and resolves it. That pin is `dev`, so the suite runs against the
same interpreter this library is developed against, and a branch pin means the
head of that branch rather than whatever happens to be on the machine.

Install nutshell once and both work. Nothing here carries a copy of any part of
it: the launcher is the one thing that knows how to find a nutshell, and a
second copy of that knowledge in this tree is a thing that goes quietly out of
date.

## Support

Whether you use this project, have learned something from it, or just like it, please consider supporting it by buying me a coffee, so I can dedicate more time on open-source projects like this :)

<a href="https://buymeacoffee.com/orgrinrt" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Coffee" style="height: auto !important;width: auto !important;" ></a>

## License

> The project is licensed under the **Mozilla Public License 2.0**.

`SPDX-License-Identifier: MPL-2.0`

> You can check out the full license [here](https://github.com/orgrinrt/the-whole-shebang/blob/main/LICENSE)
