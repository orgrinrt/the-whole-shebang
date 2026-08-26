#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/key - Reading a keypress, by name
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Callers get a name, never bytes. Nothing above this file should contain an
# escape sequence, because the moment two screens both match on `\033[A` they
# start disagreeing about the edge cases, and the edge cases here are real:
# terminals differ on home and end, and a bare escape is indistinguishable
# from the start of a sequence except by waiting.
#
# That wait is the one piece of ugliness that cannot be designed away. A
# terminal sends a sequence as loose bytes with no length in front, so the only
# evidence that it has finished is that nothing more arrives. The timeout is
# therefore not a nicety, it is the parser's terminator.
#
# Movement collapses to four names. Arrows, vi hjkl and emacs ctrl-n/p/f/b all
# mean the same thing, and deciding which is correct is not this library's
# business: someone tired should be able to press whatever is under their
# fingers and have it work.
#
# Usage:
#   use shebang::tui::key
#
#   tui_key_read || return           # blocks; sets TUI_KEY
#   case "$(tui_key_motion)" in
#       up)   ... ;;
#       down) ... ;;
#   esac
#   tui_key_is_cancel && return 1
# =============================================================================

[[ -n "${_SHEBANG_TUI_KEY_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_KEY_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

declare -g TUI_KEY=""

# How long to wait for the rest of an escape sequence. Long enough that a slow
# link does not split one, short enough that pressing escape alone still feels
# like pressing escape.
declare -g TUI_ESC_TIMEOUT="${TUI_ESC_TIMEOUT:-0.05}"

# -----------------------------------------------------------------------------
# The sequence table
# -----------------------------------------------------------------------------

# Kept as a pure function of the bytes so it can be tested without a terminal.
# The reader below does the waiting; this only decides what the bytes meant.
_tui_key_from_csi() {
    case "$1" in
        A)       printf 'up'        ;;
        B)       printf 'down'      ;;
        C)       printf 'right'     ;;
        D)       printf 'left'      ;;
        H|1~|7~) printf 'home'      ;;
        F|4~|8~) printf 'end'       ;;
        5~)      printf 'pgup'      ;;
        6~)      printf 'pgdn'      ;;
        2~)      printf 'insert'    ;;
        3~)      printf 'delete'    ;;
        Z)       printf 'shift-tab' ;;
        *)       printf 'unknown'   ;;
    esac
}

# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

#[pub]
# Block until a key is available, then name it in TUI_KEY.
#
# Returns 1 only when input is exhausted, which for a pipe means end of file
# and for a terminal means never. A caller looping on this should treat the
# non-zero as "stop", not as an error.
# Usage: tui_key_read -> sets TUI_KEY, returns 0, or 1 at end of input
tui_key_read() {
    local c rest seq ch
    TUI_KEY=""

    IFS= read -r -n1 -d '' c 2>/dev/null || return 1

    case "$c" in
        $'\033')
            # Nothing more inside the window means it really was escape.
            if ! IFS= read -r -n1 -d '' -t "$TUI_ESC_TIMEOUT" rest 2>/dev/null; then
                TUI_KEY="esc"; return 0
            fi
            if [[ "$rest" == "[" || "$rest" == "O" ]]; then
                seq=""
                # A CSI ends on a byte in 0x40..0x7E. Reading until one arrives
                # keeps this correct for parameters we do not know about.
                while IFS= read -r -n1 -d '' -t "$TUI_ESC_TIMEOUT" ch 2>/dev/null; do
                    seq+="$ch"
                    [[ "$ch" =~ [A-Za-z~] ]] && break
                done
                TUI_KEY="$(_tui_key_from_csi "$seq")"
            else
                # Escape then a letter is how most terminals send alt.
                TUI_KEY="alt-$rest"
            fi
            ;;
        $'\n'|$'\r'|"")  TUI_KEY="enter"     ;;
        $'\t')           TUI_KEY="tab"       ;;
        $'\177'|$'\b')   TUI_KEY="backspace" ;;
        $'\003')         TUI_KEY="ctrl-c"    ;;
        $'\004')         TUI_KEY="ctrl-d"    ;;
        ' ')             TUI_KEY="space"     ;;
        *)               TUI_KEY="$c"        ;;
    esac
    return 0
}

# -----------------------------------------------------------------------------
# Meaning
# -----------------------------------------------------------------------------

#[pub]
# Collapse whatever was pressed into a direction, or pass it through unchanged.
#
# Arrows, vi keys and the emacs pairs all fold together. Tab moves down and
# shift-tab moves up, so a screen is navigable from a keyboard missing arrows.
# Usage: tui_key_motion -> prints up, down, left, right, or the key itself
tui_key_motion() {
    case "$TUI_KEY" in
        up|k|$'\020'|shift-tab)  printf 'up'    ;;
        down|j|$'\016'|tab)      printf 'down'  ;;
        left|h|$'\002')          printf 'left'  ;;
        right|l|$'\006')         printf 'right' ;;
        *)                       printf '%s' "$TUI_KEY" ;;
    esac
}

#[pub]
# Did the user say yes. Named once here so no screen invents its own answer.
# Usage: tui_key_is_accept -> returns 0 when the last key meant accept
tui_key_is_accept() {
    [[ "$TUI_KEY" == "enter" || "$TUI_KEY" == "space" ]]
}

#[pub]
# Did the user say no, or ask to leave. ctrl-c is included deliberately: in raw
# mode it arrives as a byte rather than a signal, so a screen that ignored it
# would trap someone who pressed the one key everybody knows.
# Usage: tui_key_is_cancel -> returns 0 when the last key meant cancel
tui_key_is_cancel() {
    [[ "$TUI_KEY" == "esc" || "$TUI_KEY" == "q" || "$TUI_KEY" == "ctrl-c" ]]
}
