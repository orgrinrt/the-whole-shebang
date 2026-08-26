#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/menu/draw - Putting the list on the screen
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# The drawing half. It reads the view and the row arrays and writes nothing
# back, which is what lets the arrangement be tested without a terminal and
# the drawing be changed without touching the arrangement.
# =============================================================================

[[ -n "${_SHEBANG_TUI_MENU_DRAW_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_MENU_DRAW_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use super::tui::term
use super::tui::menu

# -----------------------------------------------------------------------------
# Drawing
# -----------------------------------------------------------------------------

use color

# One row. Markers are ascii on purpose: this runs in a recovery console where
# the font is whatever the kernel had, and a box-drawing character that renders
# as a question mark is worse than a hyphen that was always going to be one.
# Where the state column starts. Fixed, so the eye lands on one place instead
# of following a ragged right edge: a status appended to a label of whatever
# length it happened to be is a status nobody finds.
declare -gi TUI_MENU_STATE_COL="${TUI_MENU_STATE_COL:-34}"

_tui_menu_row() {
    local i="$1" selected="$2" state text

    # A negative index is a heading the grouping invented, so it has no row to
    # read and its label was handed in instead.
    if (( i < 0 )); then
        printf '%s%s%s' "$TUI_C_HEAD" "${3:-}" "$TUI_C_END"
        return 0
    fi
    state="${TUI_MENU_STATE[$i]}"; text="${TUI_MENU_TEXT[$i]}"

    if [[ "$state" == "heading" ]]; then
        printf '%s%s%s' "$TUI_C_HEAD" "$text" "$TUI_C_END"
        return 0
    fi

    local col="$TUI_MENU_STATE_COL" cols="${TUI_COLS:-80}"
    [[ "$col" =~ ^[0-9]+$ ]] || col=34
    # On a narrow screen the label wins; there is no point aligning a column
    # that would be off the edge.
    (( col > cols - 10 )) && col=$(( cols - 10 ))
    (( col < 12 )) && col=12

    local mark="  " label="$text" word="" colour=""
    case "$state" in
        done) word="done"; colour="$TUI_C_OK" ;;
        off)  word="off";  colour="$TUI_C_OFF" ;;
        warn) word="warn"; colour="$TUI_C_WARN" ;;
        fail) word="fail"; colour="$TUI_C_BAD" ;;
    esac
    [[ "$selected" == "1" ]] && mark="${TUI_C_SEL}> ${TUI_C_END}"

    # The label, dimmed when the row is unavailable, cut so it cannot push the
    # column it is meant to line up with.
    local room=$(( col - 5 )) shown="$label" len
    (( room < 4 )) && room=4
    len="${#label}"
    if (( len > room )); then
        shown="$(tui_cut "$label" "$room")"
        len="${#shown}"
    fi

    local pad=""
    (( col - 5 - len > 0 )) && printf -v pad '%*s' $(( col - 5 - len )) ''

    if [[ "$state" == "off" ]]; then
        printf '  %s%s%s%s%s' "$mark" "$TUI_C_OFFTXT" "$shown" "$TUI_C_END" "$pad"
    else
        printf '  %s%s%s' "$mark" "$shown" "$pad"
    fi
    [[ -n "$word" ]] && printf '%s%s%s' "$colour" "$word" "$TUI_C_END"
}

_tui_menu_rule_char() {
    if declare -F tui_unicode_ok >/dev/null 2>&1 && tui_unicode_ok; then
        printf '\u2500' | cat
    else
        printf -- '-'
    fi
}

#[pub]
# Add a line to the panel on the right: something true about the machine that
# is worth knowing while choosing, rather than after choosing wrongly.
# Usage: tui_menu_aside <label> <value>
tui_menu_aside() {
    TUI_MENU_ASIDE+=("${1}"$'\t'"${2:-}")
}

# How wide the panel gets, or 0 when there is no room for one. The list keeps
# what it needs first; the panel takes what is genuinely spare.
_tui_menu_aside_width() {
    (( ${#TUI_MENU_ASIDE[@]} > 0 )) || { printf '0'; return 0; }
    declare -F tui_layout_reset >/dev/null 2>&1 || { printf '0'; return 0; }

    tui_layout_reset cols "${TUI_COLS:-80}"
    tui_layout_add list 1fr min:46
    tui_layout_add gap  2 --priority 9
    # A width, not a share. A panel that grows with the window ends up mostly
    # blank on a wide one while the list it took the room from wraps.
    tui_layout_add side "$TUI_MENU_ASIDE_WIDTH" min:"$TUI_MENU_ASIDE_MIN" --priority 4
    tui_layout_solve
    tui_layout_has side || { printf '0'; return 0; }
    tui_layout_size side
}

# The panel itself, down the right, starting on the same row as the list.
_tui_menu_render_aside() {
    local width="$1" top_row="$2"
    (( width > 0 )) || return 0
    local left=$(( ${TUI_COLS:-80} - width + 1 ))
    (( left < 1 )) && return 0

    local row="$top_row" line label value shown
    for line in ${TUI_MENU_ASIDE[@]+"${TUI_MENU_ASIDE[@]}"}; do
        (( row >= TUI_ROWS - 5 )) && break
        IFS=$'\t' read -r label value <<< "$line"
        tui_move "$row" "$left"
        if [[ -z "$value" ]]; then
            # A label on its own is a heading for the group under it.
            printf '%s%s%s' "$TUI_C_HEAD" "$label" "$TUI_C_END"
        else
            shown="$label"
            (( ${#shown} > width - 2 )) && shown="${shown:0:$(( width - 2 ))}"
            printf '%s%s%s' "$TUI_C_MUTE" "$shown" "$TUI_C_END"
            local vrow=$(( ${#shown} ))
            tui_move "$row" $(( left + width - ${#value} ))
            (( ${#value} < width )) && printf '%s' "$value"
        fi
        row=$(( row + 1 ))
    done
}

#[pub]
# The keys this menu answers to, as "key<tab>what it does" lines. Public so a
# caller can show them somewhere of its own, and so `?` has one source rather
# than a second list that drifts from the first.
# Usage: tui_menu_keys
tui_menu_keys() {
    printf '%s\n' \
        $'up down\tmove, wrapping at either end' \
        $'[ ]\tby section, or a modifier with up and down' \
        $'home end\tfirst and last' \
        $'pgup pgdn\tby a screen' \
        $'enter\tchoose' \
        $'/\tsearch the name, the id and the note' \
        $'a\tshow or hide what cannot be run' \
        $'f\tfilter: a question about the row, not a word in it' \
        $'g\tgroup by section, by kind, or not at all' \
        $'s\tsort by the order declared, by name, or by state' \
        $'?\tthis' \
        $'q\tback'
}

# The help screen. Everything the interface can say about itself, in one place
# reached by one key, rather than spread between a key line, a manual and a
# --help nobody can reach from in here.
_tui_menu_help() {
    local title="$1" line key what
    tui_clear
    local row=1
    tui_move $row 1; printf '%s%s%s' "$TUI_C_HEAD" "$title" "$TUI_C_END"; row=$(( row + 2 ))

    if [[ -n "$TUI_MENU_ABOUT" ]]; then
        tui_move $row 1; printf '%s' "$TUI_MENU_ABOUT"; row=$(( row + 2 ))
    fi

    tui_move $row 1; printf '%sKeys%s' "$TUI_C_HEAD" "$TUI_C_END"; row=$(( row + 2 ))
    while IFS=$'\t' read -r key what; do
        [[ -n "$key" ]] || continue
        tui_move $row 1
        printf '  %s%-12s%s %s' "$TUI_C_KEY" "$key" "$TUI_C_END" "$what"
        row=$(( row + 1 ))
    done < <(tui_menu_keys)

    if [[ -n "$TUI_MENU_HELP" ]]; then
        row=$(( row + 1 ))
        while IFS= read -r line; do
            (( row >= TUI_ROWS - 1 )) && break
            tui_move $row 1; printf '%s' "$line"; row=$(( row + 1 ))
        done <<< "$TUI_MENU_HELP"
    fi

    tui_move "$TUI_ROWS" 1
    printf '%sany key to go back%s' "$TUI_C_MUTE" "$TUI_C_END"
    tui_key_read || true
}

# The whole screen. Redrawn on every key, which at this size is cheaper than
# tracking what changed and getting it wrong.
_tui_menu_render() {
    local cursor="$1" top="$2" height="$3" title="$4"
    local n i row=1 raw
    n="$(_tui_menu_len)"

    tui_clear
    tui_move $row 1; printf '%s%s%s' "$TUI_C_HEAD" "$title" "$TUI_C_END"; row=$(( row + 2 ))

    if (( n == 0 )); then
        tui_move $row 1
        printf '%snothing matches %s%s' "$TUI_C_WARN" "\"${TUI_MENU_FILTER}\"" "$TUI_C_END"
    fi

    # The panel first, so the list knows how much width is left to cut its
    # labels to.
    local aside_w; aside_w="$(_tui_menu_aside_width)"
    local list_cols="${TUI_COLS:-80}"
    (( aside_w > 0 )) && list_cols=$(( list_cols - aside_w - 2 ))
    _tui_menu_render_aside "$aside_w" 3

    local saved_cols="$TUI_COLS"
    TUI_COLS="$list_cols"
    for (( i = top; i < top + height && i < n; i++ )); do
        raw="${TUI_MENU_VIEW[$i]:-$i}"
        tui_move $row 1
        if (( i == cursor )); then _tui_menu_row "$raw" 1 "${TUI_MENU_VHEAD[$i]:-}"
        else                       _tui_menu_row "$raw" 0 "${TUI_MENU_VHEAD[$i]:-}"; fi
        row=$(( row + 1 ))
    done
    TUI_COLS="$saved_cols"

    # The note for whatever is under the cursor. Set apart by a rule and given
    # the label's own emphasis rather than dimmed into the background: dimmed
    # text at the bottom of a tall window is text nobody notices is there, and
    # a description nobody reads is a description nobody wrote.
    raw="${TUI_MENU_VIEW[$cursor]:-$cursor}"
    local note="" what=""
    if (( raw >= 0 )); then
        note="${TUI_MENU_NOTE[$raw]:-}"
        what="${TUI_MENU_TEXT[$raw]:-}"
    fi
    if [[ -n "$note" || -n "$what" ]]; then
        local rule
        printf -v rule '%*s' $(( ${TUI_COLS:-80} > 2 ? ${TUI_COLS:-80} - 1 : 1 )) ''
        tui_move $(( TUI_ROWS - 4 )) 1
        printf '%s%s%s' "$TUI_C_MUTE" "${rule// /$(_tui_menu_rule_char)}" "$TUI_C_END"
        tui_move $(( TUI_ROWS - 3 )) 1
        printf '%s%s%s' "$TUI_C_HEAD" "$what" "$TUI_C_END"
        tui_move $(( TUI_ROWS - 2 )) 1
        [[ -n "$note" ]] && printf '%s' "$note"
    fi

    # The filter is shown while it has content, because a list that is quietly
    # hiding rows and does not say so reads as a list with rows missing.
    tui_move $(( TUI_ROWS - 1 )) 1
    if [[ -n "$TUI_MENU_FILTER" ]]; then
        printf '%sfilter:%s %s%s%s' "$TUI_C_KEY" "$TUI_C_END" "$TUI_C_HEAD" "$TUI_MENU_FILTER" "$TUI_C_END"
    fi

    tui_move "$TUI_ROWS" 1
    if (( ${_TUI_MENU_FILTERING:-0} == 1 )); then
        printf '%s%s%s' "$TUI_C_MUTE" "typing to narrow   backspace   esc clears   enter choose" "$TUI_C_END"
    else
        # What is on, when it is not the default, because a list arranged some
        # other way and not saying so reads as a list in a strange order.
        local how=""
        [[ "$TUI_MENU_GROUP" != "section" ]] && how="${how}  by ${TUI_MENU_GROUP}"
        [[ "$TUI_MENU_SORT"  != "declared" ]] && how="${how}  ${TUI_MENU_SORT} order"
        [[ -n "$TUI_MENU_FILTER_ON" ]]        && how="${how}  ${TUI_MENU_FILTER_ON} only"
        local hint="up/down move   [ ] section   enter choose   / search   ? keys   q back"
        [[ -n "$how" ]] && hint="${hint}${how}"
        (( TUI_MENU_HIDE_OFF == 1 )) && hint="${hint}   ${TUI_C_KEY}a${TUI_C_END}${TUI_C_MUTE} hiding what cannot run"
        printf '%s%s%s' "$TUI_C_MUTE" "$hint" "$TUI_C_END"
    fi
}
