#!/usr/bin/env bash
# Tests for the run board.
#
# The board is read by somebody who looked away for an hour, so what is pinned
# is that the headline counts agree with the rows, the estimate of what is left
# uses the steps' own estimates first and the finished mean for the rest, and a
# wrong state is refused rather than shown.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/layout.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/table.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/board.sh"

_b() {
    tui_board_reset
    tui_board_add a "arvo: hash" 60
    tui_board_add b "kaski: crust"
    tui_board_add c "huurre: cull" 30
    tui_board_add d "kirjo: parse"
}

#[test]
it_counts_states_and_estimates_what_is_left() {
    _b
    tui_board_set a done 100
    tui_board_set b skip "" "no toolchain"
    # c by its own estimate, d by the mean of what finished.
    assert_eq "$(tui_board_left)" "130"
    assert_eq "$(tui_board_count done)" "1"
    assert_eq "$(tui_board_count pending)" "2"
}

#[test]
it_shows_every_step_and_a_headline_that_agrees() {
    _b
    tui_board_set a done 100 "ok"
    tui_board_set b fail 12 "exit 101"
    local out; out="$(tui_board_show stack)"
    assert_contains "$out" "== stack: 2 of 4 over (1 done, 0 skipped, 1 failed)"
    assert_contains "$out" "kaski: crust"
    assert_contains "$out" "exit 101"
    assert_contains "$out" "1m40s"
    assert_eq "$(printf '%s\n' "$out" | grep -c 'pending')" "2"
}

#[test]
it_refuses_a_state_or_a_step_it_does_not_know() {
    _b
    tui_board_set a finished 2>/dev/null; assert_eq "$?" "2"
    tui_board_set zz done 2>/dev/null; assert_eq "$?" "2"
    assert_eq "$(tui_board_count pending)" "4"
}

#[test]
it_writes_times_the_way_a_person_reads_them() {
    assert_eq "$(tui_board_hms 9)" "9s"
    assert_eq "$(tui_board_hms 247)" "4m07s"
    assert_eq "$(tui_board_hms 3720)" "1h02m"
}
