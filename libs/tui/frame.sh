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
#   use shebang::tui/term
#   use shebang::tui/frame
#
#   tui_frame_open "Checking the disk"
#   tui_frame_say "smart says the drive is fine"
#   tui_frame_say ""
#   tui_frame_say "3 partitions, 2 mounted"
#   tui_frame_close
#
#   tui_frame_box "Done" "everything worked" "nothing to do"
# =============================================================================

[[ -n "${_SHEBANG_TUI_FRAME_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_FRAME_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use color

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

declare -gi _TUI_FRAME_OPEN=0
declare -g  _TUI_FRAME_TITLE=""
declare -gi TUI_FRAME_WIDTH=0     # inner width, set by tui_frame_open

# The glyphs. Plain ASCII on a terminal that has not said it can do better,
# because a box drawn in mojibake is worse than no box: it reads as corruption,
# and corruption is exactly what somebody running a recovery tool is afraid of.
_tui_frame_glyphs() {
    if [[ "${TUI_FRAME_ASCII:-0}" == "1" ]] || ! _tui_frame_unicode_ok; then
        _TUI_F_TL="+"; _TUI_F_TR="+"; _TUI_F_BL="+"; _TUI_F_BR="+"
        _TUI_F_H="-";  _TUI_F_V="|"
    else
        _TUI_F_TL="┌"; _TUI_F_TR="┐"; _TUI_F_BL="└"; _TUI_F_BR="┘"
        _TUI_F_H="─";  _TUI_F_V="│"
    fi
}

# A locale that is not UTF-8 will render the box characters as several bytes of
# nonsense, and the linux console before a font is loaded is the usual place
# that happens -- which is to say, exactly where this tool gets used.
_tui_frame_unicode_ok() {
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8*|*utf8*|*UTF8*|*utf-8*) ;;
        *) return 1 ;;
    esac
    [[ "${TERM:-}" != "linux" ]]
}

# How wide the frame may be. Narrow terminals are real -- a serial console is
# 80, a phone over ssh is less -- and a frame wider than the terminal wraps into
# a mess that hides the text it was meant to set apart.
_tui_frame_width() {
    local w
    # Whatever the last probe found. Re-measuring here would fork an stty for
    # every frame drawn, and would overwrite a size a caller set deliberately --
    # which is how this gets tested at widths no real terminal is.
    [[ -n "${TUI_COLS:-}" ]] || tui_size 2>/dev/null || true
    w="${TUI_COLS:-80}"
    [[ "$w" =~ ^[0-9]+$ ]] || w=80
    (( w > 100 )) && w=100
    (( w < 20 ))  && w=20
    printf '%d' $(( w - 2 ))
}

# Cheap repeat, without seq or a loop per character.
_tui_frame_rep() {
    local c="$1" n="$2" out=""
    (( n > 0 )) || return 0
    printf -v out '%*s' "$n" ''
    printf '%s' "${out// /$c}"
}

# The visible width of a string. Not the byte count: a box drawn with the
# byte count is a box that gets wider every time somebody puts a é in a title.
_tui_frame_vis() {
    local s="$1"
    # Strip any styling first, then count characters rather than bytes.
    s="$(printf '%s' "$s" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')"
    printf '%d' "${#s}"
}

#[pub]
# Open a frame. Everything said until it closes sits inside it.
# Usage: tui_frame_open <title>
tui_frame_open() {
    local title="${1:-}"
    _TUI_FRAME_TITLE="$title"
    _TUI_FRAME_OPEN=1
    TUI_FRAME_WIDTH="$(_tui_frame_width)"

    if ! tui_is_tty; then
        # In a log, a frame is a heading. The information is the same and the
        # shape is what that medium uses for it.
        [[ -n "$title" ]] && printf '%s\n' "$title"
        return 0
    fi

    _tui_frame_glyphs
    local bar t_len
    t_len="$(_tui_frame_vis "$title")"
    if [[ -n "$title" ]] && (( t_len + 4 <= TUI_FRAME_WIDTH )); then
        bar="$(_tui_frame_rep "$_TUI_F_H" $(( TUI_FRAME_WIDTH - t_len - 3 )))"
        printf '%s%s%s %s%s%s %s%s%s\n' \
            "${DIM}" "$_TUI_F_TL" "$_TUI_F_H" "${NC}${BOLD}" "$title" "${NC}${DIM}" \
            "$bar" "$_TUI_F_TR" "${NC}"
    else
        bar="$(_tui_frame_rep "$_TUI_F_H" "$TUI_FRAME_WIDTH")"
        printf '%s%s%s%s%s\n' "${DIM}" "$_TUI_F_TL" "$bar" "$_TUI_F_TR" "${NC}"
    fi
}

#[pub]
# One line inside the open frame. Longer than the frame is truncated rather
# than wrapped: a wrapped line breaks the right-hand border and makes the whole
# thing look broken, and a line that long is a line that wanted to be two.
# Usage: tui_frame_say <text>
tui_frame_say() {
    local text="${1:-}"
    if (( _TUI_FRAME_OPEN == 0 )) || ! tui_is_tty; then
        printf '%s\n' "$text"
        return 0
    fi

    local inner=$(( TUI_FRAME_WIDTH - 2 )) len pad
    len="$(_tui_frame_vis "$text")"
    if (( len > inner )); then
        text="${text:0:$(( inner - 1 ))}…"
        len="$inner"
    fi
    pad="$(_tui_frame_rep " " $(( inner - len )))"
    printf '%s%s%s %s%s %s%s%s\n' \
        "${DIM}" "$_TUI_F_V" "${NC}" "$text" "$pad" "${DIM}" "$_TUI_F_V" "${NC}"
}

#[pub]
# Close the frame.
# Usage: tui_frame_close
tui_frame_close() {
    if (( _TUI_FRAME_OPEN == 0 )); then return 0; fi
    _TUI_FRAME_OPEN=0
    if ! tui_is_tty; then printf '\n'; return 0; fi
    local bar; bar="$(_tui_frame_rep "$_TUI_F_H" "$TUI_FRAME_WIDTH")"
    printf '%s%s%s%s%s\n' "${DIM}" "$_TUI_F_BL" "$bar" "$_TUI_F_BR" "${NC}"
}

#[pub]
# A whole frame in one call, for the common case of saying a few fixed lines.
# Usage: tui_frame_box <title> [line...]
tui_frame_box() {
    local title="${1:-}"; shift 2>/dev/null || true
    tui_frame_open "$title"
    local l
    for l in "$@"; do tui_frame_say "$l"; done
    tui_frame_close
}

#[pub]
# Run something whose output belongs to it, not to us. Nothing is framed,
# nothing is captured, nothing is reformatted -- it streams exactly as it would
# have without us. The frame is a claim about authorship and this output is
# somebody else's.
# Usage: tui_frame_foreign <command> [args...] -> returns the command's status
tui_frame_foreign() {
    local was="$_TUI_FRAME_OPEN"
    (( was == 1 )) && tui_frame_close
    "$@"
    local rc=$?
    (( was == 1 )) && tui_frame_open "$_TUI_FRAME_TITLE"
    return "$rc"
}
