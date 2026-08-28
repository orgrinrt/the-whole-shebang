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
#   use shebang::tui::term
#   use shebang::tui::report
#
#   tui_report_reset
#   tui_report_row ok   "disk health"   "no reallocated sectors"
#   tui_report_row warn "free space"    "3% left on /"
#   tui_report_row fail "boot entry"    "no loader at EFI/BOOT/BOOTX64.EFI"
#   tui_report_show "Machine check"
#   exit "$(tui_report_exit)"
# =============================================================================

[ -n "${_SHEBANG_TUI_REPORT_SH:-}" ] && return 0
readonly _SHEBANG_TUI_REPORT_SH=1

if ! command -v use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use color list

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

# Three parallel lists rather than three bash arrays.
#
# `list` is nutshell's, and it has a POSIX half, which a `declare -ga` does
# not. The shape is the same: one row is the same index in all three, appended
# together and read together.
list_new TUI_REPORT_STATUS
list_new TUI_REPORT_NAME
list_new TUI_REPORT_NOTE

#[pub]
# Start a fresh report.
# Usage: tui_report_reset
tui_report_reset() {
    list_new TUI_REPORT_STATUS
    list_new TUI_REPORT_NAME
    list_new TUI_REPORT_NOTE
}

#[pub]
# Record one result. An unknown status is recorded as `info` rather than
# refused: a diagnostic that dies because a caller mistyped a word has lost the
# thirty results it already had.
# Usage: tui_report_row <ok|warn|fail|skip|info> <name> [note]
tui_report_row() {
    local st="${1:-info}" name="${2:-}" note="${3:-}"
    case "$st" in ok|warn|fail|skip|info) ;; *) st="info" ;; esac
    list_push TUI_REPORT_STATUS "$st"
    list_push TUI_REPORT_NAME "$name"
    list_push TUI_REPORT_NOTE "$note"
}

#[pub]
# How many rows carry a status.
# Usage: tui_report_count <status> -> a number
tui_report_count() {
    local want="${1:-}" s n=0 i total
    total="$(list_len TUI_REPORT_STATUS)"
    i=0
    while [ "$i" -lt "$total" ]; do
        list_read s TUI_REPORT_STATUS "$i"
        [ "$s" = "$want" ] && n=$(( n + 1 ))
        i=$(( i + 1 ))
    done
    printf '%d' "$n"
}

#[pub]
# The worst thing in the report, or `ok` when there is nothing in it at all.
# Usage: tui_report_worst -> fail | warn | ok
tui_report_worst() {
    local s worst="ok" i total
    total="$(list_len TUI_REPORT_STATUS)"
    i=0
    while [ "$i" -lt "$total" ]; do
        list_read s TUI_REPORT_STATUS "$i"
        case "$s" in
            fail) printf 'fail'; return 0 ;;
            warn) worst="warn" ;;
        esac
        i=$(( i + 1 ))
    done
    printf '%s' "$worst"
}

#[pub]
# An exit status for the whole run. 0 when nothing is wrong, 1 when something
# failed, 2 when nothing failed but something is worth looking at. A caller can
# then tell "fine" from "fine for now" without parsing the output.
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
_TUI_R_DIM="" _TUI_R_BOLD="" _TUI_R_RED="" _TUI_R_GREEN="" \
           _TUI_R_YELLOW="" _TUI_R_NC=""
_tui_report_styles() {
    if [ "$(( ${TUI_COLOR:-0} == 1 ))" -ne 0 ] && tui_is_tty; then
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
# Record a result from a command's exit status, which is the shape every caller
# writes by hand otherwise: run a thing, look at $?, pick ok or fail.
# Usage: tui_report_run <name> <note-on-failure> <command> [args...]
tui_report_run() {
    local name="$1" note="$2"; shift 2
    if "$@" >/dev/null 2>&1; then
        tui_report_row ok "$name"
    else
        tui_report_row fail "$name" "$note"
    fi
}

#[pub]
# Print the report.
# Usage: tui_report_show [title]
tui_report_show() {
    local title="${1:-}" i n w=0 len
    _tui_report_styles
    n="$(list_len TUI_REPORT_STATUS)"

    if [ "$n" -eq 0 ]; then
        [ -n "$title" ] && printf '%s\n' "$title"
        printf 'Nothing was checked.\n'
        return 0
    fi

    # One pass to find the widest name, so the notes line up. A ragged right
    # column is the difference between a table and a list of sentences.
    local _nm
    i=0
    while [ "$i" -lt "$n" ]; do
        list_read _nm TUI_REPORT_NAME "$i"
        len="${#_nm}"
        [ "$len" -gt "$w" ] && w="$len"
        i=$(( i + 1 ))
    done
    # Capped, so one pathological name cannot push every note off the right of
    # the screen. A name longer than the cap is cut rather than allowed to
    # overrun its column: %-*s pads a short value but does not shorten a long
    # one, so without the cut the row is wider than the header promised.
    [ "$w" -gt 32 ] && w=32

    [ -n "$title" ] && printf '\n%s%s%s\n\n' "$_TUI_R_BOLD" "$title" "$_TUI_R_NC"

    local nm st nt
    i=0
    while [ "$i" -lt "$n" ]; do
        list_read nm TUI_REPORT_NAME "$i"
        list_read st TUI_REPORT_STATUS "$i"
        list_read nt TUI_REPORT_NOTE "$i"
        # `${nm:0:n}` is a bash substring; POSIX `printf` takes a precision.
        [ "${#nm}" -gt "$w" ] && nm="$(printf '%.*s+' "$(( w - 1 ))" "$nm")"
        printf '  %s  %-*s  %s%s%s\n' \
            "$(_tui_report_mark "$st")" \
            "$w" "$nm" \
            "$_TUI_R_DIM" "$nt" "$_TUI_R_NC"
        i=$(( i + 1 ))
    done

    local ok warn fail skip
    ok="$(tui_report_count ok)";     warn="$(tui_report_count warn)"
    fail="$(tui_report_count fail)"; skip="$(tui_report_count skip)"
    printf '\n  %d checked' "$n"
    [ "$fail" -gt 0 ] && printf ', %s%d failed%s' "$_TUI_R_RED" "$fail" "$_TUI_R_NC"
    [ "$warn" -gt 0 ] && printf ', %s%d worth a look%s' "$_TUI_R_YELLOW" "$warn" "$_TUI_R_NC"
    [ "$skip" -gt 0 ] && printf ', %d not applicable' "$skip"
    { [ "$fail" -eq 0 ] && [ "$warn" -eq 0 ]; } && printf ', %snothing wrong%s' "$_TUI_R_GREEN" "$_TUI_R_NC"
    printf '\n'

    # And again, underneath. By the time thirty checks have run, the one that
    # failed is off the top of the screen.
    if [ "$fail" -gt 0 ] || [ "$warn" -gt 0 ]; then
        printf '\n%sWhat to look at%s\n\n' "$_TUI_R_BOLD" "$_TUI_R_NC"
        i=0
        while [ "$i" -lt "$n" ]; do
            list_read st TUI_REPORT_STATUS "$i"
            i=$(( i + 1 ))
            case "$st" in
                fail|warn) ;;
                *) continue ;;
            esac
            list_read nm TUI_REPORT_NAME "$(( i - 1 ))"
            list_read nt TUI_REPORT_NOTE "$(( i - 1 ))"
            printf '  %s  %s\n' "$(_tui_report_mark "$st")" "$nm"
            [ -n "$nt" ] \
                && printf '        %s%s%s\n' "$_TUI_R_DIM" "$nt" "$_TUI_R_NC"
        done
    fi
    return 0
}
