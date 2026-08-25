#!/usr/bin/env bash
# Tests for the menu.
#
# The drawing is not tested; the arithmetic under it is, exhaustively, because
# that is where a list quietly becomes unusable at sizes nobody tried. Every
# boundary of the viewport is pinned rather than reasoned about.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/key.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/menu.sh"

# heading, three entries, heading, two entries
fixture() {
    tui_menu_reset
    tui_menu_heading "Disk"          # 0
    tui_menu_entry a "A" ok          # 1
    tui_menu_entry b "B" done        # 2
    tui_menu_entry c "C" off         # 3
    tui_menu_heading "Boot"          # 4
    tui_menu_entry d "D" ok          # 5
    tui_menu_entry e "E" ok          # 6
}

# --- the list ----------------------------------------------------------------

#[test]
it_starts_empty_and_resets_to_empty() {
    fixture
    assert_eq "${#TUI_MENU_ID[@]}" "7"
    tui_menu_reset
    assert_eq "${#TUI_MENU_ID[@]}" "0"
    assert_empty "$TUI_MENU_CHOICE"
}

#[test]
it_keeps_an_unknown_state_rather_than_dropping_the_entry() {
    # A row that vanished because its state was misspelled is far harder to
    # notice than one shown in the wrong style.
    tui_menu_reset
    tui_menu_entry x "X" nonsense
    assert_eq "${#TUI_MENU_ID[@]}" "1"
    assert_eq "${TUI_MENU_STATE[0]}" "ok"
}

#[test]
it_defaults_the_state_when_none_is_given() {
    tui_menu_reset
    tui_menu_entry x "X"
    assert_eq "${TUI_MENU_STATE[0]}" "ok"
}

# --- landing -----------------------------------------------------------------

#[test]
it_will_not_land_on_a_heading() {
    fixture
    assert_fails _tui_menu_landable 0
    assert_fails _tui_menu_landable 4
}

#[test]
it_lands_on_every_kind_of_entry_including_unavailable_ones() {
    # `off` is selectable on purpose: being told why something will not run
    # beats a cursor that skips it for reasons the user cannot see.
    fixture
    assert_ok _tui_menu_landable 1
    assert_ok _tui_menu_landable 2
    assert_ok _tui_menu_landable 3
}

#[test]
it_starts_below_a_leading_heading() {
    fixture
    assert_eq "$(_tui_menu_first)" "1"
}

#[test]
it_reports_zero_when_there_is_nothing_to_land_on() {
    tui_menu_reset
    tui_menu_heading "only a heading"
    assert_eq "$(_tui_menu_first)" "0"
    assert_fails _tui_menu_landable 0
}

# --- stepping ----------------------------------------------------------------

#[test]
it_steps_over_a_heading() {
    fixture
    assert_eq "$(_tui_menu_step 3 1)" "5"
    assert_eq "$(_tui_menu_step 5 -1)" "3"
}

#[test]
it_stops_at_the_end_rather_than_wrapping() {
    # Wrapping in a list whose first rows are headings throws the cursor
    # somewhere nobody asked for.
    fixture
    assert_eq "$(_tui_menu_step 6 1)" "6"
    assert_eq "$(_tui_menu_step 1 -1)" "1"
}

#[test]
it_clamps_a_step_larger_than_the_list() {
    fixture
    assert_eq "$(_tui_menu_step 1 99)"  "1"
    assert_eq "$(_tui_menu_step 6 -99)" "6"
}

#[test]
it_moves_one_at_a_time_through_consecutive_entries() {
    # The control for the skipping tests: a function that always returned the
    # far end would satisfy several of them.
    fixture
    assert_eq "$(_tui_menu_step 1 1)" "2"
    assert_eq "$(_tui_menu_step 2 1)" "3"
    assert_eq "$(_tui_menu_step 6 -1)" "5"
}

# --- the viewport ------------------------------------------------------------

#[test]
it_leaves_the_window_alone_when_the_cursor_is_inside_it() {
    # The list must not jump under the reader on every keypress.
    fixture
    assert_eq "$(_tui_menu_window 3 4 2)" "2"
}

#[test]
it_scrolls_up_when_the_cursor_goes_above() {
    fixture
    assert_eq "$(_tui_menu_window 1 4 3)" "1"
}

#[test]
it_scrolls_down_by_the_minimum_when_the_cursor_goes_below() {
    fixture
    assert_eq "$(_tui_menu_window 6 4 0)" "3"
}

#[test]
it_never_scrolls_past_the_end() {
    fixture
    assert_eq "$(_tui_menu_window 6 4 99)" "3"
}

#[test]
it_never_scrolls_above_the_start() {
    fixture
    assert_eq "$(_tui_menu_window 0 4 -5)" "0"
}

#[test]
it_pins_the_window_to_zero_when_everything_fits() {
    # n=7, height=20. Without the clamp this computes a negative top and the
    # first rows fall off the screen on a large terminal, which is the size
    # nobody tests on.
    fixture
    assert_eq "$(_tui_menu_window 3 20 0)" "0"
}

#[test]
it_survives_a_height_of_zero() {
    # TUI_ROWS minus the chrome goes negative on a very short terminal, and a
    # zero height reaches a comparison that would otherwise loop forever.
    fixture
    assert_eq "$(_tui_menu_window 3 0 0)" "3"
}

#[test]
it_shows_the_cursor_row_at_every_height_from_one_upward() {
    # The property the whole viewport exists for, checked across the range
    # rather than at a couple of hand-picked points.
    fixture
    local h c top bad=""
    for h in 1 2 3 4 5 6 7; do
        for c in 1 2 3 5 6; do
            top="$(_tui_menu_window "$c" "$h" 0)"
            (( c >= top ))     || bad+="cursor $c above top $top at h=$h; "
            (( c <  top + h )) || bad+="cursor $c below window $top+$h; "
            (( top >= 0 ))     || bad+="negative top $top at h=$h; "
        done
    done
    # Collected rather than returned early, so the assertion names every
    # violation at once instead of only the first, and so the harness sees an
    # assertion at all: a loop that returns is a test that asserted nothing.
    assert_empty "$bad"
}

#[test]
it_is_safe_to_source_twice() {
    assert_ok . "${BASH_SOURCE[0]%/*}/../libs/tui/menu.sh"
}
