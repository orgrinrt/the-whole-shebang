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

# --- cutting text to fit ---------------------------------------------------------
#
# Two modules needed this and each had its own copy, so a fix to one left the
# other wrong. It lives here because the locale question is the terminal's.

TROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"

#[test]
it_leaves_a_string_that_already_fits() {
    assert_eq "$(tui_cut "short" 20 "...")" "short"
    assert_eq "$(tui_cut "exactlyten" 10 "...")" "exactlyten"
}

#[test]
it_cuts_to_the_width_it_was_given() {
    local out
    out="$(tui_cut "a much longer string than the space allowed" 12 "...")"
    assert_eq "${#out}" "12"
    out="$(tui_cut "a much longer string than the space allowed" 5 "...")"
    assert_eq "${#out}" "5"
}

#[test]
it_ends_a_cut_string_with_the_mark() {
    assert_ok grep -q '\.\.\.$' <<<"$(tui_cut "abcdefghijkl" 8 "...")"
}

#[test]
it_refuses_a_width_of_nothing() {
    assert_eq "$(tui_cut "abc" 0 "...")" ""
    assert_eq "$(tui_cut "abc" -4 "...")" ""
    assert_eq "$(tui_cut "abc" notanumber "...")" ""
}

#[test]
it_does_not_leave_half_a_character_behind() {
    local body out n
    # Not forced to `C`, and not one character repeated.
    #
    # This test could not fail. Under `LC_ALL=C` the shell counts bytes, so the
    # width arithmetic and the cut use the same unit and cannot disagree, and
    # the repair walk runs as well because `tui_unicode_ok` is false there. The
    # body was twenty identical two-byte characters with no ASCII in it, so
    # even the arithmetic landed on boundaries. Three separate reasons it was
    # green, and a real split shipped underneath all of them: `tui_cut "héllo"
    # 3` returned `h`, a lone `c3`, and the ellipsis.
    #
    # The locale a person actually runs in is the one that matters, and mixed
    # widths are what put the boundary somewhere the arithmetic does not.
    local bodies='héllo aébc 日本語x aa日bb éé日aaé'
    local body
    for body in $bodies; do
        for n in 2 3 4 5 6 7 8; do
            out="$(tui_cut "$body" "$n" '...')"
            assert_ok python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8")' <<<"$out"
            # And again where the shell counts bytes, which is the case the
            # repair walk exists for.
            out="$(LC_ALL=C LC_CTYPE=C LANG=C tui_cut "$body" "$n" '...')"
            assert_ok python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8")' <<<"$out"
        done
    done
}

#[test]
it_keeps_every_character_the_width_allows() {
    # The other half. A cut that strips a whole character it did not need to
    # also decodes cleanly, and would pass the test above while losing text.
    local body out kept
    body="$(printf '\xc3\xa9%.0s' {1..20})"
    # 11 bytes, minus a 3-byte mark, leaves 8 bytes: four whole e-acutes.
    out="$(LC_ALL=C LC_CTYPE=C LANG=C tui_cut "$body" 11 '...')"
    kept="$(printf '%s' "${out%...}" | LC_ALL=C awk '{print length($0)}')"
    assert_eq "$kept" "8"
}

#[test]
it_has_a_detector_that_notices_a_split_character() {
    # The positive control for the decode assertion above.
    assert_fails python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8")' \
        <<<"$(printf 'xxx\xc3')"
}

#[test]
it_picks_a_mark_the_terminal_can_draw() {
    assert_eq "$(LC_ALL=C LC_CTYPE=C LANG=C tui_ellipsis)" "..."
    assert_eq "$(LC_ALL=en_US.UTF-8 TERM=linux tui_ellipsis)" "..."
    assert_eq "$(LC_ALL=en_US.UTF-8 TERM=xterm tui_ellipsis)" "…"
}

# --- the flags mean something as soon as the module is loaded ---------------------

#[test]
it_knows_about_the_terminal_without_being_asked_first() {
    # TUI_TTY and TUI_COLOR used to sit at their defaults until tui_begin ran,
    # so a module gating its colour on TUI_COLOR printed none at all for the
    # caller its own usage header describes. Measured on a real pty.
    local out
    out="$(python3 - "$TROOT" <<'PY'
import pty, os, sys
root = sys.argv[1]
script = (
    'cd %s; . libs/tui/term.sh; . libs/tui/report.sh; '
    'tui_report_reset; tui_report_row fail a b; '
    'printf "escapes:%%d\\n" "$(tui_report_show T | grep -c $\'\\x1b\')"' % root
)
buf = []
pty.spawn(["nutshell", "-c", script], lambda fd: (lambda d: (buf.append(d), d)[1])(os.read(fd, 1024)))
print(b"".join(buf).decode(errors="replace"))
PY
)"
    # Colour on a terminal, without the caller having probed anything.
    assert_ok grep -qE 'escapes:[1-9]' <<<"$out"
}

#[test]
it_still_writes_no_colour_into_a_pipe() {
    # The other direction of the same flag, and the one that matters for a log.
    local out
    out="$(cd "$TROOT" && nutshell -c '
        . libs/tui/term.sh; . libs/tui/report.sh
        tui_report_reset; tui_report_row fail a b
        tui_report_show T')"
    # The row has to have rendered, or "no colour" is true of an empty string
    # and this passes having run nothing. It could: `nutshell -c` needs the
    # launcher on PATH, where `bash -c` needed nothing at all.
    assert_ok grep -q 'a' <<<"$out"
    assert_fails grep -q $'\x1b' <<<"$out"
}
