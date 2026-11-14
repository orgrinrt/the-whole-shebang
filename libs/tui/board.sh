#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/board - Where a long run of steps is, at a glance
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Depends on tui/term, tui/layout and tui/table.
#
# A run of many slow steps (a bench suite, an install, a migration) wants one
# picture of itself before each new step: every step with its state and its
# time, how long the run has taken, and roughly how long is left. Printed into
# the scrollback rather than drawn over it, so the output of each step stays
# where it was written and a person who looks away for an hour can scroll up
# through every board the run printed. That is the trade `tui/run` makes too.
#
# The estimate of what is left is the steps' own estimates where they gave one,
# and the mean of the finished steps for the rest. A guess, and called one.
#
# Usage:
#   use shebang::tui::term
#   use shebang::tui::layout
#   use shebang::tui::table
#   use shebang::tui::board
#
#   tui_board_reset
#   tui_board_add arvo/hash "arvo: hash" 120
#   tui_board_set arvo/hash running
#   tui_board_set arvo/hash done 97 "results in mock/benches/results"
#   tui_board_show "stack bench"
# =============================================================================

[[ -n "${_SHEBANG_TUI_BOARD_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_BOARD_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

declare -ga TUI_BOARD_ID=() TUI_BOARD_LABEL=() TUI_BOARD_STATE=()
declare -ga TUI_BOARD_SECS=() TUI_BOARD_EST=() TUI_BOARD_NOTE=()
declare -gi TUI_BOARD_START=0
# The states, and the ones that mean the step is over.
readonly _TUI_BOARD_STATES=" pending running done skip fail timeout stopped "
readonly _TUI_BOARD_OVER=" done skip fail timeout stopped "

#[pub]
# Start a board; the run's clock starts here.
# Usage: tui_board_reset
tui_board_reset() {
    TUI_BOARD_ID=(); TUI_BOARD_LABEL=(); TUI_BOARD_STATE=()
    TUI_BOARD_SECS=(); TUI_BOARD_EST=(); TUI_BOARD_NOTE=()
    TUI_BOARD_START="$(date +%s)"
}

#[pub]
# A step, pending, with an estimate in seconds when one is known.
# Usage: tui_board_add <id> <label> [estimate seconds]
tui_board_add() {
    TUI_BOARD_ID+=("$1"); TUI_BOARD_LABEL+=("${2:-$1}"); TUI_BOARD_STATE+=(pending)
    TUI_BOARD_SECS+=(""); TUI_BOARD_EST+=("${3:-}"); TUI_BOARD_NOTE+=("")
}

_tui_board_index() {
    local i
    for i in "${!TUI_BOARD_ID[@]}"; do
        [[ "${TUI_BOARD_ID[$i]}" == "$1" ]] && { printf '%d' "$i"; return 0; }
    done
    return 1
}

#[pub]
# Move a step on. An unknown state or step is refused, since a board that quietly
# shows a wrong state is worse than one that says it was told nonsense.
# Usage: tui_board_set <id> <pending|running|done|skip|fail|timeout|stopped> [seconds] [note]
tui_board_set() {
    local i
    [[ "$_TUI_BOARD_STATES" == *" ${2:-} "* ]] || { printf 'tui_board_set: no state %s\n' "${2:-}" >&2; return 2; }
    i="$(_tui_board_index "$1")" || { printf 'tui_board_set: no step %s\n' "$1" >&2; return 2; }
    TUI_BOARD_STATE[$i]="$2"
    [[ -n "${3:-}" ]] && TUI_BOARD_SECS[$i]="$3"
    [[ $# -ge 4 ]] && TUI_BOARD_NOTE[$i]="$4"
    return 0
}

#[pub]
# How many steps are in a state.
# Usage: tui_board_count <state> -> a number
tui_board_count() {
    local s n=0
    for s in "${TUI_BOARD_STATE[@]}"; do [[ "$s" == "$1" ]] && (( n++ )); done
    printf '%d' "$n"
}

#[pub]
# Seconds still to go, by the estimates and the mean of the steps that finished.
# Usage: tui_board_left -> a number
tui_board_left() {
    local i sum=0 n=0 mean=0 left=0
    for i in "${!TUI_BOARD_ID[@]}"; do
        [[ "${TUI_BOARD_STATE[$i]}" == done && -n "${TUI_BOARD_SECS[$i]}" ]] &&
            { sum=$(( sum + TUI_BOARD_SECS[i] )); n=$(( n + 1 )); }
    done
    (( n > 0 )) && mean=$(( sum / n ))
    for i in "${!TUI_BOARD_ID[@]}"; do
        [[ "$_TUI_BOARD_OVER" == *" ${TUI_BOARD_STATE[$i]} "* ]] && continue
        left=$(( left + ${TUI_BOARD_EST[$i]:-$mean} ))
    done
    printf '%d' "$left"
}

#[pub]
# Seconds as `1h02m`, `4m07s` or `9s`.
# Usage: tui_board_hms <seconds> -> text
tui_board_hms() {
    local s="${1:-0}"
    if (( s >= 3600 )); then printf '%dh%02dm' $(( s / 3600 )) $(( s % 3600 / 60 ))
    elif (( s >= 60 )); then printf '%dm%02ds' $(( s / 60 )) $(( s % 60 ))
    else printf '%ds' "$s"; fi
}

_tui_board_mark() {
    local c="" e=""
    if [[ "${TUI_COLOR:-0}" == 1 ]] && tui_is_tty; then
        case "$1" in
            done) c=$'\033[32m' ;; fail|timeout|stopped) c=$'\033[31m' ;;
            running) c=$'\033[1m' ;; skip|pending) c=$'\033[2m' ;;
        esac
        e=$'\033[0m'
    fi
    printf '%s%-7s%s' "$c" "$1" "$e"
}

#[pub]
# Print the board: the title with the counts, the elapsed time and the estimate
# left, then one row a step.
# Usage: tui_board_show [title]
tui_board_show() {
    local title="${1:-run}" i now elapsed over=0 total="${#TUI_BOARD_ID[@]}" t
    now="$(date +%s)"; elapsed=$(( now - TUI_BOARD_START ))
    for i in "${!TUI_BOARD_ID[@]}"; do
        [[ "$_TUI_BOARD_OVER" == *" ${TUI_BOARD_STATE[$i]} "* ]] && (( over++ ))
    done
    printf '\n== %s: %d of %d over (%d done, %d skipped, %d failed), %s elapsed, about %s left\n' \
        "$title" "$over" "$total" "$(tui_board_count done)" "$(tui_board_count skip)" \
        "$(( $(tui_board_count fail) + $(tui_board_count timeout) + $(tui_board_count stopped) ))" \
        "$(tui_board_hms "$elapsed")" "$(tui_board_hms "$(tui_board_left)")"
    tui_table_reset
    tui_table_col state 7
    tui_table_col step 2fr min:16
    tui_table_col time 7
    tui_table_col note 3fr --priority 5
    for i in "${!TUI_BOARD_ID[@]}"; do
        t=""; [[ -n "${TUI_BOARD_SECS[$i]}" ]] && t="$(tui_board_hms "${TUI_BOARD_SECS[$i]}")"
        tui_table_row "$(_tui_board_mark "${TUI_BOARD_STATE[$i]}")" "${TUI_BOARD_LABEL[$i]}" "$t" "${TUI_BOARD_NOTE[$i]}"
    done
    tui_table_render
}
