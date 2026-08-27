#!/usr/bin/env bash
# Tests for the command runner.
#
# The exit status is the whole contract. A task engine branches on it, so a
# runner that loses or flattens a status turns a failed step into a step that
# reported success, which is the worst failure a maintenance tool has.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/key.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/run.sh"

TUI_RUN_NO_PAUSE=1

#[test]
it_reports_success() {
    tui_run "t" true >/dev/null 2>&1
    assert_eq "$TUI_RUN_STATUS" "0"
}

#[test]
it_reports_failure() {
    tui_run "t" false >/dev/null 2>&1
    assert_eq "$TUI_RUN_STATUS" "1"
}

#[test]
it_carries_the_exact_exit_status_through() {
    # Not just zero or non-zero. A caller distinguishing "not found" from
    # "refused" needs the number intact.
    tui_run "t" bash -c 'exit 7' >/dev/null 2>&1
    assert_eq "$TUI_RUN_STATUS" "7"
    tui_run "t" bash -c 'exit 42' >/dev/null 2>&1
    assert_eq "$TUI_RUN_STATUS" "42"
}

#[test]
it_returns_the_status_as_well_as_setting_it() {
    # Both, because callers use both shapes and a runner that only set the
    # variable would silently succeed inside an `if`.
    assert_ok    tui_run "t" true
    assert_fails tui_run "t" false
}

#[test]
it_actually_runs_the_command() {
    # The control. Every status test above passes against a runner that never
    # executes anything and just returns what it was told.
    local out
    out="$(tui_run "t" printf 'ran-it' 2>&1)"
    assert_contains "$out" "ran-it"
}

#[test]
it_passes_arguments_through_untouched() {
    local out
    out="$(tui_run "t" printf '%s-%s' one two 2>&1)"
    assert_contains "$out" "one-two"
}

#[test]
it_survives_an_argument_with_spaces() {
    local out
    out="$(tui_run "t" printf '%s' 'a b c' 2>&1)"
    assert_contains "$out" "a b c"
}

#[test]
it_shows_the_title() {
    local out
    out="$(tui_run "Rebuilding the initramfs" true 2>&1)"
    assert_contains "$out" "Rebuilding the initramfs"
}

#[test]
it_says_done_on_success() {
    local out
    out="$(tui_run "t" true 2>&1)"
    assert_contains "$out" "done"
}

#[test]
it_names_the_exit_number_on_failure() {
    # The number is what gets searched for when the message above it turns out
    # not to be the real reason.
    local out
    out="$(tui_run "t" bash -c 'exit 9' 2>&1)"
    assert_contains "$out" "9"
}

# --- the quiet variant -------------------------------------------------------

#[test]
it_stays_quiet_about_a_success() {
    local out
    out="$(tui_run_quiet "t" true 2>&1)"
    assert_fails grep -q "done" <<< "$out"
}

#[test]
it_still_speaks_up_about_a_failure() {
    # The control for the quiet variant: silence on failure would make it
    # useless and dangerous rather than merely quiet.
    local out
    out="$(tui_run_quiet "t" bash -c 'exit 3' 2>&1)"
    assert_contains "$out" "failed"
}

#[test]
it_carries_status_through_the_quiet_variant_too() {
    tui_run_quiet "t" bash -c 'exit 5' >/dev/null 2>&1
    assert_eq "$TUI_RUN_STATUS" "5"
    assert_ok tui_run_quiet "t" true
}

#[test]
it_is_safe_to_source_twice() {
    assert_ok . "${BASH_SOURCE[0]%/*}/../libs/tui/run.sh"
}
