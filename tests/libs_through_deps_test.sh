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

#[test]
it_asks_deps_for_every_tool_and_the_shell_only_about_functions() {
    local hits
    hits="$(grep -rnE '(^|[^`a-z])command -v ' "$_libs" | grep -vE ':[0-9]+:[[:space:]]*#' |
            grep -vE 'command -v (use|tui_suspend) ' || true)"
    assert_eq "$hits" ""
}

#[test]
it_still_sees_a_command_v_the_filter_is_meant_to_catch() {
    # The positive control for the test above: the same pipeline over a line
    # that does ask the shell about a tool must produce a hit.
    local hits
    hits="$(printf 'x.sh:3:    command -v unzip >/dev/null 2>&1\n' |
            grep -vE ':[0-9]+:[[:space:]]*#' | grep -vE 'command -v (use|tui_suspend) ' || true)"
    assert_contains "$hits" "unzip"
}
