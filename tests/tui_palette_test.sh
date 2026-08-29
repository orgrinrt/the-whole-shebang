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

# --- the loop ----------------------------------------------------------------
#
# It draws, so it needs the terminal modules. They were left out while only the
# row and the match list were tested, which is how the module's one public
# function ended up with no coverage at all: everything under it was tested and
# the thing a caller actually invokes was not.

. "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/key.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/modal.sh"

# Keys as the reader takes them off the input: bytes, not names.
_pal_run() { tui_palette_run "t" < <(printf '%b' "$1") > /dev/null 2>&1; }

#[test]
it_hands_back_the_id_that_was_chosen() {
    fixture
    assert_ok _pal_run 'quit\r'
    assert_eq "$TUI_PALETTE_CHOICE" "quit"
}

#[test]
it_searches_the_label_as_well_as_the_id() {
    # The label is what somebody remembers. `about` is reachable by its id and
    # by "what this tool is for", and a palette that only matched ids would be
    # a list of names nobody chose.
    fixture
    assert_ok _pal_run 'tool\r'
    assert_eq "$TUI_PALETTE_CHOICE" "about"
}

#[test]
an_empty_query_offers_everything_and_takes_the_first() {
    # The frame it opens on. Refusing to choose there would mean the palette
    # needing a query before it does anything, which is a search box rather
    # than a list.
    fixture
    assert_ok _pal_run '\r'
    assert_eq "$TUI_PALETTE_CHOICE" "section-prev"
}

#[test]
the_arrows_move_the_selection() {
    # Stated as a relation rather than as two ids, because which of the two
    # section rows ranks first is the matcher's business and would pin an
    # accident of it here. What movement has to do is land somewhere else.
    fixture
    _pal_run 'section\r'
    local first="$TUI_PALETTE_CHOICE"
    _pal_run 'section\033[B\r'
    local second="$TUI_PALETTE_CHOICE"
    assert_ne "$first" "$second"
    assert_ok grep -q '^section-' <<< "$second"
}

#[test]
moving_down_and_back_up_returns_to_where_it_started() {
    fixture
    _pal_run 'section\r'
    local first="$TUI_PALETTE_CHOICE"
    _pal_run 'section\033[B\033[A\r'
    assert_eq "$TUI_PALETTE_CHOICE" "$first"
}

#[test]
it_does_not_move_past_the_end_of_the_list() {
    # Off the end the selection would index nothing and the chosen id would be
    # empty, which reads to the caller exactly like a choice.
    fixture
    assert_ok _pal_run 'quit\033[B\033[B\033[B\r'
    assert_eq "$TUI_PALETTE_CHOICE" "quit"
}

#[test]
it_does_not_move_above_the_first_row() {
    fixture
    _pal_run 'section\r'
    local first="$TUI_PALETTE_CHOICE"
    assert_ok _pal_run 'section\033[A\033[A\r'
    assert_eq "$TUI_PALETTE_CHOICE" "$first"
}

#[test]
escape_chooses_nothing() {
    fixture
    TUI_PALETTE_CHOICE="left over"
    assert_fails _pal_run '\033'
    assert_empty "$TUI_PALETTE_CHOICE"
}

#[test]
rubbing_past_the_start_leaves_it() {
    # The way out is the way you came in, the same as the menu's own search.
    fixture
    assert_fails _pal_run '\177'
    assert_empty "$TUI_PALETTE_CHOICE"
}

#[test]
rubbing_out_a_letter_widens_the_list_again() {
    # `zq` matches nothing; one rub leaves `z`, which still matches nothing;
    # the second leaves nothing typed, and then enter takes the first row. If
    # backspace only left the palette this could not be written at all.
    fixture
    assert_ok _pal_run 'zq\177\177\r'
    assert_eq "$TUI_PALETTE_CHOICE" "section-prev"
}

#[test]
enter_on_a_query_that_matches_nothing_chooses_nothing() {
    # There is no row under the cursor, and the honest answer is to keep
    # waiting rather than hand back an empty id that reads as a choice.
    fixture
    assert_fails _pal_run 'zzzz\r\033'
    assert_empty "$TUI_PALETTE_CHOICE"
}

#[test]
a_space_is_part_of_the_query_rather_than_a_choice() {
    # The reader names it, so without an arm for it the space would fall
    # through to the printable check, which a name five characters long fails.
    fixture
    assert_ok _pal_run 'the previous\r'
    assert_eq "$TUI_PALETTE_CHOICE" "section-prev"
}

#[test]
running_out_of_input_chooses_nothing() {
    # A closed input is not a choice. It is what a caller sees when the
    # terminal goes away underneath it.
    fixture
    TUI_PALETTE_CHOICE="left over"
    assert_fails tui_palette_run "t" < /dev/null > /dev/null 2>&1
    assert_empty "$TUI_PALETTE_CHOICE"
}

#[test]
it_reaches_an_action_that_has_no_key_at_all() {
    # The whole reason it exists. `about` is in the palette scope and answers
    # to nothing, so if this could not be reached the palette would be a second
    # way to do what a key already does.
    fixture
    assert_fails tui_action_for main "" 
    assert_ok _pal_run 'about\r'
    assert_eq "$TUI_PALETTE_CHOICE" "about"
}

# --- the round trip a caller makes -------------------------------------------

#[test]
it_runs_nothing_itself() {
    # Stated in the module and worth pinning, because the menu leans on it: the
    # palette hands back an id and the one dispatch on the other side decides
    # what that means. A palette that ran what it could and left the rest would
    # be worse than one that runs nothing.
    fixture
    local ran=0
    _pal_handler() { ran=1; }
    tui_action_add mine palette "a thing with a handler" "" _pal_handler
    assert_ok _pal_run 'mine\r'
    assert_eq "$TUI_PALETTE_CHOICE" "mine"
    assert_eq "$ran" "0"
    unset -f _pal_handler
}

#[test]
what_it_hands_back_is_runnable_by_the_register() {
    # The other half of that: the id is enough, because the handler is in the
    # register beside it.
    fixture
    local ran=0
    _pal_handler() { ran=1; }
    tui_action_add mine palette "a thing with a handler" "" _pal_handler
    _pal_run 'mine\r'
    assert_ok tui_action_run "$TUI_PALETTE_CHOICE"
    assert_eq "$ran" "1"
    unset -f _pal_handler
}
