#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tests/bash_floor_test.sh - what the declared floor allows
# =============================================================================
# `"${arr[@]}"` on an array with no assigned elements throws under `set -u`
# before bash 4.4, and `bin/nutshell` sets `-u` before sourcing anything. The
# floor this library declares is 4.0, so the guarded form
# `${arr[@]+"${arr[@]}"}` is what an expansion over a possibly-empty array
# looks like here, and the tree carries it in sixteen places already.
#
# The two that were not guarded were reached by fixtures in this same suite,
# `_tui_action_key_names ""` and `_tui_menu_wrap` on empty text, and both
# passed on a machine running 5.3 where the expansion is legal. So the suite
# could not see it and no machine here can, which is what this file is for: it
# asks the source rather than the interpreter, and it holds on any bash.
#
# It reads the library tree rather than one file, because the defect is a habit
# and the next instance will be somewhere nobody is looking.
# =============================================================================

use test

TROOT="${BASH_SOURCE[0]%/*}/.."

# Every unguarded expansion of an array in a `for` header, one `file:line` per
# line. A comment is not code, so a usage example in a doc block showing a
# caller's own array is left out.
# This file itself is skipped, because it has to spell the shape it refuses in
# order to prove it can see one. The same carve-out nutshell's advert detector
# takes, and for the same reason: a detector that its own pattern matches
# reports itself forever and teaches everybody to ignore the line.
_bare_expansions() { # <dir>
    grep -rnE 'in[[:space:]]+"\$\{[a-zA-Z_]+\[@\]\}"' --include='*.sh' "$1" 2>/dev/null \
        | grep -vE ':[0-9]+:[[:space:]]*#' \
        | grep -v 'bash_floor_test\.sh:' \
        || true
}

#[test]
no_library_file_expands_an_array_without_the_guard() {
    local found; found="$(_bare_expansions "${TROOT}/libs")"
    assert_eq "$found" ""
}

#[test]
no_test_file_expands_an_array_without_the_guard() {
    # The suite runs under the same interpreter and the same `-u`, so a test
    # that throws on 4.0 reports the library broken when it is not.
    local found; found="$(_bare_expansions "${TROOT}/tests")"
    assert_eq "$found" ""
}

#[test]
the_check_can_tell_a_guarded_expansion_from_a_bare_one() {
    # The control. Without it both arms above pass on a build where the grep
    # matches nothing at all, which is what an empty result looks like either
    # way, and that is the failure this whole file exists to make visible.
    local d; d="$(mktemp -d)"
    printf 'for x in "${a[@]}"; do :; done\n' > "${d}/bare.sh"
    printf 'for x in ${a[@]+"${a[@]}"}; do :; done\n' > "${d}/guarded.sh"
    printf '#   for x in "${a[@]}"; do :; done\n' > "${d}/comment.sh"

    local found; found="$(_bare_expansions "$d")"
    assert_contains "$found" "bare.sh"
    assert_not_contains "$found" "guarded.sh"
    assert_not_contains "$found" "comment.sh"
    rm -rf "$d"
}
