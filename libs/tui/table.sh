#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/table - Columns that line up
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Depends on tui/term for the width and the cut, and on tui/layout for the
# column widths, because a row of columns across a fixed width is exactly the
# problem layout already solves. Borders are optional and off by default: most
# tables read better without them, and the ones that need them usually need
# them because something else is wrong with the spacing.
#
# It exists because the menu had a columnar renderer of its own, and a list
# with aligned columns is not a thing only a menu wants. Anything that shows a
# set of things with a state beside each one wants this, including a script
# with no interface at all.
#
# A column says how wide it wants to be in the same words layout uses: a count,
# a share, or a share with a floor. So a table on a narrow terminal drops to
# what fits rather than wrapping into a mess.
#
# Usage:
#   use shebang::tui::term
#   use shebang::tui::layout
#   use shebang::tui::table
#
#   tui_table_reset
#   tui_table_col name  1fr min:12
#   tui_table_col state 6
#   tui_table_col note  2fr --priority 5     # first to go on a narrow screen
#   tui_table_row "disk-wipe" "off" "needs lsblk, which is not installed"
#   tui_table_render
# =============================================================================

[[ -n "${_SHEBANG_TUI_TABLE_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_TABLE_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use color

declare -ga TUI_TABLE_COL=()       # names, in order
declare -ga TUI_TABLE_SPEC=()      # what each asked for, for layout
declare -ga TUI_TABLE_HEAD=()      # heading text, empty for none
declare -ga TUI_TABLE_ROW=()       # rows, cells separated by a unit separator
declare -g  TUI_TABLE_GAP="  "

# Unit separator, not tab. A cell may contain a tab, and `read` treats runs of
# whitespace as one delimiter, so an empty cell would swallow its own column
# and shift every column after it left.
_TUI_TABLE_US=$'\037'

#[pub]
# Start a table.
# Usage: tui_table_reset
tui_table_reset() {
    TUI_TABLE_COL=(); TUI_TABLE_SPEC=(); TUI_TABLE_HEAD=(); TUI_TABLE_ROW=()
}

#[pub]
# A column. The width is layout's vocabulary: `12`, `1fr`, `min:8`,
# `--priority N` for what gets dropped first when the terminal is narrow.
# `--head "Text"` gives it a heading.
# Usage: tui_table_col <name> <width> [min:N] [--priority N] [--head TEXT]
tui_table_col() {
    local name="$1" spec="${2:-1fr}"; shift 2 2>/dev/null || shift $#
    local head="" rest=""
    while (( $# )); do
        case "$1" in
            --head) head="${2:-}"; shift 2 ;;
            *)      rest="${rest} $1"; shift ;;
        esac
    done
    TUI_TABLE_COL+=("$name")
    TUI_TABLE_SPEC+=("${spec}${rest}")
    TUI_TABLE_HEAD+=("$head")
}

#[pub]
# A row. One argument per column; missing ones are empty.
# Usage: tui_table_row <cell> [cell...]
tui_table_row() {
    local out="" cell first=1
    for cell in "$@"; do
        if (( first == 1 )); then out="$cell"; first=0
        else out="${out}${_TUI_TABLE_US}${cell}"; fi
    done
    TUI_TABLE_ROW+=("$out")
}

#[pub]
# How many rows are in it.
# Usage: tui_table_rows -> a number
tui_table_rows() { printf '%d' "${#TUI_TABLE_ROW[@]}"; }

# Work the column widths out for a given total, through layout, so a table and
# a screen divide space by the same rules.
_tui_table_solve() {
    local total="$1" i n="${#TUI_TABLE_COL[@]}"
    declare -F tui_layout_reset >/dev/null 2>&1 || return 1

    # The gaps between columns are part of the width and have to be taken out
    # of it, or the last column runs off the edge by exactly one gap per
    # column.
    local gaps=$(( (n - 1) * ${#TUI_TABLE_GAP} ))
    (( gaps < 0 )) && gaps=0
    local room=$(( total - gaps ))
    (( room < 1 )) && room=1

    tui_layout_reset cols "$room"
    for (( i = 0; i < n; i++ )); do
        # shellcheck disable=SC2086
        tui_layout_add "${TUI_TABLE_COL[$i]}" ${TUI_TABLE_SPEC[$i]}
    done
    tui_layout_solve
}

#[pub]
# The width a column ended up with, or 0 when it was dropped.
# Usage: tui_table_width <name>
tui_table_width() {
    declare -F tui_layout_size >/dev/null 2>&1 || { printf '0'; return 1; }
    tui_layout_size "$1"
}

# One line of cells, cut to their columns and padded to them.
_tui_table_line() {
    local -a cells=()
    local rest="$1" cell
    while [[ "$rest" == *"$_TUI_TABLE_US"* ]]; do
        cell="${rest%%"$_TUI_TABLE_US"*}"
        cells+=("$cell")
        rest="${rest#*"$_TUI_TABLE_US"}"
    done
    cells+=("$rest")

    local i n="${#TUI_TABLE_COL[@]}" out="" w text pad
    for (( i = 0; i < n; i++ )); do
        w="$(tui_table_width "${TUI_TABLE_COL[$i]}")"
        (( w > 0 )) || continue                      # dropped on this width
        text="${cells[$i]:-}"
        if declare -F tui_cut >/dev/null 2>&1; then
            (( ${#text} > w )) && text="$(tui_cut "$text" "$w")"
        else
            (( ${#text} > w )) && text="${text:0:$w}"
        fi
        printf -v pad '%*s' $(( w - ${#text} )) ''
        [[ -n "$out" ]] && out="${out}${TUI_TABLE_GAP}"
        out="${out}${text}${pad}"
    done
    out="${out%"${out##*[![:space:]]}"}"
    # Clamped, whatever the columns came to. A table that draws past the edge
    # wraps, and the wrapped remainder is the mess the reflow exists to
    # prevent; when the floors genuinely cannot fit, showing less is the only
    # honest answer left.
    local limit="${_TUI_TABLE_WIDTH:-0}"
    if [[ "$limit" =~ ^[0-9]+$ ]] && (( limit > 0 )) && (( ${#out} > limit )); then
        if declare -F tui_cut >/dev/null 2>&1; then out="$(tui_cut "$out" "$limit")"
        else out="${out:0:$limit}"; fi
    fi
    printf '%s' "$out"
}

#[pub]
# Draw it. Every line is at most as wide as the terminal, and a column that
# does not fit is dropped rather than wrapped.
# Usage: tui_table_render [--width N] [--borders]
tui_table_render() {
    local width="${TUI_COLS:-80}" borders=0
    while (( $# )); do
        case "$1" in
            --width)   width="${2:-80}"; shift 2 ;;
            --borders) borders=1; shift ;;
            *)         shift ;;
        esac
    done
    [[ "$width" =~ ^[0-9]+$ ]] || width=80
    (( ${#TUI_TABLE_COL[@]} > 0 )) || return 0
    local _TUI_TABLE_WIDTH="$width"

    _tui_table_solve "$width" || return 1

    local i has_head=0
    for (( i = 0; i < ${#TUI_TABLE_HEAD[@]}; i++ )); do
        [[ -n "${TUI_TABLE_HEAD[$i]}" ]] && has_head=1
    done

    local rule=""
    if (( borders == 1 )); then
        local ch="-"
        if declare -F tui_unicode_ok >/dev/null 2>&1 && tui_unicode_ok; then
            printf -v ch '%b' '\u2500'
        fi
        local shown=0
        for (( i = 0; i < ${#TUI_TABLE_COL[@]}; i++ )); do
            local w; w="$(tui_table_width "${TUI_TABLE_COL[$i]}")"
            (( w > 0 )) || continue
            (( shown > 0 )) && rule="${rule}${TUI_TABLE_GAP}"
            local seg; printf -v seg '%*s' "$w" ''
            rule="${rule}${seg// /$ch}"
            shown=$(( shown + 1 ))
        done
    fi

    if (( has_head == 1 )); then
        local head_row=""
        for (( i = 0; i < ${#TUI_TABLE_HEAD[@]}; i++ )); do
            [[ -n "$head_row" ]] && head_row="${head_row}${_TUI_TABLE_US}"
            head_row="${head_row}${TUI_TABLE_HEAD[$i]}"
        done
        printf '%s%s%s\n' "${TUI_C_HEAD:-}" "$(_tui_table_line "$head_row")" "${TUI_C_END:-}"
        (( borders == 1 )) && printf '%s%s%s\n' "${TUI_C_MUTE:-}" "$rule" "${TUI_C_END:-}"
    elif (( borders == 1 )); then
        printf '%s%s%s\n' "${TUI_C_MUTE:-}" "$rule" "${TUI_C_END:-}"
    fi

    local row
    for row in ${TUI_TABLE_ROW[@]+"${TUI_TABLE_ROW[@]}"}; do
        printf '%s\n' "$(_tui_table_line "$row")"
    done

    (( borders == 1 )) && printf '%s%s%s\n' "${TUI_C_MUTE:-}" "$rule" "${TUI_C_END:-}"
    return 0
}
