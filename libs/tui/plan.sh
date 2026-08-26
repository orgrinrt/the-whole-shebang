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
# So a panel says what it needs and what shapes it can take, and the plan fills
# lines with them in priority order, wrapping to a new line when the next one
# does not fit. A panel is dropped when no shape of it fits anywhere, and since
# the pass runs in priority order the ones dropped are the ones that said they
# mattered least.
#
# A shape is `WxH`, and a panel may name several. `30x8` is a sidebar; `60x3`
# is the same content as a strip underneath. Each shape is scored by how many
# of the panels after it still fit if it is taken, so a panel that would take
# the room three others needed loses to a smaller shape of itself. That is one
# step of lookahead, not a search: nothing is undone.
#
# It does not promise the arrangement that drops the fewest, and it cannot.
# Finding that is bin packing. What it promises is that the same inputs give
# the same arrangement, that a placed panel is always at a size it declared,
# and that nothing overlaps or leaves the screen. Widening a terminal can still
# reshuffle: `tools/plan-resize-report` measures how often, so a change to the
# model can be compared against the one before it.
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
# What the screen is for. It sits at the top left, is never moved and never
# dropped, and everything else is placed around it. The size given is the size
# it gets, clamped to the screen: it does not grow into space nobody claimed,
# because the panels are placed against it and it cannot be both the thing they
# are measured from and a thing that moves afterwards.
#
# `tui_plan_main_w` and `tui_plan_main_h` give the clamped values back, which
# is what a caller needs to draw it.
# Usage: tui_plan_main <min-cols> <min-rows>
tui_plan_main() {
    local w="${1:-1}" h="${2:-1}"
    [[ "$w" =~ ^[0-9]+$ ]] || w=1
    [[ "$h" =~ ^[0-9]+$ ]] || h=1
    TUI_PLAN_MAIN_W="$w"; TUI_PLAN_MAIN_H="$h"
}

#[pub]
# How wide the main region ended up, clamped to the screen.
# Usage: tui_plan_main_w -> a number
tui_plan_main_w() {
    local w="$TUI_PLAN_MAIN_W"
    (( w < 1 )) && w=1
    (( w > TUI_PLAN_COLS )) && w="$TUI_PLAN_COLS"
    printf '%d' "$w"
}

#[pub]
# How tall the main region ended up, clamped to the screen.
# Usage: tui_plan_main_h -> a number
tui_plan_main_h() {
    local h="$TUI_PLAN_MAIN_H"
    (( h < 1 )) && h=1
    (( h > TUI_PLAN_ROWS )) && h="$TUI_PLAN_ROWS"
    printf '%d' "$h"
}

#[pub]
# A panel, its importance, and the shapes it can take. Higher priority is
# dropped sooner. Shapes are `WxH`, and each is weighed by how many of the
# panels after it still fit if it is taken.
# Usage: tui_plan_panel <name> <priority> <WxH> [WxH...]
tui_plan_panel() {
    local name="$1" prio="${2:-1}"; shift 2 2>/dev/null || shift $#
    [[ "$prio" =~ ^[0-9]+$ ]] || prio=1
    TUI_PLAN_NAME+=("$name")
    TUI_PLAN_PRIO+=("$prio")
    # Sorted here, once, rather than in the search where the same list was
    # re-sorted through a pipe at every node it was reached from.
    _plan_sort_shapes "$@"
    TUI_PLAN_SHAPES+=("$_PLAN_SORTED")
    TUI_PLAN_R+=(0); TUI_PLAN_C+=(0); TUI_PLAN_W+=(0); TUI_PLAN_H+=(0)
}

_plan_shape_w() { printf '%s' "${1%%x*}"; }
_plan_shape_h() { printf '%s' "${1##*x}"; }

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
        # The `x` has to be there. Without the test, `30` splits into `30` and
        # `30` and a typo for `30x8` becomes a 30x30 panel: a size nobody
        # declared, which is the one thing this promises never to place.
        [[ "$shape" == *x* ]] || continue
        w="${shape%%x*}"; h="${shape##*x}"
        [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || continue
        # A zero in either dimension is not a panel. `tui_plan_has` already
        # says no to one, while the drop count said it was placed, so the same
        # panel was both.
        (( w > 0 && h > 0 )) || continue
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
    # Joined under a stated IFS. `"${a[*]}"` uses whatever the caller's IFS
    # happens to be, and the split on the way back out used it too, so the two
    # cancelled by luck and stopped cancelling the moment a caller set IFS.
    #
    # Answered into a global rather than printed, because a command
    # substitution is a fork and this runs once per panel: ten panels was ten
    # forks per rebuild, in the file whose header is about having taken the
    # forks out of the redraw.
    local IFS=' '
    _PLAN_SORTED="${shapes[*]}"
}
declare -g _PLAN_SORTED=""

# The shapes a panel declared, as an array, split on spaces and nothing else.
_plan_shapes_of() {
    local IFS=' '
    # shellcheck disable=SC2206
    _PLAN_SHAPES_OUT=(${TUI_PLAN_SHAPES[$1]})
}
declare -ga _PLAN_SHAPES_OUT=()

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

# Can this shape go, given where the line has got to? Answers into
# _PLAN_FIT_{TOP,X,LINEH}, and returns non-zero when it cannot.
#
# Split out because the lookahead has to ask the same question about a state it
# is only imagining, and two copies of wrap arithmetic is two chances to get
# the boundary wrong.
_plan_fit() {
    local top="$1" left="$2" width="$3" height="$4"
    local line_top="$5" line_h="$6" x="$7" sw="$8" sh="$9"

    (( sw > width )) && return 1
    if (( x + sw - left > width )); then
        local next_top=$(( line_top + line_h ))
        (( next_top + sh - top > height )) && return 1
        line_top="$next_top"; x="$left"; line_h=0
    fi
    (( line_top + sh - top > height )) && return 1

    _PLAN_FIT_TOP="$line_top"
    _PLAN_FIT_X="$x"
    _PLAN_FIT_LINEH=$(( sh > line_h ? sh : line_h ))
    _PLAN_FIT_NEXTX=$(( x + sw ))
    return 0
}
declare -gi _PLAN_FIT_TOP=0 _PLAN_FIT_X=0 _PLAN_FIT_LINEH=0 _PLAN_FIT_NEXTX=0

# How many of these panels a greedy pass would place from here. Places nothing:
# this is the lookahead asking what a choice costs the ones after it. Answers
# into _PLAN_WOULD.
_plan_would_place() {
    local top="$1" left="$2" width="$3" height="$4"
    local line_top="$5" line_h="$6" x="$7"; shift 7
    local -a rest=("$@")
    local count=0 idx shape

    for idx in ${rest[@]+"${rest[@]}"}; do
        _plan_shapes_of "$idx"
        for shape in ${_PLAN_SHAPES_OUT[@]+"${_PLAN_SHAPES_OUT[@]}"}; do
            if _plan_fit "$top" "$left" "$width" "$height" \
                         "$line_top" "$line_h" "$x" "${shape%%x*}" "${shape##*x}"; then
                line_top="$_PLAN_FIT_TOP"; line_h="$_PLAN_FIT_LINEH"; x="$_PLAN_FIT_NEXTX"
                count=$(( count + 1 ))
                break
            fi
        done
    done

    _PLAN_WOULD="$count"
}
declare -gi _PLAN_WOULD=0

# One pass, in order, with one step of lookahead per panel.
#
# Greedy alone took the largest shape that fit and moved on, which is the thing
# the header says it does not do: a panel that swallows the line starves the
# ones after it, and widening the terminal by a single column could make a
# larger shape legal and delete a panel that had been showing. Twenty
# regressions in three and a half thousand samples, visible as a panel blinking
# in and out while the window is dragged.
#
# So each shape is scored by how many of the panels after it still fit, and the
# best score wins, larger area breaking the tie. Nothing is undone and nothing
# is revisited: it is one extra trial pass per shape, bounded by the shapes a
# panel declares times the panels on a screen, both of which are handfuls.
_plan_fill() {
    local top="$1" left="$2" width="$3" height="$4"; shift 4
    local -a want=("$@")
    local -a left_over=()

    local line_top="$top" line_h=0 x="$left"
    local i idx shape score
    local best_shape best_score best_top best_x best_lineh best_nextx

    for (( i = 0; i < ${#want[@]}; i++ )); do
        idx="${want[$i]}"
        best_shape=""; best_score=-1

        _plan_shapes_of "$idx"
        for shape in ${_PLAN_SHAPES_OUT[@]+"${_PLAN_SHAPES_OUT[@]}"}; do
            _plan_fit "$top" "$left" "$width" "$height" \
                      "$line_top" "$line_h" "$x" "${shape%%x*}" "${shape##*x}" || continue

            local ftop="$_PLAN_FIT_TOP" fx="$_PLAN_FIT_X"
            local flh="$_PLAN_FIT_LINEH" fnx="$_PLAN_FIT_NEXTX"
            _plan_would_place "$top" "$left" "$width" "$height" \
                              "$ftop" "$flh" "$fnx" ${want[@]:i+1}
            score="$_PLAN_WOULD"
            _PLAN_FIT_TOP="$ftop"; _PLAN_FIT_X="$fx"
            _PLAN_FIT_LINEH="$flh"; _PLAN_FIT_NEXTX="$fnx"

            # Shapes arrive largest first, so `>` keeps the largest of the
            # shapes that tie, which is the preference the declared order is
            # sorted into.
            if (( score > best_score )); then
                best_score="$score"; best_shape="$shape"
                best_top="$_PLAN_FIT_TOP"; best_x="$_PLAN_FIT_X"
                best_lineh="$_PLAN_FIT_LINEH"; best_nextx="$_PLAN_FIT_NEXTX"
            fi
        done

        if [[ -z "$best_shape" ]]; then
            left_over+=("$idx")
            continue
        fi

        TUI_PLAN_R[idx]="$best_top";           TUI_PLAN_C[idx]="$best_x"
        TUI_PLAN_W[idx]="${best_shape%%x*}";   TUI_PLAN_H[idx]="${best_shape##*x}"
        line_top="$best_top"; line_h="$best_lineh"; x="$best_nextx"
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

    # The same clamp the accessors report, so a caller drawing the main region
    # and the plan placing panels around it are working from one number.
    local main_w main_h
    main_w="$(tui_plan_main_w)"
    main_h="$(tui_plan_main_h)"

    for (( i = 0; i < n; i++ )); do
        TUI_PLAN_R[i]=0; TUI_PLAN_C[i]=0; TUI_PLAN_W[i]=0; TUI_PLAN_H[i]=0
    done

    # Priority order: 0 first, since those matter most and should have the
    # good space, then ascending, ties by declaration order.
    #
    # Sorted here rather than by sort(1). Two forks on every keypress was the
    # smaller reason; the larger one is that the ordering is what makes the
    # arrangement reproducible, and resting it on how one sort implementation
    # propagates `-n` to a second key makes the guarantee a property of the
    # host. A port to another language now has something to match.
    local -a order=()
    local j
    for (( i = 0; i < n; i++ )); do order+=("$i"); done
    for (( i = 1; i < n; i++ )); do
        local key="${order[$i]}" kp="${TUI_PLAN_PRIO[${order[$i]}]}"
        j=$(( i - 1 ))
        while (( j >= 0 )) && (( TUI_PLAN_PRIO[order[j]] > kp )); do
            order[j+1]="${order[$j]}"
            j=$(( j - 1 ))
        done
        order[j+1]="$key"
    done

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
