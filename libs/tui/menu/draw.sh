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
use super::tui::table
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

# What a row looks like, as cells for the table rather than as a line of its
# own. Answers into _TUI_MENU_CELLS.
#
# Through the table because everything else that shows a list goes through it,
# and a menu with its own column arithmetic is a menu whose columns line up
# differently from every other list in the same interface. The state column
# stopped being a number in this file and became a column, which is what it
# always was.
declare -ga _TUI_MENU_CELLS=()

_tui_menu_cells() {
    local i="$1" selected="$2" heading="${3:-}" rule_w="${4:-0}"
    _TUI_MENU_CELLS=()

    # A heading is a label for what follows rather than a thing with a state,
    # so it takes no mark and no state word.
    #
    # It carries a rule out to the right edge, which is the whole of what makes
    # it look like a heading. Without one it is a row of ordinary text in the
    # name column, at the same indent as every entry, and a section break that
    # reads as an entry is worse than no section break: the eye has nothing to
    # catch on and the label looks like something that can be chosen.
    #
    # The width is passed in because the caller has solved the columns and this
    # has not. Filling a long run and letting the table cut it looks like a
    # rule that ran out of room, since the cut leaves an ellipsis behind.
    if (( i < 0 )) || [[ "${TUI_MENU_STATE[$i]}" == "heading" ]]; then
        local label="$heading"
        # Only a declared heading has a row to read its label from. For an
        # invented one `i` is -1, and `${ARRAY[-1]}` in bash is the last
        # element rather than an error, so a heading whose label was somehow
        # empty would silently draw the last row's text.
        [[ -n "$label" || $i -lt 0 ]] || label="${TUI_MENU_TEXT[$i]}"
        local bar=""
        if (( rule_w > 0 )); then
            printf -v bar '%*s' "$rule_w" ''
            bar="${TUI_C_MUTE}${bar// /$(_tui_menu_rule_char)}${TUI_C_END}"
        fi
        _TUI_MENU_CELLS=("" "${TUI_C_HEAD}${label}${TUI_C_END}" "" "$bar")
        return 0
    fi

    local state="${TUI_MENU_STATE[$i]}" text="${TUI_MENU_TEXT[$i]}"
    local mark="" word="" colour=""
    case "$state" in
        done) word="done"; colour="$TUI_C_OK" ;;
        off)  word="off";  colour="$TUI_C_OFF" ;;
        warn) word="warn"; colour="$TUI_C_WARN" ;;
        fail) word="fail"; colour="$TUI_C_BAD" ;;
    esac
    [[ "$selected" == "1" ]] && mark="${TUI_C_SEL}>${TUI_C_END}"

    local label="$text"
    [[ "$state" == "off" ]] && label="${TUI_C_OFFTXT}${text}${TUI_C_END}"

    # The note beside the row as well as under the cursor. A description you
    # have to move the cursor onto to read is a description nobody reads while
    # deciding which row to move onto.
    local note="${TUI_MENU_NOTE[$i]:-}"
    [[ -n "$note" ]] && note="${TUI_C_MUTE}${note}${TUI_C_END}"

    _TUI_MENU_CELLS=("$mark" "$label" "${colour}${word}${TUI_C_END}" "$note")
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

# The panel down the right, as lines of exactly the given width, into
# _TUI_MENU_ASIDE_LINES.
#
# Lines rather than cursor moves because the row it lands on is composed whole
# now: a row written on its own would be erased by the next redraw of the list
# row beside it, and one written after it would need the list row's visible
# width, which costs a fork per row to measure.
declare -ga _TUI_MENU_ASIDE_LINES=()

_tui_menu_aside_lines() {
    local width="$1"
    _TUI_MENU_ASIDE_LINES=()
    (( width > 0 )) || return 0

    local line label value shown pad gap
    for line in ${TUI_MENU_ASIDE[@]+"${TUI_MENU_ASIDE[@]}"}; do
        IFS=$'\t' read -r label value <<< "$line"
        if [[ -z "$value" ]]; then
            # A label on its own is a heading for the group under it.
            shown="$label"
            (( ${#shown} > width )) && shown="${shown:0:$width}"
            printf -v pad '%*s' $(( width - ${#shown} )) ''
            _TUI_MENU_ASIDE_LINES+=("${TUI_C_HEAD}${shown}${TUI_C_END}${pad}")
            continue
        fi
        shown="$label"
        (( ${#shown} > width - 2 )) && shown="${shown:0:$(( width - 2 ))}"
        # The value is right-aligned, so the numbers line up down the panel
        # rather than starting wherever their label happened to end.
        local v="$value"
        (( ${#v} > width )) && v="${v:0:$width}"
        gap=$(( width - ${#shown} - ${#v} ))
        (( gap < 1 )) && gap=1
        printf -v pad '%*s' "$gap" ''
        _TUI_MENU_ASIDE_LINES+=("${TUI_C_MUTE}${shown}${TUI_C_END}${pad}${v}")
    done
}

#[pub]
# The keys this menu answers to, as "keys<tab>what it does" lines. Public so a
# caller can show them somewhere of its own.
#
# Read off the action register rather than written out here, so a rebound key
# prints as the key it is now. The list this replaced was a second copy that
# said `[ ]` whatever anybody had bound, which is the drift the register exists
# to make impossible.
# Usage: tui_menu_keys [scope]
tui_menu_keys() {
    (( _TUI_MENU_BOUND )) || tui_menu_bindings
    tui_action_lines "${1:-main}"
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
    done < <(tui_menu_keys main)

    # The search is a mode with its own keys, and a help screen that listed
    # only the outer ones would leave somebody in there with no way to find out
    # what backspace does.
    if [[ -n "$(tui_menu_keys filter)" ]]; then
        row=$(( row + 1 ))
        tui_move $row 1
        printf '%sWhile searching%s' "$TUI_C_HEAD" "$TUI_C_END"; row=$(( row + 2 ))
        while IFS=$'\t' read -r key what; do
            [[ -n "$key" ]] || continue
            (( row >= TUI_ROWS - 1 )) && break
            tui_move $row 1
            printf '  %s%-12s%s %s' "$TUI_C_KEY" "$key" "$TUI_C_END" "$what"
            row=$(( row + 1 ))
        done < <(tui_menu_keys filter)
    fi

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

# One frame, into the screen buffer, which then writes only the rows that
# actually changed.
#
# It used to clear the screen and draw everything on every keypress, on the
# reasoning that at this size it was cheaper than tracking what changed and
# getting it wrong. That is true under a terminal emulator with a GPU behind it
# and false on a bare console, which is the machine a maintenance tool runs on:
# a cursor step there cost the better part of a second, and the whole screen
# blinked doing it.
#
# The geometry is what decides whether the buffer can be trusted. A resize, or
# anything else that wrote to the terminal behind its back, and it starts over.
declare -g _TUI_MENU_GEOM=""

_tui_menu_render() {
    local cursor="$1" top="$2" height="$3" title="$4"
    local n i row raw line
    n=${#TUI_MENU_VIEW[@]}

    local geom="${TUI_ROWS:-24}x${TUI_COLS:-80}"
    if [[ "$geom" != "$_TUI_MENU_GEOM" ]]; then
        tui_clear
        tui_screen_invalidate
        _TUI_MENU_GEOM="$geom"
    fi

    tui_screen_begin
    tui_screen_put 1 "${TUI_C_HEAD}${title}${TUI_C_END}"

    # The panel first, so the list knows how much width is left to cut its
    # labels to.
    local aside_w; aside_w="$(_tui_menu_aside_width)"
    local list_cols="${TUI_COLS:-80}"
    (( aside_w > 0 )) && list_cols=$(( list_cols - aside_w - 2 ))
    _tui_menu_aside_lines "$aside_w"

    if (( n == 0 )); then
        tui_screen_put 3 "${TUI_C_WARN}nothing matches \"${TUI_MENU_FILTER}\"${TUI_C_END}"
    fi

    # The list, through the table, so its columns are the same columns every
    # other list in the interface uses. Built once and drawn once rather than a
    # line at a time: the table solves the widths for the whole thing, which is
    # what makes a column a column.
    local saved_cols="$TUI_COLS"
    TUI_COLS="$list_cols"
    local -a rows=()
    if declare -F tui_table_reset >/dev/null 2>&1; then
        # The name at a fixed width so the state lands in the same place on
        # every row, which is the whole reason it is a column. The note takes
        # what is left and is the first thing to go on a narrow screen: it
        # repeats below the list, so losing it there costs nothing.
        local name_w="$TUI_MENU_STATE_COL"
        [[ "$name_w" =~ ^[0-9]+$ ]] || name_w=34
        (( name_w > list_cols - 10 )) && name_w=$(( list_cols - 10 ))
        (( name_w < 12 )) && name_w=12

        tui_table_reset
        tui_table_col mark  1
        tui_table_col name  "$name_w"
        tui_table_col state 6
        tui_table_col note  1fr min:16 --priority 5

        # Solved before the rows are built, because a heading's rule has to be
        # exactly the width of the column it sits in and nothing else knows
        # what that came out as. The render below solves again with the same
        # width and gets the same answer.
        local rule_w=0
        _tui_table_solve "$list_cols" && rule_w="$(tui_table_width note)"
        [[ "$rule_w" =~ ^[0-9]+$ ]] || rule_w=0

        for (( i = top; i < top + height && i < n; i++ )); do
            raw="${TUI_MENU_VIEW[$i]:-$i}"
            if (( i == cursor )); then _tui_menu_cells "$raw" 1 "${TUI_MENU_VHEAD[$i]:-}" "$rule_w"
            else                       _tui_menu_cells "$raw" 0 "${TUI_MENU_VHEAD[$i]:-}" "$rule_w"; fi
            tui_table_row "${_TUI_MENU_CELLS[@]}"
        done
        # Captured rather than placed, so the panel beside it can be composed
        # onto the same row. One fork a frame, against one per cell before.
        while IFS= read -r line; do rows+=("$line"); done \
            < <(tui_table_render --width "$list_cols" --height "$height")
    fi
    TUI_COLS="$saved_cols"

    # The list and the panel share their rows, so they are joined here. A row
    # is written whole or the two erase each other.
    local body=$(( n - top ))
    (( body < 0 )) && body=0
    local aside_n="${#_TUI_MENU_ASIDE_LINES[@]}"
    local span="$body"
    (( aside_n > span )) && span="$aside_n"
    local last=$(( TUI_ROWS - 6 ))
    for (( i = 0; i < span; i++ )); do
        row=$(( 3 + i ))
        (( row > last )) && break
        line="${rows[$i]-}"
        if (( aside_w > 0 && i < aside_n )); then
            # The table pads its cells, so a list line is already exactly the
            # width of the list and nothing has to be measured to know where
            # the panel starts.
            local pad=""
            (( ${#line} == 0 )) && printf -v pad '%*s' "$list_cols" ''
            line="${line}${pad}  ${_TUI_MENU_ASIDE_LINES[$i]}"
        fi
        tui_screen_put "$row" "$line"
    done

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
        tui_screen_put $(( TUI_ROWS - 4 )) \
            "${TUI_C_MUTE}${rule// /$(_tui_menu_rule_char)}${TUI_C_END}"
        tui_screen_put $(( TUI_ROWS - 3 )) "${TUI_C_HEAD}${what}${TUI_C_END}"
        tui_screen_put $(( TUI_ROWS - 2 )) "$note"
    fi

    # The filter is shown while it has content, because a list that is quietly
    # hiding rows and does not say so reads as a list with rows missing.
    if [[ -n "$TUI_MENU_FILTER" ]]; then
        tui_screen_put $(( TUI_ROWS - 1 )) \
            "${TUI_C_KEY}filter:${TUI_C_END} ${TUI_C_HEAD}${TUI_MENU_FILTER}${TUI_C_END}"
    fi

    if (( ${_TUI_MENU_FILTERING:-0} == 1 )); then
        tui_screen_put "$TUI_ROWS" \
            "${TUI_C_MUTE}typing to narrow   backspace   esc clears   enter choose${TUI_C_END}"
    else
        # What is on, when it is not the default, because a list arranged some
        # other way and not saying so reads as a list in a strange order.
        local how=""
        [[ "$TUI_MENU_GROUP" != "section" ]] && how="${how}  by ${TUI_MENU_GROUP}"
        [[ "$TUI_MENU_SORT"  != "declared" ]] && how="${how}  ${TUI_MENU_SORT} order"
        [[ -n "$TUI_MENU_FILTER_ON" ]]        && how="${how}  ${TUI_MENU_FILTER_ON} only"
        local hint="${_TUI_MENU_HINT:-}"
        [[ -n "$how" ]] && hint="${hint}${how}"
        (( TUI_MENU_HIDE_OFF == 1 )) && hint="${hint}   ${TUI_C_KEY}a${TUI_C_END}${TUI_C_MUTE} hiding what cannot run"
        tui_screen_put "$TUI_ROWS" "${TUI_C_MUTE}${hint}${TUI_C_END}"
    fi

    tui_screen_flush
}
