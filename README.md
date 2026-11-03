# the-whole-shebang

> Bash libraries built on nutshell, each one taken on its own.

These sit on top of [nutshell](https://github.com/orgrinrt/nutshell) and are meant to be picked apart, where nutshell itself is installed whole. A script that wants findings and a verdict takes `diagnostics::findings` and nothing else, and a library in here that reaches for another one without a good reason is a bug. Four are in the tree, `diagnostics::findings`, `tui`, `unpack` and `verify::digest`.

## Installation

Declare it in `nut.toml` and nutshell resolves it. `ref` takes a branch or a tag, `main` follows the releases, `dev` follows the current work, and a tag pins it.

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

Modules separate with `::` all the way down, and `lib.nut` says which name maps to which file. It needs nutshell 0.7.0 or newer, because some of the tui modules use `list`, and the entry points refuse under that and name the setup step if nutshell hasn't been initialised. `nut.toml` pins nutshell's `dev` branch since the two are developed together, so what this does can change when nutshell's dev moves.

## The libraries

`diagnostics::findings` records severity-tagged findings with `finding_block`, `finding_judge` and `finding_note`, and renders a verdict whose exit code a caller can branch on, 0 for nothing found, 1 for something blocking and 3 for something that needs a human to look.

`tui` is fifteen modules for a terminal interface, written for a bootable maintenance tool and each usable alone. `term` enters and leaves a full-screen session and restores the terminal on every exit path, and does less rather than emit escape sequences when nothing is attached. `key` names keypresses so arrows, vi keys and the emacs pairs fold to the same names, `action` holds what an interface can do as data, with a label and the keys that reach it, and `screen` writes only the rows that changed, which matters on a bare console. Then there are `palette` for finding an action by typing, `menu`, `modal`, `confirm`, `table`, `progress`, `report`, `layout`, `frame`, `plan` and `run`.

`unpack` takes a named file out of an archive through libarchive, which is `bsdtar` on Linux and `/usr/bin/tar` on macOS, and `verify::digest` decides whether a downloaded file is the file it should be.

## Status

Second release, the api hasn't settled and breaking changes should be expected. The tui half is young and shaped by the one tool it was written for, so there are likely gaps that only show once something else uses it. `./test` runs the suite, `./test tests/tui_term_test.sh` runs one file, and `./check` runs the checks, all through the nutshell launcher.

## License

> The project is licensed under the **Mozilla Public License 2.0**.

`SPDX-License-Identifier: MPL-2.0`

> You can check out the full license [here](https://github.com/orgrinrt/the-whole-shebang/blob/main/LICENSE)
