#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/modal - Asking inside the interface, not under it
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Depends on tui/term.
#
# A question printed at the cursor lands wherever the last thing drawn left it,
# which after a full-screen menu is the bottom of the terminal. On a tall
# narrow window that is a long way from where the person is looking, and a
# prompt they have not noticed is a prompt they answer by reflex once they
# finally find it. That is the opposite of what a confirmation is for.
#
# So a question is drawn where the eye already is: a box over the middle of the
# screen, with the screen still visible around it. What was underneath is put
# back afterwards by redrawing, which the caller owns, because only the caller
# knows what was there.
#
# Usage:
#   use shebang::tui/term
#   use shebang::tui/modal
#
#   tui_modal_open "Wipe this disk" "/dev/sdb" "20 GiB, removable"
#   tui_modal_prompt "Type the name back to continue: "   # reads a line
#   tui_modal_close
# =============================================================================

[[ -n "${_SHEBANG_TUI_MODAL_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_MODAL_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use color

declare -gi _TUI_MODAL_OPEN=0
declare -gi _TUI_MODAL_TOP=0
declare -gi _TUI_MODAL_LEFT=0
declare -gi _TUI_MODAL_W=0
declare -gi _TUI_MODAL_H=0
declare -gi _TUI_MODAL_ROW=0

# The glyphs, ASCII wherever the nicer ones would be noise.
_tui_modal_glyphs() {
    if tui_unicode_ok; then
        printf -v _TUI_M_TL '%b' '\u250c'; printf -v _TUI_M_TR '%b' '\u2510'
        printf -v _TUI_M_BL '%b' '\u2514'; printf -v _TUI_M_BR '%b' '\u2518'
        printf -v _TUI_M_H  '%b' '\u2500'; printf -v _TUI_M_V  '%b' '\u2502'
    else
        _TUI_M_TL="+"; _TUI_M_TR="+"; _TUI_M_BL="+"; _TUI_M_BR="+"
        _TUI_M_H="-";  _TUI_M_V="|"
    fi
}
declare -g _TUI_M_TL="+" _TUI_M_TR="+" _TUI_M_BL="+" _TUI_M_BR="+"
declare -g _TUI_M_H="-"  _TUI_M_V="|"

_tui_modal_rep() {
    local c="$1" n="$2" out=""
    (( n > 0 )) || return 0
    printf -v out '%*s' "$n" ''
    printf '%s' "${out// /$c}"
}

_tui_modal_vis() {
    local s; s="$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' 2>/dev/null)" || s="$1"
    printf '%d' "${#s}"
}

#[pub]
# Open a box over the middle of the screen. Every argument after the title is a
# line inside it; the first is emphasised, because for a confirmation that line
# is the thing at stake.
# Usage: tui_modal_open <title> [line...]
tui_modal_open() {
    local title="${1:-}"; shift 2>/dev/null || true
    local -a body=("$@")

    if ! tui_is_tty; then
        # No screen to draw on. Say the same things, plainly, in order.
        [[ -n "$title" ]] && printf '%s\n' "$title"
        local l; for l in ${body[@]+"${body[@]}"}; do printf '  %s\n' "$l"; done
        _TUI_MODAL_OPEN=0
        return 0
    fi

    _tui_modal_glyphs
    tui_size 2>/dev/null || true

    local rows="${TUI_ROWS:-24}" cols="${TUI_COLS:-80}" w=0 len l
    [[ "$rows" =~ ^[0-9]+$ ]] || rows=24
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80

    len="$(_tui_modal_vis "$title")"; (( len > w )) && w="$len"
    for l in ${body[@]+"${body[@]}"}; do
        len="$(_tui_modal_vis "$l")"; (( len > w )) && w="$len"
    done
    # Room for the prompt line that usually follows, and for the borders.
    w=$(( w + 6 ))
    (( w > cols - 2 )) && w=$(( cols - 2 ))
    (( w < 20 ))       && w=20
    (( w > cols ))     && w="$cols"

    local h=$(( ${#body[@]} + 5 ))
    (( h > rows - 2 )) && h=$(( rows - 2 ))
    (( h < 5 ))        && h=5

    _TUI_MODAL_W="$w"; _TUI_MODAL_H="$h"
    _TUI_MODAL_TOP=$(( (rows - h) / 2 )); (( _TUI_MODAL_TOP < 1 )) && _TUI_MODAL_TOP=1
    _TUI_MODAL_LEFT=$(( (cols - w) / 2 )); (( _TUI_MODAL_LEFT < 1 )) && _TUI_MODAL_LEFT=1
    _TUI_MODAL_OPEN=1

    local bar; bar="$(_tui_modal_rep "$_TUI_M_H" $(( w - 2 )))"
    local r="$_TUI_MODAL_TOP"

    tui_move "$r" "$_TUI_MODAL_LEFT"
    printf '%s%s%s%s%s' "$TUI_C_HEAD" "$_TUI_M_TL" "$bar" "$_TUI_M_TR" "$TUI_C_END"
    r=$(( r + 1 ))

    _TUI_MODAL_ROW="$r"
    _tui_modal_row "$TUI_C_HEAD" "$title"
    _tui_modal_row "" ""
    local first=1
    for l in ${body[@]+"${body[@]}"}; do
        if (( first == 1 )); then
            _tui_modal_row "$TUI_C_HEAD" "$l"; first=0
        else
            _tui_modal_row "$TUI_C_MUTE" "$l"
        fi
    done
    _tui_modal_row "" ""
    return 0
}

# One line inside the box, padded to the border and moved to the next row.
_tui_modal_row() {
    local colour="$1" text="$2" inner=$(( _TUI_MODAL_W - 4 )) len pad
    (( inner < 1 )) && inner=1
    len="$(_tui_modal_vis "$text")"
    if (( len > inner )); then
        text="$(tui_cut "$text" "$inner")"
        len="$(_tui_modal_vis "$text")"
    fi
    pad="$(_tui_modal_rep " " $(( inner - len )))"
    tui_move "$_TUI_MODAL_ROW" "$_TUI_MODAL_LEFT"
    printf '%s%s%s %s%s%s%s %s%s%s' \
        "$TUI_C_HEAD" "$_TUI_M_V" "$TUI_C_END" \
        "$colour" "$text" "$TUI_C_END" "$pad" \
        "$TUI_C_HEAD" "$_TUI_M_V" "$TUI_C_END"
    _TUI_MODAL_ROW=$(( _TUI_MODAL_ROW + 1 ))
}

#[pub]
# Add a line to an open box.
# Usage: tui_modal_say <text> [colour]
tui_modal_say() {
    if (( _TUI_MODAL_OPEN == 0 )); then printf '%s\n' "${1:-}"; return 0; fi
    _tui_modal_row "${2:-}" "${1:-}"
}

#[pub]
# Ask for a line of input, with the cursor inside the box. Prints the answer.
# Returns 1 when the input ended without one.
# Usage: answer="$(tui_modal_prompt 'Type the name back: ')"
tui_modal_prompt() {
    local label="${1:-}" answer=""
    if (( _TUI_MODAL_OPEN == 0 )); then
        printf '%s' "$label" >&2
        IFS= read -r answer || return 1
        printf '%s' "$answer"
        return 0
    fi

    _tui_modal_row "$TUI_C_KEY" "$label"
    # The cursor goes back onto the prompt line, just past the label.
    local row=$(( _TUI_MODAL_ROW - 1 ))
    tui_move "$row" $(( _TUI_MODAL_LEFT + 2 + $(_tui_modal_vis "$label") ))
    tui_cursor_show
    local was_raw=0
    declare -F tui_raw_off >/dev/null 2>&1 && { tui_raw_off; was_raw=1; }
    IFS= read -r answer 2>/dev/null || { (( was_raw == 1 )) && tui_raw_on; tui_cursor_hide; return 1; }
    (( was_raw == 1 )) && tui_raw_on
    tui_cursor_hide
    printf '%s' "$answer"
    return 0
}

#[pub]
# Wait for a single key inside the box.
# Usage: tui_modal_key <label> -> sets TUI_KEY
tui_modal_key() {
    local label="${1:-}"
    if (( _TUI_MODAL_OPEN == 1 )); then _tui_modal_row "$TUI_C_KEY" "$label"; fi
    declare -F tui_key_read >/dev/null 2>&1 || return 1
    tui_key_read
}

#[pub]
# Close the box. The caller redraws what was underneath, because only the
# caller knows what that was.
# Usage: tui_modal_close
tui_modal_close() {
    (( _TUI_MODAL_OPEN == 1 )) || return 0
    local bar; bar="$(_tui_modal_rep "$_TUI_M_H" $(( _TUI_MODAL_W - 2 )))"
    tui_move "$_TUI_MODAL_ROW" "$_TUI_MODAL_LEFT"
    printf '%s%s%s%s%s' "$TUI_C_HEAD" "$_TUI_M_BL" "$bar" "$_TUI_M_BR" "$TUI_C_END"
    _TUI_MODAL_OPEN=0
    return 0
}

#[pub]
# Is a box open? For a caller deciding whether to draw inside one.
# Usage: tui_modal_is_open && ...
tui_modal_is_open() { (( _TUI_MODAL_OPEN == 1 )); }
