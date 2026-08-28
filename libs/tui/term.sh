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
#   use shebang::tui::term
#
#   tui_begin                  # alt screen, cursor away, traps armed
#   tui_move 3 1; printf 'hello'
#   tui_end                    # or just exit; the trap covers it
# =============================================================================

[ -n "${_SHEBANG_TUI_TERM_SH:-}" ] && return 0
readonly _SHEBANG_TUI_TERM_SH=1

if ! command -v use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

# The escape character, as a value. `$'\033'` is a bash spelling and this file
# is read by a POSIX shell.
_TUI_ESC="$(printf '\033')"

TUI_TTY=0        # is there a terminal to draw on
TUI_COLOR=0      # may we use colour

# Deliberately NOT integer-typed. An integer assignment is an arithmetic
# evaluation, so `TUI_ROWS="$LINES"` with a non-numeric LINES treats the value
# as a variable name and dies under set -u. These take whatever stty and the
# environment hand over, which is exactly the untrusted case.
TUI_ROWS=24
TUI_COLS=80

_TUI_STTY_SAVED=""
_TUI_ACTIVE=0

# -----------------------------------------------------------------------------
# Capability
# -----------------------------------------------------------------------------

#[pub]
# Work out what the terminal can do. Called by `tui_begin`; call it directly
# only when reading the flags without entering a screen.
# Usage: tui_probe -> sets TUI_TTY, TUI_COLOR, TUI_ROWS, TUI_COLS
tui_probe() {
    if [ -t 0 ] && [ -t 1 ]; then TUI_TTY=1; else TUI_TTY=0; fi

    # NO_COLOR is honoured because it is the one convention everyone agreed on,
    # and TERM=dumb is the other half of the same question.
    if [ "$TUI_TTY" -eq 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
        TUI_COLOR=1
    else
        TUI_COLOR=0
    fi
    tui_size
    tui_palette
}

#[pub]
# Is there a terminal to interact with. The question every caller that wants to
# ask the user something has to answer first, named here so each one does not
# reimplement it against the flag and drift.
# Usage: tui_is_tty -> returns 0 when there is a terminal
tui_is_tty() { [ $TUI_TTY -eq 1 ]; }

#[pub]
# Re-read the terminal dimensions. Armed on WINCH by `tui_begin`, so a caller
# that redraws on every key never has to ask.
# Usage: tui_size -> sets TUI_ROWS and TUI_COLS
tui_size() {
    local sz
    if [ $TUI_TTY -eq 1 ] && sz="$(stty size 2>/dev/null)"; then
        TUI_ROWS="${sz%% *}"
        TUI_COLS="${sz##* }"
    else
        TUI_ROWS="${LINES:-24}"
        TUI_COLS="${COLUMNS:-80}"
    fi
    # A zero would divide by zero in a pager calculation later, which is a
    # crash at the worst possible moment rather than a wrong number.
    case "$TUI_ROWS" in ''|*[!0-9]*) TUI_ROWS=24 ;; esac
    [ "$TUI_ROWS" -gt 0 ] || TUI_ROWS=24
    case "$TUI_COLS" in ''|*[!0-9]*) TUI_COLS=80 ;; esac
    [ "$TUI_COLS" -gt 0 ] || TUI_COLS=80
}

# -----------------------------------------------------------------------------
# Escape sequences
# -----------------------------------------------------------------------------
# All of them go through here, which is the single place the no-terminal case
# is handled. Nothing below writes an escape byte directly.

_tui_esc() { [ $TUI_TTY -eq 1 ] && printf '\033%s' "$1"; return 0; }

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
    [ $TUI_TTY -eq 1 ] || return 0
    [ -n "$_TUI_STTY_SAVED" ] && return 0
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
    [ -n "$_TUI_STTY_SAVED" ] || return 0
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
    [ $_TUI_ACTIVE -eq 1 ] || return 0
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
    if [ $was -eq 1 ]; then
        _TUI_ACTIVE=1
        tui_alt_screen_on
        tui_cursor_hide
        tui_clear
    fi
    return $rc
}

# -----------------------------------------------------------------------------
# Colour, by meaning
# -----------------------------------------------------------------------------
#
# Named for what a thing is, not for what colour it happens to be. A screen
# where "done" is plain and "press any key" is blue is a screen where colour
# carries no information: the eye learns there is nothing to find and stops
# looking. So every module colours the same kind of thing the same way, and
# anything colourless is colourless on purpose.
#
# All empty when the terminal said no colour, so a caller never has to ask.

TUI_C_OK="" TUI_C_WARN="" TUI_C_BAD="" TUI_C_OFF=""
TUI_C_KEY="" TUI_C_HEAD="" TUI_C_MUTE="" TUI_C_SEL="" TUI_C_OFFTXT=""
TUI_C_END=""

#[pub]
# Fill the palette from the colour library, gated on what the terminal said.
# Called by tui_probe; call it again if the colour variables change under you.
# Usage: tui_palette
tui_palette() {
    if [ "$(( ${TUI_COLOR:-0} == 1 ))" -ne 0 ]; then
        TUI_C_OK="${GREEN:-}"          # already true, finished, healthy
        TUI_C_WARN="${YELLOW:-}"       # worth a look
        TUI_C_BAD="${RED:-}"           # broken, or about to destroy something
        TUI_C_OFF="${DIM:-}"           # unavailable, and why
        TUI_C_KEY="${CYAN:-}"          # a key to press
        TUI_C_HEAD="${BOLD:-}"         # a heading
        TUI_C_MUTE="${DIM:-}"          # secondary text that is still meant to be read
        TUI_C_SEL="${BOLD:-}"          # the row under the cursor
        TUI_C_OFFTXT="${DIM:-}"
        TUI_C_END="${NC:-}"
    else
        TUI_C_OK=""; TUI_C_WARN=""; TUI_C_BAD=""; TUI_C_OFF=""
        TUI_C_KEY=""; TUI_C_HEAD=""; TUI_C_MUTE=""; TUI_C_SEL=""; TUI_C_OFFTXT=""
        TUI_C_END=""
    fi
}

#[pub]
# The colour for a state word: ok, done, warn, fail, off, skip.
# Usage: printf '%s%s%s' "$(tui_state_colour done)" "done" "$TUI_C_END"
tui_state_colour() {
    case "$1" in
        ok|done|good|yes)    printf '%s' "$TUI_C_OK" ;;
        warn|maybe)          printf '%s' "$TUI_C_WARN" ;;
        fail|bad|no|blocked) printf '%s' "$TUI_C_BAD" ;;
        off|skip|na)         printf '%s' "$TUI_C_OFF" ;;
        *)                   printf '' ;;
    esac
}

# -----------------------------------------------------------------------------
# Cutting text to fit
# -----------------------------------------------------------------------------

#[pub]
# Can this terminal draw characters outside ASCII? A locale that is not UTF-8
# renders them as several bytes of nonsense, and the linux console before a font
# is loaded is the usual place that happens.
# Usage: tui_unicode_ok && ...
tui_unicode_ok() {
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8*|*utf8*|*UTF8*|*utf-8*) ;;
        *) return 1 ;;
    esac
    [ "${TERM:-}" != "linux" ]
}

#[pub]
# The mark to end a line that had to be cut, in whatever this terminal can
# draw. An ellipsis is three bytes of UTF-8, so on a console that cannot render
# it the nicer mark is the corruption the ASCII fallback exists to avoid.
# Usage: tui_ellipsis -> "…" or "..."
tui_ellipsis() {
    if tui_unicode_ok; then printf '\u2026'; else printf '...'; fi
}

# The length in bytes of the character a lead byte begins, or 0 if the byte is
# not a lead byte. Read under LC_ALL=C, where bash indexes bytes.
_tui_lead_len() {
    local n="$1"
    if   [ "$(( n >= 240 && n <= 247 ))" -ne 0 ]; then printf '4'
    elif [ "$(( n >= 224 && n <= 239 ))" -ne 0 ]; then printf '3'
    elif [ "$(( n >= 192 && n <= 223 ))" -ne 0 ]; then printf '2'
    else printf '0'; fi
}
#[pub]
# How wide a string is on the screen, ignoring the colour in it.
#
# Anything lining a column up has to measure what the eye sees rather than what
# the string holds, or a cell carrying colour pushes everything after it. Two
# copies of this existed, in frame and in modal, and both forked `sed` for
# every measurement on a path that redraws on a keypress.
#
# A scan rather than a substitution, because it runs per cell per row: a fork
# costs more than walking a short string, and a menu is a hundred short ones.
# Usage: tui_vis <text> -> a number
tui_vis() {
    local s="$1" n=0 c rest
    # The common case, and the reason this is cheap: no escape at all.
    case "$s" in *"$_TUI_ESC"*) ;; *) printf '%d' "${#s}"; return 0 ;; esac

    # Chopped from the front rather than indexed. `${s:i:1}` is a bash
    # substring and the C-style `for` around it is bash too, but the reason to
    # chop rather than translate the index is the `continue` below: in the old
    # loop the header advanced `i`, and a `while` written to look the same puts
    # the advance after the `continue` where it never runs. Chopping advances
    # before the branch, so there is no order to get wrong.
    rest="$s"
    while [ -n "$rest" ]; do
        c="${rest%"${rest#?}"}"
        rest="${rest#?}"
        if [ "$c" = "$_TUI_ESC" ]; then
            case "$rest" in "["*|"]"*) rest="${rest#?}" ;; esac
            # A CSI ends on a letter; everything before it is parameters.
            while [ -n "$rest" ]; do
                c="${rest%"${rest#?}"}"
                rest="${rest#?}"
                case "$c" in [A-Za-z]) break ;; esac
            done
            continue
        fi
        n=$(( n + 1 ))
    done
    printf '%d' "$n"
}

#[pub]
# A string cut to n characters with the mark on the end.
#
# In a non-UTF-8 locale bash indexes bytes, so a plain cut can land inside a
# character and leave a lone lead byte on screen. That is the corruption the
# ASCII fallback exists to prevent, arriving by another door. Only a sequence
# that is actually incomplete is removed: an earlier version stripped whole
# characters that were never split.
# Usage: tui_cut <text> <n> [mark] -> the cut string
tui_cut() {
    local s="$1" n="$2" mark="${3:-$(tui_ellipsis)}" keep _d
    _d="$n"; case "$_d" in -*) _d="${_d#-}" ;; esac
    case "$_d" in ''|*[!0-9]*) n=0 ;; esac
    [ "$n" -le 0 ] && { printf ''; return 0; }
    [ "${#s}" -le "$n" ] && { printf '%s' "$s"; return 0; }

    keep=$(( n - ${#mark} ))
    [ "$keep" -lt 0 ] && keep=0
    # `${s:0:$keep}` is a bash substring. POSIX `printf` takes a precision, so
    # `%.*s` is the same cut with no fork, `printf` being a builtin.
    s="$(printf '%.*s' "$keep" "$s")"

    if ! tui_unicode_ok; then
        local cont=0 b code want tmp
        # Walk back over trailing continuation bytes, then look at the byte in
        # front of them. The sequence is incomplete only when that lead byte
        # wanted more bytes than are present.
        #
        # Chopped from the end rather than indexed backwards, for the same
        # reason as `tui_vis`: this loop also carries a `continue`, and `tmp`
        # after the chop is exactly what `${s:0:i-1}` used to name.
        tmp="$s"
        while [ -n "$tmp" ]; do
            b="${tmp#"${tmp%?}"}"
            tmp="${tmp%?}"
            code="$(printf '%d' "'$b" 2>/dev/null)" || code=0
            [ -n "$code" ] || code=0
            [ "$code" -lt 0 ] && code=$(( code + 256 ))
            if [ "$code" -ge 128 ] && [ "$code" -le 191 ]; then
                cont=$(( cont + 1 )); continue
            fi
            want="$(_tui_lead_len "$code")"
            if [ "$want" -gt 0 ] && [ "$want" -gt $(( cont + 1 )) ]; then
                s="$tmp"                # a real partial sequence: drop it whole
            fi
            break
        done
    fi
    printf '%s%s' "$s" "$mark"
}

# -----------------------------------------------------------------------------
# Probed once, here
# -----------------------------------------------------------------------------
#
# TUI_TTY and TUI_COLOR used to stay at their defaults until tui_begin ran, and
# a module that gates its colour on TUI_COLOR then printed none at all for a
# caller that sources it and calls it, which is what every usage header in this
# collection shows. Probing at load makes the flags mean something from the
# first line, and tui_probe stays callable for a size that changed.
tui_probe 2>/dev/null || true
