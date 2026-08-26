#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/progress - How far through, and how long left
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# For work we are doing ourselves and can count: fourteen packages, six
# partitions, thirty checks. Not for relaying somebody else's progress: pacman
# and rsync draw their own bars and draw them better, and a bar wrapped around a
# bar is two bars fighting over one line.
#
# The honest cases are handled rather than faked. Work whose size is not known
# gets a spinner, not a bar creeping to 90% and stopping, because a bar that
# lies about how far along it is teaches people to ignore bars. And with no
# terminal there is no redrawing at all: one line per step, which is what a log
# wanted anyway.
#
# Usage:
#   use shebang::tui/term
#   use shebang::tui/progress
#
#   tui_progress_open 14 "Fetching packages"
#   for p in "${pkgs[@]}"; do
#       fetch "$p"
#       tui_progress_step "$p"
#   done
#   tui_progress_close
#
#   tui_progress_open 0 "Scanning"     # size unknown: a spinner
# =============================================================================

[[ -n "${_SHEBANG_TUI_PROGRESS_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_PROGRESS_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use color

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

declare -gi _TUI_PROG_OPEN=0
declare -gi _TUI_PROG_TOTAL=0
declare -gi _TUI_PROG_DONE=0
declare -gi _TUI_PROG_SPIN=0
declare -gi _TUI_PROG_FAILED=0
declare -g  _TUI_PROG_TITLE=""
declare -gi _TUI_PROG_START=0

_TUI_PROG_SPINNER='|/-\'

# The mark for a label that had to be cut. ASCII unless the terminal has said
# it can do better: an ellipsis is three bytes of UTF-8, and on the console
# this is aimed at that renders as noise.
declare -g _TUI_PROG_ELL="..."

_tui_progress_marks() { _TUI_PROG_ELL="$(tui_ellipsis)"; }

# Styling, but only when the terminal said so, so that this module and term.sh
# agree about one session rather than two libraries deciding separately.
declare -g _TUI_PROG_DIM="" _TUI_PROG_BOLD="" _TUI_PROG_GREEN="" _TUI_PROG_NC=""
_tui_progress_styles() {
    if (( ${TUI_COLOR:-0} == 1 )) && tui_is_tty; then
        _TUI_PROG_DIM="$DIM"; _TUI_PROG_BOLD="$BOLD"
        _TUI_PROG_GREEN="$GREEN"; _TUI_PROG_NC="$NC"
    else
        _TUI_PROG_DIM=""; _TUI_PROG_BOLD=""; _TUI_PROG_GREEN=""; _TUI_PROG_NC=""
    fi
}

#[pub]
# Start counting. A total of 0 means the size is not known, which is a
# different thing from there being nothing to do.
# Usage: tui_progress_open <total> [title]
tui_progress_open() {
    local total="${1:-0}" title="${2:-}"
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    _TUI_PROG_TOTAL="$total"
    _TUI_PROG_TITLE="$title"
    _TUI_PROG_DONE=0
    _TUI_PROG_SPIN=0
    _TUI_PROG_FAILED=0
    _TUI_PROG_OPEN=1
    _TUI_PROG_START="$(printf '%(%s)T' -1 2>/dev/null || date +%s)"
    _tui_progress_marks
    _tui_progress_styles

    if ! tui_is_tty; then
        [[ -n "$title" ]] && printf '%s\n' "$title"
        return 0
    fi
    [[ -n "$title" ]] && printf '%s%s%s\n' "$_TUI_PROG_BOLD" "$title" "$_TUI_PROG_NC"
    return 0
}

#[pub]
# One more done.
# Usage: tui_progress_step [label]
tui_progress_step() {
    (( _TUI_PROG_OPEN == 1 )) || return 0
    _TUI_PROG_DONE=$(( _TUI_PROG_DONE + 1 ))
    _tui_progress_draw "${1:-}"
}

#[pub]
# One more done, and it did not work. Counted like any other step, because the
# run is as far along either way, and named so the end of the run can say how
# many failed instead of a fourteen-package fetch reporting fourteen successes
# when three of them failed.
# Usage: tui_progress_fail [label]
tui_progress_fail() {
    (( _TUI_PROG_OPEN == 1 )) || return 0
    _TUI_PROG_DONE=$(( _TUI_PROG_DONE + 1 ))
    _TUI_PROG_FAILED=$(( _TUI_PROG_FAILED + 1 ))
    _tui_progress_draw "${1:+${1} (failed)}"
}

#[pub]
# Jump to a count, for work that finishes several at once or is counted from
# somewhere else.
# Usage: tui_progress_set <done> [label]
tui_progress_set() {
    (( _TUI_PROG_OPEN == 1 )) || return 0
    local n="${1:-0}"
    [[ "$n" =~ ^[0-9]+$ ]] || return 0
    _TUI_PROG_DONE="$n"
    _tui_progress_draw "${2:-}"
}

# The bar itself, as a string, so the arithmetic can be tested without a
# terminal to draw on. Off-by-one in a bar is the classic way it reads 101% at
# the end or never reaches the right-hand edge at all.
#[pub]
# Usage: tui_progress_bar <done> <total> <width> -> prints the bar's insides
tui_progress_bar() {
    local done="${1:-0}" total="${2:-0}" width="${3:-20}" filled rest
    [[ "$done" =~ ^[0-9]+$ ]]  || done=0
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    # A width that is a number but not a sensible one is clamped, and one that
    # is not a number at all falls back to the default. Two rules used to
    # disagree about the same idea: 0 clamped to 1 while -3 quietly became 20,
    # so a typo'd width drew a plausible bar of the wrong size.
    [[ "$width" =~ ^-?[0-9]+$ ]] || width=20
    (( width < 1 )) && width=1
    if (( total <= 0 )); then
        printf '%*s' "$width" ''
        return 0
    fi
    (( done > total )) && done="$total"
    filled=$(( done * width / total ))
    (( filled > width )) && filled="$width"
    rest=$(( width - filled ))
    local a="" b=""
    (( filled > 0 )) && printf -v a '%*s' "$filled" '' && a="${a// /#}"
    (( rest   > 0 )) && printf -v b '%*s' "$rest"   '' && b="${b// /.}"
    printf '%s%s' "$a" "$b"
}

#[pub]
# The percentage, as a whole number. Nothing to do is 100%, not a division by
# zero: a run with no work in it did finish.
# Usage: tui_progress_pct <done> <total> -> 0..100
tui_progress_pct() {
    local done="${1:-0}" total="${2:-0}"
    [[ "$done" =~ ^[0-9]+$ ]]  || done=0
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    (( total <= 0 )) && { printf '100'; return 0; }
    (( done > total )) && done="$total"
    printf '%d' $(( done * 100 / total ))
}

_tui_progress_draw() {
    local label="${1:-}"

    if ! tui_is_tty; then
        # A log gets one line per step and no redrawing, because a carriage
        # return in a file is a line nobody can read afterwards.
        if (( _TUI_PROG_TOTAL > 0 )); then
            printf '  [%d/%d] %s\n' "$_TUI_PROG_DONE" "$_TUI_PROG_TOTAL" "$label"
        else
            printf '  %s\n' "$label"
        fi
        return 0
    fi

    local cols="${TUI_COLS:-80}"
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    (( cols < 1 )) && cols=1

    printf '\r'
    tui_clear_line 2>/dev/null || true

    # The redraw clears one physical line. Anything drawn wider than the
    # terminal wraps, and the wrapped part is not cleared, so a narrow console
    # collects a line of leftovers per step. Nothing here may exceed cols.
    local furniture=14                       # "  [", "] 100%  "
    local width=$(( cols / 3 ))
    (( width > 40 )) && width=40
    (( cols - furniture < width )) && width=$(( cols - furniture ))

    if (( _TUI_PROG_TOTAL > 0 )); then
        local pct; pct="$(tui_progress_pct "$_TUI_PROG_DONE" "$_TUI_PROG_TOTAL")"
        if (( width < 4 )); then
            # No room for a bar worth drawing. The number carries the
            # information anyway.
            printf '%s' "$(_tui_progress_fit "${pct}% ${label}" "$cols")"
        else
            printf '  %s[%s]%s %3s%%  %s' \
                "$_TUI_PROG_DIM" \
                "$(tui_progress_bar "$_TUI_PROG_DONE" "$_TUI_PROG_TOTAL" "$width")" \
                "$_TUI_PROG_NC" "$pct" \
                "$(_tui_progress_fit "$label" $(( cols - width - furniture )))"
        fi
    else
        _TUI_PROG_SPIN=$(( (_TUI_PROG_SPIN + 1) % 4 ))
        if (( cols < 8 )); then
            printf '%s' "${_TUI_PROG_SPINNER:$_TUI_PROG_SPIN:1}"
        else
            printf '  %s%s%s  %s' "$_TUI_PROG_DIM" \
                "${_TUI_PROG_SPINNER:$_TUI_PROG_SPIN:1}" "$_TUI_PROG_NC" \
                "$(_tui_progress_fit "$label" $(( cols - 8 )))"
        fi
    fi
}

# A label cut to fit. Left as it is when it fits, which is almost always.
_tui_progress_fit() {
    local s="${1:-}" n="${2:-0}"
    (( n < 4 )) && { printf ''; return 0; }
    # The shared cut, which knows not to leave half a character behind. This
    # was a second copy of frame's truncation and kept the bug frame had.
    tui_cut "$s" "$n" "$_TUI_PROG_ELL"
}

#[pub]
# Done. Prints how long it took, because "did that hang or is it just slow" is
# the question a bar exists to answer and the answer is worth keeping.
# Usage: tui_progress_close [note]
tui_progress_close() {
    (( _TUI_PROG_OPEN == 1 )) || return 0
    _TUI_PROG_OPEN=0
    local now took
    now="$(printf '%(%s)T' -1 2>/dev/null || date +%s)"
    took=$(( now - _TUI_PROG_START ))
    (( took < 0 )) && took=0

    local failed=""
    (( _TUI_PROG_FAILED > 0 )) && printf -v failed ', %d failed' "$_TUI_PROG_FAILED"

    if ! tui_is_tty; then
        printf '  done, %d in %ds%s%s\n' "$_TUI_PROG_DONE" "$took" "$failed" \
            "${1:+ (${1})}"
        return 0
    fi
    printf '\r'
    tui_clear_line 2>/dev/null || true
    printf '  %sdone%s  %d in %ds%s%s\n' "$_TUI_PROG_GREEN" "$_TUI_PROG_NC" \
        "$_TUI_PROG_DONE" "$took" "$failed" "${1:+  ${1}}"
}
