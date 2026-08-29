#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/verify/digest - Is this file the file it should be
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# nutshell computes a digest and reads one out of somebody's list. Deciding
# whether the two agreeing is good enough is a different job, and this is that
# job: one encapsulated feature, wanted by anything that installs a downloaded
# file, compares two trees, or has to say where something came from.
#
# **The whole point is that there are three answers and not two.** It matched,
# it did not match, and it could not be checked. A machine with no hashing tool
# has verified nothing, and a published list that does not mention this file
# has told you nothing about it, and neither of those is a failure of the file.
# Collapsing them into a boolean is how an unverified download gets installed
# under the impression it was checked.
#
# Usage:
#   . path/to/the-whole-shebang/libs/verify/digest.sh
#
#   verify_digest ./thing.zip "$expected" && echo good
#   case "$?" in 0) ;; 1) echo "wrong file" ;; 2) echo "could not tell" ;; esac
# =============================================================================

[ -n "${_SHEBANG_VERIFY_DIGEST_SH:-}" ] && return 0
_SHEBANG_VERIFY_DIGEST_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'verify: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use hash
use log

# What the three answers are called, so a caller reads a case arm rather than a
# number and the numbers stay where they are.
VERIFY_OK=0
VERIFY_MISMATCH=1
VERIFY_UNKNOWN=2

#[pub]
# Does this file hash to that digest.
#
# **Returns 0 matched, 1 differed, 2 could not tell.** A missing file, a
# missing digest and a machine that cannot hash are all the third answer,
# because in each of them nothing was learned about the file.
#
# Comparison is case-insensitive on the hex, since a published list may be
# upper case and the local tool lower, and a digest that differs only in case
# is the same digest. It is not a prefix match: a truncated digest in a list is
# a broken list, and treating a prefix as agreement would accept it.
# Usage: verify_digest <path> <expected> -> 0 | 1 | 2
verify_digest() {
    local path="${1:-}" want="${2:-}" got rc

    [ -n "$path" ] || { log_error "verify: no file given"; return "$VERIFY_UNKNOWN"; }
    if [ -z "$want" ]; then
        log_warn "verify: no digest published for ${path##*/}, so it is unverified"
        return "$VERIFY_UNKNOWN"
    fi

    got="$(hash_sha256 "$path")"; rc=$?
    case "$rc" in
        0) : ;;
        1) # `hash_sha256` has already said what it could not read. The verdict
           # is the third answer because nothing was learned about the file,
           # which is a different sentence from the one above it.
           log_warn "verify: ${path##*/} is unverified, it could not be read"
           return "$VERIFY_UNKNOWN" ;;
        2) log_warn "verify: ${path##*/} is unverified, this machine cannot hash"
           return "$VERIFY_UNKNOWN" ;;
        127)
           # **This one is about the installation, not about the file.** 127 is
           # the shell saying `hash_sha256` is not a command, which happens when
           # `use hash` resolved against a nutshell that does not carry the
           # module: an older pin, or a mirror an hour behind a merge.
           #
           # The verdict stays the third answer, since nothing was learned about
           # the file either way, and that is the whole reason this needs a
           # sentence of its own. A caller cannot tell the two apart from the
           # return, so if this stays quiet it reads exactly like a project that
           # published no sums, and downloads get installed under the impression
           # something checked them.
           log_error "verify: ${path##*/} is unverified, and this is broken rather than unknown"
           log_error "verify: hash_sha256 is not there at all, so \`use hash\` found a nutshell without it"
           return "$VERIFY_UNKNOWN" ;;
        *) log_error "verify: ${path##*/} is unverified, hashing exited ${rc}"
           return "$VERIFY_UNKNOWN" ;;
    esac

    got="$(printf '%s' "$got"  | tr 'A-F' 'a-f')"
    want="$(printf '%s' "$want" | tr 'A-F' 'a-f')"

    if [ "$got" = "$want" ]; then
        return "$VERIFY_OK"
    fi
    log_error "verify: ${path##*/} hashes to ${got}"
    log_error "verify: and it should be     ${want}"
    return "$VERIFY_MISMATCH"
}

#[pub]
# The same, against a published sums list rather than one digest.
#
# The list is a path or `-` for standard input, which is the shape a caller has
# when it fetched the list and never wrote it down. A name the list does not
# mention is the third answer, not the second: an unlisted file is unverified
# rather than wrong.
# Usage: verify_against_sums <path> <sums file|-> [name in the list] -> 0 | 1 | 2
verify_against_sums() {
    local path="${1:-}" sums="${2:-}" name="${3:-}" want
    [ -n "$path" ] && [ -n "$sums" ] || return "$VERIFY_UNKNOWN"
    [ -n "$name" ] || name="${path##*/}"

    if [ "$sums" = "-" ]; then
        want="$(hash_sums_pick "$name")" || want=""
    else
        want="$(hash_sums_get "$sums" "$name")" || want=""
    fi

    if [ -z "$want" ]; then
        log_warn "verify: ${name} is not in the list, so it is unverified"
        return "$VERIFY_UNKNOWN"
    fi
    verify_digest "$path" "$want"
}

#[pub]
# What the answer was, in words, for a report a person reads.
# Usage: verify_say <code> -> a phrase
verify_say() {
    case "${1:-}" in
        0) printf 'checked'   ;;
        1) printf 'does not match what was published' ;;
        *) printf 'unverified' ;;
    esac
}

#[pub]
# Whether an answer should stop what the caller was doing.
#
# **A mismatch stops it and an unknown does not**, which is the policy this
# library takes a position on so that every caller does not invent its own. A
# file that hashes to the wrong thing is the wrong file and installing it is
# never right; a file nobody published a digest for is the ordinary case on
# plenty of projects, and refusing it would mean refusing most of them.
#
# A caller wanting the stricter rule tests for `VERIFY_OK` instead, which is
# why this is a separate question rather than baked into the return.
# Usage: verify_is_fatal <code>
verify_is_fatal() { [ "${1:-}" = "1" ]; }
