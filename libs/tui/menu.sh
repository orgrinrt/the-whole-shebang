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

use super::tui::action
use super::tui::palette
use super::tui::menu::view
use super::tui::menu::draw

# -----------------------------------------------------------------------------
# The keys, as actions
# -----------------------------------------------------------------------------

# Installed on the first run unless a caller installed them itself, so that a
# caller wanting different keys can call this, rebind, and then run.
declare -gi _TUI_MENU_BOUND=0

#[pub]
# Put the menu's own actions in the register, with the keys they ship with.
#
# Every key the menu answers to is here, movement included, because a key that
# is dispatched somewhere else is a key `?` cannot list and a keymap cannot
# reach. That is the whole reason the register exists.
# Usage: tui_menu_bindings
tui_menu_bindings() {
    tui_action_add menu-up       main "move up, wrapping at the top"    "up k ctrl-p shift-tab"
    tui_action_add menu-down     main "move down, wrapping at the end"  "down j ctrl-n tab"
    tui_action_add menu-first    main "to the first row"                "home"
    tui_action_add menu-last     main "to the last row"                 "end"
    tui_action_add menu-page-up  main "up by a screen"                  "pgup"
    tui_action_add menu-page-down main "down by a screen"               "pgdn"
    # Two keys each, and neither is guaranteed. A terminal can swallow the
    # modified arrow and a keyboard layout can withhold the bracket, so the
    # answer is that both reach it and either can be rebound to something the
    # machine in front of you actually sends.
    tui_action_add section-prev  main "to the previous section"  "bracket-left ctrl-up alt-up"
    tui_action_add section-next  main "to the next section"      "bracket-right ctrl-down alt-down"
    tui_action_add menu-search   main "search the name, the id and the note" "slash"
    tui_action_add menu-hidden   main "show or hide what cannot be run"      "a"
    tui_action_add menu-filter   main "filter: a question about the row, not a word in it" "f"
    tui_action_add menu-group    main "group by section, by kind, or not at all"           "g"
    tui_action_add menu-sort     main "sort by the order declared, by name, or by state"   "s"
    tui_action_add menu-palette  main "everything, by name"  "p colon"
    tui_action_add menu-help     main "this"    "question"
    tui_action_add menu-choose   main "choose"  "enter space"
    tui_action_add menu-back     main "back"    "q esc ctrl-c"
    # The search is a mode, so its keys are their own namespace: in there every
    # printable key types, and only the ones that cannot be part of a phrase
    # keep a meaning. Registered rather than left in a `case` for the same
    # reason as the rest, so `?` can show them and a keymap can move them.
    tui_action_add search-leave  filter "leave the search, keeping nothing"  "esc"
    tui_action_add search-accept filter "choose the row under the cursor"    "enter"
    tui_action_add search-rub    filter "rub out a letter, or leave when there are none" "backspace"
    tui_action_add search-quit   filter "back"                               "ctrl-c"
    _TUI_MENU_BOUND=1
}

# Which motion an action id means, or nothing when the id does not move the
# cursor. One place, so the dispatch and the coalescing agree by construction
# rather than by two lists somebody has to keep in step.
_tui_menu_motion_of() {
    case "$1" in
        menu-up)        printf 'up' ;;
        menu-down)      printf 'down' ;;
        menu-first)     printf 'home' ;;
        menu-last)      printf 'end' ;;
        menu-page-up)   printf 'pgup' ;;
        menu-page-down) printf 'pgdn' ;;
        section-prev)   printf 'section-prev' ;;
        section-next)   printf 'section-next' ;;
        *)              return 1 ;;
    esac
}


# -----------------------------------------------------------------------------
# Running
# -----------------------------------------------------------------------------

# One key while the search is open. Returns 0 with `act` set to something the
# dispatch below understands, or 1 when the key was typed into the phrase and
# there is nothing further to do with it.
#
# A function rather than a branch because it reads and writes the run loop's
# own variables, which in this shell it can, and keeping it inline made the
# loop long enough that the two modes were hard to tell apart while reading.
_tui_menu_typing() {
    # In the search every printable key types. Only the keys that cannot be
    # part of a phrase keep their meaning, and those are their own scope in the
    # register rather than a second list.
    act="$(tui_action_for filter "$TUI_KEY")" || act=""
    case "$act" in
        search-leave)
            filtering=0
            TUI_MENU_FILTER=""; tui_menu_refilter
            cursor="$(_tui_menu_first)"; top=0; return 1 ;;
        search-quit|search-accept) return 0 ;;
        search-rub)
            # Rubbing past the start leaves the search, so the way out is the
            # way you came in.
            if [[ -z "$TUI_MENU_FILTER" ]]; then filtering=0; return 1; fi
            TUI_MENU_FILTER="${TUI_MENU_FILTER%?}" ;;
        *)
            case "$TUI_KEY" in
                space) TUI_MENU_FILTER+=" " ;;
                up|down|left|right|pgup|pgdn|home|end)
                    # The cursor keys still move while the search is open, so a
                    # phrase can be typed and a row picked without leaving it.
                    act="$(tui_action_for main "$TUI_KEY")" || act=""
                    return 0 ;;
                *)
                    if [[ ${#TUI_KEY} -eq 1 && "$TUI_KEY" == [[:print:]] ]]; then
                        TUI_MENU_FILTER+="$TUI_KEY"
                    else
                        return 1
                    fi ;;
            esac ;;
    esac
    # The phrase changed, so the list is rebuilt and the cursor goes to the top
    # of what is left of it.
    tui_menu_refilter; cursor="$(_tui_menu_first)"; top=0
    return 1
}

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
    (( _TUI_MENU_BOUND )) || tui_menu_bindings

    local cursor top height raw motion act pending="" filtering=0
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

        # An action can arrive from the palette rather than from a key, and
        # once it has, it is the same action. Anything else would mean the
        # palette carrying a second copy of what every key already does.
        if [[ -n "$pending" ]]; then
            act="$pending"; pending=""; filtering=0
        else
            tui_key_read || break
            # Filtering is a mode, entered with `/`. Type-to-filter without one
            # cannot work here: every letter a person would search for is also
            # a key that already means something, so `chroot` would quit at the
            # h.
            if (( filtering == 0 )); then
                # One lookup, and everything below dispatches on what the key
                # means rather than on which key it was. A key nobody bound
                # falls through and does nothing, which is what it should do.
                act="$(tui_action_for main "$TUI_KEY")" || act=""
            else
                _tui_menu_typing || continue
            fi
        fi

        case "$act" in
                menu-search) filtering=1; continue ;;
                menu-help)   _tui_menu_help "$title"; continue ;;
                menu-group)
                    tui_menu_group_next
                    tui_menu_refilter
                    cursor="$(_tui_menu_first)"; top=0; continue ;;
                menu-sort)
                    tui_menu_sort_next
                    tui_menu_refilter
                    cursor="$(_tui_menu_first)"; top=0; continue ;;
                menu-filter)
                    # A filter is a question about the row, and the search is
                    # text somebody typed. Two keys, because they are two
                    # things.
                    tui_menu_filter_on "$(_tui_menu_filter_next)"
                    tui_menu_refilter
                    cursor="$(_tui_menu_first)"
                    # Filtered down to nothing is a blank screen with no way
                    # out but q, so it turns itself back off rather than
                    # stranding somebody in an empty list.
                    if (( ${#TUI_MENU_VIEW[@]} == 0 )); then
                        tui_menu_filter_on ""
                        tui_menu_refilter
                        cursor="$(_tui_menu_first)"
                    fi
                    top=0; continue ;;
                menu-hidden)
                    TUI_MENU_HIDE_OFF=$(( 1 - TUI_MENU_HIDE_OFF ))
                    tui_menu_refilter
                    cursor="$(_tui_menu_first)"; top=0
                    # Everything may have gone: a set where nothing can run,
                    # with the unavailable hidden, is an empty list. Turn it
                    # back rather than leaving a blank screen with no way out
                    # but q.
                    if ! _tui_menu_landable "$cursor"; then
                        TUI_MENU_HIDE_OFF=$(( 1 - TUI_MENU_HIDE_OFF ))
                        tui_menu_refilter
                        cursor="$(_tui_menu_first)"
                    fi
                    continue ;;
                menu-palette)
                    # The palette picks an id and runs nothing. What comes back
                    # goes round the loop as though a key had reached it, so
                    # there is one dispatch rather than one per way in.
                    if tui_palette_run "$title"; then pending="$TUI_PALETTE_CHOICE"; fi
                    continue ;;
                menu-choose|search-accept)
                    (( ${#TUI_MENU_VIEW[@]} > 0 )) || continue
                    raw="${TUI_MENU_VIEW[$cursor]:-$cursor}"
                    TUI_MENU_CHOICE="${TUI_MENU_ID[$raw]}"
                    tui_raw_off; return 0 ;;
                search-quit) tui_raw_off; return 1 ;;
                menu-back)
                    # Leaving with a filter still applied would hide rows from
                    # the next visit, so clear it on the way out.
                    if [[ -n "$TUI_MENU_FILTER" ]]; then
                        TUI_MENU_FILTER=""; tui_menu_refilter
                        cursor="$(_tui_menu_first)"; top=0; continue
                    fi
                    tui_raw_off; return 1 ;;
            esac

        # A burst of movement is one movement. A wheel event becomes a run of
        # arrow keys, and drawing the screen for each of them makes the drawing
        # the bottleneck: the queue outlives the gesture and the list keeps
        # painting for seconds after the hand stopped.
        #
        # Only movement is absorbed. The first key that is not movement ends
        # the run and is handed back, so nothing that acts on a row is ever
        # swallowed by a scroll.
        motion="$(_tui_menu_motion_of "$act")" || continue
        local more
        while tui_key_read_now; do
            more="$(tui_action_for main "$TUI_KEY")" || more=""
            more="$(_tui_menu_motion_of "$more")" || {
                tui_key_unread
                break
            }
            cursor="$(_tui_menu_move "$cursor" "$motion" "$height")"
            motion="$more"
        done

        cursor="$(_tui_menu_move "$cursor" "$motion" "$height")"
    done
    tui_raw_off
    return 1
}

# One movement, so absorbing a run and applying the last one are the same code.
_tui_menu_move() {
    local cursor="$1" motion="$2" height="$3"
    case "$motion" in
        up)           _tui_menu_step "$cursor" -1 ;;
        down)         _tui_menu_step "$cursor"  1 ;;
        home)         _tui_menu_first ;;
        end)          _tui_menu_step "$(_tui_menu_first)" -1 ;;
        pgup)         _tui_menu_step "$cursor" -"$height" ;;
        pgdn)         _tui_menu_step "$cursor"  "$height" ;;
        section-prev) _tui_menu_section_step "$cursor" -1 ;;
        section-next) _tui_menu_section_step "$cursor"  1 ;;
        *)            printf '%d' "$cursor" ;;
    esac
}
