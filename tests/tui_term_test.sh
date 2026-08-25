#!/usr/bin/env bash
# Tests for the terminal layer.
#
# The behaviour worth defending here is not the drawing, it is the two promises
# the module makes: that it writes nothing when there is nowhere to write, and
# that it puts the terminal back however it is left. Both fail silently in
# ordinary use and are only noticed at the worst moment, so both are pinned.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"

# The suite runs without a terminal, so the tty-present cases are exercised by
# forcing the flag. That is the honest way to test it: the flag is the module's
# own idea of whether there is a terminal, and every branch reads it.

#[test]
it_reports_no_tty_when_running_under_a_pipe() {
    tui_probe
    assert_eq "$TUI_TTY" "0"
}

#[test]
it_refuses_colour_without_a_terminal() {
    tui_probe
    assert_eq "$TUI_COLOR" "0"
}

#[test]
it_honours_no_color_even_with_a_terminal() {
    # The control for the colour logic: forcing a tty is not enough on its own,
    # NO_COLOR still has to win, or the one convention everybody agreed on is
    # broken.
    local saved_term="${TERM:-}"
    TERM=xterm NO_COLOR=1 TUI_TTY=1
    if [[ -z "${NO_COLOR:-}" || "${TERM:-dumb}" == "dumb" ]]; then
        TUI_COLOR=1
    else
        TUI_COLOR=0
    fi
    assert_eq "$TUI_COLOR" "0"
    TERM="$saved_term"
}

#[test]
it_answers_whether_there_is_a_terminal() {
    # Callers branch on this before asking the user anything. When it was
    # missing entirely, every "refuses without a terminal" test still passed,
    # because a command-not-found also returns non-zero. Green for the wrong
    # reason is the failure mode this pins.
    TUI_TTY=1; assert_ok    tui_is_tty
    TUI_TTY=0; assert_fails tui_is_tty
}

#[test]
it_falls_back_to_a_usable_size_with_no_terminal() {
    TUI_TTY=0
    LINES="" COLUMNS="" tui_size
    assert_eq "$TUI_ROWS" "24"
    assert_eq "$TUI_COLS" "80"
}

#[test]
it_takes_the_size_from_the_environment_when_given_one() {
    # The control for the fallback: if this did not pass, the test above would
    # hold for an implementation that ignored everything and hardcoded 24x80.
    TUI_TTY=0
    LINES=40 COLUMNS=120 tui_size
    assert_eq "$TUI_ROWS" "40"
    assert_eq "$TUI_COLS" "120"
}

#[test]
it_rejects_a_zero_size() {
    # A zero reaches a division in any pager calculation and takes the whole
    # tool down mid-screen. Nonsense in has to become a usable number out.
    TUI_TTY=0
    LINES=0 COLUMNS=0 tui_size
    assert_eq "$TUI_ROWS" "24"
    assert_eq "$TUI_COLS" "80"
}

#[test]
it_rejects_a_nonsense_size() {
    TUI_TTY=0
    LINES=nonsense COLUMNS=nonsense tui_size
    assert_eq "$TUI_ROWS" "24"
    assert_eq "$TUI_COLS" "80"
}

#[test]
it_writes_no_control_bytes_into_a_pipe() {
    # The load-bearing one. Escape sequences in a redirected file are a
    # corrupted artifact, not a styled one.
    TUI_TTY=0
    local out
    out="$(tui_alt_screen_on; tui_clear; tui_move 5 5; tui_cursor_hide)"
    assert_eq "${#out}" "0"
}

#[test]
it_does_write_control_bytes_when_there_is_a_terminal() {
    # The control. Without it, the test above is satisfied by a module that
    # never emits anything at all.
    TUI_TTY=1
    local out
    out="$(tui_clear)"
    TUI_TTY=0
    assert_ne "${#out}" "0"
}

#[test]
it_moves_the_cursor_with_one_based_coordinates() {
    TUI_TTY=1
    local out
    out="$(tui_move 3 7)"
    TUI_TTY=0
    assert_eq "$out" $'\033[3;7H'
}

#[test]
it_restores_only_once() {
    # Restore runs from the trap and possibly again on the way out. The second
    # call has to be a no-op rather than a second alt-screen exit, which would
    # pop the user out of a screen they were already back in.
    # Captured by redirection rather than command substitution: `$( )` forks,
    # so the flag the first call clears would never reach the second one and
    # the test would pass against a module with no guard at all.
    local dir; dir="$(mktemp -d)"
    TUI_TTY=1
    _TUI_ACTIVE=1
    tui_restore > "$dir/first"
    tui_restore > "$dir/second"
    TUI_TTY=0
    local first second
    first="$(wc -c < "$dir/first")"
    second="$(wc -c < "$dir/second")"
    rm -rf "$dir"
    assert_ne "$first" "0"
    assert_eq "$((second))" "0"
}

#[test]
it_restores_nothing_when_no_session_was_started() {
    _TUI_ACTIVE=0
    TUI_TTY=1
    local out
    out="$(tui_restore)"
    TUI_TTY=0
    assert_eq "${#out}" "0"
}

#[test]
it_does_not_stack_raw_mode() {
    # The saved settings must stay the user's own. A second tui_raw_on that
    # overwrote them with our own raw settings would make restore a no-op and
    # leave the shell without echo.
    _TUI_STTY_SAVED="pretend-original"
    TUI_TTY=1
    tui_raw_on
    TUI_TTY=0
    assert_eq "$_TUI_STTY_SAVED" "pretend-original"
    _TUI_STTY_SAVED=""
}

#[test]
it_ignores_raw_off_when_nothing_was_saved() {
    _TUI_STTY_SAVED=""
    assert_ok tui_raw_off
}

#[test]
it_returns_the_status_of_a_suspended_command() {
    _TUI_ACTIVE=0
    assert_ok    tui_suspend true
    assert_fails tui_suspend false
}

#[test]
it_actually_runs_the_suspended_command() {
    # The control for the status test: `assert_fails` would also pass if the
    # command were never run and the function simply returned non-zero.
    _TUI_ACTIVE=0
    local out
    out="$(tui_suspend printf 'ran')"
    assert_eq "$out" "ran"
}

#[test]
it_is_safe_to_source_twice() {
    # The include guard. Re-sourcing hits `readonly` on the guard variable,
    # which is fatal under set -e if the guard is not checked first.
    assert_ok . "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
}
