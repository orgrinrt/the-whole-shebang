#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/menu/view - Which rows, in what order, under what headings
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# The list the reader sees is not the list the caller declared. Between them
# sit a search, a filter, a sort and a grouping, and the arithmetic that walks
# the result. All of it is here, and none of it draws anything, so the shape
# of the list can be checked at sizes and orderings no terminal would show.
# =============================================================================

[[ -n "${_SHEBANG_TUI_MENU_VIEW_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_MENU_VIEW_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use super::tui::menu

# Filtering
# -----------------------------------------------------------------------------

# Case-insensitive substring, over the text and the note both. The note carries
# the reason a row is unavailable, and searching for "not installed" to find
# everything blocked on a missing package is exactly the question a person has.
_tui_menu_match() {
    local i="$1" want="$2"
    [[ -z "$want" ]] && return 0
    # The id too, not only the label and the note. The id is what a row is
    # called everywhere else -- it is what the command line takes and what
    # somebody has in their head -- so searching `fe` for `iso-fetch` found
    # nothing, because the label said "Put an install image on the stick".
    local hay="${TUI_MENU_ID[$i]} ${TUI_MENU_TEXT[$i]} ${TUI_MENU_NOTE[$i]}"
    [[ "${hay,,}" == *"${want,,}"* ]]
}

#[pub]
# Rebuild the view for the current filter.
#
# A heading survives only when something under it does, so filtering does not
# leave a screen of section titles with nothing beneath them.
# Usage: tui_menu_refilter -> rebuilds TUI_MENU_VIEW
# Whether a row survives the current view: the search phrase, and whether
# unavailable rows are being shown at all.
_tui_menu_shown() {
    local i="$1"
    _tui_menu_match "$i" "$TUI_MENU_FILTER" || return 1
    if (( TUI_MENU_HIDE_OFF == 1 )) && [[ "${TUI_MENU_STATE[$i]}" == "off" ]]; then
        return 1
    fi
    return 0
}

tui_menu_refilter() {
    TUI_MENU_VIEW=(); TUI_MENU_VHEAD=()

    # The rows that survive the search, the filter and the hide, in declared
    # order. Everything after this is arrangement.
    local n="${#TUI_MENU_ID[@]}" i
    local -a rows=()
    for (( i = 0; i < n; i++ )); do
        [[ "${TUI_MENU_STATE[$i]}" == "heading" ]] && continue
        _tui_menu_shown "$i" || continue
        _tui_menu_passes_filter "$i" || continue
        rows+=("$i")
    done

    # The order the groups come in is taken before the sort, not after. A sort
    # orders rows inside a group and must not move the groups: sections that
    # rearrange when the ordering changes lose the reader's place entirely, and
    # with a state sort the section order would depend on which group happened
    # to hold the readiest row, so adding one task would rearrange the screen.
    local -a order=()
    _tui_menu_group_order rows order

    _tui_menu_sort_rows rows
    _tui_menu_group_rows rows order
}

# The groups, in the order they first appear in the declared rows.
_tui_menu_group_order() {
    local -n _rows="$1"
    local -n _out="$2"
    _out=()
    local row group g known
    for row in ${_rows[@]+"${_rows[@]}"}; do
        group="$(_tui_menu_group_of "$row")"
        known=0
        for g in ${_out[@]+"${_out[@]}"}; do [[ "$g" == "$group" ]] && { known=1; break; }; done
        (( known == 0 )) && _out+=("$group")
    done
}

# Order the rows within whatever group they end up in.
#
# `declared` is the caller's own order, which is usually deliberate and is the
# reason it is the default: a list somebody arranged by hand is arranged for a
# reason, and sorting it alphabetically throws that away.
_tui_menu_sort_rows() {
    local -n _rows="$1"
    (( ${#_rows[@]} > 1 )) || return 0
    case "$TUI_MENU_SORT" in
        name)  _tui_menu_sort_by _rows _tui_menu_key_name ;;
        state) _tui_menu_sort_by _rows _tui_menu_key_state ;;
        *)     : ;;
    esac
}

# What a row sorts under. Lowercased for the name, so `Back up` and `apply` do
# not end up in two alphabets.
_tui_menu_key_name()  { printf '%s' "${TUI_MENU_TEXT[$1],,}"; }

# Ready first, then already done, then unavailable, and the label inside each.
# The order somebody scanning for something to do wants: the rows they can act
# on are at the top rather than scattered through the ones they cannot.
_tui_menu_key_state() {
    local rank
    case "${TUI_MENU_STATE[$1]}" in
        ok)   rank=0 ;;
        done) rank=1 ;;
        off)  rank=2 ;;
        *)    rank=3 ;;
    esac
    printf '%d %s' "$rank" "${TUI_MENU_TEXT[$1],,}"
}

# Insertion sort by a key function, stable, in the shell. A menu is a screenful
# and `sort` is two forks on a path that runs on every keystroke.
_tui_menu_sort_by() {
    local -n _r="$1"
    local keyfn="$2" n="${#_r[@]}" i j cur curkey
    local -a keys=()
    for (( i = 0; i < n; i++ )); do keys+=("$("$keyfn" "${_r[$i]}")"); done
    for (( i = 1; i < n; i++ )); do
        cur="${_r[$i]}"; curkey="${keys[$i]}"
        j=$(( i - 1 ))
        while (( j >= 0 )) && [[ "${keys[$j]}" > "$curkey" ]]; do
            _r[j+1]="${_r[$j]}"; keys[j+1]="${keys[$j]}"
            j=$(( j - 1 ))
        done
        _r[j+1]="$cur"; keys[j+1]="$curkey"
    done
}

# What a row is grouped under, in the current grouping.
_tui_menu_group_of() {
    case "$TUI_MENU_GROUP" in
        kind)    printf '%s' "${TUI_MENU_KIND[$1]:-other}" ;;
        none)    printf '' ;;
        *)       printf '%s' "${TUI_MENU_SECTION[$1]:-}" ;;
    esac
}

# Lay the rows out under headings, in the order the groups first appear.
#
# The headings are made here rather than taken from the declared ones, because
# grouping by anything other than section means the declared headings are the
# wrong headings. A group with nothing in it never appears, so filtering does
# not leave a screen of titles with nothing beneath them.
_tui_menu_group_rows() {
    local -n _rows="$1"
    local -n _seen="$2"
    local row group

    if [[ "$TUI_MENU_GROUP" == "none" ]]; then
        for row in ${_rows[@]+"${_rows[@]}"}; do
            TUI_MENU_VIEW+=("$row"); TUI_MENU_VHEAD+=("")
        done
        return 0
    fi

    # Gathered by group rather than emitted in sorted order: sorting inside a
    # group is the point, and emitting the sorted list straight out would
    # interleave the groups.
    for group in ${_seen[@]+"${_seen[@]}"}; do
        local any=0
        for row in ${_rows[@]+"${_rows[@]}"}; do
            [[ "$(_tui_menu_group_of "$row")" == "$group" ]] || continue
            if (( any == 0 )) && [[ -n "$group" ]]; then
                TUI_MENU_VIEW+=(-1); TUI_MENU_VHEAD+=("$group")
                any=1
            fi
            TUI_MENU_VIEW+=("$row"); TUI_MENU_VHEAD+=("")
        done
    done
}

#[pub]
# Move to the next grouping, and to the next ordering. Both wrap.
# Usage: tui_menu_group_next
tui_menu_group_next() {
    case "$TUI_MENU_GROUP" in
        section) TUI_MENU_GROUP="kind" ;;
        kind)    TUI_MENU_GROUP="none" ;;
        *)       TUI_MENU_GROUP="section" ;;
    esac
}
#[pub]
# Usage: tui_menu_sort_next
tui_menu_sort_next() {
    case "$TUI_MENU_SORT" in
        declared) TUI_MENU_SORT="name" ;;
        name)     TUI_MENU_SORT="state" ;;
        *)        TUI_MENU_SORT="declared" ;;
    esac
}

# -----------------------------------------------------------------------------
# Arithmetic, kept pure so it can be tested
# -----------------------------------------------------------------------------

# Can the cursor rest here. Headings cannot, `off` entries can: a person is
# allowed to select one and be told why it will not run, which is more useful
# than a cursor that mysteriously jumps over it.
# Is this view row a heading, declared or invented by the grouping?
_tui_menu_is_heading() {
    local v="$1"
    [[ -n "${TUI_MENU_VHEAD[$v]:-}" ]] && return 0
    local raw="${TUI_MENU_VIEW[$v]:-}"
    [[ -n "$raw" ]] || return 0
    (( raw < 0 )) && return 0
    [[ "${TUI_MENU_STATE[$raw]:-heading}" == "heading" ]]
}

_tui_menu_landable() {
    ! _tui_menu_is_heading "$1"
}

#[pub]
# The row a view index refers to, or failure when it is a heading.
#
# The accessor exists because the view holds `-1` for a heading the grouping
# invented, and `${ARRAY[-1]}` in bash is the last element rather than an
# error. Anything reading the view through the index itself gets the wrong row
# silently, which is how two tests came to assert the wrong thing.
# Usage: tui_menu_raw <view-index> -> prints the row index
tui_menu_raw() {
    _tui_menu_is_heading "$1" && return 1
    local raw="${TUI_MENU_VIEW[$1]:-}"
    [[ -n "$raw" ]] || return 1
    (( raw >= 0 )) || return 1
    printf '%d' "$raw"
}

#[pub]
# The heading a view index is, or failure when it is a row.
# Usage: tui_menu_heading_at <view-index> -> prints the label
tui_menu_heading_at() {
    _tui_menu_is_heading "$1" || return 1
    local label="${TUI_MENU_VHEAD[$1]:-}"
    if [[ -z "$label" ]]; then
        local raw="${TUI_MENU_VIEW[$1]:-}"
        [[ -n "$raw" ]] && (( raw >= 0 )) && label="${TUI_MENU_TEXT[$raw]:-}"
    fi
    printf '%s' "$label"
}

# How many rows are on screen. The view is the truth; the full list is only the
# fallback for a caller that never built one.
# How many rows the reader can see.
#
# The view, and only the view. Falling back to the raw count when the view was
# empty turned "nothing matches" into "everything", silently, which is the
# worst answer a filter can give.
_tui_menu_len() { printf '%d' "${#TUI_MENU_VIEW[@]}"; }

# The next index the cursor may rest on, moving by <step>, wrapping at the ends.
#
# Wrapping, because a list is a ring: down from the last row is the first, and
# up from the first is the last. Stopping dead at the ends means the way to the
# bottom of a long list is to hold a key down, and it makes the top and the
# bottom feel like walls rather than like the same place.
#
# A step larger than one is a page, and a page does not wrap: paging past the
# end lands on the end, which is what every list with a page key does.
_tui_menu_step() {
    local from="$1" step="$2" n i tries; n="$(_tui_menu_len)"
    (( n > 0 )) || { printf '%d' "$from"; return 0; }

    if (( step > 1 || step < -1 )); then
        i=$(( from + step ))
        (( i < 0 )) && i=0
        (( i >= n )) && i=$(( n - 1 ))
        # Onto something landable, searching towards where the page came from
        # so a page never lands on a heading.
        local back=$(( step > 0 ? -1 : 1 ))
        while (( i >= 0 && i < n )); do
            _tui_menu_landable "$i" && { printf '%d' "$i"; return 0; }
            i=$(( i + back ))
        done
        printf '%d' "$from"
        return 0
    fi

    # One step, wrapping. Bounded by the length so a list with nothing landable
    # in it ends rather than spinning.
    i="$from"
    for (( tries = 0; tries < n; tries++ )); do
        i=$(( (i + step + n) % n ))
        _tui_menu_landable "$i" && { printf '%d' "$i"; return 0; }
    done
    printf '%d' "$from"
}

# The top of a section, moving by <step>, wrapping.
#
# What a modifier with an arrow does: a long list is read by section, and
# stepping past twenty rows to reach the next heading is not reading.
#
# Down goes to the top of the next section. Up goes to the top of this one, and
# to the top of the previous one when the cursor is already there, which is
# what every editor's paragraph movement does and what a reader expects from a
# key that means "back a section".
_tui_menu_section_step() {
    local from="$1" step="$2" n; n="$(_tui_menu_len)"
    (( n > 0 )) || { printf '%d' "$from"; return 0; }

    if (( step > 0 )); then
        printf '%d' "$(_tui_menu_section_top "$(_tui_menu_next_heading "$from" 1)")"
        return 0
    fi

    local here; here="$(_tui_menu_section_top "$from")"
    if [[ "$here" != "$from" ]]; then
        printf '%d' "$here"
        return 0
    fi
    # Already at the top, so the one before it: back past this section's own
    # heading, then back to the heading before that.
    local h; h="$(_tui_menu_next_heading "$from" -1)"
    printf '%d' "$(_tui_menu_section_top "$(_tui_menu_next_heading "$h" -1)")"
}

# The nearest heading from <from>, moving by <step>, wrapping. <from> itself is
# never the answer.
_tui_menu_next_heading() {
    local from="$1" step="$2" n i tries raw; n="$(_tui_menu_len)"
    i="$from"
    for (( tries = 0; tries < n; tries++ )); do
        i=$(( (i + step + n) % n ))
        _tui_menu_is_heading "$i" && { printf '%d' "$i"; return 0; }
    done
    printf '%d' "$from"
}

# The first row of the section <from> is in. Given a heading, that heading's
# first row; given a row, the first row under the heading above it.
#
# Not "the first landable at or after <from>", which is <from> itself for any
# row and makes "back to the top of this section" a move that never happens.
_tui_menu_section_top() {
    local from="$1" n i tries raw; n="$(_tui_menu_len)"
    (( n > 0 )) || { printf '%d' "$from"; return 0; }

    # Back to the heading at or above it. A list with no headings at all has no
    # sections, so the top of the only one is the first landable row.
    i="$from"
    local head=-1
    for (( tries = 0; tries < n; tries++ )); do
        _tui_menu_is_heading "$i" && { head="$i"; break; }
        (( i == 0 )) && break
        i=$(( i - 1 ))
    done
    (( head < 0 )) && { printf '%d' "$(_tui_menu_first)"; return 0; }

    i="$head"
    for (( tries = 0; tries < n; tries++ )); do
        i=$(( (i + 1) % n ))
        _tui_menu_landable "$i" && { printf '%d' "$i"; return 0; }
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
