#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/frame - A border around what is ours
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# A frame says "this part is the tool talking". That matters most in a tool
# that spends half its time relaying somebody else's output: pacman, rsync,
# cryptsetup, a kernel that has opinions. Those keep streaming, unwrapped and
# unmangled, because reformatting another program's output is how a line that
# mattered gets truncated and how a progress bar turns into a wall of text.
#
# So: our own screens are framed, foreign output is not. The border is the
# boundary between the two, and it is the only thing it means.
#
# Everything degrades. With no terminal a frame is a heading and a blank line,
# which is what the same information looks like in a log file. Nothing here
# writes a control byte when there is nowhere to write one.
#
# Usage:
#   use shebang::tui::term
#   use shebang::tui::frame
#
#   tui_frame_open "Checking the disk"
#   tui_frame_say "smart says the drive is fine"
#   tui_frame_say ""
#   tui_frame_say "3 partitions, 2 mounted"
#   tui_frame_close
#
#   tui_frame_box "Done" "everything worked" "nothing to do"
# =============================================================================

[ -n "${_SHEBANG_TUI_FRAME_SH:-}" ] && return 0

# A newline as itself, because there is no `$'\n'` here to write one inline
# with. The trailing `.` is because command substitution strips the trailing
# newline, which is the one character being asked for.
_TUI_FRAME_NL="$(printf '\n.')"; _TUI_FRAME_NL="${_TUI_FRAME_NL%.}"
readonly _SHEBANG_TUI_FRAME_SH=1

# `command -v`, not `declare -F`, which is bash's and is not there under a
# POSIX shell. It parses anywhere, so `dash -n` never objected: the floor check
# reads a file, and a file can parse perfectly and still call something that
# does not exist.
if ! command -v use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use color

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

declare -gi _TUI_FRAME_OPEN=0
declare -g  _TUI_FRAME_TITLE=""
declare -gi TUI_FRAME_WIDTH=0     # drawn width less the two borders
declare -gi _TUI_FRAME_PLAIN=0    # drawing without a border at all

# Declared here, with the safe set as the default, rather than created inside
# whichever branch happens to run. The open flag used to be set before the
# branch that made these. A frame opened before tui_probe, saying "reading
# config" as the first thing a tool says, left the flag claiming a frame was
# open with no glyphs behind it, and the next line drawn died on an unbound
# variable. term.sh declares all of its state at file scope for exactly
# this reason.
declare -g _TUI_F_TL="+" _TUI_F_TR="+" _TUI_F_BL="+" _TUI_F_BR="+"
declare -g _TUI_F_H="-"  _TUI_F_V="|"  _TUI_F_ELL="..."

# Below this there is no room for a border and the text both, so the border
# goes and the text stays. A box wider than the screen wraps, and the right
# edge lands under the left one.
declare -gi _TUI_FRAME_MIN=24

# The glyphs, and the mark used when a line is cut. They travel together: an
# ellipsis is three bytes of UTF-8, and putting one inside an ASCII border is
# the mojibake the ASCII border exists to avoid.
_tui_frame_glyphs() {
    if [ "${TUI_FRAME_ASCII:-0}" = "1" ] || ! _tui_frame_unicode_ok; then
        _TUI_F_TL="+"; _TUI_F_TR="+"; _TUI_F_BL="+"; _TUI_F_BR="+"
        _TUI_F_H="-";  _TUI_F_V="|";  _TUI_F_ELL="..."
    else
        _TUI_F_TL="\u250c"; _TUI_F_TR="\u2510"; _TUI_F_BL="\u2514"; _TUI_F_BR="\u2518"
        _TUI_F_H="\u2500";  _TUI_F_V="\u2502";  _TUI_F_ELL="\u2026"
        printf -v _TUI_F_TL '%b' "$_TUI_F_TL"; printf -v _TUI_F_TR '%b' "$_TUI_F_TR"
        printf -v _TUI_F_BL '%b' "$_TUI_F_BL"; printf -v _TUI_F_BR '%b' "$_TUI_F_BR"
        printf -v _TUI_F_H  '%b' "$_TUI_F_H";  printf -v _TUI_F_V  '%b' "$_TUI_F_V"
        printf -v _TUI_F_ELL '%b' "$_TUI_F_ELL"
    fi
}

# The locale question itself is term.sh's, since progress needs the same
# answer and two copies of a rule are two rules.
_tui_frame_unicode_ok() { tui_unicode_ok; }

# Styling, but only when the terminal said so. term.sh probes it; nutshell's
# colour module decides separately, at source time, by a different rule. Two
# policies is one too many, and the one that knows about this session wins.
_tui_frame_styles() {
    if [ "${TUI_COLOR:-0}" -eq 1 ]; then
        _TUI_F_DIM="$DIM"; _TUI_F_BOLD="$BOLD"; _TUI_F_NC="$NC"
    else
        _TUI_F_DIM=""; _TUI_F_BOLD=""; _TUI_F_NC=""
    fi
}
declare -g _TUI_F_DIM="" _TUI_F_BOLD="" _TUI_F_NC=""

# How wide to draw. Never wider than the terminal: flooring the frame rather
# than the terminal is how a 10-column console got a 20-column box, every line
# of which wrapped.
_tui_frame_width() {
    local w
    # Whatever the last probe found. Re-measuring here would fork an stty for
    # every frame drawn, and would overwrite a size a caller set deliberately --
    # which is how this gets tested at widths no real terminal is.
    [ -n "${TUI_COLS:-}" ] || tui_size 2>/dev/null || true
    w="${TUI_COLS:-80}"
    # A run of digits, and at least one. There is no `=~` here, and a
    # `case` cannot count repetitions, so the test is that nothing in it is
    # not a digit.
    case "$w" in
        ''|*[!0-9]*) w=80 ;;
    esac
    [ "$w" -gt 100 ] && w=100
    [ "$w" -lt 1 ] && w=1
    printf '%d' $(( w - 2 ))
}

# Cheap repeat, without seq or a loop per character.
_tui_frame_rep() {
    local c="$1" n="$2" out=""
    [ "$n" -gt 0 ] || return 0
    printf -v out '%*s' "$n" ''
    printf '%s' "${out// /$c}"
}

#[pub]
# The number of characters in a string, styling removed. Codepoints, not
# display columns: a CJK character occupies two columns and counts as one here,
# so a title in CJK draws a box wider than it measures. Fine for the consoles
# this is for, and worth knowing before relying on it elsewhere.
# Usage: tui_frame_vis <text> -> a number
tui_frame_vis() { tui_vis "$1"; }

#[pub]
# Open a frame. Everything said until it closes sits inside it.
# Usage: tui_frame_open <title>
tui_frame_open() {
    local title="${1:-}"
    _TUI_FRAME_TITLE="$title"
    _TUI_FRAME_OPEN=1
    TUI_FRAME_WIDTH="$(_tui_frame_width)"

    # Unconditionally, and before anything can be drawn. Whether there is a
    # terminal decides how it looks, never whether the state exists.
    _tui_frame_glyphs
    _tui_frame_styles

    _TUI_FRAME_PLAIN=0
    if ! tui_is_tty || [ "$(( TUI_FRAME_WIDTH + 2 ))" -lt "$_TUI_FRAME_MIN" ]; then
        # In a log, and on a screen too narrow to hold a border and words both,
        # a frame is a heading. The information is the same; the shape is what
        # that medium uses for it.
        _TUI_FRAME_PLAIN=1
        [ -n "$title" ] && printf '%s\n' "$title"
        return 0
    fi

    local bar t_len
    t_len="$(tui_frame_vis "$title")"
    if [ -n "$title" ] && [ "$(( t_len + 4 ))" -le "$TUI_FRAME_WIDTH" ]; then
        bar="$(_tui_frame_rep "$_TUI_F_H" $(( TUI_FRAME_WIDTH - t_len - 3 )))"
        printf '%s%s%s %s%s%s %s%s%s\n' \
            "${_TUI_F_DIM}" "$_TUI_F_TL" "$_TUI_F_H" "${_TUI_F_NC}${_TUI_F_BOLD}" \
            "$title" "${_TUI_F_NC}${_TUI_F_DIM}" "$bar" "$_TUI_F_TR" "${_TUI_F_NC}"
    else
        bar="$(_tui_frame_rep "$_TUI_F_H" "$TUI_FRAME_WIDTH")"
        printf '%s%s%s%s%s\n' "${_TUI_F_DIM}" "$_TUI_F_TL" "$bar" "$_TUI_F_TR" "${_TUI_F_NC}"
    fi
}

#[pub]
# One line inside the open frame. A line longer than the frame is cut rather
# than wrapped, because a wrapped line breaks the right-hand border and makes
# the whole thing look broken. A line containing newlines becomes several rows,
# since the obvious thing to hand this is a captured command's output.
# Usage: tui_frame_say <text>
tui_frame_say() {
    local text="${1:-}" line
    if [ "$_TUI_FRAME_OPEN" -eq 0 ] || [ "$_TUI_FRAME_PLAIN" -eq 1 ]; then
        printf '%s\n' "$text"
        return 0
    fi
    # A here-document rather than a here-string, which is bash's. Both feed
    # the loop from a string without a subshell, so the rows still reach the
    # frame's own counters; a pipe would put the loop in a subshell and the
    # frame would close believing it had drawn nothing.
    case "$text" in
        *"$_TUI_FRAME_NL"*)
            while IFS= read -r line || [ -n "$line" ]; do
                _tui_frame_row "$line"
            done <<EOF
$text
EOF
            return 0
            ;;
    esac
    _tui_frame_row "$text"
}

_tui_frame_row() {
    local text="${1:-}" inner=$(( TUI_FRAME_WIDTH - 2 )) len pad
    [ "$inner" -lt 1 ] && inner=1
    len="$(tui_frame_vis "$text")"
    if [ "$len" -gt "$inner" ]; then
        text="$(tui_cut "$text" "$inner" "$_TUI_F_ELL")"
        len="$(tui_frame_vis "$text")"
    fi
    pad="$(_tui_frame_rep " " $(( inner - len )))"
    printf '%s%s%s %s%s %s%s%s\n' \
        "${_TUI_F_DIM}" "$_TUI_F_V" "${_TUI_F_NC}" "$text" "$pad" \
        "${_TUI_F_DIM}" "$_TUI_F_V" "${_TUI_F_NC}"
}

#[pub]
# Close the frame.
# Usage: tui_frame_close
tui_frame_close() {
    if [ "$_TUI_FRAME_OPEN" -eq 0 ]; then return 0; fi
    _TUI_FRAME_OPEN=0
    if [ "$_TUI_FRAME_PLAIN" -eq 1 ]; then printf '\n'; return 0; fi
    local bar; bar="$(_tui_frame_rep "$_TUI_F_H" "$TUI_FRAME_WIDTH")"
    printf '%s%s%s%s%s\n' "${_TUI_F_DIM}" "$_TUI_F_BL" "$bar" "$_TUI_F_BR" "${_TUI_F_NC}"
}

#[pub]
# A whole frame in one call, for the common case of saying a few fixed lines.
# Usage: tui_frame_box <title> [line...]
tui_frame_box() {
    local title="${1:-}"
    # `shift` with no arguments left fails and, under set -e in a caller's
    # shell, takes the whole run with it. Guarded by the count, not by a
    # redirect that hides the message without preventing the failure.
    [ "$#" -gt 0 ] && shift
    tui_frame_open "$title"
    local l
    for l in "$@"; do tui_frame_say "$l"; done
    tui_frame_close
}

#[pub]
# Run something whose output belongs to it, not to us. Nothing is framed,
# captured or reformatted. It streams as it would have without us, which for a
# session on the alternate screen means handing the screen back first. That is
# tui_suspend's job and this does not reimplement it.
# Usage: tui_frame_foreign <command> [args...] -> returns the command's status
tui_frame_foreign() {
    local was="$_TUI_FRAME_OPEN" rc
    [ "$was" -eq 1 ] && tui_frame_close
    if declare -F tui_suspend >/dev/null 2>&1; then
        tui_suspend "$@"; rc=$?
    else
        "$@"; rc=$?
    fi
    [ "$was" -eq 1 ] && tui_frame_open "$_TUI_FRAME_TITLE"
    return "$rc"
}
