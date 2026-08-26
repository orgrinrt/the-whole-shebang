#!/usr/bin/env bash
# Tests for columns that line up.
#
# The menu had a columnar renderer of its own and a list with aligned columns
# is not a thing only a menu wants. What is checked here is that it lines up,
# that it never draws wider than it was given, and that a column too narrow to
# be useful is dropped rather than wrapped into a mess.

use test
. "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/layout.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/table.sh"

_strip() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

_three() {
    tui_table_reset
    tui_table_col name  1fr min:12 --head "task"
    tui_table_col state 6          --head "state"
    tui_table_col note  2fr min:16 --head "why" --priority 5
    tui_table_row "disk-wipe"      "off"  "needs lsblk"
    tui_table_row "boot-inspect"   "ok"   "reads and reports"
}

# --- what it holds ------------------------------------------------------------

#[test]
it_counts_the_rows_it_was_given() {
    _three
    assert_eq "$(tui_table_rows)" "2"
}

#[test]
it_forgets_everything_on_reset() {
    _three
    tui_table_reset
    assert_eq "$(tui_table_rows)" "0"
    assert_eq "${#TUI_TABLE_COL[@]}" "0"
}

#[test]
it_keeps_an_empty_cell_in_its_own_column() {
    tui_table_reset
    tui_table_col a 10
    tui_table_col b 10
    tui_table_col c 10
    tui_table_row "one" "" "three"
    local out; out="$(tui_table_render --width 40 | _strip)"
    # An empty middle cell must not swallow its column and shift the rest
    # left, which is what a whitespace delimiter does.
    assert_ok grep -qE '^one .* three$' <<<"$out"
}

# --- lining up ------------------------------------------------------------------

#[test]
it_starts_every_cell_of_a_column_in_the_same_place() {
    _three
    local out c1 c2
    out="$(tui_table_render --width 80 | _strip)"
    c1="$(awk '/disk-wipe/    { print index($0, "off") }' <<<"$out")"
    c2="$(awk '/boot-inspect/ { print index($0, "ok") }'  <<<"$out")"
    assert_ok test -n "$c1"
    assert_eq "$c2" "$c1"
}

#[test]
it_never_draws_wider_than_it_was_given() {
    local w out line
    for w in 24 30 40 46 60 80 120 200; do
        _three
        out="$(tui_table_render --width "$w" | _strip)"
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            assert_ok test "${#line}" -le "$w"
        done <<< "$out"
    done
}

#[test]
it_cuts_a_cell_rather_than_wrapping_it() {
    tui_table_reset
    tui_table_col only 20
    tui_table_row "$(printf 'x%.0s' {1..200})"
    local out; out="$(tui_table_render --width 30 | _strip)"
    # One line, not ten.
    assert_eq "$(grep -c . <<<"$out")" "1"
    assert_ok test "${#out}" -le 30
}

# --- running out of room -----------------------------------------------------------

#[test]
it_drops_the_most_droppable_column_on_a_narrow_screen() {
    _three
    local out; out="$(tui_table_render --width 30 | _strip)"
    # `why` said it was the first to go, and 30 columns cannot hold all three.
    assert_ok    grep -q 'disk-wipe' <<<"$out"
    assert_fails grep -q 'needs lsblk' <<<"$out"
}

#[test]
it_keeps_the_columns_that_did_not_ask_to_be_dropped() {
    _three
    tui_table_render --width 30 >/dev/null
    assert_ok test "$(tui_table_width name)"  -gt 0
    assert_ok test "$(tui_table_width state)" -gt 0
    assert_eq "$(tui_table_width note)" "0"
}

#[test]
it_shows_everything_when_there_is_room() {
    _three
    local out; out="$(tui_table_render --width 100 | _strip)"
    assert_ok grep -q 'needs lsblk' <<<"$out"
}

#[test]
it_gives_every_column_a_width_when_there_is_room() {
    _three
    # Not captured: a command substitution is a subshell, and the widths the
    # render works out there do not come back.
    tui_table_render --width 100 >/dev/null
    assert_ok test "$(tui_table_width note)"  -gt 0
    assert_ok test "$(tui_table_width name)"  -gt 0
    assert_ok test "$(tui_table_width state)" -gt 0
}

# --- headings and borders -------------------------------------------------------------

#[test]
it_prints_the_headings_it_was_given() {
    _three
    local out; out="$(tui_table_render --width 80 | _strip)"
    assert_ok grep -q 'task' <<<"$(head -1 <<<"$out")"
    assert_ok grep -q 'why'  <<<"$(head -1 <<<"$out")"
}

#[test]
it_prints_no_heading_row_when_no_column_asked_for_one() {
    tui_table_reset
    tui_table_col a 10
    tui_table_row "value"
    local out; out="$(tui_table_render --width 30 | _strip)"
    assert_eq "$(grep -c . <<<"$out")" "1"
    assert_ok grep -q 'value' <<<"$out"
}

#[test]
it_draws_no_borders_unless_asked() {
    _three
    local out; out="$(tui_table_render --width 80 | _strip)"
    assert_fails grep -qE '^[-─]+' <<<"$out"
}

#[test]
it_draws_borders_when_asked() {
    _three
    local out; out="$(tui_table_render --width 80 --borders | _strip)"
    assert_ok grep -qE '[-─]{4,}' <<<"$out"
}

#[test]
it_makes_a_border_as_wide_as_the_columns_it_underlines() {
    _three
    local out rule body
    out="$(tui_table_render --width 80 --borders | _strip)"
    rule="$(grep -m1 -E '^[-─]' <<<"$out")"
    body="$(grep -m1 'disk-wipe' <<<"$out")"
    # A rule that is not the width of the table reads as a mistake.
    assert_ok test "${#rule}" -ge "${#body}"
    assert_ok test "${#rule}" -le 80
}

# --- with no terminal --------------------------------------------------------------------

#[test]
it_writes_no_control_bytes_into_a_pipe() {
    TUI_COLOR=0; tui_palette
    _three
    local out; out="$(tui_table_render --width 80 --borders)"
    assert_fails grep -q $'\x1b' <<<"$out"
}

#[test]
it_renders_nothing_for_a_table_with_no_columns() {
    tui_table_reset
    tui_table_row "orphan"
    assert_ok tui_table_render --width 40
    assert_eq "$(tui_table_render --width 40)" ""
}

#[test]
it_survives_a_width_that_is_not_a_number() {
    _three
    assert_ok tui_table_render --width wide >/dev/null 2>&1
}

#[test]
it_survives_a_width_of_almost_nothing() {
    _three
    local out; out="$(tui_table_render --width 4 2>/dev/null | _strip)"
    # Whatever it shows, it must not be wider than what it was given, and it
    # must not fall over.
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        assert_ok test "${#line}" -le 4
    done <<< "$out"
}
