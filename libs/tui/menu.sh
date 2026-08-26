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
#   use shebang::tui::menu
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

# Hide the rows that cannot be run. Off by default: a list that silently omits
# things reads as a list with things missing, so this is something the reader
# turns on, and the key line says it is on.
declare -gi TUI_MENU_HIDE_OFF="${TUI_MENU_HIDE_OFF:-0}"

# What this menu is for, and any longer help, shown by `?` along with the keys.
declare -g TUI_MENU_ABOUT="${TUI_MENU_ABOUT:-}"
declare -g TUI_MENU_HELP="${TUI_MENU_HELP:-}"

# Lines for a panel down the right, as "label<tab>value". Shown when the
# terminal is wide enough to hold one without taking room the list needs, and
# not shown at all otherwise: a window that is tall and narrow has space below
# the list and none beside it, and squeezing a panel in there costs the labels
# their width for nothing.
declare -ga TUI_MENU_ASIDE=()
declare -gi TUI_MENU_ASIDE_MIN="${TUI_MENU_ASIDE_MIN:-24}"
declare -gi TUI_MENU_ASIDE_WIDTH="${TUI_MENU_ASIDE_WIDTH:-30}"
declare -g  TUI_MENU_FILTER=""

# The section a row was declared under, and the kind of thing it is. Both are
# carried per row so the list can be grouped by either without the caller
# building it twice.
declare -ga TUI_MENU_SECTION=()
declare -ga TUI_MENU_KIND=()

# How the list is arranged, and how it is ordered inside that.
#
# Two separate questions, and conflating them is what makes a list feel
# arbitrary: grouping decides which rows sit together, sorting decides the
# order within a group. `section` is the order the caller declared, which is
# usually deliberate, so it is the default for both.
declare -g TUI_MENU_GROUP="${TUI_MENU_GROUP:-section}"   # section, kind, none
declare -g TUI_MENU_SORT="${TUI_MENU_SORT:-declared}"    # declared, name, state

# A named filter is a predicate over a row, which is a different thing from the
# search: the search matches text somebody typed, a filter answers a question
# about the row. `available` is not a phrase anybody would search for.
declare -ga TUI_MENU_FILTERS=()
declare -g  TUI_MENU_FILTER_ON=""

# A synthetic heading is a row the grouping invented rather than one the caller
# declared, so it has no index into the row arrays. Parallel to TUI_MENU_VIEW:
# where this holds a label, that view row is a heading with that label.
declare -ga TUI_MENU_VHEAD=()

#[pub]
# Empty the list. Always call before building, or a second screen inherits the
# first one's entries.
# Usage: tui_menu_reset
tui_menu_reset() {
    TUI_MENU_ID=(); TUI_MENU_TEXT=(); TUI_MENU_STATE=(); TUI_MENU_NOTE=()
    TUI_MENU_SECTION=(); TUI_MENU_KIND=()
    TUI_MENU_VIEW=(); TUI_MENU_VHEAD=(); TUI_MENU_CHOICE=""; TUI_MENU_FILTER=""
    TUI_MENU_ASIDE=()
    _TUI_MENU_SECTION_NOW=""
}
declare -g _TUI_MENU_SECTION_NOW=""

#[pub]
# Add a heading. The cursor skips it, so it needs no id.
# Usage: tui_menu_heading <text>
tui_menu_heading() {
    TUI_MENU_ID+=("");  TUI_MENU_TEXT+=("$1")
    TUI_MENU_STATE+=("heading"); TUI_MENU_NOTE+=("")
    TUI_MENU_SECTION+=("$1"); TUI_MENU_KIND+=("")
    # Remembered, so every row after this one knows which section it is in and
    # the list can be regrouped without the caller declaring it twice.
    _TUI_MENU_SECTION_NOW="$1"
    TUI_MENU_VIEW+=($(( ${#TUI_MENU_ID[@]} - 1 )))
    TUI_MENU_VHEAD+=("")
}

#[pub]
# Add a choosable entry. State is ok, done or off; anything else is taken as ok
# rather than silently dropping the entry, because a missing row is harder to
# notice than a wrong colour.
# `kind` is what sort of thing the row is, in the caller's own words: check,
# fix, install, whatever the set divides into. It is what the list groups by
# when grouping by section is the wrong cut, and it is optional, because a menu
# whose rows are all the same kind gains nothing by saying so five times.
# Usage: tui_menu_entry <id> <text> [state] [note] [kind]
tui_menu_entry() {
    local state="${3:-ok}"
    case "$state" in ok|done|off) ;; *) state="ok" ;; esac
    TUI_MENU_ID+=("$1"); TUI_MENU_TEXT+=("$2")
    TUI_MENU_STATE+=("$state"); TUI_MENU_NOTE+=("${4:-}")
    TUI_MENU_SECTION+=("$_TUI_MENU_SECTION_NOW"); TUI_MENU_KIND+=("${5:-}")
    TUI_MENU_VIEW+=($(( ${#TUI_MENU_ID[@]} - 1 )))
    TUI_MENU_VHEAD+=("")
}

#[pub]
# Register a named filter: a question about a row, answered by a function that
# is given a row index and returns 0 to keep it.
#
# Separate from the search on purpose. The search matches text somebody typed,
# and works because they know what they are looking for. A filter answers a
# question they cannot phrase as a substring: "the ones I can actually run" is
# not a word that appears in any row.
# Usage: tui_menu_filter <name> <function>
tui_menu_filter() {
    [[ -n "${1:-}" && -n "${2:-}" ]] || return 1
    TUI_MENU_FILTERS+=("${1}"$'\t'"${2}")
}

#[pub]
# Turn a registered filter on, or off with an empty name.
# Usage: tui_menu_filter_on available
tui_menu_filter_on() { TUI_MENU_FILTER_ON="${1:-}"; }

# The next registered filter after the one that is on, wrapping through none.
_tui_menu_filter_next() {
    local n="${#TUI_MENU_FILTERS[@]}" i name
    (( n > 0 )) || { printf ''; return 0; }
    if [[ -z "$TUI_MENU_FILTER_ON" ]]; then
        printf '%s' "${TUI_MENU_FILTERS[0]%%$'\t'*}"
        return 0
    fi
    for (( i = 0; i < n; i++ )); do
        name="${TUI_MENU_FILTERS[$i]%%$'\t'*}"
        if [[ "$name" == "$TUI_MENU_FILTER_ON" ]]; then
            (( i + 1 < n )) && { printf '%s' "${TUI_MENU_FILTERS[$((i+1))]%%$'\t'*}"; return 0; }
            printf ''
            return 0
        fi
    done
    printf ''
}

# Does the row pass the filter that is on? No filter keeps everything.
_tui_menu_passes_filter() {
    local i="$1" entry name fn
    [[ -n "$TUI_MENU_FILTER_ON" ]] || return 0
    for entry in ${TUI_MENU_FILTERS[@]+"${TUI_MENU_FILTERS[@]}"}; do
        name="${entry%%$'\t'*}"; fn="${entry#*$'\t'}"
        [[ "$name" == "$TUI_MENU_FILTER_ON" ]] || continue
        declare -F "$fn" >/dev/null 2>&1 || return 0
        "$fn" "$i"
        return $?
    done
    return 0
}

# -----------------------------------------------------------------------------

use super::tui::menu::view
use super::tui::menu::draw


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
            if [[ "$TUI_KEY" == "?" ]]; then
                _tui_menu_help "$title"; continue
            fi
            if [[ "$TUI_KEY" == "g" ]]; then
                tui_menu_group_next
                tui_menu_refilter
                cursor="$(_tui_menu_first)"; top=0; continue
            fi
            if [[ "$TUI_KEY" == "s" ]]; then
                tui_menu_sort_next
                tui_menu_refilter
                cursor="$(_tui_menu_first)"; top=0; continue
            fi
            if [[ "$TUI_KEY" == "f" ]]; then
                # A filter is a question about the row, and the search is text
                # somebody typed. Two keys, because they are two things.
                tui_menu_filter_on "$(_tui_menu_filter_next)"
                tui_menu_refilter
                cursor="$(_tui_menu_first)"
                # Filtered down to nothing is a blank screen with no way out
                # but q, so it turns itself back off rather than stranding
                # somebody in an empty list.
                if (( $(_tui_menu_len) == 0 )); then
                    tui_menu_filter_on ""
                    tui_menu_refilter
                    cursor="$(_tui_menu_first)"
                fi
                top=0; continue
            fi
            if [[ "$TUI_KEY" == "a" ]]; then
                TUI_MENU_HIDE_OFF=$(( 1 - TUI_MENU_HIDE_OFF ))
                tui_menu_refilter
                cursor="$(_tui_menu_first)"; top=0
                # Everything may have gone: a set where nothing can run, with
                # the unavailable hidden, is an empty list. Turn it back rather
                # than leaving a blank screen with no way out but q.
                if ! _tui_menu_landable "$cursor"; then
                    TUI_MENU_HIDE_OFF=$(( 1 - TUI_MENU_HIDE_OFF ))
                    tui_menu_refilter
                    cursor="$(_tui_menu_first)"
                fi
                continue
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
            end)  cursor="$(_tui_menu_step "$(_tui_menu_first)" -1)" ;;
            pgup) cursor="$(_tui_menu_step "$cursor" -"$height")" ;;
            pgdn) cursor="$(_tui_menu_step "$cursor"  "$height")" ;;
            # A modifier with an arrow moves by section. Which modifier is
            # whatever the terminal sends, since a console that sends none of
            # them is exactly the console this has to work in, and `[` and `]`
            # are the fallback that always arrives.
            *-up|'[')   cursor="$(_tui_menu_section_step "$cursor" -1)" ;;
            *-down|']') cursor="$(_tui_menu_section_step "$cursor"  1)" ;;
        esac
    done
    tui_raw_off
    return 1
}
