#!/usr/bin/env bash
# The libraries ask nutshell's `deps` whether a tool is there, never the shell.
#
# `command -v <tool>` is a second opinion that skips the manifest's
# `[deps.paths]`, the variant detection and the remembered answer, so a library
# that asks it can disagree with the module beside it about the same machine.
# What is left is the two questions that are about nutshell's own functions
# rather than a tool: whether `use` exists before `deps` could be loaded, and
# whether `tui_suspend` has been sourced.

use test

_libs="${BASH_SOURCE[0]%/*}/../libs"

# Every `command -v` under <dir> that asks the shell about a tool: comments and
# the two questions about nutshell's own functions are not hits.
_command_v_hits() {
    grep -rnE '(^|[^`a-z])command -v ' "$1" | grep -vE ':[0-9]+:[[:space:]]*#' |
        grep -vE 'command -v (use|tui_suspend) ' || true
}

#[test]
it_asks_deps_for_every_tool_and_the_shell_only_about_functions() {
    assert_eq "$(_command_v_hits "$_libs")" ""
}

#[test]
it_still_sees_a_command_v_the_filter_is_meant_to_catch() {
    # The positive control for the test above: the same function over a tree
    # with a line that asks the shell about a tool must produce a hit, and the
    # lines it is meant to let through must not.
    local d; d="$(mktemp -d)"
    printf '    command -v unzip >/dev/null 2>&1\n' > "$d/hit.sh"
    printf '# command -v unzip\ncommand -v use >/dev/null\ncommand -v tui_suspend >/dev/null\n' > "$d/pass.sh"
    assert_contains "$(_command_v_hits "$d")" "hit.sh:1:    command -v unzip"
    assert_eq "$(_command_v_hits "$d" | grep -c .)" "1"
    rm -rf "$d"
}
