#!/usr/bin/env bash
# Tests for the palette.
#
# The loop needs a terminal, so what is tested here is everything under it: the
# row as it renders, and the bounding of the match list. Both are where a
# palette actually goes wrong, since a box that draws more rows than the screen
# has is the failure nobody sees on a large terminal.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/action.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/palette.sh"

fixture() {
    tui_action_reset
    tui_action_add section-prev main    "to the previous section" "bracket-left ctrl-up"
    tui_action_add section-next main    "to the next section"     "bracket-right"
    tui_action_add quit         main    "back"                    "q"
    tui_action_add about        palette "what this tool is for"   ""
}

# --- a row -------------------------------------------------------------------

#[test]
it_puts_the_keys_after_the_label() {
    # In front of the label they push every label to a different place, and the
    # label is what somebody is reading down the list for.
    fixture
    assert_eq "$(_tui_palette_row quit)" "back   (q)"
}

#[test]
it_prints_a_key_as_the_character_rather_than_the_name() {
    # This is where somebody learns a key exists, which is most of why the
    # palette is worth having beyond the searching. A row saying `bracket-left`
    # teaches them the name of a key instead of which key to press.
    fixture
    assert_eq "$(_tui_palette_row section-prev)" "to the previous section   ([ ctrl-up)"
}

#[test]
it_prints_a_row_for_an_action_with_no_key_at_all() {
    # The ones that are only reachable here. Leaving them out, or printing an
    # empty bracket after them, would both be worse than saying nothing.
    fixture
    assert_eq "$(_tui_palette_row about)" "what this tool is for"
}

#[test]
it_falls_back_to_the_id_when_an_action_has_no_label() {
    fixture
    tui_action_add bare main "" "b"
    assert_eq "$(_tui_palette_row bare)" "bare   (b)"
}

#[test]
it_refuses_a_row_for_an_action_that_is_not_there() {
    fixture
    assert_fails _tui_palette_row nope
}

# --- the match list ----------------------------------------------------------

#[test]
it_collects_the_matches_in_order() {
    fixture
    local -a hits=()
    _tui_palette_matches hits "sn"
    assert_eq "${hits[0]}" "section-next"
}

#[test]
it_shows_everything_before_anything_is_typed() {
    fixture
    local -a hits=()
    _tui_palette_matches hits ""
    assert_eq "${#hits[@]}" "4"
}

#[test]
it_comes_back_empty_rather_than_stale_when_nothing_matches() {
    # The array is the caller's, and a helper that left the last query's hits
    # in it would draw a list that has nothing to do with what was typed.
    fixture
    local -a hits=(stale rows here)
    _tui_palette_matches hits "zzzz"
    assert_eq "${#hits[@]}" "0"
}

#[test]
it_stops_at_the_row_budget() {
    # A box cannot be taller than the terminal, and nobody reads past the first
    # handful. Without the bound the box grows past the screen on a wide
    # register and the top of it scrolls away.
    tui_action_reset
    local i
    for i in $(seq 1 40); do tui_action_add "act-$i" main "action number $i" ""; done
    local -a hits=()
    TUI_PALETTE_ROWS=8
    _tui_palette_matches hits ""
    assert_eq "${#hits[@]}" "8"
    TUI_PALETTE_ROWS=3
    _tui_palette_matches hits ""
    assert_eq "${#hits[@]}" "3"
    TUI_PALETTE_ROWS=8
}

#[test]
it_keeps_a_list_shorter_than_the_budget_whole() {
    # The control for the test above: a bound that always returned its own
    # limit would satisfy that one.
    fixture
    local -a hits=()
    TUI_PALETTE_ROWS=8
    _tui_palette_matches hits ""
    assert_eq "${#hits[@]}" "4"
}

#[test]
it_is_safe_to_source_twice() {
    assert_ok . "${BASH_SOURCE[0]%/*}/../libs/tui/palette.sh"
}
