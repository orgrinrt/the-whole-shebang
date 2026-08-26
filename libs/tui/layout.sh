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
#   use shebang::tui/term
#   use shebang::tui/layout
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
declare -ga TUI_LAYOUT_START=()     # solved, 1-based
declare -g  TUI_LAYOUT_AXIS="rows"
declare -gi TUI_LAYOUT_TOTAL=0

#[pub]
# Start a layout along `rows` or `cols`, over a total. The total defaults to
# the terminal's own size on that axis.
# Usage: tui_layout_reset rows [total]
tui_layout_reset() {
    TUI_LAYOUT_NAME=(); TUI_LAYOUT_WANT=(); TUI_LAYOUT_MIN=()
    TUI_LAYOUT_PRIO=(); TUI_LAYOUT_SIZE=(); TUI_LAYOUT_START=()
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
# Usage: tui_layout_add <name> <want> [min:N] [--priority N]
tui_layout_add() {
    local name="$1" want="${2:-1fr}" min=0 prio=0
    shift 2 2>/dev/null || shift $#
    while (( $# )); do
        case "$1" in
            min:*)       min="${1#min:}"; shift ;;
            --priority)  prio="${2:-0}"; shift 2 ;;
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

# The floor a region will not go below: its min, or its fixed size.
_tui_layout_floor() {
    local i="$1" f
    f="$(_tui_layout_fixed "${TUI_LAYOUT_WANT[$i]}")"
    if (( TUI_LAYOUT_MIN[i] > 0 )); then printf '%d' "${TUI_LAYOUT_MIN[$i]}"
    else printf '%d' "$f"; fi
}

#[pub]
# Work out where everything goes. Regions that did not fit get size 0, and
# tui_layout_has says so.
# Usage: tui_layout_solve
tui_layout_solve() {
    local n="${#TUI_LAYOUT_NAME[@]}" i
    (( n > 0 )) || return 0

    local -a keep=()
    for (( i = 0; i < n; i++ )); do keep+=(1); done

    # Drop the least important until the floors fit. Whole regions, because a
    # region squeezed under its floor is one that costs space and does not do
    # its job.
    while :; do
        local need=0
        for (( i = 0; i < n; i++ )); do
            (( keep[i] == 1 )) || continue
            need=$(( need + $(_tui_layout_floor "$i") ))
        done
        (( need <= TUI_LAYOUT_TOTAL )) && break

        local worst=-1 worst_prio=0
        for (( i = 0; i < n; i++ )); do
            (( keep[i] == 1 )) || continue
            (( TUI_LAYOUT_PRIO[i] == 0 )) && continue
            if (( TUI_LAYOUT_PRIO[i] > worst_prio )); then
                worst_prio="${TUI_LAYOUT_PRIO[$i]}"; worst="$i"
            fi
        done
        # Nothing left that may be dropped. The rest keep their floors and
        # overflow, which the caller can see by comparing the sizes to the
        # total; pretending otherwise would just hide it.
        (( worst < 0 )) && break
        keep[worst]=0
    done

    # Fixed sizes first, then the shares divide what is left.
    local fixed=0 shares=0
    for (( i = 0; i < n; i++ )); do
        if (( keep[i] == 0 )); then TUI_LAYOUT_SIZE[i]=0; continue; fi
        local f s
        f="$(_tui_layout_fixed "${TUI_LAYOUT_WANT[$i]}")"
        s="$(_tui_layout_share "${TUI_LAYOUT_WANT[$i]}")"
        if (( s > 0 )); then shares=$(( shares + s )); TUI_LAYOUT_SIZE[i]=0
        else
            (( f < TUI_LAYOUT_MIN[i] )) && f="${TUI_LAYOUT_MIN[$i]}"
            TUI_LAYOUT_SIZE[i]="$f"; fixed=$(( fixed + f ))
        fi
    done

    local left=$(( TUI_LAYOUT_TOTAL - fixed ))
    (( left < 0 )) && left=0
    if (( shares > 0 )); then
        local per=$(( left / shares )) extra=$(( left % shares ))
        for (( i = 0; i < n; i++ )); do
            (( keep[i] == 1 )) || continue
            local s; s="$(_tui_layout_share "${TUI_LAYOUT_WANT[$i]}")"
            (( s > 0 )) || continue
            local got=$(( per * s ))
            # The remainder goes to the first share rather than vanishing, so
            # the regions add up to the total exactly.
            if (( extra > 0 )); then got=$(( got + extra )); extra=0; fi
            (( got < TUI_LAYOUT_MIN[i] )) && got="${TUI_LAYOUT_MIN[$i]}"
            TUI_LAYOUT_SIZE[i]="$got"
        done
    fi

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
