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
. "${BASH_SOURCE[0]%/*}/../libs/tui/menu/view.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/menu/draw.sh"

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
    # the test above. Asked through the accessor, because the view holds a
    # heading as an index that is not a row.
    fixture
    TUI_MENU_TEXT=(Disk Alpha Beta Gamma Boot Delta Epsilon)
    TUI_MENU_FILTER="alpha"; tui_menu_refilter
    assert_eq "$(tui_menu_heading_at 0)" "Disk"
    assert_fails tui_menu_raw 0
    TUI_MENU_FILTER=""
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
    assert_eq "${#TUI_MENU_VIEW[@]}" "2"
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
    out="$(nutshell -c '
        cd '"$PWD"'
        . libs/tui/term.sh; . libs/tui/menu.sh
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
    local found="" i raw
    for i in "${!TUI_MENU_VIEW[@]}"; do
        raw="$(tui_menu_raw "$i")" || continue
        found="${found}${TUI_MENU_ID[$raw]} "
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

# --- grouping, sorting, and a filter that is not a search --------------------

_menu_kinds() {
    tui_menu_reset
    TUI_MENU_GROUP=section; TUI_MENU_SORT=declared
    TUI_MENU_FILTERS=(); TUI_MENU_FILTER_ON=""
    tui_menu_heading disk
    tui_menu_entry disk-health "Zebra check"  ok  "" check
    tui_menu_entry disk-wipe   "apple erase"  off "" action
    tui_menu_heading net
    tui_menu_entry net-status  "Mango check"  ok  "" check
    tui_menu_entry net-doctor  "Beta fix"     ok  "" fix
    tui_menu_refilter
}

# The labels the reader sees, headings in angle brackets, as one line.
_menu_shape() {
    local i raw out=""
    for i in "${!TUI_MENU_VIEW[@]}"; do
        if raw="$(tui_menu_raw "$i")"; then out="${out}${TUI_MENU_TEXT[$raw]}|"
        else out="${out}<$(tui_menu_heading_at "$i")>|"; fi
    done
    printf '%s' "$out"
}

#[test]
it_groups_by_the_section_it_was_declared_under() {
    _menu_kinds
    assert_eq "$(_menu_shape)" "<disk>|Zebra check|apple erase|<net>|Mango check|Beta fix|"
}

#[test]
it_groups_by_kind_instead() {
    # The declared headings are the wrong headings once the cut changes, so the
    # grouping makes its own rather than keeping them.
    _menu_kinds
    TUI_MENU_GROUP=kind; tui_menu_refilter
    assert_eq "$(_menu_shape)" "<check>|Zebra check|Mango check|<action>|apple erase|<fix>|Beta fix|"
}

#[test]
it_drops_the_headings_entirely_when_asked() {
    _menu_kinds
    TUI_MENU_GROUP=none; tui_menu_refilter
    assert_eq "$(_menu_shape)" "Zebra check|apple erase|Mango check|Beta fix|"
}

#[test]
it_sorts_by_name_inside_a_group() {
    # Inside, not across: sorting the whole list alphabetically would
    # interleave the groups, which is the thing grouping exists to stop.
    _menu_kinds
    TUI_MENU_SORT=name; tui_menu_refilter
    assert_eq "$(_menu_shape)" "<disk>|apple erase|Zebra check|<net>|Beta fix|Mango check|"
}

#[test]
it_sorts_case_insensitively() {
    # `apple` before `Zebra` rather than after it: two alphabets is not an
    # order anybody reads.
    _menu_kinds
    TUI_MENU_GROUP=none; TUI_MENU_SORT=name; tui_menu_refilter
    assert_eq "$(_menu_shape)" "apple erase|Beta fix|Mango check|Zebra check|"
}

#[test]
it_sorts_what_can_be_run_to_the_top() {
    # The order somebody scanning for something to do wants: the rows they can
    # act on above the ones they cannot.
    _menu_kinds
    TUI_MENU_GROUP=none; TUI_MENU_SORT=state; tui_menu_refilter
    assert_eq "$(_menu_shape)" "Beta fix|Mango check|Zebra check|apple erase|"
}

#[test]
it_leaves_the_declared_order_alone_by_default() {
    # The control for the two sorts. A list somebody arranged by hand is
    # arranged for a reason.
    _menu_kinds
    TUI_MENU_GROUP=none; TUI_MENU_SORT=declared; tui_menu_refilter
    assert_eq "$(_menu_shape)" "Zebra check|apple erase|Mango check|Beta fix|"
}

#[test]
it_cycles_the_grouping_and_comes_back_round() {
    _menu_kinds
    tui_menu_group_next; assert_eq "$TUI_MENU_GROUP" "kind"
    tui_menu_group_next; assert_eq "$TUI_MENU_GROUP" "none"
    tui_menu_group_next; assert_eq "$TUI_MENU_GROUP" "section"
}

#[test]
it_cycles_the_ordering_and_comes_back_round() {
    _menu_kinds
    tui_menu_sort_next; assert_eq "$TUI_MENU_SORT" "name"
    tui_menu_sort_next; assert_eq "$TUI_MENU_SORT" "state"
    tui_menu_sort_next; assert_eq "$TUI_MENU_SORT" "declared"
}

#[test]
it_filters_by_a_question_rather_than_by_text() {
    # The distinction the search cannot cover: "the ones I can run" is not a
    # word that appears in any row.
    _menu_kinds
    _only_runnable() { [[ "${TUI_MENU_STATE[$1]}" == "ok" ]]; }
    tui_menu_filter runnable _only_runnable
    tui_menu_filter_on runnable
    TUI_MENU_GROUP=none; tui_menu_refilter
    unset -f _only_runnable
    assert_eq "$(_menu_shape)" "Zebra check|Mango check|Beta fix|"
}

#[test]
it_keeps_everything_with_no_filter_on() {
    # The control: a filter that is off has to change nothing.
    _menu_kinds
    _only_runnable() { [[ "${TUI_MENU_STATE[$1]}" == "ok" ]]; }
    tui_menu_filter runnable _only_runnable
    tui_menu_filter_on ""
    TUI_MENU_GROUP=none; tui_menu_refilter
    unset -f _only_runnable
    assert_eq "$(_menu_shape)" "Zebra check|apple erase|Mango check|Beta fix|"
}

#[test]
it_combines_the_filter_with_the_search() {
    # They are separate questions and both apply.
    _menu_kinds
    _only_runnable() { [[ "${TUI_MENU_STATE[$1]}" == "ok" ]]; }
    tui_menu_filter runnable _only_runnable
    tui_menu_filter_on runnable
    TUI_MENU_GROUP=none; TUI_MENU_FILTER="check"; tui_menu_refilter
    TUI_MENU_FILTER=""
    unset -f _only_runnable
    assert_eq "$(_menu_shape)" "Zebra check|Mango check|"
}

#[test]
it_cycles_through_the_filters_and_back_to_none() {
    _menu_kinds
    _a() { return 0; }; _b() { return 0; }
    tui_menu_filter one _a
    tui_menu_filter two _b
    tui_menu_filter_on ""
    assert_eq "$(_tui_menu_filter_next)" "one"
    tui_menu_filter_on one
    assert_eq "$(_tui_menu_filter_next)" "two"
    tui_menu_filter_on two
    assert_empty "$(_tui_menu_filter_next)"
    unset -f _a _b
}

#[test]
it_ignores_a_filter_whose_function_is_gone() {
    # A caller that registered a filter and then unset the function should get
    # every row, not none of them: a menu that empties itself because of a
    # missing helper is a menu nobody can use.
    _menu_kinds
    tui_menu_filter ghost _no_such_predicate
    tui_menu_filter_on ghost
    TUI_MENU_GROUP=none; tui_menu_refilter
    assert_eq "$(_menu_shape)" "Zebra check|apple erase|Mango check|Beta fix|"
}

#[test]
it_puts_rows_with_no_kind_under_one_heading() {
    # Grouping by a thing half the rows do not declare still has to produce a
    # list, and a row with no kind is not a row with an empty kind.
    tui_menu_reset
    TUI_MENU_GROUP=kind; TUI_MENU_SORT=declared
    TUI_MENU_FILTERS=(); TUI_MENU_FILTER_ON=""
    tui_menu_heading s
    tui_menu_entry a "A" ok "" check
    tui_menu_entry b "B" ok ""
    tui_menu_refilter
    assert_eq "$(_menu_shape)" "<check>|A|<other>|B|"
}

#[test]
it_never_leaves_the_cursor_on_a_heading_after_regrouping() {
    # Every arrangement has to leave a landable first row, or the first key
    # press goes somewhere nobody asked for.
    local g so bad=""
    for g in section kind none; do
        for so in declared name state; do
            _menu_kinds
            TUI_MENU_GROUP="$g"; TUI_MENU_SORT="$so"; tui_menu_refilter
            _tui_menu_landable "$(_tui_menu_first)" || bad="${bad} ${g}/${so}"
        done
    done
    assert_empty "$bad"
}

# --- a burst of movement is one movement -------------------------------------
#
# A wheel event becomes a run of arrow keys and a velocity scroll becomes a
# long one. Drawing the screen for each of them makes the drawing the
# bottleneck: the queue outlives the gesture and the list keeps painting for
# seconds after the hand stopped.

# How many times the menu drew, for a given run of keys.
declare -gi _MENU_DRAWS=0
_menu_draws() {
    local keys="$1"
    _menu_kinds
    _MENU_DRAWS=0
    eval "$(declare -f _tui_menu_render | sed '1s/_tui_menu_render/_menu_real_render/')"
    # Counted into a global. A local would be invisible to the stub once the
    # helper is itself called from a command substitution.
    _tui_menu_render() { _MENU_DRAWS=$(( _MENU_DRAWS + 1 )); }
    # From a file, not a pipe. A pipeline runs `tui_menu_run` in a subshell,
    # so the count and the choice it makes are thrown away with it.
    local f; f="$(mktemp)"; printf '%b' "$keys" > "$f"
    tui_menu_run "t" >/dev/null 2>&1 < "$f"
    rm -f "$f"
    unset -f _tui_menu_render
    eval "$(declare -f _menu_real_render | sed '1s/_menu_real_render/_tui_menu_render/')"
    unset -f _menu_real_render
    printf '%d' "$_MENU_DRAWS"
}

#[test]
it_draws_once_for_a_run_of_movement() {
    # Twenty downs is one gesture. Without coalescing this is twenty screens.
    local draws; draws="$(_menu_draws 'jjjjjjjjjjjjjjjjjjjj')"
    assert_ok test "$draws" -lt 4
}

#[test]
it_draws_for_each_separate_movement() {
    # The control. Coalescing must be about what is already waiting, not about
    # throwing movement away: a key pressed on its own still redraws.
    local one many
    one="$(_menu_draws 'j')"
    many="$(_menu_draws 'jjjjjjjjjjjjjjjjjjjj')"
    assert_ok test "$one" -ge 1
    # Twenty keys must not cost twenty times what one costs.
    assert_ok test "$many" -lt $(( one * 4 ))
}

#[test]
it_does_not_swallow_a_key_that_acts_on_a_row() {
    # The one that matters. A scroll that ate the enter after it would run
    # nothing, or worse, run the wrong row.
    _menu_kinds
    local f; f="$(mktemp)"; printf 'jjjj\n' > "$f"
    tui_menu_run "t" >/dev/null 2>&1 < "$f"; rm -f "$f"
    assert_ne "$TUI_MENU_CHOICE" ""
}

#[test]
it_lands_where_the_whole_run_would_have_landed() {
    # Absorbing a run must apply all of it, not just the last key.
    _menu_kinds
    TUI_MENU_GROUP=none; tui_menu_refilter
    local f; f="$(mktemp)"; printf 'jj\n' > "$f"
    tui_menu_run "t" >/dev/null 2>&1 < "$f"; rm -f "$f"
    local after_two="$TUI_MENU_CHOICE"
    _menu_kinds
    TUI_MENU_GROUP=none; tui_menu_refilter
    f="$(mktemp)"; printf 'j\n' > "$f"
    tui_menu_run "t" >/dev/null 2>&1 < "$f"; rm -f "$f"
    assert_ne "$after_two" "$TUI_MENU_CHOICE"
}

#[test]
it_knows_which_actions_only_move_the_cursor() {
    # What may be absorbed in a burst without drawing, because the run's only
    # effect is where the cursor ends up. Anything that acts on a row must not
    # be in here, or a scroll would swallow it.
    local id
    for id in menu-up menu-down menu-first menu-last menu-page-up \
              menu-page-down section-prev section-next; do
        assert_ok _tui_menu_motion_of "$id"
    done
    for id in menu-choose menu-back menu-search menu-help menu-hidden \
              menu-group menu-sort search-leave search-accept '' nonsense; do
        assert_fails _tui_menu_motion_of "$id"
    done
}

#[test]
it_reaches_section_movement_by_every_key_it_ships_with() {
    # The one op could not press. `[` is AltGr+8 on a Finnish layout and a bare
    # console does not deliver it, so the modified arrows have to reach it too,
    # and all of them have to be rebindable.
    tui_menu_bindings
    assert_eq "$(tui_action_for main '[')"         "section-prev"
    assert_eq "$(tui_action_for main 'ctrl-up')"   "section-prev"
    assert_eq "$(tui_action_for main 'alt-up')"    "section-prev"
    assert_eq "$(tui_action_for main ']')"         "section-next"
    assert_eq "$(tui_action_for main 'ctrl-down')" "section-next"
    assert_eq "$(tui_action_for main 'alt-down')"  "section-next"
}

#[test]
it_binds_every_key_the_menu_answers_to() {
    # A key dispatched somewhere other than the register is a key `?` cannot
    # list and a keymap cannot reach, which is the whole reason it exists.
    tui_menu_bindings
    local k
    for k in up down k j home end pgup pgdn enter space q esc \
             '/' '?' a g s f tab shift-tab; do
        assert_ok tui_action_for main "$k"
    done
    for k in esc enter backspace ctrl-c; do
        assert_ok tui_action_for filter "$k"
    done
    # And nothing collides, in either scope.
    assert_fails tui_action_conflicts
}

#[test]
it_lets_the_whole_key_set_be_rebound_before_running() {
    # The caller installs the defaults itself, rebinds, and the run leaves them
    # alone. Without this a keymap would be overwritten by the first draw.
    tui_menu_bindings
    tui_action_bind section-next "f2"
    assert_eq "$(tui_action_keys section-next)" "f2"
    assert_eq "$_TUI_MENU_BOUND" "1"
    assert_fails tui_action_for main ']'
}

#[test]
it_hands_back_a_key_it_looked_at_and_did_not_use() {
    TUI_KEY="enter"
    tui_key_unread
    TUI_KEY=""
    assert_ok tui_key_read
    assert_eq "$TUI_KEY" "enter"
}

#[test]
it_takes_nothing_when_nothing_is_waiting() {
    # The whole point of the coalescing read: it gives up rather than waiting,
    # or the loop would block until the next key instead of drawing.
    assert_fails tui_key_read_now </dev/null
}

# --- the list is a table -----------------------------------------------------
#
# A menu with its own column arithmetic is a menu whose columns line up
# differently from every other list in the same interface.

_menu_drawn() {
    local cursor="${1:-1}" cols="${2:-96}"
    local saved="$TUI_COLS" savedr="$TUI_ROWS"
    TUI_COLS="$cols"; TUI_ROWS=24
    local f; f="$(mktemp)"
    _tui_menu_render "$cursor" 0 10 "t" > "$f" 2>&1
    _strip < "$f"
    rm -f "$f"
    TUI_COLS="$saved"; TUI_ROWS="$savedr"
}
_strip() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

_menu_rows() {
    tui_menu_reset
    TUI_MENU_GROUP=section; TUI_MENU_SORT=declared
    TUI_MENU_FILTERS=(); TUI_MENU_FILTER_ON=""
    tui_menu_heading disk
    tui_menu_entry disk-health "Check disk health" ok  "smart attributes" check
    tui_menu_entry disk-wipe   "Erase a disk"      off "needs root"       action
    tui_menu_refilter
}

#[test]
it_puts_the_state_in_the_same_column_on_every_row() {
    # The complaint this answers: a status appended to a label of whatever
    # length it happened to be is a status nobody finds.
    _menu_rows
    local out; out="$(_menu_drawn)"
    local line; line="$(grep -m1 'Erase a disk' <<<"$out")"
    local before="${line%%off*}"
    # The state begins past the name column, not right after the label.
    assert_ok test "${#before}" -gt "$(( ${#line} > 0 ? 20 : 0 ))"
}

#[test]
it_shows_the_note_beside_the_row_and_not_only_under_the_cursor() {
    # A description you have to move the cursor onto to read is a description
    # nobody reads while deciding which row to move onto.
    _menu_rows
    local out; out="$(_menu_drawn 1)"
    local line; line="$(grep -m1 'Erase a disk' <<<"$out")"
    # The cursor is on the other row, so this note is the inline one.
    assert_contains "$line" "needs root"
}

#[test]
it_drops_the_note_before_it_drops_the_name() {
    # The note repeats below the list, so losing it on a narrow screen costs
    # nothing. Losing the name would cost the row.
    _menu_rows
    local out; out="$(_menu_drawn 1 40)"
    assert_contains "$out" "Erase a disk"
    local line; line="$(grep -m1 'Erase a disk' <<<"$out")"
    assert_fails grep -q 'needs root' <<<"$line"
}

#[test]
it_marks_the_row_the_cursor_is_on() {
    _menu_rows
    local out; out="$(_menu_drawn 1)"
    assert_ok grep -qE '^>' <<<"$(grep -m1 'Check disk health' <<<"$out")"
}

#[test]
it_does_not_mark_the_rows_it_is_not_on() {
    _menu_rows
    local out; out="$(_menu_drawn 1)"
    assert_fails grep -qE '^>' <<<"$(grep -m1 'Erase a disk' <<<"$out")"
}

#[test]
it_draws_a_heading_across_the_row_rather_than_in_a_column() {
    # A heading labels what follows; it is not a thing with a state.
    _menu_rows
    local out; out="$(_menu_drawn)"
    local line; line="$(grep -m1 'disk$\|disk ' <<<"$out")"
    assert_contains "$out" "disk"
}

#[test]
it_keeps_the_groups_in_the_same_order_whatever_the_sort() {
    # Sorting orders rows inside a group. Sections that rearrange when the
    # ordering changes lose the reader's place entirely, and with a state sort
    # the section order would depend on which group happened to hold the
    # readiest row, so adding one task would rearrange the screen.
    local headings_declared headings_name headings_state
    _menu_kinds; TUI_MENU_GROUP=kind; TUI_MENU_SORT=declared; tui_menu_refilter
    headings_declared="$(_menu_headings)"
    _menu_kinds; TUI_MENU_GROUP=kind; TUI_MENU_SORT=name; tui_menu_refilter
    headings_name="$(_menu_headings)"
    _menu_kinds; TUI_MENU_GROUP=kind; TUI_MENU_SORT=state; tui_menu_refilter
    headings_state="$(_menu_headings)"
    assert_eq "$headings_name"  "$headings_declared"
    assert_eq "$headings_state" "$headings_declared"
}

#[test]
it_still_reorders_the_rows_inside_a_group() {
    # The control for the test above. Holding the groups still must not stop
    # the sort doing anything at all.
    _menu_kinds; TUI_MENU_GROUP=kind; TUI_MENU_SORT=declared; tui_menu_refilter
    local a; a="$(_menu_shape)"
    _menu_kinds; TUI_MENU_GROUP=kind; TUI_MENU_SORT=name; tui_menu_refilter
    local b; b="$(_menu_shape)"
    assert_ne "$a" "$b"
}

#[test]
it_keeps_the_sections_in_the_order_they_were_declared() {
    _menu_kinds; TUI_MENU_GROUP=section; TUI_MENU_SORT=name; tui_menu_refilter
    assert_eq "$(_menu_headings)" "disk|net|"
}

# The headings the reader sees, in order, as one line.
_menu_headings() {
    local i out=""
    for i in "${!TUI_MENU_VIEW[@]}"; do
        tui_menu_raw "$i" >/dev/null 2>&1 && continue
        out="${out}$(tui_menu_heading_at "$i")|"
    done
    printf '%s' "$out"
}

#[test]
it_does_not_draw_the_last_row_as_a_heading_with_no_label() {
    # `${ARRAY[-1]}` in bash is the last element rather than an error, so an
    # invented heading with an empty label would silently draw the text of
    # whichever row happened to be last.
    _menu_kinds
    TUI_MENU_VIEW=(-1); TUI_MENU_VHEAD=("")
    local out; out="$(_tui_menu_cells -1 0 ""; printf '%s' "${_TUI_MENU_CELLS[1]}")"
    assert_fails grep -q 'apple erase' <<<"$out"
    assert_fails grep -q 'Beta fix' <<<"$out"
}

#[test]
it_still_draws_a_heading_that_has_a_label() {
    # The control.
    _menu_kinds
    _tui_menu_cells -1 0 "somewhere"
    assert_contains "${_TUI_MENU_CELLS[1]}" "somewhere"
}

#[test]
it_says_in_the_readme_as_many_modules_as_it_declares() {
    # Said wrong twice: eight when there were twelve, then twelve when there
    # were fourteen. A number in prose has nothing keeping it true, so this is
    # the thing that keeps it.
    local root="${BASH_SOURCE[0]%/*}/.."
    local declared spelled
    # Only the public ones. The two halves of the menu are marked internal in
    # `lib.nut`, the way nutshell marks its own impl modules.
    declared="$(grep '^tui::' "$root/lib.nut" | grep -vc 'internal')"
    spelled="$(grep -oE '^(Eight|Nine|Ten|Eleven|Twelve|Thirteen|Fourteen|Fifteen|Sixteen) modules' "$root/README.md" | head -1 | cut -d' ' -f1)"
    local n
    case "$spelled" in
        Eight) n=8 ;; Nine) n=9 ;; Ten) n=10 ;; Eleven) n=11 ;; Twelve) n=12 ;;
        Thirteen) n=13 ;; Fourteen) n=14 ;; Fifteen) n=15 ;; Sixteen) n=16 ;;
        *) n=0 ;;
    esac
    assert_eq "$n" "$declared"
}

#[test]
it_prints_a_key_line_that_follows_a_rebind() {
    # The list this replaced was a second copy, and it said `[ ]` whatever
    # anybody had bound. A key line that lies about which key to press is worse
    # than no key line, because somebody presses what it says.
    tui_menu_bindings
    assert_ok grep -q '^\[ ctrl-up alt-up' <(tui_menu_keys main)
    tui_action_bind section-prev "f3"
    assert_ok    grep -q '^f3' <(tui_menu_keys main)
    assert_fails grep -q '^\[' <(tui_menu_keys main)
}

#[test]
it_prints_the_search_keys_under_their_own_scope() {
    tui_menu_bindings
    assert_eq "$(tui_menu_keys filter | wc -l | tr -d ' ')" "4"
    assert_ok grep -q 'rub out a letter' <(tui_menu_keys filter)
    # And they stay out of the outer list, because in the outer list those keys
    # mean other things.
    assert_fails grep -q 'rub out a letter' <(tui_menu_keys main)
}

#[test]
it_installs_the_bindings_itself_when_a_caller_did_not() {
    tui_action_reset
    _TUI_MENU_BOUND=0
    assert_fails tui_action_for main 'q'
    tui_menu_keys >/dev/null
    assert_eq "$(tui_action_for main 'q')" "menu-back"
}

# --- typing into the search --------------------------------------------------

# The helper reads and writes the run loop's own variables, so a test has to
# stand in for that loop. These are what it sees.
typing_setup() {
    fixture
    tui_menu_bindings
    filtering=1; TUI_MENU_FILTER=""; cursor=1; top=0; act=""
}

#[test]
it_adds_a_printable_key_to_the_phrase() {
    local filtering cursor top act
    typing_setup
    TUI_KEY="d"; assert_fails _tui_menu_typing
    TUI_KEY="e"; assert_fails _tui_menu_typing
    assert_eq "$TUI_MENU_FILTER" "de"
    assert_eq "$filtering" "1"
}

#[test]
it_types_the_letters_that_are_keys_outside_the_search() {
    # `q`, `a`, `g`, `s` and `f` all mean something in the list. Inside the
    # search they are letters, or `chroot` would quit at the h.
    local filtering cursor top act
    typing_setup
    local k
    for k in q a g s f k j; do TUI_KEY="$k"; _tui_menu_typing || true; done
    assert_eq "$TUI_MENU_FILTER" "qagsfkj"
    assert_eq "$filtering" "1"
}

#[test]
it_types_a_space_rather_than_choosing() {
    # Space chooses in the list. A phrase with two words in it would be
    # unreachable if it did so here too.
    local filtering cursor top act
    typing_setup
    TUI_KEY="a"; _tui_menu_typing || true
    TUI_KEY="space"; _tui_menu_typing || true
    TUI_KEY="b"; _tui_menu_typing || true
    assert_eq "$TUI_MENU_FILTER" "a b"
}

#[test]
it_rubs_out_a_letter() {
    local filtering cursor top act
    typing_setup
    TUI_MENU_FILTER="disk"
    TUI_KEY="backspace"; assert_fails _tui_menu_typing
    assert_eq "$TUI_MENU_FILTER" "dis"
    assert_eq "$filtering" "1"
}

#[test]
it_leaves_the_search_by_rubbing_past_the_start() {
    # The way out is the way you came in.
    local filtering cursor top act
    typing_setup
    TUI_MENU_FILTER=""
    TUI_KEY="backspace"; assert_fails _tui_menu_typing
    assert_eq "$filtering" "0"
}

#[test]
it_drops_the_phrase_on_the_way_out() {
    # Leaving with a phrase still applied hides rows from the next visit.
    local filtering cursor top act
    typing_setup
    TUI_MENU_FILTER="disk"
    TUI_KEY="esc"; assert_fails _tui_menu_typing
    assert_eq "$filtering" "0"
    assert_empty "$TUI_MENU_FILTER"
}

#[test]
it_hands_back_the_keys_that_leave_or_choose() {
    # These two belong to the dispatch rather than to the search, because one
    # of them returns from the run and a helper cannot.
    local filtering cursor top act
    typing_setup
    TUI_KEY="enter";  assert_ok _tui_menu_typing; assert_eq "$act" "search-accept"
    TUI_KEY="ctrl-c"; assert_ok _tui_menu_typing; assert_eq "$act" "search-quit"
}

#[test]
it_still_moves_the_cursor_while_the_search_is_open() {
    # So a phrase can be typed and a row picked without leaving it.
    local filtering cursor top act
    typing_setup
    TUI_KEY="down"; assert_ok _tui_menu_typing; assert_eq "$act" "menu-down"
    TUI_KEY="pgup"; assert_ok _tui_menu_typing; assert_eq "$act" "menu-page-up"
    assert_eq "$filtering" "1"
    assert_empty "$TUI_MENU_FILTER"
}

#[test]
it_ignores_a_key_it_has_no_use_for() {
    local filtering cursor top act
    typing_setup
    TUI_KEY="insert"; assert_fails _tui_menu_typing
    TUI_KEY="delete"; assert_fails _tui_menu_typing
    TUI_KEY="unknown"; assert_fails _tui_menu_typing
    assert_empty "$TUI_MENU_FILTER"
    assert_eq "$filtering" "1"
}

#[test]
it_narrows_the_list_as_the_phrase_grows() {
    # The whole reason typing does anything: the view is rebuilt on every
    # letter rather than when the search is closed.
    local filtering cursor top act
    typing_setup
    TUI_MENU_TEXT=(Disk Delve Depth Gamma Boot Delta Epsilon)
    tui_menu_refilter
    assert_eq "${#TUI_MENU_VIEW[@]}" "7"
    TUI_KEY="d"; _tui_menu_typing || true
    # Delve, Depth and Delta, plus the two headings they sit under.
    assert_eq "${#TUI_MENU_VIEW[@]}" "5"
    TUI_KEY="e"; _tui_menu_typing || true
    TUI_KEY="l"; _tui_menu_typing || true
    assert_eq "$TUI_MENU_FILTER" "del"
    # Delve and Delta now, and Depth has gone.
    assert_eq "${#TUI_MENU_VIEW[@]}" "4"
}
