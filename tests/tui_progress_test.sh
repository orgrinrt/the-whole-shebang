#!/usr/bin/env bash
# Tests for progress.
#
# The arithmetic is separated out precisely so it can be pinned here. A bar
# that reads 101%, or that never quite reaches the right edge, or that divides
# by a total of zero, is the kind of thing found by a user and not by a
# developer. The developer always runs it with ten items.

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
# width clamp had no coverage at all, and two real bugs lived in exactly there.
# What was easy to test got tested.

_pstrip() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

# Absolute. Relative paths inside `bash -c` resolve against the caller's
# directory, so run from anywhere but the repo root these sourced nothing at
# all, and the test asserting no colour then passed because there was no module
# loaded to produce any.
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
        out="$(WANT_COLS=$c PROOT="$PROOT" nutshell -c '
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
    out="$(WANT_COLS=40 PROOT="$PROOT" nutshell -c '
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
    out="$(LC_ALL=C LANG=C WANT_COLS=40 PROOT="$PROOT" nutshell -c '
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
    out="$(LC_ALL=en_US.UTF-8 TERM=xterm WANT_COLS=40 PROOT="$PROOT" nutshell -c '
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
    out="$(WANT_COLS=12 PROOT="$PROOT" nutshell -c '
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
    out="$(WANT_COLS=40 PROOT="$PROOT" nutshell -c '
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
    out="$(WANT_COLS=40 PROOT="$PROOT" nutshell -c '
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
    out="$(WANT_COLS=40 PROOT="$PROOT" nutshell -c '
        . "$PROOT/libs/tui/term.sh"; . "$PROOT/libs/tui/progress.sh"
        TUI_TTY=1; TUI_COLS="${WANT_COLS}"
        tui_progress_open 1 "T"; tui_progress_step a; tui_progress_close
    ' 2>&1 | _pstrip)"
    # "Did that hang or is it just slow" is the question a bar exists to
    # answer, and the answer is worth keeping after it finishes.
    assert_ok grep -qE 'done.*1 in [0-9]+s' <<<"$out"
}

# --- steps that did not work ------------------------------------------------------

#[test]
it_counts_a_failed_step_as_progress() {
    TUI_TTY=0
    local out
    out="$(tui_progress_open 3 "T"; tui_progress_step a; tui_progress_fail b; tui_progress_step c; tui_progress_close)"
    # The run is as far along either way.
    assert_ok grep -q 'done, 3' <<<"$out"
}

#[test]
it_says_how_many_failed() {
    TUI_TTY=0
    local out
    out="$(tui_progress_open 3 "T"; tui_progress_fail a; tui_progress_fail b; tui_progress_step c; tui_progress_close)"
    # A fourteen-package fetch reporting fourteen successes when three of them
    # failed is the failure this exists to prevent.
    assert_ok grep -q '2 failed' <<<"$out"
}

#[test]
it_says_nothing_about_failures_when_there_were_none() {
    TUI_TTY=0
    local out
    out="$(tui_progress_open 2 "T"; tui_progress_step a; tui_progress_step b; tui_progress_close)"
    assert_fails grep -q 'failed' <<<"$out"
}

#[test]
it_names_the_step_that_failed() {
    TUI_TTY=0
    local out
    out="$(tui_progress_open 2 "T"; tui_progress_fail "linux-firmware"; tui_progress_close)"
    assert_ok grep -q 'linux-firmware' <<<"$out"
    assert_ok grep -q 'failed'         <<<"$out"
}

#[test]
it_forgets_the_failures_of_the_previous_run() {
    TUI_TTY=0
    local out
    out="$(tui_progress_open 1 "A"; tui_progress_fail x; tui_progress_close)"
    assert_ok grep -q '1 failed' <<<"$out"
    out="$(tui_progress_open 1 "B"; tui_progress_step y; tui_progress_close)"
    assert_fails grep -q 'failed' <<<"$out"
}

#[test]
it_ignores_a_failure_with_no_run_open() {
    TUI_TTY=0
    local out; out="$(tui_progress_fail "orphan")"
    assert_eq "$out" ""
}

# --- counting in bytes ---------------------------------------------------------
#
# A transfer is progress whose size is known and whose position can be
# measured, so it belongs here. What it is not is a step count: a finished
# image closed with `done 1236641792 in 412s`, which is the byte total read
# out as a tally of things done.

#[test]
it_reads_a_byte_count_the_way_somebody_does() {
    assert_eq "$(tui_bytes 0)"          "0 B"
    assert_eq "$(tui_bytes 1)"          "1 B"
    assert_eq "$(tui_bytes 1023)"       "1023 B"
    assert_eq "$(tui_bytes 1024)"       "1 KiB"
    assert_eq "$(tui_bytes 1048575)"    "1023 KiB"
    assert_eq "$(tui_bytes 1048576)"    "1 MiB"
    assert_eq "$(tui_bytes 1073741823)" "1023 MiB"
    assert_eq "$(tui_bytes 1073741824)" "1.0 GiB"
    assert_eq "$(tui_bytes 1236641792)" "1.1 GiB"
    # The disk sizes this is actually reached for. Stopping at GiB reported a
    # two terabyte drive as `2048.0 GiB`.
    assert_eq "$(tui_bytes 1099511627775)" "1023.9 GiB"
    assert_eq "$(tui_bytes 1099511627776)" "1.0 TiB"
    assert_eq "$(tui_bytes 2199023255552)" "2.0 TiB"
}

#[test]
it_treats_a_count_that_is_not_a_number_as_nothing() {
    # The size comes from `stat` on a file that may not exist yet, so this
    # gets an empty string in the ordinary course of things.
    assert_eq "$(tui_bytes "")"      "0 B"
    assert_eq "$(tui_bytes "nope")"  "0 B"
    assert_eq "$(tui_bytes "-5")"    "0 B"
}

#[test]
it_closes_a_byte_run_with_a_size_rather_than_a_tally() {
    local out
    out="$(tui_progress_open 1236641792 "" bytes
           tui_progress_set 1236641792
           tui_progress_close)"
    assert_contains "$out" "1.1 GiB"
    # The number itself is what used to land there, read out as a tally of
    # things done.
    assert_fails grep -q '1236641792' <<<"$out"
}

#[test]
it_closes_a_step_run_with_a_tally_as_it_always_did() {
    local out
    out="$(tui_progress_open 14 ""; tui_progress_step a; tui_progress_close)"
    assert_contains "$out" "done, 1 in"
}

#[test]
it_logs_a_byte_run_in_sizes_when_there_is_no_terminal() {
    local out
    out="$(tui_progress_open 1048576 "" bytes; tui_progress_set 524288 "half")"
    assert_contains "$out" "512 KiB"
    assert_contains "$out" "1 MiB"
    assert_fails grep -q '524288' <<<"$out"
}

#[test]
it_takes_anything_that_is_not_bytes_as_steps() {
    # A bar that refused to draw over a misspelled unit would be worse than
    # one that counts.
    local out
    out="$(tui_progress_open 1048576 "" "Bytes"; tui_progress_set 524288; tui_progress_close)"
    assert_contains "$out" "524288"
}

#[test]
it_forgets_the_unit_of_the_previous_run() {
    local out
    tui_progress_open 1024 "" bytes >/dev/null; tui_progress_close >/dev/null
    out="$(tui_progress_open 10 ""; tui_progress_set 4; tui_progress_close)"
    assert_contains "$out" "done, 4 in"
    assert_fails grep -q 'KiB' <<<"$out"
}

# --- stopping, which is not finishing ------------------------------------------

#[test]
it_says_stopped_rather_than_done_when_a_run_gives_up() {
    local out
    out="$(tui_progress_open 1048576 "" bytes; tui_progress_set 262144; tui_progress_stop "the connection went")"
    # `done` on a transfer that failed is the bar telling the reader the
    # opposite of what happened.
    assert_fails grep -q 'done' <<<"$out"
    assert_contains "$out" "stopped at 256 KiB"
    assert_contains "$out" "the connection went"
}

#[test]
it_ignores_a_stop_with_no_run_open() {
    tui_progress_open 4 "" >/dev/null; tui_progress_close >/dev/null
    assert_empty "$(tui_progress_stop "nothing is open")"
}

#[test]
it_will_not_close_a_run_it_already_stopped() {
    local out
    out="$(tui_progress_open 4 ""; tui_progress_stop "gave up"; tui_progress_close)"
    assert_contains "$out" "stopped"
    assert_fails grep -q 'done' <<<"$out"
}

#[test]
it_does_not_close_a_byte_run_as_done_when_a_step_failed() {
    # `tui_progress_fail` is one step of many failing, not the run giving up.
    # In a byte run it adds a byte to the transfer and reports a step tally,
    # and the run is still open afterwards. The header used to teach this call
    # for a failed transfer, which is the call that defeats the feature.
    local out
    out="$(tui_progress_open 1048576 "" bytes
           tui_progress_set 524288
           tui_progress_fail "the transfer stopped"
           tui_progress_close)"
    # It counted a step, so the byte count moved by one.
    assert_contains "$out" "1 failed"
    # And this is what the header was teaching: it still says done.
    assert_contains "$out" "done"
}

#[test]
it_says_stopped_for_the_same_case_the_header_now_shows() {
    local out
    out="$(tui_progress_open 1048576 "" bytes
           tui_progress_set 524288
           tui_progress_stop "the transfer stopped")"
    assert_contains "$out" "stopped at 512 KiB"
    assert_fails grep -q 'done' <<<"$out"
    assert_fails grep -q 'failed' <<<"$out"
}
