#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/menu - A list you choose from
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Depends on tui/term and tui/key, and nothing else in the collection.
#
# The list is built by the caller and then run. Headings are entries too, so
# that ordering is expressed by the order things are added rather than by a
# separate structure the caller has to keep in step; the cursor simply refuses
# to land on them.
#
# An entry carries a state, and the three states are the ones a maintenance
# tool actually needs. `ok` is available. `done` is already true, shown rather
# than hidden because "nothing to do here" is information a person came for.
# `off` cannot run now, shown for the same reason: a menu that hides what it
# will not do leaves the user hunting for a thing that was never there.
#
# The scrolling arithmetic is separated out and tested on its own. Off-by-one
# in a viewport is the classic way a list becomes unusable at exactly the sizes
# nobody tried, and it is pure arithmetic, so there is no excuse for guessing.
#
# Usage:
#   use shebang::tui/menu
#
#   tui_menu_reset
#   tui_menu_heading "Disk"
#   tui_menu_entry disk-smart "Check disk health"      ok   "Reads SMART."
#   tui_menu_entry disk-luks  "Back up LUKS headers"   done "Already on the stick."
#   tui_menu_run "hulilupteri"   &&  printf '%s\n' "$TUI_MENU_CHOICE"
# =============================================================================

[[ -n "${_SHEBANG_TUI_MENU_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_MENU_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

# -----------------------------------------------------------------------------
# The list
# -----------------------------------------------------------------------------

declare -ga TUI_MENU_ID=()      # "" for a heading
declare -ga TUI_MENU_TEXT=()
declare -ga TUI_MENU_STATE=()   # ok | done | off | heading
declare -ga TUI_MENU_NOTE=()
declare -g  TUI_MENU_CHOICE=""

# Which rows are on screen, as indices into the arrays above. Everything that
# moves a cursor or scrolls works on this rather than on the full list, so
# filtering needs no special case anywhere: an unfiltered menu is simply one
# whose view is everything.
declare -ga TUI_MENU_VIEW=()
declare -g  TUI_MENU_FILTER=""

#[pub]
# Empty the list. Always call before building, or a second screen inherits the
# first one's entries.
# Usage: tui_menu_reset
tui_menu_reset() {
    TUI_MENU_ID=(); TUI_MENU_TEXT=(); TUI_MENU_STATE=(); TUI_MENU_NOTE=()
    TUI_MENU_VIEW=(); TUI_MENU_CHOICE=""; TUI_MENU_FILTER=""
}

#[pub]
# Add a heading. The cursor skips it, so it needs no id.
# Usage: tui_menu_heading <text>
tui_menu_heading() {
    TUI_MENU_ID+=("");  TUI_MENU_TEXT+=("$1")
    TUI_MENU_STATE+=("heading"); TUI_MENU_NOTE+=("")
    TUI_MENU_VIEW+=($(( ${#TUI_MENU_ID[@]} - 1 )))
}

#[pub]
# Add a choosable entry. State is ok, done or off; anything else is taken as ok
# rather than silently dropping the entry, because a missing row is harder to
# notice than a wrong colour.
# Usage: tui_menu_entry <id> <text> [state] [note]
tui_menu_entry() {
    local state="${3:-ok}"
    case "$state" in ok|done|off) ;; *) state="ok" ;; esac
    TUI_MENU_ID+=("$1"); TUI_MENU_TEXT+=("$2")
    TUI_MENU_STATE+=("$state"); TUI_MENU_NOTE+=("${4:-}")
    TUI_MENU_VIEW+=($(( ${#TUI_MENU_ID[@]} - 1 )))
}

# -----------------------------------------------------------------------------
# Filtering
# -----------------------------------------------------------------------------

# Case-insensitive substring, over the text and the note both. The note carries
# the reason a row is unavailable, and searching for "not installed" to find
# everything blocked on a missing package is exactly the question a person has.
_tui_menu_match() {
    local i="$1" want="$2"
    [[ -z "$want" ]] && return 0
    local hay="${TUI_MENU_TEXT[$i]} ${TUI_MENU_NOTE[$i]}"
    [[ "${hay,,}" == *"${want,,}"* ]]
}

#[pub]
# Rebuild the view for the current filter.
#
# A heading survives only when something under it does, so filtering does not
# leave a screen of section titles with nothing beneath them.
# Usage: tui_menu_refilter -> rebuilds TUI_MENU_VIEW
tui_menu_refilter() {
    local n="${#TUI_MENU_ID[@]}" i j keep
    TUI_MENU_VIEW=()
    for (( i = 0; i < n; i++ )); do
        if [[ "${TUI_MENU_STATE[$i]}" == "heading" ]]; then
            keep=1
            for (( j = i + 1; j < n; j++ )); do
                [[ "${TUI_MENU_STATE[$j]}" == "heading" ]] && break
                if _tui_menu_match "$j" "$TUI_MENU_FILTER"; then keep=0; break; fi
            done
            (( keep == 0 )) && TUI_MENU_VIEW+=("$i")
        else
            _tui_menu_match "$i" "$TUI_MENU_FILTER" && TUI_MENU_VIEW+=("$i")
        fi
    done
}

# -----------------------------------------------------------------------------
# Arithmetic, kept pure so it can be tested
# -----------------------------------------------------------------------------

# Can the cursor rest here. Headings cannot, `off` entries can: a person is
# allowed to select one and be told why it will not run, which is more useful
# than a cursor that mysteriously jumps over it.
_tui_menu_landable() {
    local raw="${TUI_MENU_VIEW[$1]:-}"
    [[ -n "$raw" ]] || raw="$1"
    [[ "${TUI_MENU_STATE[$raw]:-heading}" != "heading" ]]
}

# How many rows are on screen. The view is the truth; the full list is only the
# fallback for a caller that never built one.
_tui_menu_len() {
    if (( ${#TUI_MENU_VIEW[@]} > 0 )); then printf '%d' "${#TUI_MENU_VIEW[@]}"
    else printf '%d' "${#TUI_MENU_ID[@]}"; fi
}

# The next index the cursor may rest on, moving by <step>. Stops at the ends
# rather than wrapping: in a list where the first rows are headings, wrapping
# sends the cursor somewhere the user did not ask for.
_tui_menu_step() {
    local from="$1" step="$2" n i; n="$(_tui_menu_len)"
    i=$(( from + step ))
    while (( i >= 0 && i < n )); do
        _tui_menu_landable "$i" && { printf '%d' "$i"; return 0; }
        i=$(( i + step ))
    done
    printf '%d' "$from"
}

# First index the cursor may rest on. Used for the initial position, which is
# otherwise index 0 and therefore usually a heading.
_tui_menu_first() {
    local n i=0; n="$(_tui_menu_len)"
    while (( i < n )); do
        _tui_menu_landable "$i" && { printf '%d' "$i"; return 0; }
        i=$(( i + 1 ))
    done
    printf '%d' 0
}

# Where the viewport starts, given the cursor, the height and where it started
# last time. Keeps the cursor on screen while moving the window as little as
# possible, so the list does not jump under the reader on every keypress.
_tui_menu_window() {
    local cursor="$1" height="$2" top="$3" n; n="$(_tui_menu_len)"
    (( height < 1 )) && height=1
    (( cursor <  top ))               && top=$cursor
    (( cursor >= top + height ))      && top=$(( cursor - height + 1 ))
    (( top > n - height ))            && top=$(( n - height ))
    (( top < 0 ))                     && top=0
    printf '%d' "$top"
}

# -----------------------------------------------------------------------------
# Drawing
# -----------------------------------------------------------------------------

use color

# One row. Markers are ascii on purpose: this runs in a recovery console where
# the font is whatever the kernel had, and a box-drawing character that renders
# as a question mark is worse than a hyphen that was always going to be one.
_tui_menu_row() {
    local i="$1" selected="$2" state="${TUI_MENU_STATE[$i]}" text="${TUI_MENU_TEXT[$i]}"

    if [[ "$state" == "heading" ]]; then
        printf '%s' "${BOLD}${text}${NC}"
        return 0
    fi

    local mark="  " body="$text"
    case "$state" in
        done) body="${text}${DIM}   done${NC}" ;;
        off)  body="${DIM}${text}${NC}"        ;;
    esac
    [[ "$selected" == "1" ]] && mark="${BOLD}> ${NC}"
    printf '  %s%s' "$mark" "$body"
}

# The whole screen. Redrawn on every key, which at this size is cheaper than
# tracking what changed and getting it wrong.
_tui_menu_render() {
    local cursor="$1" top="$2" height="$3" title="$4"
    local n i row=1 raw
    n="$(_tui_menu_len)"

    tui_clear
    tui_move $row 1; printf '%s%s%s' "$BOLD" "$title" "$NC"; row=$(( row + 2 ))

    if (( n == 0 )); then
        tui_move $row 1
        printf '%snothing matches %s%s' "$DIM" "\"${TUI_MENU_FILTER}\"" "$NC"
    fi

    for (( i = top; i < top + height && i < n; i++ )); do
        raw="${TUI_MENU_VIEW[$i]:-$i}"
        tui_move $row 1
        if (( i == cursor )); then _tui_menu_row "$raw" 1; else _tui_menu_row "$raw" 0; fi
        row=$(( row + 1 ))
    done

    # The note for whatever is under the cursor, pinned to the bottom so it
    # does not move as the list scrolls.
    raw="${TUI_MENU_VIEW[$cursor]:-$cursor}"
    local note="${TUI_MENU_NOTE[$raw]:-}"
    tui_move $(( TUI_ROWS - 2 )) 1
    [[ -n "$note" ]] && printf '%s%s%s' "$DIM" "$note" "$NC"

    # The filter is shown while it has content, because a list that is quietly
    # hiding rows and does not say so reads as a list with rows missing.
    tui_move $(( TUI_ROWS - 1 )) 1
    if [[ -n "$TUI_MENU_FILTER" ]]; then
        printf '%sfilter:%s %s' "$BOLD" "$NC" "$TUI_MENU_FILTER"
    fi

    tui_move "$TUI_ROWS" 1
    if (( ${_TUI_MENU_FILTERING:-0} == 1 )); then
        printf '%s%s%s' "$DIM" "typing to narrow   backspace   esc clears   enter choose" "$NC"
    else
        printf '%s%s%s' "$DIM" "up/down move   enter choose   / search   q back" "$NC"
    fi
}

# -----------------------------------------------------------------------------
# Running
# -----------------------------------------------------------------------------

#[pub]
# Show the list and wait for a choice.
#
# Returns 0 with TUI_MENU_CHOICE set to the chosen id, or 1 if the user backed
# out. An empty list returns 1 rather than drawing a screen with nothing on it
# and trapping the user in it.
# Usage: tui_menu_run <title> -> sets TUI_MENU_CHOICE, returns 0 or 1
tui_menu_run() {
    local title="${1:-}" n="${#TUI_MENU_ID[@]}"
    TUI_MENU_CHOICE=""
    (( n > 0 )) || return 1

    local cursor top height raw motion filtering=0
    tui_menu_refilter
    cursor="$(_tui_menu_first)"
    _tui_menu_landable "$cursor" || return 1     # headings only, nothing to pick
    top=0

    tui_raw_on
    while true; do
        tui_size
        height=$(( TUI_ROWS - 6 ))
        (( height < 1 )) && height=1
        top="$(_tui_menu_window "$cursor" "$height" "$top")"
        _TUI_MENU_FILTERING=$filtering
        _tui_menu_render "$cursor" "$top" "$height" "$title"

        tui_key_read || break

        # Filtering is a mode, entered with `/`. Type-to-filter without one
        # cannot work here: every letter a person would search for is also a
        # key that already means something, so `chroot` would quit at the h.
        if (( filtering == 0 )); then
            if [[ "$TUI_KEY" == "/" ]]; then
                filtering=1; continue
            fi
            if tui_key_is_accept; then
                (( $(_tui_menu_len) > 0 )) || continue
                raw="${TUI_MENU_VIEW[$cursor]:-$cursor}"
                TUI_MENU_CHOICE="${TUI_MENU_ID[$raw]}"
                tui_raw_off; return 0
            fi
            if tui_key_is_cancel; then
                # Leaving with a filter still applied would hide rows from the
                # next visit, so clear it on the way out.
                if [[ -n "$TUI_MENU_FILTER" ]]; then
                    TUI_MENU_FILTER=""; tui_menu_refilter
                    cursor="$(_tui_menu_first)"; top=0; continue
                fi
                tui_raw_off; return 1
            fi
        else
            # In filter mode every printable key types. Only the keys that
            # cannot be part of a search phrase keep their meaning.
            case "$TUI_KEY" in
                esc)
                    filtering=0
                    TUI_MENU_FILTER=""; tui_menu_refilter
                    cursor="$(_tui_menu_first)"; top=0; continue ;;
                ctrl-c) tui_raw_off; return 1 ;;
                enter)
                    (( $(_tui_menu_len) > 0 )) || continue
                    raw="${TUI_MENU_VIEW[$cursor]:-$cursor}"
                    TUI_MENU_CHOICE="${TUI_MENU_ID[$raw]}"
                    tui_raw_off; return 0 ;;
                backspace)
                    # Backspacing past the start leaves filter mode, so the
                    # way out is the way you came in.
                    if [[ -z "$TUI_MENU_FILTER" ]]; then filtering=0; continue; fi
                    TUI_MENU_FILTER="${TUI_MENU_FILTER%?}" ;;
                space) TUI_MENU_FILTER+=" " ;;
                up|down|left|right|pgup|pgdn|home|end) : ;;
                *)
                    if [[ ${#TUI_KEY} -eq 1 && "$TUI_KEY" == [[:print:]] ]]; then
                        TUI_MENU_FILTER+="$TUI_KEY"
                    fi ;;
            esac
            case "$TUI_KEY" in
                up|down|left|right|pgup|pgdn|home|end) ;;
                *) tui_menu_refilter; cursor="$(_tui_menu_first)"; top=0; continue ;;
            esac
        fi

        motion="$(tui_key_motion)"
        case "$motion" in
            up)   cursor="$(_tui_menu_step "$cursor" -1)" ;;
            down) cursor="$(_tui_menu_step "$cursor"  1)" ;;
            home) cursor="$(_tui_menu_first)"             ;;
            pgup) cursor="$(_tui_menu_step "$cursor" -"$height")" ;;
            pgdn) cursor="$(_tui_menu_step "$cursor"  "$height")" ;;
        esac
    done
    tui_raw_off
    return 1
}
