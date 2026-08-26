#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/confirm - Asking before something irreversible
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Depends on tui/term and tui/key, and nothing else in the collection.
#
# Three strengths, because one is never enough and five is theatre.
#
# `tui_confirm` is a yes or no, defaulting to no. Anything a tired person can
# answer by leaning on return should default to the harmless outcome.
#
# `tui_confirm_typed` makes them type a given word. The point is not that the
# word is hard, it is that it cannot be answered by reflex, and that the word
# names the thing being done rather than being a generic yes.
#
# `tui_confirm_name` makes them type back a specific name, usually the device
# about to be destroyed. This is the only one that defends against the actual
# failure, which is not "did not mean to say yes" but "meant yes about a
# different disk". A generic confirmation cannot catch that, however loud it is.
#
# Every one of them refuses by default when there is no terminal. A script
# running unattended must not be able to blunder into a destructive branch
# because nothing was there to say no; the caller has to pass the answer in
# explicitly instead.
#
# When tui/modal is loaded and a session is on the screen, the question is
# drawn in a box over the middle of it. Printed at the cursor instead, it lands
# wherever the last thing drawn left it, which after a full-screen menu is the
# bottom of the terminal: a long way from where the person is looking on a tall
# window, and a prompt nobody notices is a prompt answered by reflex once they
# find it. The caller redraws afterwards; TUI_CONFIRM_REDRAW names a function
# to call for that.
#
# Usage:
#   use shebang::tui/confirm
#
#   tui_confirm "Reinstall the bootloader?"          || return
#   tui_confirm_typed "Wipe /dev/sdb?" ERASE         || return
#   tui_confirm_name  "Destroy this disk" /dev/sdb   || return
# =============================================================================

[[ -n "${_SHEBANG_TUI_CONFIRM_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_CONFIRM_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use color

# A function that redraws whatever the confirmation covered. The menu sets it
# to its own draw, so a box appears over the list and the list comes back.
declare -g TUI_CONFIRM_REDRAW="${TUI_CONFIRM_REDRAW:-}"

# Is there a screen to draw a box on, and something loaded that can draw one?
_tui_confirm_modal_ok() {
    tui_is_tty || return 1
    declare -F tui_modal_open >/dev/null 2>&1 || return 1
    # Only inside a session. Outside one there is nothing underneath to cover,
    # and printing the question where the cursor is is exactly right.
    [[ "${_TUI_ACTIVE:-0}" == "1" ]]
}

_tui_confirm_redraw() {
    [[ -n "$TUI_CONFIRM_REDRAW" ]] || return 0
    declare -F "$TUI_CONFIRM_REDRAW" >/dev/null 2>&1 || return 0
    "$TUI_CONFIRM_REDRAW"
}

# Set to 1 to make every confirmation answer yes without asking. For tests and
# for a caller that has already obtained consent some other way. Deliberately
# ugly to type, and deliberately not a short flag.
declare -g TUI_CONFIRM_ASSUME_YES="${TUI_CONFIRM_ASSUME_YES:-0}"

# The answer given when there is no terminal to ask at. No, always.
_tui_confirm_headless() {
    [[ "$TUI_CONFIRM_ASSUME_YES" == "1" ]] && return 0
    return 1
}

#[pub]
# Ask a yes or no question. Defaults to no on empty input, on end of input, and
# when there is no terminal.
# Usage: tui_confirm <question> -> returns 0 for yes, 1 for no
tui_confirm() {
    [[ "$TUI_CONFIRM_ASSUME_YES" == "1" ]] && return 0
    tui_is_tty || return 1

    local answer=""
    if _tui_confirm_modal_ok; then
        tui_modal_open "$1"
        answer="$(tui_modal_prompt '[y/N] ')" || { tui_modal_close; _tui_confirm_redraw; return 1; }
        tui_modal_close
        _tui_confirm_redraw
    else
        printf '%s [y/N] ' "$1"
        IFS= read -r answer 2>/dev/null || { printf '\n'; return 1; }
    fi
    case "$answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *)               return 1 ;;
    esac
}

#[pub]
# Ask for a word to be typed back exactly. Case sensitive, because a word that
# can be answered in lower case is a word that can be answered without reading.
# Usage: tui_confirm_typed <question> <word> -> returns 0 when it matches
tui_confirm_typed() {
    local question="$1" want="$2" answer=""
    [[ "$TUI_CONFIRM_ASSUME_YES" == "1" ]] && return 0
    tui_is_tty || return 1

    if _tui_confirm_modal_ok; then
        tui_modal_open "$question" "Type ${want} to continue."
        answer="$(tui_modal_prompt '> ')" || { tui_modal_close; _tui_confirm_redraw; return 1; }
        tui_modal_close
        _tui_confirm_redraw
    else
        printf '%s\n' "$question"
        printf '%sType %s to continue:%s ' "$TUI_C_HEAD" "$want" "$TUI_C_END"
        IFS= read -r answer 2>/dev/null || { printf '\n'; return 1; }
    fi
    [[ "$answer" == "$want" ]]
}

#[pub]
# Ask for a specific name to be typed back, and show what is at stake first.
#
# For anything that takes a target. The name is the device, the volume or the
# host, so the confirmation is about *which* rather than *whether*, which is
# the mistake that actually happens.
# Usage: tui_confirm_name <what> <name> [detail...] -> returns 0 when it matches
tui_confirm_name() {
    local what="$1" name="$2"; shift 2
    local answer="" line
    [[ "$TUI_CONFIRM_ASSUME_YES" == "1" ]] && return 0
    tui_is_tty || return 1

    if _tui_confirm_modal_ok; then
        tui_modal_open "$what" "$name" "$@" "" "This cannot be undone."
        answer="$(tui_modal_prompt 'Type the name back: ')" \
            || { tui_modal_close; _tui_confirm_redraw; return 1; }
        tui_modal_close
        _tui_confirm_redraw
    else
        printf '\n%s%s%s\n' "$TUI_C_BAD" "$what" "$TUI_C_END"
        printf '  %s%s%s\n' "$TUI_C_HEAD" "$name" "$TUI_C_END"
        for line in "$@"; do printf '  %s%s%s\n' "$TUI_C_MUTE" "$line" "$TUI_C_END"; done
        printf '\nThis cannot be undone.\n'
        printf 'Type the name back to continue: '
        IFS= read -r answer 2>/dev/null || { printf '\n'; return 1; }
    fi
    [[ "$answer" == "$name" ]]
}
