#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/diagnostics - Severity-tagged findings and a verdict
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Source this file directly; it pulls in what it needs from nutshell and
# nothing else. Nothing here depends on another shebang library, which is the
# whole arrangement: a library you can take without taking the collection.
#
# It borrows nutshell's log formatter rather than printing its own shape, so a
# finding reads the same as every other line in a run.
#
# The name is `diagnostics` rather than `analyser` or `diagnoser` because this
# analyses nothing. The caller does the examining; this records what was found,
# separates what stops the world from what wants attention, and renders the
# verdict. That is what a compiler means by the word, and it is what viola
# means by it.
#
# Every check script grows the same three things: a way to record something it
# found, a way to distinguish what stops the world from what merely wants a
# human's attention, and an exit code that says which happened. Written fresh
# each time they disagree with each other, which matters because a caller
# branching on exit codes cannot tell a script that found nothing from one that
# forgot to report.
#
# The severities are deliberately two rather than five. A check that offers
# four shades of concern makes the reader do the triage the check was supposed
# to do, and in practice everything lands as either "this cannot proceed" or
# "someone has to look at this".
#
# Usage:
#   use shebang::diagnostics
#
#   finding_block "version moved on a feature branch"
#   finding_note  "A version moves on a release. If this PR is one, say so."
#   finding_judge "README is 94 days older than the last commit"
#
#   findings_verdict          # prints the summary, returns 0, 1 or 3
#
# Exit codes, which are the interface between a check and whatever runs it:
#   0  nothing found
#   1  at least one blocking finding
#   3  findings needing judgement, none of them blocking
# =============================================================================

[[ -n "${_SHEBANG_DIAGNOSTICS_SH:-}" ]] && return 0
readonly _SHEBANG_DIAGNOSTICS_SH=1

# nutshell has to be initialised first. Erroring here beats failing later on an
# undefined `log_tagged`, where the message names a symbol rather than the
# setup step that was skipped.
if ! declare -F use >/dev/null 2>&1; then
    printf 'diagnostics: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use log

declare -gi _FINDINGS_BLOCK=0
declare -gi _FINDINGS_JUDGE=0
_FINDINGS_BLOCK_TEXT=""
_FINDINGS_JUDGE_TEXT=""
_FINDINGS_CLEAN_TEXT="clean."

# -----------------------------------------------------------------------------
# Recording
# -----------------------------------------------------------------------------

#[pub]
# Record something that stops the caller.
#
# A fact rather than an opinion: a named type that does not exist, a dead link,
# a version that moved.
# Usage: finding_block <message>
finding_block() {
    log_tagged "BLOCK" red "$*"
    _FINDINGS_BLOCK+=1
}

#[pub]
# Record something a human or a reviewing agent has to weigh.
#
# Never used for a fact that speaks for itself, because routing a fact through
# someone's judgement is how it gets waved through.
# Usage: finding_judge <message>
finding_judge() {
    log_tagged "JUDGE" yellow "$*"
    _FINDINGS_JUDGE+=1
}

#[pub]
# A continuation line under the finding above it.
#
# Where a check says what the finding means and what to do about it, which is
# the difference between a report a reader can act on and a list they have to
# interpret.
#
# It is one call to nutshell's formatter and it stays a function of its own,
# because the vocabulary is the library. A check that has to reach past this to
# a log call for its second line has been handed two shapes for one report.
# Usage: finding_note <message>
finding_note() {
    log_substep "$*"
}

# -----------------------------------------------------------------------------
# Counting
# -----------------------------------------------------------------------------

#[pub]
# How many blocking findings have been recorded.
# Usage: findings_blocking -> a count
findings_blocking() { printf '%d' "$_FINDINGS_BLOCK"; }

#[pub]
# How many findings needing judgement have been recorded.
# Usage: findings_judgement -> a count
findings_judgement() { printf '%d' "$_FINDINGS_JUDGE"; }

#[pub]
# Start the counts again, for a script checking several subjects in one run
# and reporting each.
# Usage: findings_reset
findings_reset() {
    _FINDINGS_BLOCK=0
    _FINDINGS_JUDGE=0
}

# -----------------------------------------------------------------------------
# The verdict
# -----------------------------------------------------------------------------

#[pub]
# What the verdict says in each case.
#
# Set per script, because "blocking" means something different to a reviewer
# than to a release gate, and the closing line is the part a reader acts on.
# Usage: findings_explain <blocking-text> <judgement-text> [clean-text]
findings_explain() {
    _FINDINGS_BLOCK_TEXT="$1"
    _FINDINGS_JUDGE_TEXT="$2"
    [[ $# -ge 3 ]] && _FINDINGS_CLEAN_TEXT="$3"
}

#[pub]
# Print the closing text for whichever case holds, and return the exit code for
# it. The last thing a check script does.
# Usage: findings_verdict -> 0 clean, 1 blocking, 3 judgement
findings_verdict() {
    printf '\n'
    if (( _FINDINGS_BLOCK > 0 )); then
        [[ -n "$_FINDINGS_BLOCK_TEXT" ]] && printf '%s\n' "$_FINDINGS_BLOCK_TEXT"
        return 1
    fi
    if (( _FINDINGS_JUDGE > 0 )); then
        [[ -n "$_FINDINGS_JUDGE_TEXT" ]] && printf '%s\n' "$_FINDINGS_JUDGE_TEXT"
        return 3
    fi
    printf '%s\n' "$_FINDINGS_CLEAN_TEXT"
    return 0
}
