# The audit before the TUI work, and what it found

Op asked for the whole surface of `nutshell` and this library to be read before
anything is implemented. This is that read. **Its main result is that most of
what was about to be built already exists**, and the work is smaller and
differently shaped than the feature list suggested.

## What is already here

`nutshell` publishes 431 functions across 32 modules. This library publishes
about 50 across 12 TUI modules plus diagnostics. The relevant ones:

| wanted | already there | where |
|---|---|---|
| elevate for one call, then drop | `priv_run` | `nutshell/lib/priv.sh:264` |
| run a step back as the person | `priv_as_user` | `priv.sh:173` |
| the person's home, not root's | `priv_user_home` | `priv.sh:126` |
| ask whether a password is needed | `priv_needs_password` | `priv.sh:240` |
| hand a file back after root made it | `priv_return` | `priv.sh:312` |
| a modal over the screen | `tui_modal_say` and friends | `tui/modal.sh` |
| move the cursor, clear one line | `tui_move`, `tui_clear_line` | `tui/term.sh` |
| a heading that is not a row | `tui_menu_heading` | `tui/menu.sh:120` |
| fetch json, download a file | `http_get_json`, `http_download` | `nutshell/lib/http.sh` |

**Nothing on that list needs writing.** Four of the eleven feature requests
turn out to be wiring or rendering rather than machinery.

## The elevation half is done and unused

`priv_run` takes a reason in words, says it before the prompt appears, passes
argv straight through without a shell so quoting cannot go wrong, refuses when
there is no way to elevate, and refuses rather than hangs when a password is
needed and there is no terminal to type it on. It runs one command and returns.
That is the whole of what was asked for.

`priv_user_home` reads the password database rather than `$HOME`, which is the
precise hazard op named: a path built from `$HOME` under `sudo` lands in
`/root`. `hulilupteri/lib/host.sh:56` carries the incident that taught it, where
one run under sudo put the journal somewhere the person could not write.

**And `hulilupteri` calls exactly one of the nine, `priv_user_home`, as a
home-directory helper.** Every place that needs root builds a `sudo` argv by
hand and prints it for somebody to paste. So the tool doing its own privileged
work is a wiring job through `priv_run`, not a design problem.

One genuine gap: `priv_run` logs the reason but not the command. Op wants the
exact command visible **before** the prompt rather than after it. That is a few
lines inside `priv_run`, and it belongs there rather than in each caller,
because a caller that has to remember to print it is a caller that will not.

## The repaint is a rendering problem, not a missing primitive

`term.sh` already exposes `tui_move` and `tui_clear_line`, so addressing one
row costs nothing new. The menu redraws everything on every keypress anyway,
which is a second per cursor movement on a bare console and imperceptible under
a GPU-accelerated terminal emulator. That difference is why it was never seen:
**the machine it was built for is the one it was never run on.**

The work is damage tracking: know which rows changed, move to those, rewrite
them. The two rows that change on a cursor step are the one leaving and the one
arriving.

## Headings exist and do not look like anything

`tui_menu_heading` declares one, `menu/draw.sh:55` draws it, and `menu/view.sh`
keeps it only while something under it survives a filter, which is careful work.
What is missing is any visual difference: it spans the row instead of filling
the columns, and that is all. So the abstraction op asked for is present and the
styling is not, which is the cheaper half of the two.

## The actions abstraction is the one real absence

Nothing in either library models an action. Keys are dispatched by a `case` in
`menu.sh:381`, and the section-movement fallback is `'['` and `']'` written as
literals at lines 375, 390 and 391.

That fallback is what op could not press. The comment above it says the bracket
keys "always arrive", which is true of a US layout and false of a Finnish one,
where `[` is `AltGr+8` and the console does not deliver it as a bare `[`.
**A key that a layout can withhold cannot be a fallback for a key a terminal can
withhold.**

So the actions module is where the work actually is, and everything op listed
hangs off it: `?` renders the main-scope actions, the palette fuzzy-searches all
of them, `keymap.toml` rebinds them by id, and `ctrl` with an arrow is an action
like any other rather than a special case in a dispatch table. One source of
truth, and the derived surfaces cannot drift from it because they are reads of
it.

What an action needs, on the evidence of what the menu already does: an id, a
label, a scope deciding whether `?` shows it, a default binding named rather
than spelled as a character, and a handler. The binding wants naming because
that is what makes it layout-independent and what lets `keymap.toml` speak about
it.

## What this changes about the order

The feature list read as five pieces of new machinery. It is one, plus wiring
and rendering. **The actions module is the only thing here that does not
exist**, and it is also what three of the other items derive from, so it comes
first and the rest follow cheaply.
