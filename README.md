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

## License

See `LICENSE`.
