#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/palette - Reaching an action by name
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Depends on tui/term, tui/key, tui/modal and tui/action.
#
# Every key is a thing somebody has to already know, and a screen only has so
# many of them. The palette is the other way in: type a few letters of what you
# want and pick it off a list, whether it has a key, whether that key is bound
# to something you can press, and whether you have ever seen it before.
#
# It searches the whole register rather than one scope, because a list of only
# the actions nobody gave a key to would be a list of leftovers.
#
# Usage:
#   use shebang::tui::palette
#
#   tui_palette_run  &&  printf '%s\n' "$TUI_PALETTE_CHOICE"
# =============================================================================

[[ -n "${_SHEBANG_TUI_PALETTE_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_PALETTE_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use super::tui::action

declare -g  TUI_PALETTE_CHOICE=""
declare -gi TUI_PALETTE_ROWS="${TUI_PALETTE_ROWS:-8}"

# One row, as it appears in the box: the label, then the keys that reach it
# where there are any.
#
# The keys are on the right of the label rather than the left, because the
# label is what somebody is reading down the list for, and a column of keys in
# front of it pushes every label to a different place. This is also where
# somebody learns a key exists, which is most of why the palette is worth
# having beyond the searching.
_tui_palette_row() {
    local id="$1" label keys out k
    label="$(tui_action_label "$id")" || return 1
    [[ -n "$label" ]] || label="$id"
    keys="$(tui_action_keys "$id")"
    out=""
    for k in $keys; do out+="${out:+ }$(tui_action_key_char "$k")"; done
    if [[ -n "$out" ]]; then printf '%s   (%s)' "$label" "$out"
    else printf '%s' "$label"; fi
}

# What is on screen for this query, into the array named by $1. Bounded, since
# a box cannot be taller than the terminal and nobody reads past the first
# handful anyway.
_tui_palette_matches() {
    local -n _out="$1"
    local q="$2" id n=0
    _out=()
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        _out+=("$id")
        n=$(( n + 1 ))
        (( n >= TUI_PALETTE_ROWS )) && break
    done < <(tui_action_search "$q")
}

#[pub]
# Open the palette and wait. Sets TUI_PALETTE_CHOICE to the chosen action's id
# and returns 0, or returns 1 when nothing was chosen.
#
# **It does not run anything.** The caller decides, because an action the owner
# dispatches itself has no handler here to call, and a palette that ran what it
# could and silently did nothing for the rest would be worse than one that ran
# nothing at all.
# Usage: tui_palette_run [title] -> sets TUI_PALETTE_CHOICE
tui_palette_run() {
    local title="${1:-Actions}" q="" sel=0 i
    local -a hits=()
    TUI_PALETTE_CHOICE=""

    tui_raw_on
    while true; do
        _tui_palette_matches hits "$q"
        (( sel >= ${#hits[@]} )) && sel=$(( ${#hits[@]} - 1 ))
        (( sel < 0 )) && sel=0

        tui_clear
        local -a body=()
        if (( ${#hits[@]} == 0 )); then
            body=("nothing matches")
        else
            for i in "${!hits[@]}"; do
                if (( i == sel )); then
                    body+=("> $(_tui_palette_row "${hits[$i]}")")
                else
                    body+=("  $(_tui_palette_row "${hits[$i]}")")
                fi
            done
        fi
        # Redrawn whole every keypress. The box changes height as the list
        # narrows, so painting over the last one would leave its bottom edge
        # sitting under the new one.
        tui_modal_open "$title" ${body[@]+"${body[@]}"}
        tui_modal_say "> ${q}_" "$TUI_C_KEY"
        tui_modal_close

        tui_key_read || break
        case "$TUI_KEY" in
            esc|ctrl-c) tui_raw_off; return 1 ;;
            enter)
                (( ${#hits[@]} > 0 )) || continue
                TUI_PALETTE_CHOICE="${hits[$sel]}"
                tui_raw_off; return 0 ;;
            up)   (( sel > 0 )) && sel=$(( sel - 1 )) ;;
            down) (( sel < ${#hits[@]} - 1 )) && sel=$(( sel + 1 )) ;;
            backspace)
                # Rubbing past the start leaves, so the way out is the way you
                # came in, the same as the menu's own search.
                [[ -n "$q" ]] || { tui_raw_off; return 1; }
                q="${q%?}"; sel=0 ;;
            space) q+=" "; sel=0 ;;
            *)
                if [[ ${#TUI_KEY} -eq 1 && "$TUI_KEY" == [[:print:]] ]]; then
                    q+="$TUI_KEY"; sel=0
                fi ;;
        esac
    done
    tui_raw_off
    return 1
}
