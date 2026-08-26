#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/plan - Fitting panels around the thing you came for
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Depends on tui/term for the size, and draws nothing. It answers where each
# panel goes, and the caller draws there, which is what makes the arithmetic
# testable at sizes no real terminal is.
#
# tui/layout divides one axis. This places panels around a main region in two,
# and the difference is the whole point: a panel that will not fit beside the
# list is not therefore homeless. There is usually room underneath, and a panel
# that was a tall column beside the list can be two or three short columns
# below it, showing the same things.
#
# So a panel says what it needs and what shapes it can take, and the plan finds
# an arrangement. Dropping one is the last resort, not the first move: it
# happens only when no shape of it fits anywhere, and then the least important
# goes first. The search is for the arrangement that drops the fewest, tried
# with none dropped, then one, and so on.
#
# A shape is `WxH`, smallest first, and a panel may name several. `30x8` is a
# sidebar; `60x3` is the same content as a strip underneath. The plan prefers
# the largest shape that still lets everything else fit, rather than the
# largest that fits on its own, because a panel that takes the room three
# others needed has not earned it.
#
# Usage:
#   use shebang::tui::term
#   use shebang::tui::plan
#
#   tui_plan_reset 120 40
#   tui_plan_main 60 20                       # what the screen is for
#   tui_plan_panel facts   3  30x12 44x6      # priority 3, two shapes
#   tui_plan_panel help    9  24x8
#   tui_plan_solve
#   tui_plan_has facts && printf '%s %s %s %s\n' \
#       "$(tui_plan_row facts)" "$(tui_plan_col facts)" \
#       "$(tui_plan_w facts)"  "$(tui_plan_h facts)"
# =============================================================================

[[ -n "${_SHEBANG_TUI_PLAN_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_PLAN_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

declare -gi TUI_PLAN_COLS=80
declare -gi TUI_PLAN_ROWS=24
declare -gi TUI_PLAN_MAIN_W=0
declare -gi TUI_PLAN_MAIN_H=0

declare -ga TUI_PLAN_NAME=()
declare -ga TUI_PLAN_PRIO=()
declare -ga TUI_PLAN_SHAPES=()     # "WxH WxH", smallest first

# Solved, parallel to NAME. 0 wide means it was not placed.
declare -ga TUI_PLAN_R=()
declare -ga TUI_PLAN_C=()
declare -ga TUI_PLAN_W=()
declare -ga TUI_PLAN_H=()

declare -gi TUI_PLAN_DROPPED=0


#[pub]
# Start a plan for a screen of this size. Defaults to the terminal's.
# Usage: tui_plan_reset [cols] [rows]
tui_plan_reset() {
    local c="${1:-${TUI_COLS:-80}}" r="${2:-${TUI_ROWS:-24}}"
    [[ "$c" =~ ^[0-9]+$ ]] || c=80
    [[ "$r" =~ ^[0-9]+$ ]] || r=24
    TUI_PLAN_COLS="$c"; TUI_PLAN_ROWS="$r"
    TUI_PLAN_MAIN_W=0; TUI_PLAN_MAIN_H=0
    TUI_PLAN_NAME=(); TUI_PLAN_PRIO=(); TUI_PLAN_SHAPES=()
    TUI_PLAN_R=(); TUI_PLAN_C=(); TUI_PLAN_W=(); TUI_PLAN_H=()
    TUI_PLAN_DROPPED=0
}

#[pub]
# What the screen is for. It is never moved and never dropped; everything else
# is placed around it. Its width and height are the least it can work in, and
# it grows into whatever is left.
# Usage: tui_plan_main <min-cols> <min-rows>
tui_plan_main() {
    local w="${1:-1}" h="${2:-1}"
    [[ "$w" =~ ^[0-9]+$ ]] || w=1
    [[ "$h" =~ ^[0-9]+$ ]] || h=1
    TUI_PLAN_MAIN_W="$w"; TUI_PLAN_MAIN_H="$h"
}

#[pub]
# A panel, its importance, and the shapes it can take. Higher priority is
# dropped sooner; 0 is never dropped. Shapes are `WxH`, and the plan prefers
# the largest that still lets everything else fit.
# Usage: tui_plan_panel <name> <priority> <WxH> [WxH...]
tui_plan_panel() {
    local name="$1" prio="${2:-1}"; shift 2 2>/dev/null || shift $#
    [[ "$prio" =~ ^[0-9]+$ ]] || prio=1
    TUI_PLAN_NAME+=("$name")
    TUI_PLAN_PRIO+=("$prio")
    # Sorted here, once, rather than in the search where the same list was
    # re-sorted through a pipe at every node it was reached from.
    TUI_PLAN_SHAPES+=("$(_plan_sort_shapes "$@")")
    TUI_PLAN_R+=(0); TUI_PLAN_C+=(0); TUI_PLAN_W+=(0); TUI_PLAN_H+=(0)
}

_plan_shape_w() { printf '%s' "${1%%x*}"; }
_plan_shape_h() { printf '%s' "${1##*x}"; }

# The free rectangles, as "row col w h". Two of them: the strip to the right of
# the main region, and the strip below it. That is the whole geometry, and it
# is enough: a panel is either beside what you came for or under it.
_plan_free() {
    local main_w="$1" main_h="$2"
    local right_w=$(( TUI_PLAN_COLS - main_w ))
    local below_h=$(( TUI_PLAN_ROWS - main_h ))
    (( right_w > 0 )) && printf '1 %d %d %d\n' $(( main_w + 1 )) "$right_w" "$main_h"
    (( below_h > 0 )) && printf '%d 1 %d %d\n' $(( main_h + 1 )) "$TUI_PLAN_COLS" "$below_h"
}

# Place every kept panel, in priority order, into the free rectangles.
#
# It backtracks. Taking the biggest shape that fits and moving on is the
# obvious way and it is wrong: a panel that takes the whole strip because it
# could starves the one after it, and a smaller shape for the first would have
# left room for both. So a shape that leads to a dead end is undone and the
# next one down is tried.
#
# The search is bounded by the shapes a panel declares, which is a handful, and
# by the panels on a screen, which is a handful. Six panels with three shapes
# each is a few hundred arrangements; the shell can afford that once per
# resize.
_plan_attempt() {
    local main_w="$1" main_h="$2"; shift 2
    local -a keep=("$@")
    local n="${#TUI_PLAN_NAME[@]}" i

    _PLAN_FREE=()
    while read -r r c w h; do
        [[ -n "$r" ]] || continue
        _PLAN_FREE+=("$r $c $w $h")
    done < <(_plan_free "$main_w" "$main_h")

    for (( i = 0; i < n; i++ )); do
        TUI_PLAN_R[i]=0; TUI_PLAN_C[i]=0; TUI_PLAN_W[i]=0; TUI_PLAN_H[i]=0
    done

    # Priority order: 0 first, since those cannot be dropped and should get the
    # good space, then ascending.
    _PLAN_ORDER=()
    while read -r i; do _PLAN_ORDER+=("$i"); done < <(
        for (( i = 0; i < n; i++ )); do
            (( keep[i] == 1 )) || continue
            printf '%d %d\n' "${TUI_PLAN_PRIO[$i]}" "$i"
        done | sort -n -k1,1 -k2,2 | awk '{print $2}'
    )

    _plan_place 0
}

# The shapes a panel can take, largest area first. Declared order is the
# author's, not a preference: "the largest that fits" is about the space it
# covers, so that is what it is sorted by.
#
# In the shell, because it runs once per panel and a handful of shapes does not
# need sort(1). It used to run inside the search, through a pipe, at every node
# a panel was reached from.
_plan_sort_shapes() {
    local -a shapes=() areas=()
    local shape w h i j n=0
    for shape in "$@"; do
        w="${shape%%x*}"; h="${shape##*x}"
        [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || continue
        shapes+=("$shape"); areas+=($(( w * h ))); n=$(( n + 1 ))
    done
    # Insertion sort, descending by area. n is single digits.
    for (( i = 1; i < n; i++ )); do
        local a="${areas[$i]}" sh="${shapes[$i]}"
        j=$(( i - 1 ))
        while (( j >= 0 )) && (( areas[j] < a )); do
            areas[j+1]="${areas[$j]}"; shapes[j+1]="${shapes[$j]}"
            j=$(( j - 1 ))
        done
        areas[j+1]="$a"; shapes[j+1]="$sh"
    done
    printf '%s' "${shapes[*]}"
}

# Lines, filled in order, wrapping when the next panel does not fit.
#
# This used to be a backtracking search over every shape at every free
# rectangle, which is bin packing, which is NP-hard: ten panels on a screen
# where they did not all fit took two and a half minutes, and a menu redraws on
# every keypress.
#
# Neither of the layout engines worth copying does that. ratatui solves
# constraints with Cassowary, through its kasuari crate; taffy's own
# documentation calls it "a direct recursive tree computation" for flexbox and
# grid. Both are deterministic passes and neither searches.
#
# Flex lines are the model that fits what a panel is here: fill along a line,
# and when the next one does not fit, start a new one under it. A panel that
# cannot sit beside the list ends up under it, and several of them end up as
# columns side by side, which is the behaviour that was wanted. One decision
# per panel, in order, and nothing is ever undone.

# Fill one area with as many of the given panels as fit, in order, wrapping.
# Places what it can and leaves the rest in _PLAN_LEFT.
#
# Not printed: a caller reading printed leftovers has to run this in a process
# substitution, which is a subshell, and every placement it made there is
# discarded. The placements are the point of calling it.
declare -ga _PLAN_LEFT=()

_plan_fill() {
    local top="$1" left="$2" width="$3" height="$4"; shift 4
    local -a want=("$@")
    local -a left_over=()

    local line_top="$top" line_h=0 x="$left"
    local idx shape sw sh placed

    for idx in ${want[@]+"${want[@]}"}; do
        placed=0
        while IFS= read -r shape; do
            [[ -n "$shape" ]] || continue
            sw="${shape%%x*}"; sh="${shape##*x}"
            (( sw > width )) && continue

            # Wrap when this line has no room left for it.
            if (( x + sw - left > width )); then
                local next_top=$(( line_top + line_h ))
                if (( next_top + sh - top > height )); then continue; fi
                line_top="$next_top"; x="$left"; line_h=0
            fi
            (( line_top + sh - top > height )) && continue

            TUI_PLAN_R[idx]="$line_top"; TUI_PLAN_C[idx]="$x"
            TUI_PLAN_W[idx]="$sw";       TUI_PLAN_H[idx]="$sh"
            x=$(( x + sw ))
            (( sh > line_h )) && line_h="$sh"
            placed=1
            break
        done < <(printf '%s\n' ${TUI_PLAN_SHAPES[$idx]})
        (( placed == 0 )) && left_over+=("$idx")
    done

    _PLAN_LEFT=(${left_over[@]+"${left_over[@]}"})
}

#[pub]
# Work out the arrangement: fill the space beside the main region, then the
# space under it with whatever is left. A panel that fits in neither is
# dropped, and since the pass runs in priority order the ones dropped are the
# ones that said they mattered least. TUI_PLAN_DROPPED says how many.
# Usage: tui_plan_solve
tui_plan_solve() {
    local n="${#TUI_PLAN_NAME[@]}" i
    TUI_PLAN_DROPPED=0
    (( n > 0 )) || return 0

    local main_w="$TUI_PLAN_MAIN_W" main_h="$TUI_PLAN_MAIN_H"
    (( main_w < 1 )) && main_w=1
    (( main_h < 1 )) && main_h=1
    (( main_w > TUI_PLAN_COLS )) && main_w="$TUI_PLAN_COLS"
    (( main_h > TUI_PLAN_ROWS )) && main_h="$TUI_PLAN_ROWS"

    for (( i = 0; i < n; i++ )); do
        TUI_PLAN_R[i]=0; TUI_PLAN_C[i]=0; TUI_PLAN_W[i]=0; TUI_PLAN_H[i]=0
    done

    # Priority order: 0 first, since those cannot be dropped and should have
    # the good space, then ascending.
    local -a order=()
    while read -r i; do [[ -n "$i" ]] && order+=("$i"); done < <(
        for (( i = 0; i < n; i++ )); do
            printf '%d %d\n' "${TUI_PLAN_PRIO[$i]}" "$i"
        done | sort -n -k1,1 -k2,2 | awk '{print $2}'
    )

    # Beside first: a panel belongs next to the thing it is about, when there
    # is room for it there.
    local -a rest=()
    local right_w=$(( TUI_PLAN_COLS - main_w ))
    if (( right_w > 0 )); then
        _plan_fill 1 $(( main_w + 1 )) "$right_w" "$main_h" ${order[@]+"${order[@]}"}
        rest=(${_PLAN_LEFT[@]+"${_PLAN_LEFT[@]}"})
    else
        rest=(${order[@]+"${order[@]}"})
    fi

    # Then underneath, which is the full width, so a tall column becomes a row
    # of short ones.
    local -a dropped=()
    local below_h=$(( TUI_PLAN_ROWS - main_h ))
    if (( below_h > 0 )) && (( ${#rest[@]} > 0 )); then
        _plan_fill $(( main_h + 1 )) 1 "$TUI_PLAN_COLS" "$below_h" ${rest[@]+"${rest[@]}"}
        dropped=(${_PLAN_LEFT[@]+"${_PLAN_LEFT[@]}"})
    else
        dropped=(${rest[@]+"${rest[@]}"})
    fi

    TUI_PLAN_DROPPED="${#dropped[@]}"
    # Always 0. How it went is in TUI_PLAN_DROPPED and in tui_plan_has, and a
    # solve that returns non-zero because a panel was dropped takes a caller
    # running under `set -e` with it: dropping a panel is an ordinary outcome,
    # not a failure to lay out.
    return 0
}

_plan_index() {
    local want="$1" i
    for (( i = 0; i < ${#TUI_PLAN_NAME[@]}; i++ )); do
        [[ "${TUI_PLAN_NAME[$i]}" == "$want" ]] && { printf '%d' "$i"; return 0; }
    done
    return 1
}

#[pub]
# Did this panel get room?
# Usage: tui_plan_has facts && ...
tui_plan_has() {
    local i; i="$(_plan_index "$1")" || return 1
    (( TUI_PLAN_W[i] > 0 && TUI_PLAN_H[i] > 0 ))
}

#[pub]
# Where it goes, and how big it is. 0 when it was dropped.
# Usage: tui_plan_row <name> / tui_plan_col / tui_plan_w / tui_plan_h
tui_plan_row() { local i; i="$(_plan_index "$1")" || { printf '0'; return 1; }; printf '%d' "${TUI_PLAN_R[$i]}"; }
tui_plan_col() { local i; i="$(_plan_index "$1")" || { printf '0'; return 1; }; printf '%d' "${TUI_PLAN_C[$i]}"; }
tui_plan_w()   { local i; i="$(_plan_index "$1")" || { printf '0'; return 1; }; printf '%d' "${TUI_PLAN_W[$i]}"; }
tui_plan_h()   { local i; i="$(_plan_index "$1")" || { printf '0'; return 1; }; printf '%d' "${TUI_PLAN_H[$i]}"; }

#[pub]
# Which shape a panel ended up in, as `WxH`, or nothing when it was dropped.
# For a caller that draws differently depending on the shape it got.
# Usage: tui_plan_shape facts -> 30x12
tui_plan_shape() {
    local i; i="$(_plan_index "$1")" || return 1
    (( TUI_PLAN_W[i] > 0 )) || return 1
    printf '%dx%d' "${TUI_PLAN_W[$i]}" "${TUI_PLAN_H[$i]}"
}

#[pub]
# Is this panel beside what you came for, or underneath it? A caller lays a
# column out differently from a strip, which is the reason for the shapes.
# Usage: tui_plan_where facts -> beside | below | nowhere
tui_plan_where() {
    local i; i="$(_plan_index "$1")" || { printf 'nowhere'; return 1; }
    (( TUI_PLAN_W[i] > 0 )) || { printf 'nowhere'; return 1; }
    local main_h="$TUI_PLAN_MAIN_H"
    (( main_h < 1 )) && main_h=1
    if (( TUI_PLAN_R[i] <= main_h )); then printf 'beside'; else printf 'below'; fi
}
