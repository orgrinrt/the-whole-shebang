#!/usr/bin/env bash
# Tests for the screen buffer.
#
# The whole module is one claim, that a frame writes only what changed, and the
# claim is a count. So the count is what these assert, against `TUI_SCREEN_WROTE`,
# which exists for no other reason: a test that could only check the bytes came
# out right would pass just as happily on the full redraw this replaced.
#
# `tui_is_tty` decides between two entirely different paths, so both are run.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/screen.sh"

# A terminal, as far as the module can tell. TUI_TTY is what tui_is_tty reads,
# and there is no terminal on a test runner, so it is set by hand.
on_a_terminal()  { TUI_TTY=1; tui_screen_invalidate; }
off_a_terminal() { TUI_TTY=0; tui_screen_invalidate; }

# One frame, its output captured and its escapes stripped.
frame() {
    local out; out="$("$@" 2>&1)"
    printf '%s' "$out" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'
}

three_rows() {
    tui_screen_begin
    tui_screen_put 1 "one"
    tui_screen_put 2 "two"
    tui_screen_put 3 "three"
    tui_screen_flush
}

# --- the count, which is the whole claim -------------------------------------

#[test]
it_writes_every_row_of_the_first_frame() {
    on_a_terminal
    three_rows >/dev/null
    assert_eq "$TUI_SCREEN_WROTE" "3"
}

#[test]
it_writes_nothing_at_all_when_nothing_changed() {
    # The case that pays for the module. Redrawing an identical frame is what
    # a menu does whenever a key did something that changed no row.
    on_a_terminal
    three_rows >/dev/null
    three_rows >/dev/null
    assert_eq "$TUI_SCREEN_WROTE" "0"
}

#[test]
it_writes_only_the_rows_that_moved() {
    # A cursor step changes the row it left and the row it arrived on, and
    # costs two rows rather than a screen. That is the number the module is
    # for, so it is the number asserted.
    on_a_terminal
    tui_screen_begin
    local i
    for i in $(seq 1 40); do tui_screen_put "$i" "row $i"; done
    tui_screen_flush >/dev/null
    assert_eq "$TUI_SCREEN_WROTE" "40"

    tui_screen_begin
    for i in $(seq 1 40); do tui_screen_put "$i" "row $i"; done
    tui_screen_put 7 "> row 7"
    tui_screen_put 8 "row 8 "
    tui_screen_flush >/dev/null
    assert_eq "$TUI_SCREEN_WROTE" "2"
}

#[test]
it_treats_a_colour_change_as_a_change() {
    # A selection moving is only ever a colour change, so a buffer that
    # compared visible text would leave the mark where it was.
    on_a_terminal
    tui_screen_begin; tui_screen_put 1 "row"; tui_screen_flush >/dev/null
    tui_screen_begin; tui_screen_put 1 $'\033[1mrow\033[0m'; tui_screen_flush >/dev/null
    assert_eq "$TUI_SCREEN_WROTE" "1"
}

#[test]
it_clears_a_row_that_this_frame_does_not_have() {
    # A list that got shorter leaves its old rows on screen otherwise, and a
    # row nobody wrote is the hardest kind of stale to notice, because it looks
    # exactly like a row somebody meant.
    on_a_terminal
    three_rows >/dev/null
    tui_screen_begin
    tui_screen_put 1 "one"
    tui_screen_flush >/dev/null
    assert_eq "$TUI_SCREEN_WROTE" "2"
    local out
    out="$(tui_screen_begin; tui_screen_put 1 "one"; tui_screen_flush)"
    assert_empty "$out"
}

#[test]
it_writes_everything_again_after_it_is_invalidated() {
    # What a modal, a subprocess or a resize leaves behind. The buffer cannot
    # know any of them happened, so the caller says so, and a frame that
    # skipped a row on the strength of a stale belief would leave whatever
    # overwrote it sitting there.
    on_a_terminal
    three_rows >/dev/null
    three_rows >/dev/null
    assert_eq "$TUI_SCREEN_WROTE" "0"
    tui_screen_invalidate
    three_rows >/dev/null
    assert_eq "$TUI_SCREEN_WROTE" "3"
}

#[test]
it_starts_a_frame_empty_rather_than_from_the_last_one() {
    # Otherwise a row that is not put this time keeps the value it had, and the
    # clearing above never happens.
    on_a_terminal
    three_rows >/dev/null
    tui_screen_begin
    tui_screen_put 2 "two"
    assert_empty "${_TUI_SCREEN_NEW[1]-}"
    assert_empty "${_TUI_SCREEN_NEW[3]-}"
}

# --- what actually comes out -------------------------------------------------

#[test]
it_positions_each_row_it_writes() {
    on_a_terminal
    local out; out="$(three_rows)"
    assert_ok grep -q $'\033\[1;1H' <<< "$out"
    assert_ok grep -q $'\033\[2;1H' <<< "$out"
    assert_ok grep -q $'\033\[3;1H' <<< "$out"
}

#[test]
it_clears_a_row_to_the_end_rather_than_padding_it() {
    # Padding to the width of the terminal costs that many bytes a row, which
    # on the console this exists for is most of what it is trying to avoid.
    on_a_terminal
    local out; out="$(three_rows)"
    assert_ok grep -q $'\033\[2K' <<< "$out"
    assert_fails grep -q '   ' <<< "$(frame three_rows)"
}

#[test]
it_writes_the_rows_in_order() {
    on_a_terminal
    assert_eq "$(frame three_rows)" "onetwothree"
}

# --- no terminal -------------------------------------------------------------

#[test]
it_prints_the_frame_a_line_at_a_time_with_no_terminal() {
    # A pipe or a log wants the rows and none of the positioning, the same as
    # everything else here that writes a control byte.
    off_a_terminal
    local out; out="$(three_rows)"
    assert_eq "$out" "$(printf 'one\ntwo\nthree')"
    assert_fails grep -q $'\033' <<< "$out"
}

#[test]
it_repeats_the_whole_frame_with_no_terminal() {
    # Damage tracking means nothing once the last frame has scrolled away, and
    # a second frame that printed only its changes would read as a list that
    # had lost most of its rows.
    off_a_terminal
    three_rows >/dev/null
    local out; out="$(three_rows)"
    assert_eq "$out" "$(printf 'one\ntwo\nthree')"
    assert_eq "$TUI_SCREEN_WROTE" "3"
}

# --- putting a row -----------------------------------------------------------

#[test]
it_refuses_a_row_that_is_not_a_row() {
    on_a_terminal
    tui_screen_begin
    assert_fails tui_screen_put 0 "above the first row"
    assert_fails tui_screen_put -1 "further above it"
    assert_fails tui_screen_put "" "no row at all"
    assert_fails tui_screen_put abc "not a number"
    assert_fails tui_screen_put 1.5 "not a whole one"
    assert_eq "${#_TUI_SCREEN_NEW[@]}" "0"
}

#[test]
it_takes_an_empty_row_as_a_row() {
    # A blank line between blocks is content, and dropping it would close the
    # gap the layout was counting on.
    on_a_terminal
    tui_screen_begin
    assert_ok tui_screen_put 2 ""
    tui_screen_put 1 "one"
    tui_screen_flush >/dev/null
    assert_eq "$TUI_SCREEN_WROTE" "2"
}

#[test]
it_leaves_a_gap_where_no_row_was_put() {
    on_a_terminal
    tui_screen_begin
    tui_screen_put 1 "one"
    tui_screen_put 5 "five"
    # Into a file rather than a command substitution, which forks, and the
    # count set inside a fork does not come back.
    local f; f="$(mktemp)"
    tui_screen_flush > "$f"
    assert_eq "$TUI_SCREEN_WROTE" "5"
    assert_ok grep -q $'\033\[5;1H' "$f"
    rm -f "$f"
}

#[test]
it_replaces_a_row_put_twice_in_one_frame() {
    on_a_terminal
    tui_screen_begin
    tui_screen_put 1 "first"
    tui_screen_put 1 "second"
    assert_eq "$(frame tui_screen_flush)" "second"
}

#[test]
it_flushes_an_empty_frame_without_complaint() {
    on_a_terminal
    tui_screen_begin
    assert_ok tui_screen_flush
    assert_eq "$TUI_SCREEN_WROTE" "0"
}

#[test]
it_is_safe_to_source_twice() {
    assert_ok . "${BASH_SOURCE[0]%/*}/../libs/tui/screen.sh"
}
