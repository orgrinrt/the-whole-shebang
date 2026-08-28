#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tests/pin_test.sh - The nutshell this repository asks for
# =============================================================================
# Three hand-checks that decided a change, kept so nobody has to run them by
# hand again. The pin replaced 715 lines of resolver, so what it does is worth
# a test in a way a manifest key usually is not.
# =============================================================================

TROOT="${BASH_SOURCE[0]%/*}/.."

# The predicate the test asserts, over one manifest. Written as a function so
# the fixtures below can drive it both ways: a check that only ever reads the
# real manifest cannot show that it is capable of failing.
_pin_is_above_the_first_table() {
    local ft pn
    ft="$(grep -n '^\[' "$1" | head -1 | cut -d: -f1)"
    pn="$(grep -n '^nutshell_branch' "$1" | head -1 | cut -d: -f1)"
    [ -n "$ft" ] && [ -n "$pn" ] && [ "$pn" -lt "$ft" ]
}

#[test]
it_keeps_the_pin_above_the_first_table() {
    # A bare key after a table header belongs to that table, so `nutshell_branch`
    # under `[meta]` is a pin nothing reads and nothing complains about. The
    # manifest's own comment says so; this is what makes the comment enforceable.
    assert_ok _pin_is_above_the_first_table "$TROOT/nut.toml"
}

#[test]
it_notices_a_pin_that_slid_under_a_table() {
    # The control for the one above. Without it that test passes whether or not
    # the predicate can tell the two apart.
    local good bad
    good="$(mktemp)"; bad="$(mktemp)"
    printf 'nutshell_branch = "dev"\n\n[meta]\nv = 1\n' > "$good"
    printf '[meta]\nnutshell_branch = "dev"\nv = 1\n'   > "$bad"
    assert_ok    _pin_is_above_the_first_table "$good"
    assert_fails _pin_is_above_the_first_table "$bad"
    rm -f "$good" "$bad"
}

#[test]
it_notices_a_manifest_with_no_pin_at_all() {
    # The other way a pin goes missing, and the one a placement check will
    # happily call fine if it only ever compares two line numbers it found.
    local none
    none="$(mktemp)"
    printf '[meta]\nv = 1\n' > "$none"
    assert_fails _pin_is_above_the_first_table "$none"
    rm -f "$none"
}

#[test]
it_resolves_a_nutshell_new_enough_for_this_repository() {
    # The pin fails open: an unreachable ref leaves the ambient nutshell in
    # place and everything runs against whatever the machine has. When that one
    # is too old the failures land on this repository's tests and read as a
    # defect here, which is exactly what happened at 0.4.1, before `array` was
    # renamed `list`.
    local min="0.7.0" got="${NUTSHELL_VERSION:-0.0.0}"
    assert_eq "$(printf '%s\n%s\n' "$min" "$got" | sort -V | head -1)" "$min"
}

#[test]
it_takes_the_first_argument_as_dollar_one() {
    # `nutshell -c` does not take bash's argv0 placeholder: `$1` is the first
    # argument given, not the second. A test that sources `"$1"` gets a
    # different file if that ever changes, and the failure would not read as an
    # argument-convention change. This repository tracks the head of `dev`, so
    # it would arrive without warning.
    assert_eq "$(nutshell -c 'printf %s "$1"' one two)" "one"
    assert_eq "$(nutshell -c 'printf %s "$2"' one two)" "two"
}
