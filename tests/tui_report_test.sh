#!/usr/bin/env bash
# Tests for the report.
#
# Two contracts. The exit status has to be usable by something that never reads
# the text -- a hook, a cron line, another script -- so "nothing wrong", "worth
# a look" and "broken" must stay distinguishable. And every failure has to
# appear in the summary underneath, because by the time thirty checks have run
# the one that failed is off the top of the screen, and a report that hides it
# there is a report that wasted the run.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/report.sh"

_strip() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

# --- counting -------------------------------------------------------------------

#[test]
it_starts_empty() {
    tui_report_reset
    assert_eq "$(tui_report_count ok)"   "0"
    assert_eq "$(tui_report_count fail)" "0"
    assert_eq "$(tui_report_worst)"      "ok"
    assert_eq "$(tui_report_exit)"       "0"
}

#[test]
it_counts_each_status_separately() {
    tui_report_reset
    tui_report_row ok   a; tui_report_row ok   b
    tui_report_row warn c
    tui_report_row fail d; tui_report_row fail e; tui_report_row fail f
    tui_report_row skip g
    assert_eq "$(tui_report_count ok)"   "2"
    assert_eq "$(tui_report_count warn)" "1"
    assert_eq "$(tui_report_count fail)" "3"
    assert_eq "$(tui_report_count skip)" "1"
    assert_eq "$(tui_report_count info)" "0"
}

#[test]
it_forgets_everything_on_reset() {
    tui_report_reset
    tui_report_row fail a
    tui_report_reset
    assert_eq "$(tui_report_count fail)" "0"
    assert_eq "$(tui_report_worst)"      "ok"
}

# --- the worst thing, and the exit status ------------------------------------------

#[test]
it_calls_a_clean_run_ok() {
    tui_report_reset
    tui_report_row ok a; tui_report_row ok b; tui_report_row skip c
    assert_eq "$(tui_report_worst)" "ok"
    assert_eq "$(tui_report_exit)"  "0"
}

#[test]
it_distinguishes_worth_a_look_from_broken() {
    tui_report_reset
    tui_report_row ok a; tui_report_row warn b
    # 2, not 1: a caller that cannot read the text still has to be able to tell
    # "fine for now" from "something failed".
    assert_eq "$(tui_report_worst)" "warn"
    assert_eq "$(tui_report_exit)"  "2"
}

#[test]
it_lets_a_failure_outrank_everything_else() {
    tui_report_reset
    tui_report_row ok a; tui_report_row warn b; tui_report_row fail c; tui_report_row ok d
    assert_eq "$(tui_report_worst)" "fail"
    assert_eq "$(tui_report_exit)"  "1"
}

#[test]
it_finds_a_failure_wherever_it_sits_in_the_run() {
    local pos
    for pos in first middle last; do
        tui_report_reset
        [[ "$pos" == first  ]] && tui_report_row fail x
        tui_report_row ok a
        [[ "$pos" == middle ]] && tui_report_row fail x
        tui_report_row ok b
        [[ "$pos" == last   ]] && tui_report_row fail x
        assert_eq "$(tui_report_exit)" "1"
    done
}

#[test]
it_does_not_let_skipped_or_informational_rows_count_against_a_run() {
    tui_report_reset
    tui_report_row skip a; tui_report_row info b
    # Not applicable is not a problem, and neither is a remark.
    assert_eq "$(tui_report_worst)" "ok"
    assert_eq "$(tui_report_exit)"  "0"
}

#[test]
it_records_a_status_it_does_not_know_as_a_remark() {
    tui_report_reset
    tui_report_row nonsense a "note"
    # Dying on a mistyped status would throw away the results already gathered,
    # which on a long diagnostic run is the expensive half.
    assert_eq "$(tui_report_count info)" "1"
    assert_eq "$(tui_report_exit)" "0"
}

# --- what gets printed ----------------------------------------------------------------

#[test]
it_says_so_when_nothing_was_checked() {
    tui_report_reset
    local out; out="$(tui_report_show "Empty" | _strip)"
    assert_ok grep -q 'Nothing was checked' <<<"$out"
}

#[test]
it_prints_every_row() {
    tui_report_reset
    tui_report_row ok   "disk health" "no reallocated sectors"
    tui_report_row fail "wifi"        "not managed"
    local out; out="$(tui_report_show "Check" | _strip)"
    assert_ok grep -q 'disk health' <<<"$out"
    assert_ok grep -q 'wifi'        <<<"$out"
    assert_ok grep -q 'no reallocated sectors' <<<"$out"
}

#[test]
it_repeats_every_failure_underneath() {
    tui_report_reset
    local i
    for i in $(seq 1 20); do tui_report_row ok "check $i"; done
    tui_report_row fail "the one that matters" "and why"
    local out; out="$(tui_report_show "Long run" | _strip)"
    assert_ok grep -q 'What to look at' <<<"$out"
    # Twice: once in the list, once in the summary that survives scrolling.
    assert_eq "$(grep -c 'the one that matters' <<<"$out")" "2"
    assert_eq "$(grep -c 'and why' <<<"$out")" "2"
}

#[test]
it_repeats_warnings_underneath_too() {
    tui_report_reset
    tui_report_row ok a; tui_report_row warn "low space" "3% left"
    local out; out="$(tui_report_show | _strip)"
    assert_ok grep -q 'What to look at' <<<"$out"
    assert_eq "$(grep -c 'low space' <<<"$out")" "2"
}

#[test]
it_does_not_add_a_what_to_look_at_when_nothing_is_wrong() {
    tui_report_reset
    tui_report_row ok a; tui_report_row ok b; tui_report_row skip c
    local out; out="$(tui_report_show "Fine" | _strip)"
    assert_fails grep -q 'What to look at' <<<"$out"
    assert_ok    grep -q 'nothing wrong'   <<<"$out"
}

#[test]
it_does_not_list_passing_rows_in_the_summary() {
    tui_report_reset
    tui_report_row ok "quiet one"; tui_report_row fail "loud one"
    local out; out="$(tui_report_show | _strip)"
    assert_eq "$(grep -c 'quiet one' <<<"$out")" "1"
}

#[test]
it_counts_out_loud() {
    tui_report_reset
    tui_report_row ok a; tui_report_row ok b; tui_report_row warn c
    tui_report_row fail d; tui_report_row skip e
    local out; out="$(tui_report_show | _strip)"
    assert_ok grep -q '5 checked'        <<<"$out"
    assert_ok grep -q '1 failed'         <<<"$out"
    assert_ok grep -q '1 worth a look'   <<<"$out"
    assert_ok grep -q '1 not applicable' <<<"$out"
}

#[test]
it_lines_the_notes_up() {
    tui_report_reset
    tui_report_row ok "a"                  "first"
    tui_report_row ok "a much longer name" "second"
    local out c1 c2
    out="$(tui_report_show | _strip)"
    c1="$(awk '/first/  { print index($0, "first");  exit }' <<<"$out")"
    c2="$(awk '/second/ { print index($0, "second"); exit }' <<<"$out")"
    # Both notes start in the same column, or it is a list of sentences rather
    # than a table. Guard against both being empty, which would pass silently.
    assert_ok test -n "$c1"
    assert_ok test "$c1" -gt 1
    assert_eq "$c2" "$c1"
}

#[test]
it_does_not_let_one_enormous_name_wreck_the_table() {
    tui_report_reset
    tui_report_row ok "$(printf 'x%.0s' {1..200})" "note"
    tui_report_row ok "short" "note"
    local out; out="$(tui_report_show | _strip)"
    # The column is capped, so a single pathological name does not push every
    # other note off the right of the screen.
    assert_ok grep -q 'short' <<<"$out"
    assert_ok test "$(awk '/short/ { print index($0, "note") }' <<<"$out")" -lt 60
}

#[test]
it_writes_no_control_bytes_with_no_terminal() {
    TUI_TTY=0
    NC=""; BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""
    tui_report_reset
    tui_report_row fail "a" "b"
    local out; out="$(tui_report_show "T")"
    assert_fails grep -q $'\x1b' <<<"$out"
}

#[test]
it_names_the_status_in_words_not_only_in_colour() {
    tui_report_reset
    tui_report_row fail "a"; tui_report_row warn "b"; tui_report_row ok "c"
    local out; out="$(tui_report_show | _strip)"
    # Over ssh to a terminal with no colour, a coloured dot says nothing.
    assert_ok grep -q 'fail' <<<"$out"
    assert_ok grep -q 'warn' <<<"$out"
    assert_ok grep -q 'ok'   <<<"$out"
}

#[test]
it_prints_a_row_with_no_note_at_all() {
    tui_report_reset
    tui_report_row ok "bare"
    local out; out="$(tui_report_show | _strip)"
    assert_ok grep -q 'bare' <<<"$out"
    assert_fails grep -qi 'unbound' <<<"$out"
}
