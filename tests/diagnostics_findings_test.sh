#!/usr/bin/env bash
# Tests for findings and the verdict.
#
# This library predates every other one here and had no tests at all. It is
# also the one whose whole point is an exit code somebody else branches on: a
# hook, a cron line, a release gate. A wrong code is silent by construction,
# since the caller acts on it instead of reading the text.
#
# So most of what is below is about the code rather than the words, and the
# ordering between the two kinds of finding, which is the part an obvious
# implementation gets wrong: a run with one blocking finding and forty needing
# judgement is blocked, and a verdict that counted the majority would say
# otherwise.

use test

. "${BASH_SOURCE[0]%/*}/../libs/diagnostics/findings.sh"

# The verdict's status, with its output out of the way.
_verdict() { findings_verdict >/dev/null 2>&1; }

# What it printed, with its status out of the way.
_verdict_says() { findings_verdict 2>/dev/null || true; }

_fresh() {
    findings_reset
    _FINDINGS_BLOCK_TEXT=""; _FINDINGS_JUDGE_TEXT=""; _FINDINGS_CLEAN_TEXT="clean."
}

# --- the counts --------------------------------------------------------------

#[test]
it_starts_at_nothing() {
    _fresh
    assert_eq "$(findings_blocking)" "0"
    assert_eq "$(findings_judgement)" "0"
}

#[test]
it_counts_each_kind_apart_from_the_other() {
    _fresh
    finding_block "a" >/dev/null 2>&1
    finding_block "b" >/dev/null 2>&1
    finding_judge "c" >/dev/null 2>&1

    assert_eq "$(findings_blocking)" "2"
    assert_eq "$(findings_judgement)" "1"
}

#[test]
it_does_not_count_a_note_as_a_finding() {
    # A note is a continuation line under the finding above it. Counting it
    # would make a well-explained finding weigh more than a terse one.
    _fresh
    finding_block "a" >/dev/null 2>&1
    finding_note "why" >/dev/null 2>&1
    finding_note "and what to do" >/dev/null 2>&1

    assert_eq "$(findings_blocking)" "1"
    assert_eq "$(findings_judgement)" "0"
}

#[test]
it_forgets_everything_when_reset() {
    _fresh
    finding_block "a" >/dev/null 2>&1
    finding_judge "b" >/dev/null 2>&1
    findings_reset

    assert_eq "$(findings_blocking)" "0"
    assert_eq "$(findings_judgement)" "0"
    # And the verdict agrees, which is the thing a script checking several
    # subjects in one run depends on.
    assert_ok _verdict
}

# --- the status, which is what a caller actually reads -----------------------

#[test]
it_returns_zero_when_nothing_was_found() {
    _fresh
    assert_ok _verdict
}

#[test]
it_returns_one_for_something_blocking() {
    _fresh
    finding_block "a" >/dev/null 2>&1
    local rc=0; _verdict || rc=$?
    assert_eq "$rc" "1"
}

#[test]
it_returns_three_for_something_needing_judgement() {
    # Three rather than two, because two is what a shell hands back for a
    # misused builtin and a caller cannot tell the two apart.
    _fresh
    finding_judge "a" >/dev/null 2>&1
    local rc=0; _verdict || rc=$?
    assert_eq "$rc" "3"
}

#[test]
it_blocks_on_one_blocking_finding_under_any_number_of_judgements() {
    # The ordering, and the case an implementation counting the majority gets
    # wrong. One fact that stops the caller outranks forty things somebody
    # might weigh differently.
    _fresh
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do finding_judge "j$i" >/dev/null 2>&1; done
    finding_block "the one that matters" >/dev/null 2>&1

    assert_eq "$(findings_judgement)" "10"
    assert_eq "$(findings_blocking)" "1"
    local rc=0; _verdict || rc=$?
    assert_eq "$rc" "1"
}

#[test]
it_does_not_block_on_judgements_alone_however_many() {
    # The control for the one above. A verdict that returned 1 whenever
    # anything at all was recorded would satisfy it and be useless.
    _fresh
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do finding_judge "j$i" >/dev/null 2>&1; done
    local rc=0; _verdict || rc=$?
    assert_eq "$rc" "3"
}

# --- what it says ------------------------------------------------------------

#[test]
it_says_the_clean_line_when_there_is_nothing() {
    _fresh
    assert_contains "$(_verdict_says)" "clean."
}

#[test]
it_says_the_text_the_script_set_for_each_case() {
    _fresh
    findings_explain "this is blocked" "somebody has to look" "all fine here"

    assert_contains "$(_verdict_says)" "all fine here"

    finding_judge "a" >/dev/null 2>&1
    assert_contains "$(_verdict_says)" "somebody has to look"

    finding_block "b" >/dev/null 2>&1
    assert_contains "$(_verdict_says)" "this is blocked"
}

#[test]
it_keeps_the_clean_line_it_had_when_only_two_are_given() {
    # The third argument is optional and what it defaults to is the library's,
    # not the caller's. Read in its own shell, because `_fresh` above assigns
    # that default itself: asserting it here would have been a test of the
    # fixture, and emptying the library's default killed nothing.
    local said
    said="$(bash -c '
        . "$1"/init || exit 1
        . "$2"
        findings_explain "blocked" "judge"
        findings_verdict 2>/dev/null || true
    ' _ "${NUTSHELL_INIT%/init}" "${BASH_SOURCE[0]%/*}/../libs/diagnostics/findings.sh")"

    assert_ne "${said//[[:space:]]/}" ""
    assert_contains "$said" "clean"
}

#[test]
it_says_nothing_extra_when_a_case_has_no_text() {
    # An unset case prints the finding lines and no closing line, rather than
    # an empty one or the word "null". The status still says what happened.
    _fresh
    finding_block "a" >/dev/null 2>&1
    local said; said="$(_verdict_says)"
    assert_eq "${said//[[:space:]]/}" ""
}

#[test]
it_survives_a_message_full_of_format_characters() {
    # The messages come from whatever the caller found, which includes file
    # contents. A `%s` reaching a bare `printf` as its format is how a
    # reporting library corrupts the report it exists to produce.
    #
    # The finding's own output is captured, not discarded. Discarded, this
    # asserted only the count and the closing line, and routing every message
    # through `printf "$*"` killed nothing.
    #
    # Through a file rather than a command substitution, because a substitution
    # is a subshell and the counter increment would not come back out of it.
    # Written the other way first, and the count came back 0.
    _fresh
    local f; f="$(mktemp)"
    finding_block 'saw %s and %d and 100%% in a file' >"$f" 2>&1
    local said; said="$(cat "$f")"; rm -f "$f"

    assert_contains "$said" "saw %s and %d and 100%% in a file"
    assert_eq "$(findings_blocking)" "1"
}

#[test]
it_keeps_a_format_character_in_the_closing_line_too() {
    # The other half, and the one a caller sets rather than finds. Same hazard,
    # different `printf`.
    _fresh
    findings_explain '100%s of them are blocked' 'a %d thing'
    finding_block "a" >/dev/null 2>&1
    assert_contains "$(_verdict_says)" "100%s of them are blocked"
}
