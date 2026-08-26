#!/usr/bin/env bash
# Tests for dividing the screen.
#
# It draws nothing, which is the point: the arithmetic can be pinned at sizes
# no real terminal is, and that is where a layout breaks. The properties that
# matter are that the regions add up to the total exactly, that a region never
# ends up under the size it said it needed, and that when there is not enough
# room whole regions are dropped rather than every region squeezed until none
# of them works.

use test
. "${BASH_SOURCE[0]%/*}/../libs/tui/layout.sh"

# The sum of every placed region.
_sum() {
    local i n=0
    for (( i = 0; i < ${#TUI_LAYOUT_SIZE[@]}; i++ )); do
        n=$(( n + TUI_LAYOUT_SIZE[i] ))
    done
    printf '%d' "$n"
}

# --- fixed sizes -------------------------------------------------------------

#[test]
it_gives_a_fixed_region_exactly_what_it_asked_for() {
    tui_layout_reset rows 20
    tui_layout_add head 1
    tui_layout_add body 15
    tui_layout_add keys 1
    tui_layout_solve
    assert_eq "$(tui_layout_size head)" "1"
    assert_eq "$(tui_layout_size body)" "15"
    assert_eq "$(tui_layout_size keys)" "1"
}

#[test]
it_places_regions_one_after_another() {
    tui_layout_reset rows 20
    tui_layout_add head 2
    tui_layout_add body 5
    tui_layout_add keys 1
    tui_layout_solve
    assert_eq "$(tui_layout_start head)" "1"
    assert_eq "$(tui_layout_start body)" "3"
    assert_eq "$(tui_layout_start keys)" "8"
    assert_eq "$(tui_layout_end body)"   "8"
}

# --- shares -------------------------------------------------------------------

#[test]
it_gives_the_rest_to_a_share() {
    tui_layout_reset rows 20
    tui_layout_add head 1
    tui_layout_add body 1fr
    tui_layout_add keys 1
    tui_layout_solve
    assert_eq "$(tui_layout_size body)" "18"
    assert_eq "$(_sum)" "20"
}

#[test]
it_divides_the_rest_between_shares() {
    tui_layout_reset cols 30
    tui_layout_add main 2fr
    tui_layout_add side 1fr
    tui_layout_solve
    assert_eq "$(tui_layout_size main)" "20"
    assert_eq "$(tui_layout_size side)" "10"
    assert_eq "$(_sum)" "30"
}

#[test]
it_loses_nothing_to_a_remainder() {
    # 10 across 3 shares is 3 each and one left over. That one has to land
    # somewhere or the layout is a row short of the screen and the bottom line
    # is drawn over.
    tui_layout_reset rows 10
    tui_layout_add a 1fr
    tui_layout_add b 1fr
    tui_layout_add c 1fr
    tui_layout_solve
    assert_eq "$(_sum)" "10"
}

#[test]
it_adds_up_at_every_size() {
    local t
    for t in 5 7 10 13 24 25 40 41 80 100; do
        tui_layout_reset rows "$t"
        tui_layout_add head 1
        tui_layout_add body 2fr
        tui_layout_add note 1fr
        tui_layout_add keys 1
        tui_layout_solve
        assert_eq "$(_sum)" "$t"
    done
}

#[test]
it_treats_a_bare_fr_as_one_share() {
    tui_layout_reset rows 12
    tui_layout_add a fr
    tui_layout_add b fr
    tui_layout_solve
    assert_eq "$(tui_layout_size a)" "6"
    assert_eq "$(tui_layout_size b)" "6"
}

# --- running out of room --------------------------------------------------------

#[test]
it_drops_the_least_important_first() {
    tui_layout_reset rows 10
    tui_layout_add head 1
    tui_layout_add body 1fr min:4
    tui_layout_add note 4          --priority 1
    tui_layout_add side 6          --priority 5
    tui_layout_solve
    # The sidebar is the most droppable, so it goes before the note does.
    assert_fails tui_layout_has side
    assert_ok    tui_layout_has body
    assert_ok    tui_layout_has head
}

#[test]
it_keeps_dropping_until_what_is_left_fits() {
    tui_layout_reset rows 6
    tui_layout_add head 1
    tui_layout_add body 1fr min:3
    tui_layout_add note 4 --priority 1
    tui_layout_add side 6 --priority 5
    tui_layout_solve
    assert_fails tui_layout_has side
    assert_fails tui_layout_has note
    assert_ok    tui_layout_has body
    assert_ok    tui_layout_has head
}

#[test]
it_never_drops_a_region_that_may_not_be_dropped() {
    tui_layout_reset rows 3
    tui_layout_add head 1
    tui_layout_add body 1fr min:8
    tui_layout_solve
    # Neither may go. There is not enough room, and the honest answer is to
    # place them anyway rather than to quietly discard the body.
    assert_ok tui_layout_has head
    assert_ok tui_layout_has body
}

#[test]
it_drops_whole_rather_than_shrinking_below_a_floor() {
    tui_layout_reset cols 30
    tui_layout_add main 1fr min:20
    tui_layout_add side 1fr min:20 --priority 3
    tui_layout_solve
    # Two twenties do not fit in thirty. Ten each would be two useless columns,
    # so one goes and the other gets the room.
    assert_ok    tui_layout_has main
    assert_fails tui_layout_has side
    assert_ok test "$(tui_layout_size main)" -ge 20
}

#[test]
it_gives_a_dropped_region_no_position() {
    tui_layout_reset rows 6
    tui_layout_add body 1fr min:4
    tui_layout_add side 6 --priority 2
    tui_layout_solve
    assert_eq "$(tui_layout_size side)"  "0"
    assert_eq "$(tui_layout_start side)" "0"
    assert_fails tui_layout_end side
}

#[test]
it_leaves_no_gap_where_a_dropped_region_was() {
    tui_layout_reset rows 10
    tui_layout_add head 1
    tui_layout_add side 8 --priority 4
    tui_layout_add body 1fr min:4
    tui_layout_add keys 1
    tui_layout_solve
    # body follows head directly, because side is not there to sit between.
    assert_fails tui_layout_has side
    assert_eq "$(tui_layout_start body)" "2"
}

# --- floors --------------------------------------------------------------------

#[test]
it_honours_a_floor_on_a_share() {
    tui_layout_reset rows 12
    tui_layout_add head 8
    tui_layout_add body 1fr min:6
    tui_layout_solve
    # The share would have got 4. It said it cannot work below 6.
    assert_ok test "$(tui_layout_size body)" -ge 6
}

#[test]
it_honours_a_floor_on_a_fixed_size() {
    tui_layout_reset rows 20
    tui_layout_add body 2 min:5
    tui_layout_solve
    assert_eq "$(tui_layout_size body)" "5"
}

# --- being asked about nothing ------------------------------------------------------

#[test]
it_answers_about_a_region_that_does_not_exist() {
    tui_layout_reset rows 20
    tui_layout_add body 1fr
    tui_layout_solve
    assert_fails tui_layout_has  nonsense
    assert_fails tui_layout_size nonsense
    assert_eq "$(tui_layout_size nonsense 2>/dev/null || true)" "0"
}

#[test]
it_solves_an_empty_layout_without_complaining() {
    tui_layout_reset rows 20
    assert_ok tui_layout_solve
    assert_eq "$(_sum)" "0"
}

#[test]
it_survives_a_total_of_nothing() {
    tui_layout_reset rows 0
    tui_layout_add body 1fr
    assert_ok tui_layout_solve
    assert_eq "$(tui_layout_size body)" "0"
}

#[test]
it_survives_a_size_that_is_not_a_number() {
    tui_layout_reset rows notanumber
    tui_layout_add body 1fr
    assert_ok tui_layout_solve 2>/dev/null
    tui_layout_reset rows 10
    tui_layout_add body wide
    assert_ok tui_layout_solve 2>/dev/null
}

#[test]
it_forgets_the_previous_layout_on_reset() {
    tui_layout_reset rows 20
    tui_layout_add body 1fr
    tui_layout_solve
    tui_layout_reset rows 20
    tui_layout_add other 1fr
    tui_layout_solve
    assert_fails tui_layout_has body
    assert_ok    tui_layout_has other
}

#[test]
it_takes_the_terminals_own_size_when_given_none() {
    TUI_ROWS=17 TUI_COLS=41
    tui_layout_reset rows
    tui_layout_add body 1fr
    tui_layout_solve
    assert_eq "$(tui_layout_size body)" "17"
    tui_layout_reset cols
    tui_layout_add body 1fr
    tui_layout_solve
    assert_eq "$(tui_layout_size body)" "41"
}

# --- floors that do not fit together -------------------------------------------
#
# A share raised to its floor has to take that room from the other shares. It
# used to be raised on its own, so the regions added up to more than the screen
# and the last one was drawn over the edge.

#[test]
it_never_places_more_than_the_screen_holds() {
    local t
    # From 46 up, which is where the list's own floor stops being the binding
    # constraint. Below that nothing may be dropped and the overflow is the
    # honest answer, which the test below covers.
    for t in 46 60 72 78 80 100 140 200; do
        tui_layout_reset cols "$t"
        tui_layout_add list 1fr min:46
        tui_layout_add gap  2  --priority 9
        tui_layout_add side 30 min:24 --priority 4
        tui_layout_solve
        assert_ok test "$(_sum)" -le "$t"
    done
}

#[test]
it_keeps_a_floored_share_at_its_floor() {
    tui_layout_reset cols 78
    tui_layout_add list 1fr min:46
    tui_layout_add side 30 --priority 4
    tui_layout_solve
    # The share takes everything the panel left, which is more than its floor.
    # A floor is the point below which it would be dropped, not a target.
    assert_eq "$(tui_layout_size list)" "48"
    assert_eq "$(tui_layout_size side)" "30"
    assert_eq "$(_sum)" "78"
}

#[test]
it_drops_the_droppable_rather_than_starving_the_floor() {
    tui_layout_reset cols 60
    tui_layout_add list 1fr min:46
    tui_layout_add side 30 --priority 4
    tui_layout_solve
    # 46 and 30 do not both fit in 60. The list said 46 is its floor and cannot
    # be dropped, so the panel goes.
    assert_fails tui_layout_has side
    assert_eq "$(tui_layout_size list)" "60"
}

#[test]
it_drops_in_priority_order_across_a_resolve() {
    tui_layout_reset cols 72
    tui_layout_add list 1fr min:46
    tui_layout_add gap  2  --priority 9
    tui_layout_add side 30 min:24 --priority 4
    tui_layout_solve
    # The gap is the most droppable, and dropping it is not enough, so the
    # panel follows. Dropping one changes what the shares get, so the whole
    # thing is worked out again rather than patched.
    assert_fails tui_layout_has gap
    assert_fails tui_layout_has side
    assert_eq "$(tui_layout_size list)" "72"
}

#[test]
it_gives_a_share_with_no_floor_at_least_something() {
    tui_layout_reset cols 10
    tui_layout_add a 1fr
    tui_layout_add b 1fr
    tui_layout_solve
    assert_ok test "$(tui_layout_size a)" -ge 1
    assert_ok test "$(tui_layout_size b)" -ge 1
}

#[test]
it_reports_the_overflow_rather_than_hiding_it() {
    tui_layout_reset cols 20
    tui_layout_add a 30
    tui_layout_add b 30
    tui_layout_solve
    # Neither may be dropped and neither fits. They keep their sizes, and a
    # caller adding them up can see it; silently shrinking them to something
    # that fits would be a layout lying about what it placed.
    assert_ok test "$(_sum)" -gt 20
}
