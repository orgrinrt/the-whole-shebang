#!/usr/bin/env bash
# Tests for the action register.
#
# Every test rebuilds the register from empty, because the register is global
# state and a test that inherited a previous one's actions would pass for the
# wrong reason and fail whenever the file was reordered.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/action.sh"

# A small register, the shape a menu actually builds.
fixture() {
    tui_action_reset
    tui_action_add section-prev main   "to the previous section" "bracket-left ctrl-up"
    tui_action_add section-next main   "to the next section"     "bracket-right ctrl-down"
    tui_action_add search       main   "search the list"         "slash"
    tui_action_add help         main   "this"                    "question"
    tui_action_add quit         main   "back"                    "q"
    tui_action_add search-leave filter "leave the search"        "esc"
    tui_action_add about        palette "what this tool is for"  ""
}

# --- naming a key ------------------------------------------------------------

#[test]
it_names_the_punctuation_a_layout_can_withhold() {
    # The whole reason the module exists: `[` is AltGr+8 on a Finnish layout,
    # so it has to be nameable to be rebindable.
    assert_eq "$(tui_action_key_name '[')" "bracket-left"
    assert_eq "$(tui_action_key_name ']')" "bracket-right"
    assert_eq "$(tui_action_key_name '/')" "slash"
    assert_eq "$(tui_action_key_name '?')" "question"
    assert_eq "$(tui_action_key_name '\')" "backslash"
    assert_eq "$(tui_action_key_name '|')" "pipe"
    assert_eq "$(tui_action_key_name '$')" "dollar"
    assert_eq "$(tui_action_key_name '%')" "percent"
    assert_eq "$(tui_action_key_name '`')" "backtick"
    assert_eq "$(tui_action_key_name "'")" "apostrophe"
    assert_eq "$(tui_action_key_name '"')" "quote"
}

#[test]
it_leaves_a_key_that_already_has_a_name_alone() {
    # The reader already names these, and renaming them here would mean two
    # spellings for one key and a lookup that missed on whichever it was given.
    local k
    for k in up down left right pgup pgdn home end enter space tab esc \
             backspace ctrl-up ctrl-down shift-tab alt-x q a g s f; do
        assert_eq "$(tui_action_key_name "$k")" "$k"
    done
}

#[test]
it_round_trips_every_named_character() {
    # Every name in one table has to come back through the other, or a key line
    # prints a name where a character belongs and nobody can press what it says.
    local c
    for c in '/' '?' '[' ']' '\' ',' '.' '-' '+' '=' ':' ';' "'" '"' '*' '#' \
             '@' '%' '^' '&' '~' '<' '>' '(' ')' '{' '}' '!' '$' '|' '_' '`'; do
        assert_eq "$(tui_action_key_char "$(tui_action_key_name "$c")")" "$c"
    done
}

#[test]
it_prints_an_unnamed_key_as_itself() {
    assert_eq "$(tui_action_key_char ctrl-down)" "ctrl-down"
    assert_eq "$(tui_action_key_char pgup)" "pgup"
    assert_eq "$(tui_action_key_char q)" "q"
}

# --- building it -------------------------------------------------------------

#[test]
it_starts_empty_and_resets_to_empty() {
    fixture
    assert_eq "$(tui_action_ids | wc -l | tr -d ' ')" "7"
    tui_action_reset
    assert_eq "$(tui_action_ids | wc -l | tr -d ' ')" "0"
    assert_eq "${#TUI_ACTION_ID[@]}" "0"
}

#[test]
it_keeps_what_it_was_told() {
    fixture
    assert_eq "$(tui_action_label section-next)" "to the next section"
    assert_eq "$(tui_action_scope section-next)" "main"
    assert_eq "$(tui_action_keys section-next)"  "bracket-right ctrl-down"
    assert_eq "$(tui_action_scope about)" "palette"
    assert_eq "$(tui_action_keys about)"  ""
}

#[test]
it_refuses_an_action_with_no_id() {
    tui_action_reset
    assert_fails tui_action_add '' main 'nameless' 'x'
    assert_eq "${#TUI_ACTION_ID[@]}" "0"
}

#[test]
it_refuses_a_scope_that_is_not_one_of_the_three() {
    # A typo in a scope is invisible otherwise: the action registers, `?` never
    # lists it, and nothing anywhere says why.
    tui_action_reset
    assert_fails tui_action_add thing menu 'wrong scope' 'x'
    assert_fails tui_action_add thing '' 'no scope' 'x'
    assert_fails tui_action_add thing Main 'wrong case' 'x'
    assert_eq "${#TUI_ACTION_ID[@]}" "0"
}

#[test]
it_replaces_rather_than_duplicates_on_a_second_add() {
    fixture
    tui_action_add quit main "quit for real" "q ctrl-c"
    assert_eq "$(tui_action_ids | wc -l | tr -d ' ')" "7"
    assert_eq "$(tui_action_label quit)" "quit for real"
    assert_eq "$(tui_action_keys quit)"  "q ctrl-c"
}

#[test]
it_fails_every_read_of_an_id_that_is_not_there() {
    fixture
    assert_fails tui_action_label nope
    assert_fails tui_action_scope nope
    assert_fails tui_action_keys nope
    assert_fails tui_action_handler nope
    assert_fails tui_action_bind nope 'x'
}

# --- rebinding ---------------------------------------------------------------

#[test]
it_rebinds_by_id_and_the_old_key_stops_working() {
    # The point of the whole module, tested end to end: somebody on a layout
    # that cannot produce `[` points the action at a key they can press.
    fixture
    assert_eq "$(tui_action_for main '[')" "section-prev"
    tui_action_bind section-prev "ctrl-up"
    assert_eq "$(tui_action_for main 'ctrl-up')" "section-prev"
    assert_fails tui_action_for main '['
}

#[test]
it_replaces_the_binding_rather_than_adding_to_it() {
    # An additive rebind leaves the default in place beside the new key, which
    # is how a rebind ends up not being one.
    fixture
    tui_action_bind section-next "f2"
    assert_eq "$(tui_action_keys section-next)" "f2"
    assert_fails tui_action_for main ']'
}

#[test]
it_lets_an_action_be_unbound_entirely() {
    fixture
    tui_action_bind help ""
    assert_eq "$(tui_action_keys help)" ""
    assert_fails tui_action_for main '?'
    # Still reachable by name, which is the difference between unbound and gone.
    assert_eq "$(tui_action_search help | head -1)" "help"
}

# --- looking one up ----------------------------------------------------------

#[test]
it_finds_an_action_by_the_raw_key_or_by_its_name() {
    # The loop has the raw key and a config file has the name. Refusing either
    # would only mean every caller converting first.
    fixture
    assert_eq "$(tui_action_for main '[')"            "section-prev"
    assert_eq "$(tui_action_for main 'bracket-left')" "section-prev"
    assert_eq "$(tui_action_for main '/')"            "search"
    assert_eq "$(tui_action_for main 'slash')"        "search"
    assert_eq "$(tui_action_for main 'q')"            "quit"
}

#[test]
it_finds_an_action_by_any_of_its_keys() {
    fixture
    assert_eq "$(tui_action_for main 'bracket-right')" "section-next"
    assert_eq "$(tui_action_for main 'ctrl-down')"     "section-next"
}

#[test]
it_keeps_the_scopes_apart() {
    # `esc` means leave-the-search in the filter and nothing in the main scope.
    # One namespace would make every filter key a main key too.
    fixture
    assert_eq "$(tui_action_for filter 'esc')" "search-leave"
    assert_fails tui_action_for main 'esc'
    assert_fails tui_action_for filter '/'
}

#[test]
it_finds_nothing_for_a_key_nobody_bound() {
    fixture
    assert_fails tui_action_for main 'z'
    assert_fails tui_action_for main 'f7'
    assert_fails tui_action_for main ''
    assert_fails tui_action_for '' 'q'
    assert_fails tui_action_for nosuchscope 'q'
}

#[test]
it_does_not_match_a_key_that_is_only_part_of_a_binding() {
    # `bracket-right ctrl-down` is two keys, not one string. A substring match
    # here would have `ctrl` reach an action nobody bound it to.
    fixture
    assert_fails tui_action_for main 'ctrl'
    assert_fails tui_action_for main 'bracket'
    assert_fails tui_action_for main 'bracket-right ctrl-down'
}

# --- conflicts ---------------------------------------------------------------

#[test]
it_reports_nothing_when_no_two_actions_share_a_key() {
    fixture
    assert_fails tui_action_conflicts
    assert_eq "$(tui_action_conflicts)" ""
}

#[test]
it_names_a_key_two_actions_answer_to() {
    fixture
    tui_action_add other main "something else" "slash"
    assert_ok tui_action_conflicts
    assert_eq "$(tui_action_conflicts)" "main slash search other"
}

#[test]
it_does_not_call_the_same_key_in_two_scopes_a_conflict() {
    # `esc` in the filter and `esc` in the main scope are two different keys as
    # far as the dispatch is concerned, so reporting them would be noise that
    # trains somebody to ignore the real ones.
    fixture
    tui_action_add cancel main "back out" "esc"
    assert_fails tui_action_conflicts
}

# --- the key line ------------------------------------------------------------

#[test]
it_prints_a_key_line_of_characters_not_names() {
    # A key line saying `bracket-left` tells somebody the name of a key rather
    # than which key to press.
    fixture
    local line
    line="$(tui_action_lines main | grep 'previous section')"
    assert_eq "$line" "$(printf '[ ctrl-up\tto the previous section')"
}

#[test]
it_leaves_an_unbound_action_off_the_key_line() {
    fixture
    assert_eq "$(tui_action_lines palette)" ""
    assert_eq "$(tui_action_lines main | wc -l | tr -d ' ')" "5"
    assert_eq "$(tui_action_lines filter | wc -l | tr -d ' ')" "1"
}

#[test]
it_defaults_the_key_line_to_the_main_scope() {
    fixture
    assert_eq "$(tui_action_lines)" "$(tui_action_lines main)"
}

# --- the palette -------------------------------------------------------------

#[test]
it_matches_letters_that_are_not_next_to_each_other() {
    # What a palette is for: `sn` reaches `section-next` without anybody
    # knowing where the letters fall.
    fixture
    assert_eq "$(tui_action_search sn | head -1)" "section-next"
    assert_eq "$(tui_action_search sp | head -1)" "section-prev"
}

#[test]
it_ranks_the_tighter_match_first() {
    # `sea` is contiguous in `search` and scattered across `section-prev`, so
    # the one somebody meant comes first.
    fixture
    assert_eq "$(tui_action_search sea | head -1)" "search"
}

#[test]
it_matches_the_label_as_well_as_the_id() {
    fixture
    assert_eq "$(tui_action_search 'what this tool' | head -1)" "about"
}

#[test]
it_ignores_case_on_both_sides() {
    fixture
    tui_action_add Loud main "SHOUTING" "L"
    assert_eq "$(tui_action_search loud | head -1)" "Loud"
    assert_eq "$(tui_action_search SEARCH | head -1)" "search"
    assert_eq "$(tui_action_search shouting | head -1)" "Loud"
}

#[test]
it_matches_everything_on_an_empty_query() {
    # The palette's first frame, before anybody has typed. An empty list there
    # reads as a palette that found nothing.
    fixture
    assert_eq "$(tui_action_search '' | wc -l | tr -d ' ')" "7"
    assert_eq "$(tui_action_search '' | head -1)" "section-prev"
}

#[test]
it_matches_nothing_when_the_letters_are_not_in_order() {
    fixture
    assert_eq "$(tui_action_search zzz)" ""
    # The letters are all there, in the wrong order, which is not a match.
    assert_eq "$(tui_action_search 'txen-noitces')" ""
}

#[test]
it_searches_every_scope_including_the_unbound() {
    # A palette that searched only what had no key would be a list of
    # leftovers, and one that searched only what had a key would be a slower
    # way to press it.
    fixture
    assert_eq "$(tui_action_search about | head -1)" "about"
    assert_eq "$(tui_action_search leave | head -1)" "search-leave"
}

# --- running one -------------------------------------------------------------

_probe_ran=""
_probe() { _probe_ran="ran:$*"; }

#[test]
it_runs_an_action_that_carries_a_handler() {
    tui_action_reset
    tui_action_add probe main "a probe" "p" _probe
    _probe_ran=""
    tui_action_run probe one two
    assert_eq "$_probe_ran" "ran:one two"
}

#[test]
it_refuses_to_run_what_it_cannot() {
    tui_action_reset
    tui_action_add bare  main "the owner dispatches this one" "b"
    tui_action_add wrong main "names a function nobody defined" "w" _no_such_function
    # Three different nothings, and a palette that reported any of them as run
    # would be lying about the only thing it does.
    assert_fails tui_action_run nope
    assert_fails tui_action_run bare
    assert_fails tui_action_run wrong
    assert_fails tui_action_run ''
}

#[test]
it_reports_a_handlers_own_failure() {
    _fails() { return 3; }
    tui_action_reset
    tui_action_add boom main "fails on purpose" "b" _fails
    assert_fails tui_action_run boom
}

# --- the matcher itself ------------------------------------------------------

#[test]
it_prefers_a_letter_that_begins_a_word() {
    # Somebody typing two letters is typing initials. Without this, `sn` picks
    # whichever row was registered first, because the `n` of `section` is the
    # leftmost one in both `section-next` and `section-prev`.
    assert_eq "$(_tui_action_scan sn 'section-next' 1)" "2 0 9"
    assert_eq "$(_tui_action_scan sn 'section-next' 0)" "1 0 7"
}

#[test]
it_treats_the_string_start_and_every_separator_as_a_word_start() {
    assert_ok   _tui_action_boundary 'a-b c_d.e/f' 0
    assert_ok   _tui_action_boundary 'a-b c_d.e/f' 2
    assert_ok   _tui_action_boundary 'a-b c_d.e/f' 4
    assert_ok   _tui_action_boundary 'a-b c_d.e/f' 6
    assert_ok   _tui_action_boundary 'a-b c_d.e/f' 8
    assert_ok   _tui_action_boundary 'a-b c_d.e/f' 10
    assert_fails _tui_action_boundary 'a-b c_d.e/f' 1
    assert_fails _tui_action_boundary 'a-b c_d.e/f' 3
    assert_fails _tui_action_boundary 'abc' 2
}

#[test]
it_falls_back_when_preferring_a_word_start_strands_a_later_letter() {
    # `a` begins a word only at the very end here, and taking it leaves nothing
    # for the `b`. The plain leftmost pass finds the match, which is why both
    # passes are kept rather than only the better-ranking one.
    assert_fails _tui_action_scan ab 'xa b -a' 1
    assert_ok    _tui_action_scan ab 'xa b -a' 0
    assert_eq "$(_tui_action_fuzzy ab 'xa b -a')" "1 1 3"   # the b begins a word, the a does not
}

#[test]
it_finds_no_match_when_neither_pass_can() {
    assert_fails _tui_action_scan ab 'ba' 1
    assert_fails _tui_action_scan ab 'ba' 0
    assert_fails _tui_action_fuzzy ab 'ba'
    assert_fails _tui_action_fuzzy abc 'ab'
}

#[test]
it_matches_an_empty_needle_against_anything() {
    assert_eq "$(_tui_action_fuzzy '' 'whatever')" "0 0 0"
    assert_eq "$(_tui_action_fuzzy '' '')" "0 0 0"
}

#[test]
it_measures_the_run_from_the_first_letter_to_the_last() {
    # The span is what makes a tight match beat a scattered one, so an
    # off-by-one here quietly reverses the ranking.
    assert_eq "$(_tui_action_scan abc 'abc' 0)" "1 0 3"
    assert_eq "$(_tui_action_scan abc 'xxabc' 0)" "0 2 3"
    assert_eq "$(_tui_action_scan ac 'abbbc' 0)" "1 0 5"
}

#[test]
it_names_the_control_bytes_the_movement_keys_send() {
    # The reader hands these through raw. A raw byte is not something a config
    # file can name or a key line can print, so it gets a name here.
    assert_eq "$(tui_action_key_name $'\002')" "ctrl-b"
    assert_eq "$(tui_action_key_name $'\006')" "ctrl-f"
    assert_eq "$(tui_action_key_name $'\016')" "ctrl-n"
    assert_eq "$(tui_action_key_name $'\020')" "ctrl-p"
    # And they print as their name rather than as the byte, which would render
    # as nothing at all on a key line.
    assert_eq "$(tui_action_key_char ctrl-p)" "ctrl-p"
}

#[test]
it_reaches_an_action_bound_to_a_control_byte() {
    tui_action_reset
    tui_action_add up main "move up" "up ctrl-p"
    assert_eq "$(tui_action_for main $'\020')" "up"
    assert_eq "$(tui_action_for main 'ctrl-p')" "up"
    assert_fails tui_action_for main $'\016'
}
