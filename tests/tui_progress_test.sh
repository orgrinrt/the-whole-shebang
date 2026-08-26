#!/usr/bin/env bash
# Tests for progress.
#
# The arithmetic is separated out precisely so it can be pinned here. A bar
# that reads 101%, or that never quite reaches the right edge, or that divides
# by a total of zero, is the kind of thing found by a user and not by a
# developer -- the developer always runs it with ten items.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/progress.sh"

# --- the bar ------------------------------------------------------------------

#[test]
it_draws_an_empty_bar_at_the_start() {
    assert_eq "$(tui_progress_bar 0 10 10)" ".........."
}

#[test]
it_draws_a_full_bar_at_the_end() {
    assert_eq "$(tui_progress_bar 10 10 10)" "##########"
}

#[test]
it_fills_proportionally() {
    assert_eq "$(tui_progress_bar 5 10 10)"  "#####....."
    assert_eq "$(tui_progress_bar 1 10 10)"  "#........."
    assert_eq "$(tui_progress_bar 9 10 10)"  "#########."
    assert_eq "$(tui_progress_bar 1 4 8)"    "##......"
    assert_eq "$(tui_progress_bar 3 4 8)"    "######.."
}

#[test]
it_always_draws_exactly_the_width_it_was_given() {
    local d t w out
    for w in 1 3 8 20 40; do
        for t in 1 3 7 10 100; do
            for d in 0 1 2 5 10 99 100; do
                out="$(tui_progress_bar "$d" "$t" "$w")"
                assert_eq "${#out}" "$w"
            done
        done
    done
}

#[test]
it_clamps_rather_than_overflowing_past_the_end() {
    # More done than there was to do happens: a count that double-counts, or a
    # total that was wrong. It must not draw past the edge.
    assert_eq "$(tui_progress_bar 20 10 10)" "##########"
    assert_eq "$(tui_progress_pct 20 10)"    "100"
}

#[test]
it_does_not_divide_by_a_total_of_zero() {
    # An unknown size is 0, and this must be blank rather than a crash.
    local out; out="$(tui_progress_bar 5 0 10)"
    assert_eq "${#out}" "10"
    assert_fails grep -q '#' <<<"$out"
}

#[test]
it_calls_no_work_at_all_finished() {
    # A run with nothing in it did finish. 0/0 is 100%, not 0% and not an error.
    assert_eq "$(tui_progress_pct 0 0)" "100"
}

#[test]
it_survives_being_handed_something_that_is_not_a_number() {
    # These come from wc, from a config file, from another program's output.
    local out
    out="$(tui_progress_bar x 10 10 2>&1)"; assert_eq "${#out}" "10"
    out="$(tui_progress_bar 5 x 10 2>&1)";  assert_eq "${#out}" "10"
    out="$(tui_progress_bar 5 10 x 2>&1)";  assert_eq "${#out}" "20"
    assert_eq "$(tui_progress_pct x y 2>&1)" "100"
}

#[test]
it_never_draws_a_zero_width_bar() {
    local out; out="$(tui_progress_bar 5 10 0)"
    assert_eq "${#out}" "1"
    # Exact, not a bound. `-ge 1` passed on the real answer and would have
    # passed on any answer at all.
    out="$(tui_progress_bar 5 10 -3)"
    assert_eq "${#out}" "1"
    # A width that is not a number is a different case from one that is a bad
    # number, and falls back to the default rather than to the minimum.
    out="$(tui_progress_bar 5 10 wide)"
    assert_eq "${#out}" "20"
}

# --- the percentage ------------------------------------------------------------

#[test]
it_rounds_the_percentage_down_rather_than_reaching_a_hundred_early() {
    # 99/100 must not read 100%: "finished" is the one thing a percentage is
    # trusted to say exactly.
    assert_eq "$(tui_progress_pct 99 100)" "99"
    assert_eq "$(tui_progress_pct 999 1000)" "99"
    assert_eq "$(tui_progress_pct 1 3)"    "33"
    assert_eq "$(tui_progress_pct 2 3)"    "66"
}

#[test]
it_reaches_a_hundred_only_when_it_is_done() {
    assert_eq "$(tui_progress_pct 100 100)" "100"
    assert_eq "$(tui_progress_pct 3 3)"     "100"
}

# --- with no terminal ------------------------------------------------------------

#[test]
it_writes_one_line_per_step_into_a_log() {
    TUI_TTY=0
    local out
    out="$(tui_progress_open 3 "Fetching"; tui_progress_step a; tui_progress_step b; tui_progress_step c; tui_progress_close)"
    assert_ok grep -q 'Fetching'  <<<"$out"
    assert_ok grep -q '\[1/3\] a' <<<"$out"
    assert_ok grep -q '\[3/3\] c' <<<"$out"
}

#[test]
it_writes_no_carriage_returns_into_a_log() {
    TUI_TTY=0
    local out
    out="$(tui_progress_open 3 "T"; tui_progress_step a; tui_progress_close)"
    # A carriage return in a file is a line nobody can read afterwards.
    assert_fails grep -q $'\r'   <<<"$out"
    assert_fails grep -q $'\x1b' <<<"$out"
}

#[test]
it_says_how_many_it_did_at_the_end() {
    TUI_TTY=0
    local out
    out="$(tui_progress_open 2 "T"; tui_progress_step a; tui_progress_step b; tui_progress_close)"
    assert_ok grep -q 'done, 2' <<<"$out"
}

# --- being used wrongly ------------------------------------------------------------

#[test]
it_ignores_a_step_with_no_run_open() {
    TUI_TTY=0
    local out; out="$(tui_progress_step "orphan")"
    assert_eq "$out" ""
}

#[test]
it_ignores_a_close_with_no_run_open() {
    TUI_TTY=0
    local out; out="$(tui_progress_close)"
    assert_eq "$out" ""
}

#[test]
it_ignores_a_close_twice() {
    TUI_TTY=0
    local out; out="$(tui_progress_open 1 T; tui_progress_close; tui_progress_close)"
    assert_eq "$(grep -c 'done,' <<<"$out")" "1"
}

#[test]
it_takes_a_total_that_is_not_a_number_as_unknown() {
    TUI_TTY=0
    local out
    # The 2>&1 belongs to the whole substitution. Attached to the last command
    # it misses stderr from tui_progress_open, which is the call taking the
    # non-numeric argument and the entire point of the test.
    out="$( { tui_progress_open notanumber "T"; tui_progress_step a; tui_progress_close; } 2>&1 )"
    # Unknown size, so no fabricated fraction.
    assert_fails grep -q '\[1/' <<<"$out"
    assert_fails grep -qi 'unbound\|syntax error' <<<"$out"
}

#[test]
it_ignores_a_set_to_something_that_is_not_a_number() {
    TUI_TTY=0
    local out
    out="$(tui_progress_open 10 T; tui_progress_set 4 four; tui_progress_set x; tui_progress_close)"
    # The bad set is dropped rather than resetting the count to zero.
    assert_ok grep -q 'done, 4' <<<"$out"
}

#[test]
it_jumps_to_a_count_for_work_finished_in_batches() {
    TUI_TTY=0
    local out
    out="$(tui_progress_open 10 T; tui_progress_set 7 seven; tui_progress_close)"
    assert_ok grep -q '\[7/10\] seven' <<<"$out"
    assert_ok grep -q 'done, 7'        <<<"$out"
}

# --- the half that draws --------------------------------------------------------
#
# Every test above sets TUI_TTY=0, so the spinner, the label budget and the
# width clamp had no coverage at all -- and two real bugs lived in exactly
# there. What was easy to test got tested.

_pstrip() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

# Absolute. Relative paths inside `bash -c` resolve against the caller's
# directory, so run from anywhere but the repo root these sourced nothing at
# all -- and the test asserting no colour then passed because there was no
# module loaded to produce any.
PROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
# The widest line actually drawn, in characters, with the carriage returns that
# separate redraws turned into line breaks.
_pwidest() {
    local w=0 l
    while IFS= read -r l; do
        l="${l%%$'\r'*}"
        (( ${#l} > w )) && w="${#l}"
    done < <(tr '\r' '\n' <<<"$1" | _pstrip)
    printf '%d' "$w"
}

#[test]
it_never_draws_wider_than_the_terminal() {
    TUI_TTY=1
    local c out w
    for c in 5 10 15 20 24 40 80 120; do
        out="$(WANT_COLS=$c PROOT="$PROOT" bash -c '
            . "$PROOT/lib/nutshell/init" 2>/dev/null
            . "$PROOT/libs/tui/term.sh"; . "$PROOT/libs/tui/progress.sh"
            # After sourcing: term.sh declares TUI_COLS at file scope, so a
            # value inherited from the environment is overwritten by the
            # default the moment the module loads.
            TUI_TTY=1; TUI_COLS="${WANT_COLS}"
            tui_progress_open 10 "T"
            tui_progress_step "a label long enough to need cutting on a small screen"
            tui_progress_step "another"
        ' 2>&1)"
        w="$(_pwidest "$out")"
        # The redraw clears one physical line. Anything wider wraps, and the
        # wrapped part survives the clear, so a narrow console piles up one
        # line of leftovers per step.
        assert_ok test "$w" -le "$c"
    done
    TUI_TTY=0
}

#[test]
it_draws_a_spinner_when_the_size_is_unknown() {
    local out
    out="$(WANT_COLS=40 PROOT="$PROOT" bash -c '
        . "$PROOT/lib/nutshell/init" 2>/dev/null
        . "$PROOT/libs/tui/term.sh"; . "$PROOT/libs/tui/progress.sh"
        TUI_TTY=1; TUI_COLS="${WANT_COLS}"
        tui_progress_open 0 "Scanning"
        tui_progress_step one; tui_progress_step two
    ' 2>&1 | _pstrip)"
    # A bar creeping to 90% and stopping is a bar that lies about how far along
    # it is, and people learn to ignore those.
    assert_fails grep -q '#' <<<"$out"
    assert_ok    grep -q '[|/\-]' <<<"$out"
}

#[test]
it_cuts_a_long_label_with_a_mark_the_terminal_can_draw() {
    local out
    out="$(LC_ALL=C LANG=C WANT_COLS=40 PROOT="$PROOT" bash -c '
        . "$PROOT/lib/nutshell/init" 2>/dev/null
        . "$PROOT/libs/tui/term.sh"; . "$PROOT/libs/tui/progress.sh"
        TUI_TTY=1; TUI_COLS="${WANT_COLS}"
        tui_progress_open 10 "T"
        tui_progress_step "a label far longer than the space left for it on this line"
    ' 2>&1 | _pstrip)"
    # An ellipsis is three bytes of UTF-8, and this module is aimed at a
    # console that renders those as noise.
    assert_fails grep -q '…' <<<"$out"
    assert_ok    grep -q '\.\.\.' <<<"$out"
}

#[test]
it_uses_the_nicer_mark_where_it_renders() {
    local out
    out="$(LC_ALL=en_US.UTF-8 TERM=xterm WANT_COLS=40 PROOT="$PROOT" bash -c '
        . "$PROOT/lib/nutshell/init" 2>/dev/null
        . "$PROOT/libs/tui/term.sh"; . "$PROOT/libs/tui/progress.sh"
        TUI_TTY=1; TUI_COLS="${WANT_COLS}"
        tui_progress_open 10 "T"
        tui_progress_step "a label far longer than the space left for it on this line"
    ' 2>&1 | _pstrip)"
    assert_ok grep -q '…' <<<"$out"
}

#[test]
it_keeps_the_percentage_when_there_is_no_room_for_a_bar() {
    local out
    out="$(WANT_COLS=12 PROOT="$PROOT" bash -c '
        . "$PROOT/lib/nutshell/init" 2>/dev/null
        . "$PROOT/libs/tui/term.sh"; . "$PROOT/libs/tui/progress.sh"
        TUI_TTY=1; TUI_COLS="${WANT_COLS}"
        tui_progress_open 4 "T"
        tui_progress_step one; tui_progress_step two
    ' 2>&1 | _pstrip)"
    # The number is the part that carries the information. The bar is the part
    # that can be dropped.
    assert_ok grep -q '50%' <<<"$out"
}

#[test]
it_writes_no_colour_when_the_terminal_said_no_colour() {
    local out
    out="$(WANT_COLS=40 PROOT="$PROOT" bash -c '
        . "$PROOT/lib/nutshell/init" 2>/dev/null
        . "$PROOT/libs/tui/term.sh"; . "$PROOT/libs/tui/progress.sh"
        DIM=$'"'"'\033[2m'"'"'; BOLD=$'"'"'\033[1m'"'"'; GREEN=$'"'"'\033[32m'"'"'; NC=$'"'"'\033[0m'"'"'
        TUI_TTY=1; TUI_COLOR=0; TUI_COLS="${WANT_COLS}"
        tui_progress_open 2 "T"; tui_progress_step a; tui_progress_close
    ' 2>&1)"
    # The module has to have loaded, or "no colour" is true of an empty
    # string and this test passes having run nothing.
    assert_ok grep -q 'done' <<<"$out"
    # Not "no escapes at all": clearing the line is terminal control and is
    # right even with colour off. What must be absent is the colour itself.
    assert_fails grep -qE $'\x1b\[[0-9;]*m' <<<"$out"
}

#[test]
it_writes_colour_when_the_terminal_wants_it() {
    local out
    out="$(WANT_COLS=40 PROOT="$PROOT" bash -c '
        . "$PROOT/lib/nutshell/init" 2>/dev/null
        . "$PROOT/libs/tui/term.sh"; . "$PROOT/libs/tui/progress.sh"
        DIM=$'"'"'\033[2m'"'"'; BOLD=$'"'"'\033[1m'"'"'; GREEN=$'"'"'\033[32m'"'"'; NC=$'"'"'\033[0m'"'"'
        TUI_TTY=1; TUI_COLOR=1; TUI_COLS="${WANT_COLS}"
        tui_progress_open 2 "T"; tui_progress_step a; tui_progress_close
    ' 2>&1)"
    # Or the test above is satisfied by a module that never colours anything.
    assert_ok grep -qE $'\x1b\[[0-9;]*m' <<<"$out"
}

#[test]
it_says_how_long_it_took() {
    local out
    out="$(WANT_COLS=40 PROOT="$PROOT" bash -c '
        . "$PROOT/lib/nutshell/init" 2>/dev/null
        . "$PROOT/libs/tui/term.sh"; . "$PROOT/libs/tui/progress.sh"
        TUI_TTY=1; TUI_COLS="${WANT_COLS}"
        tui_progress_open 1 "T"; tui_progress_step a; tui_progress_close
    ' 2>&1 | _pstrip)"
    # "Did that hang or is it just slow" is the question a bar exists to
    # answer, and the answer is worth keeping after it finishes.
    assert_ok grep -qE 'done.*1 in [0-9]+s' <<<"$out"
}
