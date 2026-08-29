#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/menu/keys - The keys the menu answers to
# =============================================================================
# Part of the-whole-shebang. Internal to tui/menu.
#
# Split out of the menu because it is a different question from what a list is
# and how it is scrolled: this is what the menu registers into the action
# register, the line along the bottom built off it, and the one mode where the
# keys mean something else.
# =============================================================================

[[ -n "${_SHEBANG_TUI_MENU_KEYS_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_MENU_KEYS_SH=1

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
    _tui_menu_hint
}

# The line along the bottom, built from the register once rather than written
# out. It used to name `[ ]` in the source, which was a third copy of the keys
# after the key line and the help screen, and the one that stayed wrong longest
# because nobody reads a hint they have already read.
#
# Built once per binding rather than per frame: a command substitution per key
# is six forks, and the frame it would sit in is the one being made cheap.
declare -g _TUI_MENU_HINT=""

_tui_menu_hint() {
    local up down sect ch fwd search help back
    up="$(_tui_menu_first_key menu-up)"
    down="$(_tui_menu_first_key menu-down)"
    sect="$(_tui_menu_first_key section-prev)"
    fwd="$(_tui_menu_first_key section-next)"
    search="$(_tui_menu_first_key menu-search)"
    help="$(_tui_menu_first_key menu-help)"
    back="$(_tui_menu_first_key menu-back)"
    ch="$(_tui_menu_first_key menu-choose)"
    _TUI_MENU_HINT="${up}/${down} move   ${sect} ${fwd} section   ${ch} choose"
    _TUI_MENU_HINT+="   ${search} search   ${help} keys   ${back} back"
}

# The first key an action answers to, as the character to press, or nothing
# where it answers to none.
_tui_menu_first_key() {
    local keys; keys="$(tui_action_keys "$1")" || return 0
    [[ -n "$keys" ]] || return 0
    tui_action_key_char "${keys%% *}"
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
