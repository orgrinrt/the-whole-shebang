#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/layout - Dividing the screen, and giving up gracefully
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Depends on tui/term for the size, and on nothing else. It draws nothing: it
# answers where each part goes, and the caller draws there. That separation is
# what makes the arithmetic testable at sizes no real terminal is, which is
# where a layout actually breaks.
#
# A screen is split into regions along one axis. Each region says how much it
# wants, what it cannot do without, and how important it is. When everything
# fits, everything is placed. When it does not, the least important regions are
# dropped whole rather than every region being squeezed until all of them are
# useless: half a sidebar is not half as good as a sidebar, it is worse than no
# sidebar, because it costs the space and does not do the job.
#
# Sizes:
#   12       exactly twelve rows or columns
#   2fr      a share of what is left after the fixed ones
#   min:8    never smaller than eight, and dropped rather than made smaller
#
# Usage:
#   use shebang::tui::term
#   use shebang::tui::layout
#
#   tui_layout_reset rows 40
#   tui_layout_add head  1
#   tui_layout_add body  1fr min:6
#   tui_layout_add note  3          --priority 2
#   tui_layout_add keys  1
#   tui_layout_solve
#   tui_layout_has note && tui_move "$(tui_layout_start note)" 1
# =============================================================================

[[ -n "${_SHEBANG_TUI_LAYOUT_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_LAYOUT_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

declare -ga TUI_LAYOUT_NAME=()
declare -ga TUI_LAYOUT_WANT=()      # a number, or a share like 2fr
declare -ga TUI_LAYOUT_MIN=()
declare -ga TUI_LAYOUT_PRIO=()      # 0 keeps it always; higher goes first
declare -ga TUI_LAYOUT_SIZE=()      # solved
declare -ga TUI_LAYOUT_FIXED=()     # the want's fixed size, or 0
declare -ga TUI_LAYOUT_SHARE=()     # the want's share count, or 0
declare -ga TUI_LAYOUT_START=()     # solved, 1-based
declare -g  TUI_LAYOUT_AXIS="rows"
declare -gi TUI_LAYOUT_TOTAL=0
declare -ga _TUI_LAYOUT_KEEP=()

#[pub]
# Start a layout along `rows` or `cols`, over a total. The total defaults to
# the terminal's own size on that axis.
# Usage: tui_layout_reset rows [total]
tui_layout_reset() {
    TUI_LAYOUT_NAME=(); TUI_LAYOUT_WANT=(); TUI_LAYOUT_MIN=()
    TUI_LAYOUT_PRIO=(); TUI_LAYOUT_SIZE=(); TUI_LAYOUT_START=()
    TUI_LAYOUT_FIXED=(); TUI_LAYOUT_SHARE=()
    TUI_LAYOUT_AXIS="${1:-rows}"

    local total="${2:-}"
    if [[ -z "$total" ]]; then
        if [[ "$TUI_LAYOUT_AXIS" == "cols" ]]; then total="${TUI_COLS:-80}"
        else total="${TUI_ROWS:-24}"; fi
    fi
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    TUI_LAYOUT_TOTAL="$total"
}

#[pub]
# Add a region. `want` is a count or a share (`2fr`). `min:N` sets the size
# below which it is dropped instead of shrunk. `--priority N` decides what goes
# first when there is not enough room; 0 is never dropped.
#
# Never dropped means never dropped, including when it does not fit: regions at
# priority 0 that together want more than the total keep their sizes and the
# sum runs past it. Whatever draws them has to clamp the line, which is what
# tui/table does. Asking for more than there is has to show up somewhere, and
# silently shrinking something the caller said is not optional is worse.
# Usage: tui_layout_add <name> <want> [min:N] [--priority N]
tui_layout_add() {
    local name="$1" want="${2:-1fr}" min=0 prio=0
    shift 2 2>/dev/null || shift $#
    while (( $# )); do
        case "$1" in
            min:*)       min="${1#min:}"; shift ;;
            # Guarded, because bash refuses `shift 2` when one argument is
            # left and does not shift at all, so `$#` never reaches zero
            # and a trailing option flag with its value forgotten spins
            # this loop forever.
            --priority)  prio="${2:-0}"; shift 2 2>/dev/null || shift $# ;;
            *)           shift ;;
        esac
    done
    [[ "$min" =~ ^[0-9]+$ ]]  || min=0
    [[ "$prio" =~ ^[0-9]+$ ]] || prio=0
    TUI_LAYOUT_NAME+=("$name")
    TUI_LAYOUT_WANT+=("$want")
    TUI_LAYOUT_MIN+=("$min")
    TUI_LAYOUT_PRIO+=("$prio")
    TUI_LAYOUT_SIZE+=(0)
    TUI_LAYOUT_START+=(0)
    # Read once, here, rather than on every pass of the solve. A want does not
    # change after it is declared, and asking through a command substitution
    # is a fork: the solve loops over the regions three times, so a table of
    # three columns paid a dozen of them per redraw and a redraw happens on
    # every keypress.
    TUI_LAYOUT_FIXED+=("$(_tui_layout_fixed "$want")")
    TUI_LAYOUT_SHARE+=("$(_tui_layout_share "$want")")
}

# The fixed part of a want, or 0 for a share.
_tui_layout_fixed() {
    local w="$1"
    [[ "$w" =~ ^[0-9]+$ ]] && { printf '%d' "$w"; return 0; }
    printf '0'
}

# The share count of a want, or 0 for a fixed size.
_tui_layout_share() {
    local w="$1"
    [[ "$w" =~ ^([0-9]+)fr$ ]] && { printf '%d' "${BASH_REMATCH[1]}"; return 0; }
    [[ "$w" == "fr" ]] && { printf '1'; return 0; }
    printf '0'
}

# The smallest this region can usefully be. A fixed region is its size; a share
# is its floor, or one column if it named none.
_tui_layout_floor() {
    local i="$1" f s
    f="${TUI_LAYOUT_FIXED[$i]:-0}"
    s="${TUI_LAYOUT_SHARE[$i]:-0}"
    if (( s > 0 )); then
        if (( TUI_LAYOUT_MIN[i] > 0 )); then printf '%d' "${TUI_LAYOUT_MIN[$i]}"
        else printf '1'; fi
    else
        (( f < TUI_LAYOUT_MIN[i] )) && f="${TUI_LAYOUT_MIN[$i]}"
        printf '%d' "$f"
    fi
}

# One attempt, over the regions still being kept. Returns 1 when they do not
# fit, which is the outer loop's cue to drop one and try again. Sizing and
# dropping have to be one decision: sized first and dropped after, a floor
# raised during sizing pushes the total past the screen with nothing left to
# give it back.
_tui_layout_attempt() {
    local n="${#TUI_LAYOUT_NAME[@]}" i
    local fixed=0 shares=0 f sh

    local -a pinned=()
    for (( i = 0; i < n; i++ )); do pinned+=(0); TUI_LAYOUT_SIZE[i]=0; done

    for (( i = 0; i < n; i++ )); do
        (( _TUI_LAYOUT_KEEP[i] == 1 )) || continue
        f="${TUI_LAYOUT_FIXED[$i]}"
        sh="${TUI_LAYOUT_SHARE[$i]}"
        if (( sh > 0 )); then
            shares=$(( shares + sh ))
        else
            (( f < TUI_LAYOUT_MIN[i] )) && f="${TUI_LAYOUT_MIN[$i]}"
            TUI_LAYOUT_SIZE[i]="$f"; fixed=$(( fixed + f )); pinned[i]=1
        fi
    done

    (( fixed > TUI_LAYOUT_TOTAL )) && return 1

    # A share that would land under its floor is pinned there and stops being a
    # share; what is left divides again among the rest.
    local guard=0 left per got raised
    while (( shares > 0 )); do
        left=$(( TUI_LAYOUT_TOTAL - fixed ))
        (( left < 0 )) && left=0
        per=$(( left / shares ))
        raised=0
        for (( i = 0; i < n; i++ )); do
            (( _TUI_LAYOUT_KEEP[i] == 1 && pinned[i] == 0 )) || continue
            sh="${TUI_LAYOUT_SHARE[$i]}"
            (( sh > 0 )) || continue
            got=$(( per * sh ))
            if (( got < TUI_LAYOUT_MIN[i] )); then
                TUI_LAYOUT_SIZE[i]="${TUI_LAYOUT_MIN[$i]}"
                fixed=$(( fixed + TUI_LAYOUT_MIN[i] ))
                shares=$(( shares - sh ))
                pinned[i]=1; raised=1
                break
            fi
        done
        (( raised == 0 )) && break
        (( fixed > TUI_LAYOUT_TOTAL )) && return 1
        guard=$(( guard + 1 ))
        (( guard > n + 1 )) && break
    done

    if (( shares > 0 )); then
        left=$(( TUI_LAYOUT_TOTAL - fixed ))
        (( left < 0 )) && left=0
        per=$(( left / shares ))
        local extra=$(( left % shares ))
        for (( i = 0; i < n; i++ )); do
            (( _TUI_LAYOUT_KEEP[i] == 1 && pinned[i] == 0 )) || continue
            sh="${TUI_LAYOUT_SHARE[$i]}"
            (( sh > 0 )) || continue
            got=$(( per * sh ))
            # The remainder goes to the first share rather than vanishing, so
            # the regions add up to the total exactly.
            if (( extra > 0 )); then got=$(( got + extra )); extra=0; fi
            TUI_LAYOUT_SIZE[i]="$got"
        done
    fi
    return 0
}

#[pub]
# Work out where everything goes. Regions that did not fit get size 0, and
# tui_layout_has says so.
# Usage: tui_layout_solve
tui_layout_solve() {
    local n="${#TUI_LAYOUT_NAME[@]}" i
    (( n > 0 )) || return 0

    _TUI_LAYOUT_KEEP=()
    for (( i = 0; i < n; i++ )); do _TUI_LAYOUT_KEEP+=(1); done

    while :; do
        _tui_layout_attempt && break

        # Did not fit. Drop the least important region that may be dropped and
        # try the whole thing again, because dropping one changes what every
        # share gets.
        local worst=-1 worst_prio=0
        for (( i = 0; i < n; i++ )); do
            (( _TUI_LAYOUT_KEEP[i] == 1 )) || continue
            (( TUI_LAYOUT_PRIO[i] == 0 )) && continue
            if (( TUI_LAYOUT_PRIO[i] > worst_prio )); then
                worst_prio="${TUI_LAYOUT_PRIO[$i]}"; worst="$i"
            fi
        done
        if (( worst < 0 )); then
            # Nothing left that may go. The rest keep their floors and overflow,
            # which the caller can see by adding the sizes up; pretending
            # otherwise would only hide it.
            for (( i = 0; i < n; i++ )); do
                (( _TUI_LAYOUT_KEEP[i] == 1 )) || continue
                (( TUI_LAYOUT_SIZE[i] > 0 )) && continue
                TUI_LAYOUT_SIZE[i]="$(_tui_layout_floor "$i")"
            done
            break
        fi
        _TUI_LAYOUT_KEEP[worst]=0
        TUI_LAYOUT_SIZE[worst]=0
    done

    local at=1
    for (( i = 0; i < n; i++ )); do
        if (( TUI_LAYOUT_SIZE[i] == 0 )); then TUI_LAYOUT_START[i]=0; continue; fi
        TUI_LAYOUT_START[i]="$at"
        at=$(( at + TUI_LAYOUT_SIZE[i] ))
    done
    return 0
}

# The index of a named region, or 1 if there is none.
_tui_layout_index() {
    local want="$1" i
    for (( i = 0; i < ${#TUI_LAYOUT_NAME[@]}; i++ )); do
        [[ "${TUI_LAYOUT_NAME[$i]}" == "$want" ]] && { printf '%d' "$i"; return 0; }
    done
    return 1
}

#[pub]
# Did this region get any room?
# Usage: tui_layout_has sidebar && ...
tui_layout_has() {
    local i; i="$(_tui_layout_index "$1")" || return 1
    (( TUI_LAYOUT_SIZE[i] > 0 ))
}

#[pub]
# Its size, or 0 when it was dropped.
# Usage: tui_layout_size body
tui_layout_size() {
    local i; i="$(_tui_layout_index "$1")" || { printf '0'; return 1; }
    printf '%d' "${TUI_LAYOUT_SIZE[$i]}"
}

#[pub]
# Its first row or column, 1-based, or 0 when it was dropped.
# Usage: tui_layout_start body
tui_layout_start() {
    local i; i="$(_tui_layout_index "$1")" || { printf '0'; return 1; }
    printf '%d' "${TUI_LAYOUT_START[$i]}"
}

#[pub]
# One past its last row or column, so a loop can stop at it.
# Usage: tui_layout_end body
tui_layout_end() {
    local i; i="$(_tui_layout_index "$1")" || { printf '0'; return 1; }
    (( TUI_LAYOUT_SIZE[i] == 0 )) && { printf '0'; return 1; }
    printf '%d' $(( TUI_LAYOUT_START[i] + TUI_LAYOUT_SIZE[i] ))
}
