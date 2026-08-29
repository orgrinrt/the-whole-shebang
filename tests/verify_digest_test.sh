#!/usr/bin/env bash
# Tests for deciding whether a file is the file it should be.
#
# The whole subject is that there are three answers and not two, so most of
# what is below is about which of the three came back rather than about the
# hashing, which is nutshell's and is tested there.
#
# The third answer is the one an obvious implementation loses. "This machine
# cannot hash" and "nobody published a digest for this" are both "I learned
# nothing about the file", and a boolean turns them into "it failed" or, far
# worse, into "it passed".

use test

. "${BASH_SOURCE[0]%/*}/../libs/verify/digest.sh"

_v_setup() {
    VROOT="$(mktemp -d)"
    printf 'hello\n' > "$VROOT/f"
    mkdir -p "$VROOT/empty"
    if command -v sha256sum >/dev/null 2>&1; then VSUM="$(sha256sum < "$VROOT/f")"
    else VSUM="$(shasum -a 256 < "$VROOT/f")"; fi
    VSUM="${VSUM%% *}"
}
_v_end() { rm -rf "$VROOT"; unset VROOT VSUM; }

#[test]
it_says_matched_when_it_matches() {
    _v_setup
    verify_digest "$VROOT/f" "$VSUM"; assert_eq "$?" "0"
    _v_end
}

#[test]
it_says_mismatch_when_the_file_is_a_different_file() {
    _v_setup
    verify_digest "$VROOT/f" "0000000000000000000000000000000000000000000000000000000000000000" 2>/dev/null
    assert_eq "$?" "1"
    _v_end
}

#[test]
a_machine_that_cannot_hash_gets_the_third_answer_and_not_a_mismatch() {
    # **The one that matters.** Reporting this as a mismatch condemns a file
    # nobody looked at, and reporting it as a match installs one.
    _v_setup
    local saved="$PATH"; PATH="$VROOT/empty"
    verify_digest "$VROOT/f" "$VSUM" 2>/dev/null; local rc=$?
    PATH="$saved"
    assert_eq "$rc" "2"
    _v_end
}

#[test]
a_missing_digest_gets_the_third_answer_too() {
    # Plenty of projects publish no sums at all. That is a fact about the
    # project rather than about the file, and it is the ordinary case.
    _v_setup
    verify_digest "$VROOT/f" "" 2>/dev/null; assert_eq "$?" "2"
    _v_end
}

#[test]
a_missing_file_is_not_a_mismatch_either() {
    _v_setup
    verify_digest "$VROOT/nosuch" "$VSUM" 2>/dev/null; assert_eq "$?" "2"
    verify_digest "" "$VSUM" 2>/dev/null;              assert_eq "$?" "2"
    _v_end
}

#[test]
it_reads_the_same_digest_in_either_case() {
    # A published list may be upper case and the local tool lower. Same digest.
    _v_setup
    verify_digest "$VROOT/f" "$(printf '%s' "$VSUM" | tr 'a-f' 'A-F')"
    assert_eq "$?" "0"
    _v_end
}

#[test]
a_truncated_digest_is_a_mismatch_and_not_a_prefix_match() {
    # A short digest in a list is a broken list. Accepting a prefix would let
    # one through, and a one-character "digest" would match nearly everything.
    _v_setup
    verify_digest "$VROOT/f" "${VSUM:0:16}" 2>/dev/null; assert_eq "$?" "1"
    verify_digest "$VROOT/f" "${VSUM:0:1}"  2>/dev/null; assert_eq "$?" "1"
    _v_end
}

#[test]
it_names_both_digests_when_they_differ() {
    # So whoever reads the failure can see which one is the odd one, rather
    # than being told only that something was wrong.
    _v_setup
    local out; out="$(verify_digest "$VROOT/f" "abc123" 2>&1)"
    assert_contains "$out" "$VSUM"
    assert_contains "$out" "abc123"
    _v_end
}

#[test]
it_checks_against_a_published_list() {
    _v_setup
    printf '%s  f\nffff  other.zip\n' "$VSUM" > "$VROOT/SUMS"
    verify_against_sums "$VROOT/f" "$VROOT/SUMS"; assert_eq "$?" "0"
    _v_end
}

#[test]
it_takes_the_list_off_stdin_too() {
    # The shape a caller has when it fetched the list and never wrote it down.
    _v_setup
    printf '%s  f\n' "$VSUM" > "$VROOT/SUMS"
    verify_against_sums "$VROOT/f" - < "$VROOT/SUMS"; assert_eq "$?" "0"
    _v_end
}

#[test]
a_name_the_list_does_not_mention_is_unverified_rather_than_wrong() {
    # A list covering three of four published files is ordinary, and the fourth
    # has not failed anything.
    _v_setup
    printf 'ffff  other.zip\n' > "$VROOT/SUMS"
    verify_against_sums "$VROOT/f" "$VROOT/SUMS" 2>/dev/null; assert_eq "$?" "2"
    _v_end
}

#[test]
it_checks_the_name_the_caller_names_rather_than_the_local_filename() {
    # A download saved to a temporary path still has to be looked up under the
    # name the project published it as.
    _v_setup
    cp "$VROOT/f" "$VROOT/downloaded.tmp"
    printf '%s  real-name.zip\n' "$VSUM" > "$VROOT/SUMS"
    verify_against_sums "$VROOT/downloaded.tmp" "$VROOT/SUMS" 2>/dev/null
    assert_eq "$?" "2"
    verify_against_sums "$VROOT/downloaded.tmp" "$VROOT/SUMS" real-name.zip
    assert_eq "$?" "0"
    _v_end
}

#[test]
a_list_that_disagrees_with_the_file_is_a_mismatch() {
    # The list is present and names the file, and the file is the wrong one.
    # That is the second answer, not the third.
    _v_setup
    printf '0000000000000000000000000000000000000000000000000000000000000000  f\n' > "$VROOT/SUMS"
    verify_against_sums "$VROOT/f" "$VROOT/SUMS" 2>/dev/null; assert_eq "$?" "1"
    _v_end
}

#[test]
only_a_mismatch_stops_the_caller() {
    # The policy this library takes a position on so every caller does not
    # invent its own. A wrong file is never installable; an unverified one is
    # the ordinary case on plenty of projects and refusing it would refuse most
    # of them.
    assert_ok    verify_is_fatal 1
    assert_fails verify_is_fatal 0
    assert_fails verify_is_fatal 2
}

#[test]
each_answer_has_words_of_its_own() {
    # Three phrases, all different, because a report saying the same thing for
    # a checked file and an unverified one is the boolean coming back in prose.
    assert_eq "$(verify_say 0)" "checked"
    assert_ne "$(verify_say 1)" "$(verify_say 0)"
    assert_ne "$(verify_say 2)" "$(verify_say 0)"
    assert_ne "$(verify_say 2)" "$(verify_say 1)"
    assert_contains "$(verify_say 2)" "unverified"
}

# A broken installation is the third answer, and it says so in different words.
#
# `hash_sha256` missing gives 127, which used to fall to a catch-all arm that
# returned the third answer and printed nothing at all. The verdict is right,
# since nothing was learned about the file either way, and printing nothing is
# what made it dangerous: the caller cannot tell the two apart from the return,
# so a library that will not load reads exactly like a project that published
# no sums, and `install.sh` installs on that word.
#
# What is asserted is both halves: the verdict stays 2, and the words differ.
#[test]
a_library_that_did_not_load_says_so_rather_than_looking_like_no_digest() {
    _v_setup
    local saved out rc
    saved="$(declare -f hash_sha256)"
    unset -f hash_sha256

    out="$(verify_digest "$VROOT/f" "$VSUM" 2>&1)"; rc=$?
    assert_eq "$rc" "2"
    assert_ok grep -qi 'broken rather than unknown' <<<"$out"
    assert_ok grep -qi 'hash_sha256 is not there' <<<"$out"

    # And it does not read like the no-digest case, which is the confusion.
    assert_fails grep -qi 'no digest published' <<<"$out"

    eval "$saved"
    _v_end
}

# The control for the test above: with the module present the same call is
# quiet about installations and returns the first answer, so the assertions
# there are reachable rather than true of anything.
#[test]
it_says_nothing_about_a_broken_install_when_nothing_is_broken() {
    _v_setup
    local out
    out="$(verify_digest "$VROOT/f" "$VSUM" 2>&1)"
    assert_fails grep -qi 'broken rather than unknown' <<<"$out"
    _v_end
}

# An unreadable file is the third answer too, and it had no sentence either.
#[test]
a_file_that_cannot_be_read_is_unverified_and_says_which() {
    _v_setup
    local out rc
    out="$(verify_digest "$VROOT/nosuch" "$VSUM" 2>&1)"; rc=$?
    assert_eq "$rc" "2"
    assert_ok grep -qi 'could not be read' <<<"$out"
    _v_end
}
