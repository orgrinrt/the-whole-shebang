#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/term - The terminal, and putting it back
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# The bottom of the tui library. Everything else here draws on top of this, and
# nothing else in the collection is needed to use it.
#
# Two ideas carry the whole file.
#
# The first is that there may be no terminal. A script gets run over ssh,
# through a pipe, from cron, and inside another tool that captured its output.
# Refusing to work in those is worse than being plain in them, so every entry
# point is safe to call with nothing attached and simply does less. Control
# bytes are never written when there is nowhere to write them, because a pipe
# full of escape sequences is a corrupted file rather than a styled one.
#
# The second is that whatever is changed gets put back, on every exit path
# including the ones nobody plans for. Raw mode and a hidden cursor are global
# state owned by the terminal rather than by the process, so a crash leaves the
# user with a shell that does not echo. This is the reason the restore runs
# from a trap and is written to be safe to call twice: a tool that leaves a
# dead shell behind is a tool nobody starts a second time.
#
# Usage:
#   use shebang::tui/term
#
#   tui_begin                  # alt screen, cursor away, traps armed
#   tui_move 3 1; printf 'hello'
#   tui_end                    # or just exit; the trap covers it
# =============================================================================

[[ -n "${_SHEBANG_TUI_TERM_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_TERM_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

declare -gi TUI_TTY=0        # is there a terminal to draw on
declare -gi TUI_COLOR=0      # may we use colour

# Deliberately NOT integer-typed. An integer assignment is an arithmetic
# evaluation, so `TUI_ROWS="$LINES"` with a non-numeric LINES treats the value
# as a variable name and dies under set -u. These take whatever stty and the
# environment hand over, which is exactly the untrusted case.
declare -g TUI_ROWS=24
declare -g TUI_COLS=80

_TUI_STTY_SAVED=""
declare -gi _TUI_ACTIVE=0

# -----------------------------------------------------------------------------
# Capability
# -----------------------------------------------------------------------------

#[pub]
# Work out what the terminal can do. Called by `tui_begin`; call it directly
# only when reading the flags without entering a screen.
# Usage: tui_probe -> sets TUI_TTY, TUI_COLOR, TUI_ROWS, TUI_COLS
tui_probe() {
    if [[ -t 0 && -t 1 ]]; then TUI_TTY=1; else TUI_TTY=0; fi

    # NO_COLOR is honoured because it is the one convention everyone agreed on,
    # and TERM=dumb is the other half of the same question.
    if [[ $TUI_TTY -eq 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
        TUI_COLOR=1
    else
        TUI_COLOR=0
    fi
    tui_size
}

#[pub]
# Is there a terminal to interact with. The question every caller that wants to
# ask the user something has to answer first, named here so each one does not
# reimplement it against the flag and drift.
# Usage: tui_is_tty -> returns 0 when there is a terminal
tui_is_tty() { [[ $TUI_TTY -eq 1 ]]; }

#[pub]
# Re-read the terminal dimensions. Armed on WINCH by `tui_begin`, so a caller
# that redraws on every key never has to ask.
# Usage: tui_size -> sets TUI_ROWS and TUI_COLS
tui_size() {
    local sz
    if [[ $TUI_TTY -eq 1 ]] && sz="$(stty size 2>/dev/null)"; then
        TUI_ROWS="${sz%% *}"
        TUI_COLS="${sz##* }"
    else
        TUI_ROWS="${LINES:-24}"
        TUI_COLS="${COLUMNS:-80}"
    fi
    # A zero would divide by zero in a pager calculation later, which is a
    # crash at the worst possible moment rather than a wrong number.
    [[ "$TUI_ROWS" =~ ^[0-9]+$ && $TUI_ROWS -gt 0 ]] || TUI_ROWS=24
    [[ "$TUI_COLS" =~ ^[0-9]+$ && $TUI_COLS -gt 0 ]] || TUI_COLS=80
}

# -----------------------------------------------------------------------------
# Escape sequences
# -----------------------------------------------------------------------------
# All of them go through here, which is the single place the no-terminal case
# is handled. Nothing below writes an escape byte directly.

_tui_esc() { [[ $TUI_TTY -eq 1 ]] && printf '\033%s' "$1"; return 0; }

#[pub]
# Switch to the alternate screen, so the user's scrollback survives the run.
# Usage: tui_alt_screen_on
tui_alt_screen_on() { _tui_esc '[?1049h'; }

#[pub]
# Return to the normal screen, restoring whatever was there before.
# Usage: tui_alt_screen_off
tui_alt_screen_off() { _tui_esc '[?1049l'; }

#[pub]
# Hide the cursor while drawing, so it does not flicker across the screen.
# Usage: tui_cursor_hide
tui_cursor_hide() { _tui_esc '[?25l'; }

#[pub]
# Show the cursor again. Part of putting the terminal back.
# Usage: tui_cursor_show
tui_cursor_show() { _tui_esc '[?25h'; }

#[pub]
# Clear the screen and park the cursor at the top left.
# Usage: tui_clear
tui_clear() { _tui_esc '[2J'; _tui_esc '[H'; }

#[pub]
# Wipe the current line and return to its start, for in-place status updates.
# Usage: tui_clear_line
tui_clear_line() { _tui_esc '[2K'; printf '\r'; }

#[pub]
# Move the cursor. Both coordinates are 1-based, as the terminal counts them.
# Usage: tui_move <row> <col>
tui_move() { _tui_esc "[${1};${2}H"; }

# -----------------------------------------------------------------------------
# Raw mode
# -----------------------------------------------------------------------------

#[pub]
# Turn off echo and line buffering so single keypresses can be read. Saves the
# previous settings verbatim; calling it twice does not stack, so the saved
# state is always the user's own rather than our own from a moment ago.
# Usage: tui_raw_on
tui_raw_on() {
    [[ $TUI_TTY -eq 1 ]] || return 0
    [[ -n "$_TUI_STTY_SAVED" ]] && return 0
    _TUI_STTY_SAVED="$(stty -g 2>/dev/null)" || return 0
    # -icanon with min 1 makes a read return after exactly one byte rather than
    # waiting for a newline, which is what reading a keypress means.
    stty -echo -icanon min 1 time 0 2>/dev/null || true
}

#[pub]
# Put the line discipline back. Falls through to `stty sane` if the saved
# settings will not apply, because leaving a terminal without echo is worse
# than leaving it with settings that are merely not the ones it had.
# Usage: tui_raw_off
tui_raw_off() {
    [[ -n "$_TUI_STTY_SAVED" ]] || return 0
    stty "$_TUI_STTY_SAVED" 2>/dev/null || stty sane 2>/dev/null || true
    _TUI_STTY_SAVED=""
}

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

#[pub]
# Put everything back. Safe to call any number of times, which matters because
# it runs from the trap and possibly again on the way out.
# Usage: tui_restore
tui_restore() {
    [[ $_TUI_ACTIVE -eq 1 ]] || return 0
    _TUI_ACTIVE=0
    tui_raw_off
    tui_cursor_show
    tui_alt_screen_off
    return 0
}

#[pub]
# Enter a full-screen session and arm the traps that leave it cleanly.
#
# INT and TERM restore and then re-raise with the default handler, so the exit
# status still reports an interrupted run. Swallowing them would make a script
# that was killed look like one that finished.
# Usage: tui_begin
tui_begin() {
    tui_probe
    _TUI_ACTIVE=1
    trap 'tui_restore' EXIT
    trap 'tui_restore; trap - INT;  kill -INT  $$' INT
    trap 'tui_restore; trap - TERM; kill -TERM $$' TERM
    trap 'tui_size' WINCH
    tui_alt_screen_on
    tui_cursor_hide
    tui_clear
}

#[pub]
# Leave the session early. The EXIT trap covers the ordinary case, so this is
# for handing the terminal back before doing something else with it.
# Usage: tui_end
tui_end() { tui_restore; }

#[pub]
# Run a command with the real terminal handed back, then resume drawing.
#
# For anything that owns the screen itself: an editor, a chroot shell, fsck,
# a package manager. Without it, every such task leaves the display corrupted
# and the caller redraws over the wreckage.
# Usage: tui_suspend <command> [args...] -> returns the command's status
tui_suspend() {
    local was=$_TUI_ACTIVE rc=0
    tui_restore
    "$@" || rc=$?
    if [[ $was -eq 1 ]]; then
        _TUI_ACTIVE=1
        tui_alt_screen_on
        tui_cursor_hide
        tui_clear
    fi
    return $rc
}
