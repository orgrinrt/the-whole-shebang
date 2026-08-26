#!/usr/bin/env bash
# Tests for the menu.
#
# The drawing is not tested; the arithmetic under it is, exhaustively, because
# that is where a list quietly becomes unusable at sizes nobody tried. Every
# boundary of the viewport is pinned rather than reasoned about.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/key.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/layout.sh"
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
it_wraps_at_either_end_rather_than_stopping() {
    # A list is a ring. Stopping dead means the way to the bottom of a long
    # list is to hold a key down, and it makes the two ends feel like walls
    # rather than like the same place. The headings at either end are skipped
    # on the way round, so the cursor still lands somewhere it can rest.
    fixture
    assert_eq "$(_tui_menu_step 6 1)" "1"
    assert_eq "$(_tui_menu_step 1 -1)" "6"
}

#[test]
it_clamps_a_page_larger_than_the_list() {
    # A page does not wrap: paging past the end lands on the end, which is what
    # every list with a page key does, and a page that wrapped would lose the
    # reader's place entirely.
    fixture
    assert_eq "$(_tui_menu_step 1 99)"  "6"
    assert_eq "$(_tui_menu_step 6 -99)" "1"
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

# --- filtering ---------------------------------------------------------------

#[test]
it_shows_everything_when_the_filter_is_empty() {
    fixture; TUI_MENU_FILTER=""; tui_menu_refilter
    assert_eq "${#TUI_MENU_VIEW[@]}" "7"
}

#[test]
it_narrows_to_matching_entries() {
    fixture
    TUI_MENU_TEXT=(Disk Alpha Beta Gamma Boot Delta Epsilon)
    TUI_MENU_FILTER="delta"; tui_menu_refilter
    # Delta, plus the Boot heading it sits under.
    assert_eq "${#TUI_MENU_VIEW[@]}" "2"
}

#[test]
it_matches_without_regard_to_case() {
    fixture
    TUI_MENU_TEXT=(Disk Alpha Beta Gamma Boot Delta Epsilon)
    TUI_MENU_FILTER="DELTA"; tui_menu_refilter
    local n1="${#TUI_MENU_VIEW[@]}"
    TUI_MENU_FILTER="delta"; tui_menu_refilter
    assert_eq "${#TUI_MENU_VIEW[@]}" "$n1"
}

#[test]
it_searches_the_note_as_well_as_the_text() {
    # The note carries why a row is unavailable. Searching "not installed" to
    # find everything blocked on a missing package is the question people have.
    tui_menu_reset
    tui_menu_heading "Disk"
    tui_menu_entry a "Alpha" off "needs cryptsetup, which is not installed"
    tui_menu_entry b "Beta"  ok  "ready"
    TUI_MENU_FILTER="not installed"; tui_menu_refilter
    assert_eq "${#TUI_MENU_VIEW[@]}" "2"
}

#[test]
it_drops_a_heading_whose_entries_all_vanish() {
    # Otherwise filtering leaves a screen of section titles with nothing under
    # them, which reads as a broken list rather than a narrowed one.
    fixture
    TUI_MENU_TEXT=(Disk Alpha Beta Gamma Boot Delta Epsilon)
    TUI_MENU_FILTER="alpha"; tui_menu_refilter
    local i seen_boot=0
    for i in "${TUI_MENU_VIEW[@]}"; do [[ "$i" == "4" ]] && seen_boot=1; done
    assert_eq "$seen_boot" "0"
}

#[test]
it_keeps_a_heading_whose_entries_survive() {
    # The control for the heading rule: dropping every heading would satisfy
    # the test above.
    fixture
    TUI_MENU_TEXT=(Disk Alpha Beta Gamma Boot Delta Epsilon)
    TUI_MENU_FILTER="alpha"; tui_menu_refilter
    assert_eq "${TUI_MENU_VIEW[0]}" "0"
}

#[test]
it_can_match_nothing_at_all() {
    fixture
    TUI_MENU_FILTER="zzzz-no-such-thing"; tui_menu_refilter
    assert_eq "${#TUI_MENU_VIEW[@]}" "0"
}

#[test]
it_keeps_the_cursor_on_a_real_row_after_filtering() {
    # The view is renumbered by a filter, so a cursor held over from before it
    # would point at a different row, or past the end.
    fixture
    TUI_MENU_TEXT=(Disk Alpha Beta Gamma Boot Delta Epsilon)
    TUI_MENU_FILTER="epsilon"; tui_menu_refilter
    local c; c="$(_tui_menu_first)"
    assert_ok _tui_menu_landable "$c"
    (( c < ${#TUI_MENU_VIEW[@]} )) && assert_ok true || assert_ok false
}

#[test]
it_scrolls_against_the_filtered_length_not_the_full_one() {
    # A window clamped to the unfiltered count would scroll past the end of a
    # narrowed list and show blank rows.
    fixture
    TUI_MENU_TEXT=(Disk Alpha Beta Gamma Boot Delta Epsilon)
    TUI_MENU_FILTER="alpha"; tui_menu_refilter
    assert_eq "$(_tui_menu_window 0 4 0)" "0"
    assert_eq "$(_tui_menu_len)" "2"
}

#[test]
it_resets_the_filter_with_the_menu() {
    fixture
    TUI_MENU_FILTER="something"; tui_menu_refilter
    tui_menu_reset
    assert_empty "$TUI_MENU_FILTER"
    assert_eq "${#TUI_MENU_VIEW[@]}" "0"
}

# --- hiding what cannot be run -----------------------------------------------
#
# A recovery tool shows a lot of rows that do not apply to the machine it is
# on. Reading past them to find the three that do is the common case, so there
# is a key for it; and it is off by default, because a list quietly omitting
# rows reads as a list with rows missing.

#[test]
it_shows_everything_by_default() {
    tui_menu_reset
    tui_menu_heading "disk"
    tui_menu_entry a "runnable"     ok
    tui_menu_entry b "not runnable" off
    tui_menu_refilter
    assert_eq "${#TUI_MENU_VIEW[@]}" "3"
}

#[test]
it_hides_the_unavailable_when_asked() {
    tui_menu_reset
    tui_menu_heading "disk"
    tui_menu_entry a "runnable"     ok
    tui_menu_entry b "not runnable" off
    TUI_MENU_HIDE_OFF=1
    tui_menu_refilter
    # The heading and the one row that can run.
    assert_eq "${#TUI_MENU_VIEW[@]}" "2"
    TUI_MENU_HIDE_OFF=0
}

#[test]
it_drops_a_heading_whose_rows_all_went() {
    tui_menu_reset
    tui_menu_heading "disk"
    tui_menu_entry a "one" off
    tui_menu_entry b "two" off
    tui_menu_heading "boot"
    tui_menu_entry c "three" ok
    TUI_MENU_HIDE_OFF=1
    tui_menu_refilter
    # An empty section is noise. Only "boot" and its row survive.
    assert_eq "${#TUI_MENU_VIEW[@]}" "2"
    TUI_MENU_HIDE_OFF=0
}

#[test]
it_keeps_done_rows_when_hiding_the_unavailable() {
    tui_menu_reset
    tui_menu_heading "disk"
    tui_menu_entry a "already true" done
    tui_menu_entry b "cannot run"   off
    TUI_MENU_HIDE_OFF=1
    tui_menu_refilter
    # "done" is a thing that worked, not a thing that cannot run.
    assert_eq "${#TUI_MENU_VIEW[@]}" "2"
    TUI_MENU_HIDE_OFF=0
}

#[test]
it_combines_hiding_with_a_search() {
    tui_menu_reset
    tui_menu_heading "disk"
    tui_menu_entry a "wipe a disk"  ok
    tui_menu_entry b "wipe a stick" off
    tui_menu_entry c "check a disk" ok
    TUI_MENU_HIDE_OFF=1
    TUI_MENU_FILTER="wipe"
    tui_menu_refilter
    assert_eq "${#TUI_MENU_VIEW[@]}" "2"
    TUI_MENU_HIDE_OFF=0; TUI_MENU_FILTER=""
}

# --- the keys, listed once ------------------------------------------------------

#[test]
it_names_every_key_it_answers_to() {
    local out; out="$(tui_menu_keys)"
    assert_ok grep -q 'enter' <<<"$out"
    assert_ok grep -q '/'     <<<"$out"
    assert_ok grep -q '?'     <<<"$out"
    assert_ok grep -q 'q'     <<<"$out"
    assert_ok grep -q '^a'    <<<"$out"
}

#[test]
it_describes_every_key_it_lists() {
    # A key with no description is a key nobody learns.
    local key what bad=""
    while IFS=$'\t' read -r key what; do
        [[ -n "$key" ]] || continue
        [[ -n "$what" ]] || bad+="${key} "
    done < <(tui_menu_keys)
    assert_empty "$bad"
}

#[test]
it_lists_a_key_for_everything_the_loop_handles() {
    # The list and the loop drifting apart is how a key becomes undiscoverable.
    local src listed
    src="$(cat "${BASH_SOURCE[0]%/*}/../libs/tui/menu.sh")"
    listed="$(tui_menu_keys | cut -f1)"
    # Every single-character key the loop tests for has to appear in the list.
    local k bad=""
    for k in '/' '?' 'a'; do
        grep -qF "\"\$TUI_KEY\" == \"$k\"" <<<"$src" || continue
        grep -qF "$k" <<<"$listed" || bad+="${k} "
    done
    assert_empty "$bad"
}

# --- the panel on the right ------------------------------------------------------
#
# A wide terminal has room beside the list; a tall narrow one does not, and
# squeezing a panel into it costs the labels their width for nothing. The
# decision is the layout's, so it can be checked at widths without a terminal.

#[test]
it_shows_no_panel_when_nothing_was_added() {
    tui_menu_reset
    TUI_COLS=200
    assert_eq "$(_tui_menu_aside_width)" "0"
}

#[test]
it_shows_a_panel_on_a_wide_terminal() {
    tui_menu_reset
    tui_menu_aside "running from" "host"
    TUI_COLS=140
    assert_ok test "$(_tui_menu_aside_width)" -gt 0
}

#[test]
it_shows_no_panel_on_a_narrow_terminal() {
    tui_menu_reset
    tui_menu_aside "running from" "host"
    local c
    for c in 40 60 70; do
        TUI_COLS=$c
        # The list needs its width first. A panel here would take it.
        assert_eq "$(_tui_menu_aside_width)" "0"
    done
}

#[test]
it_never_gives_the_panel_room_the_list_needs() {
    tui_menu_reset
    tui_menu_aside "a" "b"
    local c w shown=0
    for c in 72 80 100 120 160 200; do
        TUI_COLS=$c
        w="$(_tui_menu_aside_width)"
        (( w == 0 )) && continue
        shown=1
        assert_ok test $(( c - w - 2 )) -ge 46
    done
    # Or the loop asserted nothing at all, which is how this first passed.
    assert_eq "$shown" "1"
}

#[test]
it_shows_no_panel_when_there_is_nothing_to_lay_one_out_with() {
    # menu works without layout loaded. Without it there is no way to know
    # whether a panel would fit, and guessing is how the list gets squeezed.
    local out
    out="$(bash -c '
        cd '"$PWD"'
        . lib/nutshell/init; . libs/tui/term.sh; . libs/tui/menu.sh
        tui_menu_reset; tui_menu_aside a b
        TUI_COLS=200; _tui_menu_aside_width')"
    assert_eq "$out" "0"
}

#[test]
it_holds_the_lines_it_was_given() {
    tui_menu_reset
    tui_menu_aside "running from" "host"
    tui_menu_aside "stick"        "not mounted"
    assert_eq "${#TUI_MENU_ASIDE[@]}" "2"
    assert_ok grep -q 'running from' <<<"${TUI_MENU_ASIDE[0]}"
    assert_ok grep -q 'host'         <<<"${TUI_MENU_ASIDE[0]}"
}

#[test]
it_takes_a_label_with_no_value_as_a_heading() {
    tui_menu_reset
    tui_menu_aside "Machine"
    assert_eq "${TUI_MENU_ASIDE[0]}" "$(printf 'Machine\t')"
}

#[test]
it_forgets_the_panel_on_reset() {
    tui_menu_reset
    tui_menu_aside "a" "b"
    tui_menu_reset
    assert_eq "${#TUI_MENU_ASIDE[@]}" "0"
}

#[test]
it_finds_a_row_by_the_name_it_is_called_by() {
    tui_menu_reset
    tui_menu_heading install
    tui_menu_entry iso-fetch     "Put an install image on the stick" ok
    tui_menu_entry stick-refresh "Freshen the stick from this machine" ok
    # The id is what a row is called everywhere else: it is what the command
    # line takes and what somebody has in their head. Searching `fe` for
    # `iso-fetch` found nothing, because only the label was searched.
    TUI_MENU_FILTER="fe"
    tui_menu_refilter
    local found=""
    local i
    for i in "${TUI_MENU_VIEW[@]}"; do
        [[ "${TUI_MENU_STATE[$i]}" == "heading" ]] && continue
        found="${found}${TUI_MENU_ID[$i]} "
    done
    assert_eq "$found" "iso-fetch "
    TUI_MENU_FILTER=""
}

#[test]
it_still_finds_a_row_by_its_label_and_its_note() {
    tui_menu_reset
    tui_menu_heading install
    tui_menu_entry aaa "Put an install image on the stick" ok "needs the network"
    TUI_MENU_FILTER="image"; tui_menu_refilter
    assert_eq "${#TUI_MENU_VIEW[@]}" "2"
    TUI_MENU_FILTER="network"; tui_menu_refilter
    assert_eq "${#TUI_MENU_VIEW[@]}" "2"
    TUI_MENU_FILTER=""
}

# --- the cursor is a ring ----------------------------------------------------
#
# Stopping dead at the ends means the way to the bottom of a long list is to
# hold a key down, and it makes the top and the bottom feel like walls rather
# than like the same place.

_menu_two_sections() {
    tui_menu_reset
    tui_menu_heading a
    tui_menu_entry one   One   ok ""
    tui_menu_entry two   Two   ok ""
    tui_menu_heading b
    tui_menu_entry three Three ok ""
    tui_menu_entry four  Four  ok ""
    tui_menu_refilter
}

#[test]
it_wraps_from_the_first_row_to_the_last() {
    _menu_two_sections
    assert_eq "$(_tui_menu_step 1 -1)" "5"
}

#[test]
it_wraps_from_the_last_row_to_the_first() {
    _menu_two_sections
    assert_eq "$(_tui_menu_step 5 1)" "1"
}

#[test]
it_skips_a_heading_on_the_way_round() {
    # Wrapping must not land on a heading, which is not landable, and the
    # heading is exactly what sits at either end of the ring.
    _menu_two_sections
    assert_eq "$(_tui_menu_step 2 1)" "4"
    assert_eq "$(_tui_menu_step 4 -1)" "2"
}

#[test]
it_stays_put_when_nothing_is_landable() {
    # A list of nothing but headings has no ring to go round, and a wrap that
    # searches forever is a hang.
    tui_menu_reset
    tui_menu_heading a
    tui_menu_heading b
    tui_menu_refilter
    assert_eq "$(_tui_menu_step 0 1)" "0"
    assert_eq "$(_tui_menu_step 0 -1)" "0"
}

#[test]
it_does_not_wrap_a_page() {
    # Paging past the end lands on the end, which is what every list with a
    # page key does. A page that wrapped would lose the reader's place.
    _menu_two_sections
    assert_eq "$(_tui_menu_step 1 10)" "5"
    assert_eq "$(_tui_menu_step 5 -10)" "1"
}

#[test]
it_never_lands_a_page_on_a_heading() {
    _menu_two_sections
    local i
    for i in 1 2 4 5; do
        assert_ok _tui_menu_landable "$(_tui_menu_step "$i" 3)"
        assert_ok _tui_menu_landable "$(_tui_menu_step "$i" -3)"
    done
}

# --- moving by section -------------------------------------------------------

#[test]
it_moves_down_to_the_top_of_the_next_section() {
    _menu_two_sections
    assert_eq "$(_tui_menu_section_step 1 1)" "4"
    assert_eq "$(_tui_menu_section_step 2 1)" "4"
}

#[test]
it_moves_up_to_the_top_of_this_section_first() {
    # What every editor's paragraph movement does, and what a reader expects
    # from a key that means back a section.
    _menu_two_sections
    assert_eq "$(_tui_menu_section_step 2 -1)" "1"
    assert_eq "$(_tui_menu_section_step 5 -1)" "4"
}

#[test]
it_moves_up_to_the_previous_section_when_already_at_the_top() {
    _menu_two_sections
    assert_eq "$(_tui_menu_section_step 4 -1)" "1"
}

#[test]
it_wraps_by_section_too() {
    _menu_two_sections
    assert_eq "$(_tui_menu_section_step 4 1)" "1"
    assert_eq "$(_tui_menu_section_step 1 -1)" "4"
}

#[test]
it_stays_put_moving_by_section_in_a_list_with_none() {
    tui_menu_reset
    tui_menu_entry x X ok ""
    tui_menu_entry y Y ok ""
    tui_menu_refilter
    assert_eq "$(_tui_menu_section_step 0 1)" "0"
    assert_eq "$(_tui_menu_section_step 0 -1)" "0"
}

#[test]
it_moves_by_section_over_the_filtered_view() {
    # The view is what the reader sees, so section movement has to be over it
    # and not over the rows underneath.
    _menu_two_sections
    TUI_MENU_FILTER="Th"
    tui_menu_refilter
    local first; first="$(_tui_menu_first)"
    assert_eq "$(_tui_menu_section_step "$first" 1)" "$first"
    TUI_MENU_FILTER=""
    tui_menu_refilter
}

# --- what the terminal sends -------------------------------------------------

#[test]
it_names_a_modified_arrow() {
    assert_eq "$(_tui_key_from_csi '1;2A')" "shift-up"
    assert_eq "$(_tui_key_from_csi '1;5B')" "ctrl-down"
    assert_eq "$(_tui_key_from_csi '1;3C')" "alt-right"
}

#[test]
it_still_names_a_plain_arrow() {
    assert_eq "$(_tui_key_from_csi 'A')" "up"
    assert_eq "$(_tui_key_from_csi 'B')" "down"
}

#[test]
it_reads_a_modifier_it_does_not_know_as_the_arrow_itself() {
    # A key nobody named should move the cursor rather than do nothing.
    assert_eq "$(_tui_key_from_csi '1;9A')" "up"
}

#[test]
it_does_not_fold_a_modified_arrow_into_plain_motion() {
    # `tui_key_motion` folds the arrows and the vi keys together. A modified
    # one has to come out the other side intact or the menu cannot tell it
    # from the plain one.
    TUI_KEY="ctrl-down"
    assert_eq "$(tui_key_motion)" "ctrl-down"
    TUI_KEY="down"
    assert_eq "$(tui_key_motion)" "down"
}
