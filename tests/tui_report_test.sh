#!/usr/bin/env bash
# Tests for the report.
#
# Two contracts. The exit status has to be usable by something that never reads
# the text (a hook, a cron line, another script), so "nothing wrong", "worth a
# look" and "broken" must stay distinguishable. And every failure has to
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
    # The colour variables are set here, deliberately, to real escapes. The
    # first version of this test blanked them and then asserted that no escapes
    # appeared, proving only that it had blanked them, in the one place a
    # reader would look to find out whether the module is safe in a pipe.
    local RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m'
    local DIM=$'\033[2m'  BOLD=$'\033[1m'  NC=$'\033[0m'
    TUI_TTY=0; TUI_COLOR=0
    tui_report_reset
    tui_report_row fail "a" "b"
    tui_report_row ok   "c" "d"
    local out; out="$(tui_report_show "T")"
    assert_fails grep -q $'\x1b' <<<"$out"
}

#[test]
it_writes_colour_when_there_is_a_terminal_that_wants_it() {
    # The other half. Without it, the test above is satisfied by a module that
    # never emits colour at all, and nothing would notice colour disappearing.
    local RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m'
    local DIM=$'\033[2m'  BOLD=$'\033[1m'  NC=$'\033[0m'
    TUI_TTY=1; TUI_COLOR=1
    tui_report_reset
    tui_report_row fail "a" "b"
    local out; out="$(tui_report_show "T")"
    assert_ok grep -q $'\x1b' <<<"$out"
    TUI_TTY=0; TUI_COLOR=0
}

#[test]
it_names_the_status_in_words_not_only_in_colour() {
    tui_report_reset
    tui_report_row fail "alpha"; tui_report_row warn "beta"; tui_report_row ok "gamma"
    local out; out="$(tui_report_show | _strip)"
    # Anchored to the row the status belongs to. Unanchored, `grep -q ok`
    # matched the word "look" in the summary line and `grep -q fail` matched
    # "1 failed", so two thirds of this survived the marks being deleted.
    assert_ok grep -qE '^ +fail +alpha' <<<"$out"
    assert_ok grep -qE '^ +warn +beta'  <<<"$out"
    assert_ok grep -qE '^ +ok +gamma'   <<<"$out"
}

#[test]
it_has_a_detector_that_notices_the_marks_going_missing() {
    # The positive control for the test above, which is the one that was
    # fooled. With the mark emptied, the anchored patterns must stop matching.
    _tui_report_mark() { printf ''; }
    tui_report_reset
    tui_report_row fail "alpha"
    local out; out="$(tui_report_show | _strip)"
    assert_fails grep -qE '^ +fail +alpha' <<<"$out"
    unset -f _tui_report_mark
    . "${BASH_SOURCE[0]%/*}/../libs/tui/report.sh" 2>/dev/null || true
}

#[test]
it_prints_a_row_with_no_note_at_all() {
    tui_report_reset
    tui_report_row ok "bare"
    local out; out="$(tui_report_show 2>&1 | _strip)"
    assert_ok grep -q 'bare' <<<"$out"
    # 2>&1 inside the substitution, or the diagnostic this looks for goes to
    # stderr, is never captured, and the assertion cannot fail.
    assert_fails grep -qi 'unbound' <<<"$out"
}

# --- recording from an exit status ------------------------------------------------

#[test]
it_records_a_success_from_a_command_that_worked() {
    tui_report_reset
    tui_report_run "a check" "would have failed" true
    assert_eq "$(tui_report_count ok)"   "1"
    assert_eq "$(tui_report_count fail)" "0"
}

#[test]
it_records_a_failure_with_the_note_it_was_given() {
    tui_report_reset
    tui_report_run "a check" "the reason it matters" false
    assert_eq "$(tui_report_count fail)" "1"
    assert_ok grep -q 'the reason it matters' <<<"$(tui_report_show | _strip)"
}

#[test]
it_keeps_a_commands_output_out_of_the_report() {
    tui_report_reset
    tui_report_run "noisy" "note" bash -c 'echo to-stdout; echo to-stderr >&2; true'
    local out; out="$(tui_report_show | _strip)"
    # A report is a table. A command that prints a page would destroy it.
    assert_fails grep -q 'to-stdout' <<<"$out"
    assert_fails grep -q 'to-stderr' <<<"$out"
}

#[test]
it_passes_the_arguments_the_command_needs() {
    tui_report_reset
    tui_report_run "args" "note" bash -c '[[ "$1" == "expected" ]]' _ expected
    assert_eq "$(tui_report_count ok)" "1"
}

#[test]
it_cuts_a_name_too_long_for_its_column() {
    tui_report_reset
    tui_report_row ok "$(printf 'x%.0s' {1..80})" "note"
    tui_report_row ok "short" "note"
    local out c1 c2; out="$(tui_report_show | _strip)"
    c1="$(awk '/note/ { print index($0, "note"); exit }' <<<"$out")"
    c2="$(awk '/note/ { n = index($0, "note") } END { print n }' <<<"$out")"
    # Both notes in the same column. Padding cannot shorten an over-long name,
    # so without cutting it the row runs past where the header said it would.
    assert_eq "$c2" "$c1"
}
