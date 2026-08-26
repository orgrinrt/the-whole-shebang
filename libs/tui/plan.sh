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
    TUI_PLAN_SHAPES+=("$*")
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
_plan_shapes_by_area() {
    local shape w h
    for shape in $1; do
        w="${shape%%x*}"; h="${shape##*x}"
        [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || continue
        printf '%d %s\n' $(( w * h )) "$shape"
    done | sort -rn | awk '{print $2}'
}

# Free space, as a set of overlapping maximal rectangles.
#
# One rectangle cannot describe what is left after taking a bite out of
# another: the remainder is an L, and keeping one arm of it throws the other
# away. Keeping both arms as separate rectangles is better and still loses,
# because a panel can only use the arm it was offered.
#
# So the free space is every maximal rectangle that fits in it, which overlap
# each other on purpose. Placing something splits every free rectangle it
# touches into the pieces to its left, right, above and below, and any
# rectangle wholly inside another is then dropped as saying nothing new.
_plan_split_all() {
    local pr="$1" pc="$2" pw="$3" ph="$4"
    local pr2=$(( pr + ph )) pc2=$(( pc + pw ))
    local -a out=()
    local rect fr fc fw fh

    for rect in ${_PLAN_FREE[@]+"${_PLAN_FREE[@]}"}; do
        read -r fr fc fw fh <<< "$rect"
        (( fw > 0 && fh > 0 )) || continue
        local fr2=$(( fr + fh )) fc2=$(( fc + fw ))

        # No overlap: kept whole.
        if (( pc >= fc2 || pc2 <= fc || pr >= fr2 || pr2 <= fr )); then
            out+=("$rect"); continue
        fi

        # Left of it.
        (( pc > fc ))   && out+=("$fr $fc $(( pc - fc )) $fh")
        # Right of it.
        (( pc2 < fc2 )) && out+=("$fr $pc2 $(( fc2 - pc2 )) $fh")
        # Above it.
        (( pr > fr ))   && out+=("$fr $fc $fw $(( pr - fr ))")
        # Below it.
        (( pr2 < fr2 )) && out+=("$pr2 $fc $fw $(( fr2 - pr2 ))")
    done

    # Anything wholly inside another rectangle says nothing the other does not,
    # and left in, the list grows without bound as panels are placed.
    _PLAN_FREE=()
    local i j n="${#out[@]}" keep
    for (( i = 0; i < n; i++ )); do
        read -r fr fc fw fh <<< "${out[$i]}"
        (( fw > 0 && fh > 0 )) || continue
        keep=1
        for (( j = 0; j < n; j++ )); do
            (( i == j )) && continue
            local gr gc gw gh
            read -r gr gc gw gh <<< "${out[$j]}"
            (( gw > 0 && gh > 0 )) || continue
            if (( fr >= gr && fc >= gc && fr + fh <= gr + gh && fc + fw <= gc + gw )); then
                # Identical rectangles would each contain the other, so the
                # earlier one wins and the later is dropped.
                if (( fr == gr && fc == gc && fw == gw && fh == gh )); then
                    (( j < i )) && { keep=0; break; }
                else
                    keep=0; break
                fi
            fi
        done
        (( keep == 1 )) && _PLAN_FREE+=("${out[$i]}")
    done
}

# Place the panels from _PLAN_ORDER[at] onwards. Returns 0 when every one of
# them found a home.
_plan_place() {
    local at="$1"
    (( at >= ${#_PLAN_ORDER[@]} )) && return 0

    local idx="${_PLAN_ORDER[$at]}"
    local shape sw sh j
    local -a saved

    while IFS= read -r shape; do
        [[ -n "$shape" ]] || continue
        sw="${shape%%x*}"; sh="${shape##*x}"
        for (( j = 0; j < ${#_PLAN_FREE[@]}; j++ )); do
            local fr fc fw fh
            read -r fr fc fw fh <<< "${_PLAN_FREE[$j]}"
            (( fw >= sw && fh >= sh )) || continue

            saved=("${_PLAN_FREE[@]}")
            TUI_PLAN_R[idx]="$fr"; TUI_PLAN_C[idx]="$fc"
            TUI_PLAN_W[idx]="$sw"; TUI_PLAN_H[idx]="$sh"
            _plan_split_all "$fr" "$fc" "$sw" "$sh"

            if _plan_place $(( at + 1 )); then return 0; fi

            # That choice led nowhere. Put the space back and try a smaller
            # shape, or another rectangle.
            _PLAN_FREE=("${saved[@]}")
            TUI_PLAN_R[idx]=0; TUI_PLAN_C[idx]=0
            TUI_PLAN_W[idx]=0; TUI_PLAN_H[idx]=0
        done
    done < <(_plan_shapes_by_area "${TUI_PLAN_SHAPES[$idx]}")

    return 1
}

declare -ga _PLAN_FREE=()
declare -ga _PLAN_ORDER=()

#[pub]
# Work out the arrangement. Every panel that can be placed is placed; the ones
# that cannot are dropped, least important first, and the answer is the
# arrangement that drops the fewest.
# Usage: tui_plan_solve
tui_plan_solve() {
    local n="${#TUI_PLAN_NAME[@]}" i
    (( n > 0 )) || { TUI_PLAN_DROPPED=0; return 0; }

    local main_w="$TUI_PLAN_MAIN_W" main_h="$TUI_PLAN_MAIN_H"
    (( main_w < 1 )) && main_w=1
    (( main_h < 1 )) && main_h=1
    (( main_w > TUI_PLAN_COLS )) && main_w="$TUI_PLAN_COLS"
    (( main_h > TUI_PLAN_ROWS )) && main_h="$TUI_PLAN_ROWS"

    # None dropped first, then one, then two. The first arrangement that works
    # is the one that drops the fewest, which is the answer asked for.
    local allowed
    for (( allowed = 0; allowed <= n; allowed++ )); do
        local -a keep=()
        for (( i = 0; i < n; i++ )); do keep+=(1); done

        # Drop the least important `allowed` of them, highest priority number
        # first, never one marked 0.
        local dropped=0 idx
        while (( dropped < allowed )); do
            local worst=-1 worst_prio=0
            for (( i = 0; i < n; i++ )); do
                (( keep[i] == 1 )) || continue
                (( TUI_PLAN_PRIO[i] == 0 )) && continue
                if (( TUI_PLAN_PRIO[i] > worst_prio )); then
                    worst_prio="${TUI_PLAN_PRIO[$i]}"; worst="$i"
                fi
            done
            (( worst < 0 )) && break
            keep[worst]=0; dropped=$(( dropped + 1 ))
        done
        # Asked to drop more than there is anything droppable left to drop.
        (( dropped < allowed )) && break

        if _plan_attempt "$main_w" "$main_h" ${keep[@]+"${keep[@]}"}; then
            TUI_PLAN_DROPPED="$dropped"
            return 0
        fi
    done

    # Nothing fits at all. Everything that may be dropped is, and what is left
    # is placed as far as it goes: the caller can see what happened by asking
    # which panels have room.
    TUI_PLAN_DROPPED="$n"
    for (( i = 0; i < n; i++ )); do
        TUI_PLAN_R[i]=0; TUI_PLAN_C[i]=0; TUI_PLAN_W[i]=0; TUI_PLAN_H[i]=0
    done
    return 1
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
