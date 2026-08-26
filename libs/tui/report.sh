#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/report - What was checked and how it went
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# For a run of checks that each pass, fail or have something to say. Diagnostics
# mostly: thirty things looked at, twenty-eight fine, one worrying, one broken.
#
# The shape is the point. A wall of prose hides the one line that mattered, and
# a bare exit code says nothing at all. What someone wants, in order, is: is
# anything wrong, what, and what should they do about it. So failures are
# repeated underneath with their notes, because the top of the list has usually
# scrolled off by the time the run finishes.
#
# Collected, then shown. Printing as it goes would be simpler and would mean
# not knowing there were four problems until after reading past all of them.
#
# Usage:
#   use shebang::tui/term
#   use shebang::tui/report
#
#   tui_report_reset
#   tui_report_row ok   "disk health"   "no reallocated sectors"
#   tui_report_row warn "free space"    "3% left on /"
#   tui_report_row fail "boot entry"    "no loader at EFI/BOOT/BOOTX64.EFI"
#   tui_report_show "Machine check"
#   exit "$(tui_report_exit)"
# =============================================================================

[[ -n "${_SHEBANG_TUI_REPORT_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_REPORT_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use color

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

declare -ga TUI_REPORT_STATUS=()
declare -ga TUI_REPORT_NAME=()
declare -ga TUI_REPORT_NOTE=()

#[pub]
# Start a fresh report.
# Usage: tui_report_reset
tui_report_reset() {
    TUI_REPORT_STATUS=(); TUI_REPORT_NAME=(); TUI_REPORT_NOTE=()
}

#[pub]
# Record one result. An unknown status is recorded as `info` rather than
# refused: a diagnostic that dies because a caller mistyped a word has lost the
# thirty results it already had.
# Usage: tui_report_row <ok|warn|fail|skip|info> <name> [note]
tui_report_row() {
    local st="${1:-info}" name="${2:-}" note="${3:-}"
    case "$st" in ok|warn|fail|skip|info) ;; *) st="info" ;; esac
    TUI_REPORT_STATUS+=("$st")
    TUI_REPORT_NAME+=("$name")
    TUI_REPORT_NOTE+=("$note")
}

#[pub]
# How many rows carry a status.
# Usage: tui_report_count <status> -> a number
tui_report_count() {
    local want="${1:-}" s n=0
    for s in ${TUI_REPORT_STATUS[@]+"${TUI_REPORT_STATUS[@]}"}; do
        [[ "$s" == "$want" ]] && n=$(( n + 1 ))
    done
    printf '%d' "$n"
}

#[pub]
# The worst thing in the report, or `ok` when there is nothing in it at all.
# Usage: tui_report_worst -> fail | warn | ok
tui_report_worst() {
    local s worst="ok"
    for s in ${TUI_REPORT_STATUS[@]+"${TUI_REPORT_STATUS[@]}"}; do
        case "$s" in
            fail) printf 'fail'; return 0 ;;
            warn) worst="warn" ;;
        esac
    done
    printf '%s' "$worst"
}

#[pub]
# An exit status for the whole run. 0 when nothing is wrong, 1 when something
# failed, 2 when nothing failed but something is worth looking at -- so that a
# caller can tell "fine" from "fine for now" without parsing the output.
# Usage: exit "$(tui_report_exit)"
tui_report_exit() {
    case "$(tui_report_worst)" in
        fail) printf '1' ;;
        warn) printf '2' ;;
        *)    printf '0' ;;
    esac
}

# Styling, but only when the terminal said so. This module used to consult
# nothing at all: it printed the colour variables and relied on a different
# library having blanked them, by a different rule, at the moment it was
# sourced. That is not the same as being safe in a pipe, and a test asserting
# it was safe could only pass by blanking the variables itself.
declare -g _TUI_R_DIM="" _TUI_R_BOLD="" _TUI_R_RED="" _TUI_R_GREEN="" \
           _TUI_R_YELLOW="" _TUI_R_NC=""
_tui_report_styles() {
    if (( ${TUI_COLOR:-0} == 1 )) && tui_is_tty; then
        _TUI_R_DIM="$DIM"; _TUI_R_BOLD="$BOLD"; _TUI_R_NC="$NC"
        _TUI_R_RED="$RED"; _TUI_R_GREEN="$GREEN"; _TUI_R_YELLOW="$YELLOW"
    else
        _TUI_R_DIM=""; _TUI_R_BOLD=""; _TUI_R_NC=""
        _TUI_R_RED=""; _TUI_R_GREEN=""; _TUI_R_YELLOW=""
    fi
}

# The mark for a status. Words rather than symbols alone: a red dot means
# nothing over ssh to a terminal with no colour, and this is a tool that gets
# used over exactly that.
_tui_report_mark() {
    case "$1" in
        ok)   printf '%sok  %s'   "$_TUI_R_GREEN"  "$_TUI_R_NC" ;;
        warn) printf '%swarn%s'   "$_TUI_R_YELLOW" "$_TUI_R_NC" ;;
        fail) printf '%sfail%s'   "$_TUI_R_RED"    "$_TUI_R_NC" ;;
        skip) printf '%sskip%s'   "$_TUI_R_DIM"    "$_TUI_R_NC" ;;
        *)    printf '%s--  %s'   "$_TUI_R_DIM"    "$_TUI_R_NC" ;;
    esac
}

#[pub]
# Print the report.
# Usage: tui_report_show [title]
tui_report_show() {
    local title="${1:-}" i n w=0 len
    _tui_report_styles
    n="${#TUI_REPORT_STATUS[@]}"

    if (( n == 0 )); then
        [[ -n "$title" ]] && printf '%s\n' "$title"
        printf 'Nothing was checked.\n'
        return 0
    fi

    # One pass to find the widest name, so the notes line up. A ragged right
    # column is the difference between a table and a list of sentences.
    for (( i = 0; i < n; i++ )); do
        len="${#TUI_REPORT_NAME[$i]}"
        (( len > w )) && w="$len"
    done
    (( w > 32 )) && w=32

    [[ -n "$title" ]] && printf '\n%s%s%s\n\n' "$_TUI_R_BOLD" "$title" "$_TUI_R_NC"

    for (( i = 0; i < n; i++ )); do
        printf '  %s  %-*s  %s%s%s\n' \
            "$(_tui_report_mark "${TUI_REPORT_STATUS[$i]}")" \
            "$w" "${TUI_REPORT_NAME[$i]}" \
            "$_TUI_R_DIM" "${TUI_REPORT_NOTE[$i]}" "$_TUI_R_NC"
    done

    local ok warn fail skip
    ok="$(tui_report_count ok)";     warn="$(tui_report_count warn)"
    fail="$(tui_report_count fail)"; skip="$(tui_report_count skip)"
    printf '\n  %d checked' "$n"
    (( fail > 0 )) && printf ', %s%d failed%s' "$_TUI_R_RED" "$fail" "$_TUI_R_NC"
    (( warn > 0 )) && printf ', %s%d worth a look%s' "$_TUI_R_YELLOW" "$warn" "$_TUI_R_NC"
    (( skip > 0 )) && printf ', %d not applicable' "$skip"
    (( fail == 0 && warn == 0 )) && printf ', %snothing wrong%s' "$_TUI_R_GREEN" "$_TUI_R_NC"
    printf '\n'

    # And again, underneath. By the time thirty checks have run, the one that
    # failed is off the top of the screen.
    if (( fail > 0 || warn > 0 )); then
        printf '\n%sWhat to look at%s\n\n' "$_TUI_R_BOLD" "$_TUI_R_NC"
        for (( i = 0; i < n; i++ )); do
            case "${TUI_REPORT_STATUS[$i]}" in
                fail|warn) ;;
                *) continue ;;
            esac
            printf '  %s  %s\n' \
                "$(_tui_report_mark "${TUI_REPORT_STATUS[$i]}")" "${TUI_REPORT_NAME[$i]}"
            [[ -n "${TUI_REPORT_NOTE[$i]}" ]] \
                && printf '        %s%s%s\n' "$_TUI_R_DIM" "${TUI_REPORT_NOTE[$i]}" "$_TUI_R_NC"
        done
    fi
    return 0
}
