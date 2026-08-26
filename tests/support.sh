#!/usr/bin/env bash
# Shared helpers for the suite. Not a test file: `test_run_dir` only picks up
# `*_test.sh`, so this is sourced by the files that want it.

# Does this finish, or does it spin?
#
# A test for a loop that used to hang cannot simply call the thing: the
# regression would wedge the suite instead of failing it. So the call runs in
# its own bash, a watchdog kills it after a couple of seconds, and what is
# asserted is that it finished on its own.
#
# Usage: _finishes 'tui_table_col note 2fr --head'
_finishes() {
    local code="$1" root="${BASH_SOURCE[0]%/*}/.."
    local out; out="$(mktemp)"
    bash -c "use(){ :; }
             . '${root}/libs/tui/term.sh'
             . '${root}/libs/tui/layout.sh'
             . '${root}/libs/tui/table.sh'
             ${code}
             printf 'finished' >> '${out}'" >/dev/null 2>&1 &
    local pid=$!
    ( sleep 3; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    local dog=$!
    wait "$pid" 2>/dev/null
    kill "$dog" 2>/dev/null
    local got; got="$(cat "$out" 2>/dev/null)"
    rm -f "$out"
    [[ "$got" == "finished" ]]
}
