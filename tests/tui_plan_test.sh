#!/usr/bin/env bash
# Tests for fitting panels around the thing you came for.
#
# It draws nothing, so every arrangement can be checked at sizes no real
# terminal is, which is where a layout breaks. The properties that matter: a
# panel is dropped only when no shape of it fits anywhere, nothing overlaps
# anything, nothing is placed off the screen, and a panel that cannot sit
# beside the main region moves underneath it rather than disappearing.

use test
. "${BASH_SOURCE[0]%/*}/../libs/tui/plan.sh"

# Do any two placed panels share a cell, or fall outside the screen?
_overlaps() {
    local n="${#TUI_PLAN_NAME[@]}" i j
    for (( i = 0; i < n; i++ )); do
        (( TUI_PLAN_W[i] > 0 )) || continue
        (( TUI_PLAN_C[i] >= 1 && TUI_PLAN_R[i] >= 1 )) || { printf 'offscreen'; return 0; }
        (( TUI_PLAN_C[i] + TUI_PLAN_W[i] - 1 <= TUI_PLAN_COLS )) || { printf 'too wide'; return 0; }
        (( TUI_PLAN_R[i] + TUI_PLAN_H[i] - 1 <= TUI_PLAN_ROWS )) || { printf 'too tall'; return 0; }
        for (( j = i + 1; j < n; j++ )); do
            (( TUI_PLAN_W[j] > 0 )) || continue
            (( TUI_PLAN_C[i] + TUI_PLAN_W[i] <= TUI_PLAN_C[j] )) && continue
            (( TUI_PLAN_C[j] + TUI_PLAN_W[j] <= TUI_PLAN_C[i] )) && continue
            (( TUI_PLAN_R[i] + TUI_PLAN_H[i] <= TUI_PLAN_R[j] )) && continue
            (( TUI_PLAN_R[j] + TUI_PLAN_H[j] <= TUI_PLAN_R[i] )) && continue
            printf '%s overlaps %s' "${TUI_PLAN_NAME[$i]}" "${TUI_PLAN_NAME[$j]}"
            return 0
        done
    done
    printf ''
}

# Does any panel sit on top of the main region?
_hits_main() {
    local n="${#TUI_PLAN_NAME[@]}" i
    for (( i = 0; i < n; i++ )); do
        (( TUI_PLAN_W[i] > 0 )) || continue
        (( TUI_PLAN_C[i] > TUI_PLAN_MAIN_W )) && continue
        (( TUI_PLAN_R[i] > TUI_PLAN_MAIN_H )) && continue
        printf '%s' "${TUI_PLAN_NAME[$i]}"; return 0
    done
    printf ''
}

# --- placing ------------------------------------------------------------------

#[test]
it_puts_a_panel_beside_the_main_region_when_there_is_width() {
    tui_plan_reset 140 40
    tui_plan_main 60 18
    tui_plan_panel side 3 30x12
    tui_plan_solve
    assert_ok tui_plan_has side
    assert_eq "$(tui_plan_where side)" "beside"
    assert_ok test "$(tui_plan_col side)" -gt 60
}

#[test]
it_moves_a_panel_underneath_when_there_is_no_width() {
    tui_plan_reset 62 40
    tui_plan_main 60 18
    tui_plan_panel side 3 30x12
    tui_plan_solve
    # The point of the whole thing: a panel that will not fit beside the list
    # is not homeless, there is room under it.
    assert_ok tui_plan_has side
    assert_eq "$(tui_plan_where side)" "below"
}

#[test]
it_lays_two_panels_side_by_side_underneath() {
    tui_plan_reset 62 40
    tui_plan_main 60 18
    tui_plan_panel a 3 28x10
    tui_plan_panel b 4 28x10
    tui_plan_solve
    assert_ok tui_plan_has a
    assert_ok tui_plan_has b
    # Two short columns below, rather than one long one and a dropped panel.
    assert_eq "$(tui_plan_where a)" "below"
    assert_eq "$(tui_plan_where b)" "below"
    assert_empty "$(_overlaps)"
}

#[test]
it_never_puts_a_panel_on_the_main_region() {
    local c r
    for c in 62 80 100 140 200; do
        for r in 20 24 40 60; do
            tui_plan_reset "$c" "$r"
            tui_plan_main 60 18
            tui_plan_panel a 3 30x12 58x4
            tui_plan_panel b 5 24x8  40x3
            tui_plan_solve
            assert_empty "$(_hits_main)"
        done
    done
}

#[test]
it_never_overlaps_and_never_goes_off_the_screen() {
    local c r
    for c in 40 62 80 100 140 200; do
        for r in 12 20 24 40 60; do
            tui_plan_reset "$c" "$r"
            tui_plan_main 50 15
            tui_plan_panel a 3 30x12 58x4
            tui_plan_panel b 5 24x8  40x3
            tui_plan_panel c 7 20x6
            tui_plan_solve
            assert_empty "$(_overlaps)"
        done
    done
}

# --- choosing a shape ------------------------------------------------------------

#[test]
it_prefers_the_largest_shape_that_fits() {
    tui_plan_reset 140 40
    tui_plan_main 60 18
    tui_plan_panel side 3 20x4 30x12
    tui_plan_solve
    # Declared order is the author's, not a preference. The largest is about
    # the space it covers.
    assert_eq "$(tui_plan_shape side)" "30x12"
}

#[test]
it_takes_a_smaller_shape_rather_than_starving_the_next_panel() {
    tui_plan_reset 140 20
    tui_plan_main 60 18
    tui_plan_panel a 3 30x12 58x5
    tui_plan_panel b 5 24x8
    tui_plan_solve
    # 58x5 fits beside and would leave 22 columns, too few for b. The bigger
    # shape on its own is not the better arrangement.
    assert_ok tui_plan_has a
    assert_ok tui_plan_has b
    assert_eq "$TUI_PLAN_DROPPED" "0"
}

#[test]
it_uses_the_wide_short_shape_when_that_is_what_the_room_is() {
    tui_plan_reset 100 26
    tui_plan_main 96 20
    tui_plan_panel strip 3 20x12 90x4
    tui_plan_solve
    # Four columns to the right and six rows underneath: the strip is the only
    # shape that fits anywhere.
    assert_ok tui_plan_has strip
    assert_eq "$(tui_plan_shape strip)" "90x4"
    assert_eq "$(tui_plan_where strip)" "below"
}

# --- dropping, and only then -------------------------------------------------------

#[test]
it_drops_nothing_when_everything_fits() {
    tui_plan_reset 200 60
    tui_plan_main 60 18
    tui_plan_panel a 3 30x12
    tui_plan_panel b 5 30x12
    tui_plan_panel c 7 30x12
    tui_plan_solve
    assert_eq "$TUI_PLAN_DROPPED" "0"
    assert_ok tui_plan_has a; assert_ok tui_plan_has b; assert_ok tui_plan_has c
}

#[test]
it_drops_the_least_important_first() {
    tui_plan_reset 96 20
    tui_plan_main 60 18
    tui_plan_panel keepme  1 30x12
    tui_plan_panel dropme  9 30x12
    tui_plan_solve
    # One 30-wide column fits beside; the second does not, and the second is
    # the one that said it mattered less.
    assert_ok    tui_plan_has keepme
    assert_fails tui_plan_has dropme
}

#[test]
it_never_drops_a_panel_marked_as_never() {
    tui_plan_reset 96 20
    tui_plan_main 60 18
    tui_plan_panel essential 0 30x12
    tui_plan_panel other     4 30x12
    tui_plan_solve
    assert_ok    tui_plan_has essential
    assert_fails tui_plan_has other
}

#[test]
it_drops_as_few_as_it_can() {
    tui_plan_reset 130 20
    tui_plan_main 60 18
    tui_plan_panel a 3 30x12
    tui_plan_panel b 5 30x12
    tui_plan_panel c 7 60x12
    tui_plan_solve
    # 70 columns spare: a and b fit, c does not. One dropped, not two.
    assert_eq "$TUI_PLAN_DROPPED" "1"
    assert_ok tui_plan_has a
    assert_ok tui_plan_has b
}

#[test]
it_drops_a_panel_that_fits_nowhere_at_all() {
    tui_plan_reset 62 20
    tui_plan_main 60 18
    tui_plan_panel huge 4 40x10
    tui_plan_solve
    assert_fails tui_plan_has huge
    assert_eq "$(tui_plan_w huge)" "0"
    assert_eq "$(tui_plan_row huge)" "0"
}

#[test]
it_says_nothing_is_anywhere_when_nothing_fits() {
    tui_plan_reset 62 20
    tui_plan_main 60 18
    tui_plan_panel a 3 40x10
    tui_plan_panel b 4 40x10
    tui_plan_solve
    assert_eq "$(tui_plan_where a)" "nowhere"
    assert_eq "$(tui_plan_where b)" "nowhere"
}

# --- being asked about nothing ------------------------------------------------------

#[test]
it_solves_a_screen_with_no_panels() {
    tui_plan_reset 100 30
    tui_plan_main 60 18
    assert_ok tui_plan_solve
    assert_eq "$TUI_PLAN_DROPPED" "0"
}

#[test]
it_answers_about_a_panel_that_does_not_exist() {
    tui_plan_reset 100 30
    tui_plan_main 60 18
    tui_plan_solve
    assert_fails tui_plan_has nonsense
    assert_eq "$(tui_plan_w nonsense 2>/dev/null || true)" "0"
    assert_eq "$(tui_plan_where nonsense 2>/dev/null || true)" "nowhere"
}

#[test]
it_survives_a_main_region_bigger_than_the_screen() {
    tui_plan_reset 40 10
    tui_plan_main 200 100
    tui_plan_panel a 3 10x3
    assert_ok tui_plan_solve 2>/dev/null
    assert_empty "$(_overlaps)"
}

#[test]
it_survives_a_shape_that_is_not_a_shape() {
    tui_plan_reset 100 30
    tui_plan_main 60 18
    tui_plan_panel a 3 nonsense 30x12
    assert_ok tui_plan_solve 2>/dev/null
    # The good shape is still usable; the nonsense one is simply not a
    # candidate.
    assert_eq "$(tui_plan_shape a)" "30x12"
}

#[test]
it_survives_a_size_that_is_not_a_number() {
    tui_plan_reset wide tall
    tui_plan_main 10 3
    tui_plan_panel a 3 10x3
    assert_ok tui_plan_solve 2>/dev/null
    assert_empty "$(_overlaps)"
}

#[test]
it_forgets_the_previous_plan() {
    tui_plan_reset 140 40
    tui_plan_main 60 18
    tui_plan_panel gone 3 30x12
    tui_plan_solve
    tui_plan_reset 140 40
    tui_plan_main 60 18
    tui_plan_panel other 3 30x12
    tui_plan_solve
    assert_fails tui_plan_has gone
    assert_ok    tui_plan_has other
}

# --- the claim, checked against something that does not share its reasoning ---------
#
# "Drops the fewest" was asserted at four hand-computed points, and every one
# of them happened to be a case the old lossy split got right. A law stated as
# universal and checked at four chosen instantiations is the sampled-law shape:
# the 18% it got wrong was never named.
#
# So: a second placer that shares no code with the one under test. Plain shelf
# packing, which is deliberately weaker — it finds fewer arrangements than
# optimal — so anything it places that the real one drops is a real loss and
# not an artefact of a cleverer comparison.

# Shelves: fill a row left to right, drop to the next when the row is full.
# Prints how many of the given WxH panels it placed in a WxH region.
_shelf_places() {
    local rw="$1" rh="$2"; shift 2
    local x=0 y=0 shelf_h=0 placed=0 spec w h
    for spec in "$@"; do
        w="${spec%%x*}"; h="${spec##*x}"
        if (( x + w > rw )); then
            y=$(( y + shelf_h )); x=0; shelf_h=0
        fi
        (( y + h > rh )) && continue
        (( x + w > rw )) && continue
        x=$(( x + w )); (( h > shelf_h )) && shelf_h="$h"
        placed=$(( placed + 1 ))
    done
    printf '%d' "$placed"
}

#[test]
it_places_at_least_what_plain_shelf_packing_would() {
    # A sweep, not four points. Every panel is droppable, so the only thing
    # being compared is how many found room.
    local cols rows n bad="" i
    for cols in 60 80 100 140; do
        for rows in 20 26 34 40; do
            for n in 2 3 4; do
                tui_plan_reset "$cols" "$rows"
                # No main region worth speaking of: the whole screen is the
                # area both placers are working in, so the comparison is fair.
                tui_plan_main 1 1
                local -a shapes=()
                for (( i = 0; i < n; i++ )); do
                    tui_plan_panel "p$i" $(( i + 1 )) 60x4
                    shapes+=("60x4")
                done
                tui_plan_solve

                local mine=0
                for (( i = 0; i < n; i++ )); do
                    tui_plan_has "p$i" && mine=$(( mine + 1 ))
                done
                local theirs
                theirs="$(_shelf_places $(( cols - 1 )) $(( rows - 1 )) "${shapes[@]}")"
                (( mine < theirs )) && bad+="${cols}x${rows}/${n}:${mine}<${theirs} "
            done
        done
    done
    assert_empty "$bad"
}

#[test]
it_places_at_least_what_shelf_packing_would_with_mixed_shapes() {
    local cols rows bad=""
    for cols in 70 90 120 160; do
        for rows in 22 30 40; do
            tui_plan_reset "$cols" "$rows"
            tui_plan_main 1 1
            tui_plan_panel a 1 40x6
            tui_plan_panel b 2 30x8
            tui_plan_panel c 3 50x4
            tui_plan_panel d 4 20x10
            tui_plan_solve
            local mine=0 p
            for p in a b c d; do tui_plan_has "$p" && mine=$(( mine + 1 )); done
            local theirs
            theirs="$(_shelf_places $(( cols - 1 )) $(( rows - 1 )) 40x6 30x8 50x4 20x10)"
            (( mine < theirs )) && bad+="${cols}x${rows}:${mine}<${theirs} "
        done
    done
    assert_empty "$bad"
}

#[test]
it_has_an_oracle_that_can_actually_disagree() {
    # The positive control. An oracle that always agrees proves nothing, so:
    # a region that plainly holds three panels, and a count that says three.
    assert_eq "$(_shelf_places 200 40 60x4 60x4 60x4)" "3"
    # And one that plainly holds none of them.
    assert_eq "$(_shelf_places 10 4 60x4 60x4)" "0"
}

#[test]
it_keeps_three_panels_that_all_fit_in_one_region() {
    tui_plan_reset 200 20
    tui_plan_main 1 1
    tui_plan_panel a 1 60x4
    tui_plan_panel b 2 60x4
    tui_plan_panel c 3 60x4
    tui_plan_solve
    # The worst case the sweep found: two of three dropped into a region that
    # holds all three, because the leftover arm of the L had been discarded.
    assert_eq "$TUI_PLAN_DROPPED" "0"
    assert_empty "$(_overlaps)"
}
