#!/usr/bin/env bash
# Tests for the copy of nutshell's resolver that this repository carries.
#
# `lib/find-nutshell` is a copy. It has to be: it is what finds nutshell, so it
# cannot be fetched by the thing it finds. The cost is that it drifts, and a
# stale one is quiet about it. It goes on resolving whatever it understood when
# it was copied and simply does not know a pin shape added since, and the error
# a consumer sees is about a missing module rather than about an old resolver.
#
# Nothing else in either repository notices that. This does.
#
# The copy is kept byte for byte identical to the original, which is why the
# check below is a plain `diff` and not a version comparison. There is no
# version string in that file to compare, and a note added on this side would
# have to be excluded from the check, which is how a check for drift starts
# tolerating drift. So the explanation lives here instead of in the file.

use test

_fnc_ours() { printf '%s' "${BASH_SOURCE[0]%/*}/../lib/find-nutshell"; }

# The one it was copied from, out of whatever nutshell this suite resolved.
_fnc_theirs() {
    local root="${NUTSHELL_INIT%/init}"
    [[ -n "$root" && -r "${root}/find-nutshell" ]] || return 1
    printf '%s' "${root}/find-nutshell"
}

#[test]
it_carries_a_copy_at_all() {
    assert_ok test -r "$(_fnc_ours)"
    # And it is the resolver rather than something else of that name.
    assert_ok grep -q 'nutshell_find()' "$(_fnc_ours)"
}

#[test]
it_has_not_drifted_from_the_nutshell_it_resolved() {
    local theirs
    if ! theirs="$(_fnc_theirs)"; then
        # Resolved to something with no resolver beside it, which is a vendored
        # or hand-placed nutshell. Nothing to compare against, and saying so
        # beats passing quietly.
        assert_ne "${NUTSHELL_INIT:-}" ""
        return 0
    fi
    # The whole file. There is no version string in it to compare, and the
    # drift that matters is in the resolution order rather than in any number.
    if ! diff -q "$(_fnc_ours)" "$theirs" >/dev/null 2>&1; then
        printf 'the copy at lib/find-nutshell has drifted from %s\n' "$theirs"
        printf 'copy it across, or say here why the two should differ:\n'
        diff "$theirs" "$(_fnc_ours)" | head -20
    fi
    assert_ok diff -q "$(_fnc_ours)" "$theirs"
}

#[test]
it_depends_on_nothing_that_needs_nutshell() {
    # The property that makes it copyable in the first place. A `use` in here
    # would need the thing it is looking for.
    local ours; ours="$(_fnc_ours)"
    assert_empty "$(grep -nE '^[[:space:]]*use[[:space:]]' "$ours" || true)"
    assert_empty "$(grep -nE '^[[:space:]]*\. .*(init|lib/)' "$ours" || true)"
}
