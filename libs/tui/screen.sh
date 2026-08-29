#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/screen - Writing only the rows that changed
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Depends on tui/term.
#
# A full-screen redraw on every keypress is imperceptible under a terminal
# emulator with a GPU behind it and close to a second on a bare console, which
# is exactly the machine a maintenance tool runs on. Moving the cursor one row
# should cost two rows of writing, and it costs a whole screen instead.
#
# So a frame is built as rows rather than written as it is composed, and the
# flush writes only the rows that differ from the one before. A cursor step
# changes two rows and a filter keystroke changes most of them, and both come
# out right without anybody deciding which case it is.
#
# The escape codes count as content, so a row that only changed colour is
# rewritten, which is correct and is what makes a selection move.
#
# Usage:
#   use shebang::tui::term
#   use shebang::tui::screen
#
#   tui_screen_begin
#   tui_screen_put 1 "a title"
#   tui_screen_put 3 "a row"
#   tui_screen_flush
# =============================================================================

[[ -n "${_SHEBANG_TUI_SCREEN_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_SCREEN_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

# The frame being built, and the one on screen. Indexed by row, one-based, so
# the arrays line up with what a terminal calls a row and nobody has to hold an
# offset in their head.
declare -ga _TUI_SCREEN_NEW=()
declare -ga _TUI_SCREEN_OLD=()
declare -gi _TUI_SCREEN_OLD_ROWS=0

# Whether anything is known about what is on screen at all. Nothing is, before
# the first flush and after an invalidate, and the difference matters for a row
# that is empty: comparing it against an unknown that also reads as empty says
# it does not need writing, when in fact whatever is up there does need
# clearing. That is the one row a diff will never write and never notice.
declare -gi _TUI_SCREEN_KNOWN=0

# How many rows the last flush actually wrote. Kept because it is the only
# honest way to test that a frame wrote two rows rather than forty, and a test
# that cannot see that is a test of nothing.
declare -gi TUI_SCREEN_WROTE=0

# An escape byte as itself, since there is no `$'\e'` to write one inline with
# where the row strings are assembled.
printf -v _TUI_SCREEN_ESC '\033'
declare -gr _TUI_SCREEN_ESC

#[pub]
# Start a frame. Everything put after this replaces what the last frame had at
# that row; a row nothing is put at is cleared by the flush.
# Usage: tui_screen_begin
tui_screen_begin() { _TUI_SCREEN_NEW=(); }

#[pub]
# Set one row's content. Row is one-based, the way a terminal counts them.
# Usage: tui_screen_put <row> <text>
tui_screen_put() {
    local row="${1:-0}"
    [[ "$row" =~ ^[0-9]+$ ]] || return 1
    (( row >= 1 )) || return 1
    _TUI_SCREEN_NEW[$row]="${2:-}"
}

#[pub]
# Forget what is on screen, so the next flush writes every row.
#
# Called after anything that wrote to the terminal behind the buffer's back: a
# modal, a subprocess, a resize. **The buffer cannot know that happened**, and
# a frame that skips a row because it believes the right thing is already there
# leaves whatever overwrote it in place.
# Usage: tui_screen_invalidate
tui_screen_invalidate() {
    _TUI_SCREEN_OLD=(); _TUI_SCREEN_OLD_ROWS=0; _TUI_SCREEN_KNOWN=0
}

# The rows this frame and the last one span between them, so a row that has
# gone away is still visited and cleared.
_tui_screen_extent() {
    local n="${#_TUI_SCREEN_NEW[@]}" hi=0 i
    for i in "${!_TUI_SCREEN_NEW[@]}"; do (( i > hi )) && hi=$i; done
    (( _TUI_SCREEN_OLD_ROWS > hi )) && hi="$_TUI_SCREEN_OLD_ROWS"
    printf '%d' "$hi"
}

#[pub]
# Write the frame, and only the rows that differ from the one on screen.
# Sets TUI_SCREEN_WROTE to how many rows that was.
# Usage: tui_screen_flush
tui_screen_flush() {
    local hi row now before out=""
    hi="$(_tui_screen_extent)"
    TUI_SCREEN_WROTE=0

    # With nowhere to position a cursor there is nothing to be clever about:
    # the frame is the rows, in order, one to a line, which is what a pipe or a
    # log wants and what every other thing here degrades to. Damage tracking
    # means nothing when the last frame has already scrolled away.
    if ! tui_is_tty; then
        for (( row = 1; row <= hi; row++ )); do
            printf '%s\n' "${_TUI_SCREEN_NEW[$row]-}"
            TUI_SCREEN_WROTE=$(( TUI_SCREEN_WROTE + 1 ))
        done
        _TUI_SCREEN_OLD=(); _TUI_SCREEN_OLD_ROWS=0; _TUI_SCREEN_KNOWN=0
        return 0
    fi

    for (( row = 1; row <= hi; row++ )); do
        now="${_TUI_SCREEN_NEW[$row]-}"
        before="${_TUI_SCREEN_OLD[$row]-}"
        (( _TUI_SCREEN_KNOWN == 1 )) && [[ "$now" == "$before" ]] && continue
        # Cleared to the end rather than padded with spaces: padding costs the
        # width of the terminal in bytes per row, which on the console this
        # exists for is most of the cost the whole module is here to avoid.
        # Built as a string rather than through `tui_move`, which prints. A
        # command substitution to capture it would be two forks per changed
        # row, which is most of the cost this module exists to remove.
        out+="${_TUI_SCREEN_ESC}[${row};1H${_TUI_SCREEN_ESC}[2K${now}"
        TUI_SCREEN_WROTE=$(( TUI_SCREEN_WROTE + 1 ))
    done

    # One write. Several small ones to a serial console interleave with
    # whatever else is talking to it, and the frame arrives in pieces.
    [[ -n "$out" ]] && printf '%s' "$out"

    _TUI_SCREEN_OLD=()
    for row in "${!_TUI_SCREEN_NEW[@]}"; do
        _TUI_SCREEN_OLD[$row]="${_TUI_SCREEN_NEW[$row]}"
    done
    _TUI_SCREEN_OLD_ROWS="$hi"
    _TUI_SCREEN_KNOWN=1
    return 0
}
