#!/usr/bin/env bash
# Tests for the frame.
#
# A frame is a claim about who is speaking, so the two failures that matter are
# a border that does not line up (which reads as a broken program) and control
# bytes written where there is no terminal (which corrupts a log or a pipe).
# Both are checked at sizes and in locales nobody would run by hand.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/frame.sh"

_strip() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' <<<"$1"; }
# The distinct character widths of the visible lines. Counted in bash, because
# awk's length() counts bytes and the box characters are three bytes each --
# which would make every unicode frame look crooked to a test that is wrong.
_widths() {
    local l
    while IFS= read -r l; do
        [[ -n "$l" ]] || continue
        printf '%d\n' "${#l}"
    done < <(_strip "$1") | sort -n | uniq
}

# --- with no terminal ---------------------------------------------------------

#[test]
it_writes_no_control_bytes_when_there_is_no_terminal() {
    TUI_TTY=0
    local out; out="$(tui_frame_box "Title" "one" "two")"
    # An escape byte in a pipe is a corrupted file, not a styled one.
    assert_fails grep -q $'\x1b' <<<"$out"
}

#[test]
it_still_says_everything_when_there_is_no_terminal() {
    TUI_TTY=0
    local out; out="$(tui_frame_box "Checking" "first line" "second line")"
    assert_ok grep -q 'Checking'    <<<"$out"
    assert_ok grep -q 'first line'  <<<"$out"
    assert_ok grep -q 'second line' <<<"$out"
}

#[test]
it_draws_no_border_when_there_is_no_terminal() {
    TUI_TTY=0
    local out; out="$(tui_frame_box "Title" "body")"
    assert_fails grep -q '[│┌└|+]' <<<"$out"
}

#[test]
it_does_not_truncate_when_there_is_no_terminal() {
    TUI_TTY=0
    local long="a line that is far longer than eighty characters and would be cut short if this were being drawn inside a border on a narrow terminal somewhere"
    local out; out="$(TUI_COLS=40 tui_frame_box "T" "$long")"
    # A log has no width. Cutting here would lose the end of a message that
    # was the reason somebody opened the log.
    assert_ok grep -qF "$long" <<<"$out"
}

# --- borders that line up -----------------------------------------------------

#[test]
it_draws_every_line_the_same_width() {
    TUI_TTY=1
    local out w
    out="$(TUI_COLS=60 tui_frame_box "Checking the disk" "short" "" "a bit longer")"
    w="$(_widths "$out")"
    # One distinct width, or the box is crooked.
    assert_eq "$(grep -c . <<<"$w")" "1"
}

#[test]
it_lines_up_at_every_terminal_width_that_has_room_for_a_border() {
    TUI_TTY=1
    local c out w
    for c in 24 25 30 40 60 80 100 120 200; do
        out="$(TUI_COLS=$c tui_frame_box "A title here" "some body text" "and more")"
        w="$(_widths "$out")"
        assert_eq "$(grep -c . <<<"$w")" "1"
    done
}

#[test]
it_lines_up_with_no_title_at_all() {
    TUI_TTY=1
    local out w; out="$(TUI_COLS=50 tui_frame_box "" "body")"
    w="$(_widths "$out")"
    assert_eq "$(grep -c . <<<"$w")" "1"
}

#[test]
it_lines_up_when_the_title_is_longer_than_the_frame() {
    TUI_TTY=1
    local out w
    out="$(TUI_COLS=30 tui_frame_box "a title considerably wider than the frame it is meant to sit in" "body")"
    w="$(_widths "$out")"
    # It falls back to a plain top border rather than pushing the corner out.
    assert_eq "$(grep -c . <<<"$w")" "1"
}

#[test]
it_never_draws_wider_than_the_terminal() {
    TUI_TTY=1
    local c out w
    for c in 20 40 80; do
        out="$(TUI_COLS=$c tui_frame_box "T" "body")"
        w="$(_widths "$out" | head -1)"
        assert_ok test "$w" -le "$c"
    done
}

#[test]
it_drops_the_border_rather_than_wrapping_on_a_narrow_terminal() {
    TUI_TTY=1
    # Serial consoles and phones over ssh are real. A border needs room for
    # two edges, two spaces and some words; below that the border is what goes,
    # because a box wider than the screen wraps and the right edge lands under
    # the left one.
    local c out
    for c in 5 10 15 19 20 23; do
        out="$(TUI_COLS=$c tui_frame_box "T" "body")"
        out="$(_strip "$out")"
        assert_fails grep -q '[│┌└|+]' <<<"$out"
        assert_ok    grep -q 'body'    <<<"$out"
    done
}

#[test]
it_never_draws_wider_than_the_terminal_at_any_size() {
    TUI_TTY=1
    # The assertion that was written but only ever run at 20 and above, which
    # is one value short of where it failed.
    local c out w
    for c in 5 10 15 19 20 23 24 40 80; do
        out="$(TUI_COLS=$c tui_frame_box "T" "body")"
        for w in $(_widths "$out"); do
            assert_ok test "$w" -le "$c"
        done
    done
}

#[test]
it_does_not_run_away_on_an_enormous_terminal() {
    TUI_TTY=1
    local out w; out="$(TUI_COLS=400 tui_frame_box "T" "body")"
    w="$(_widths "$out" | head -1)"
    # A frame the width of an ultrawide is unreadable; it is capped.
    assert_ok test "$w" -le 100
}

# --- truncation ---------------------------------------------------------------

#[test]
it_keeps_the_border_when_a_line_is_cut() {
    TUI_TTY=1
    local out w; out="$(TUI_COLS=40 tui_frame_box "T" "$(printf 'x%.0s' {1..200})")"
    w="$(_widths "$out")"
    assert_eq "$(grep -c . <<<"$w")" "1"
}

# --- the glyphs ----------------------------------------------------------------

#[test]
it_uses_plain_ascii_when_told_to() {
    TUI_TTY=1
    local out; out="$(TUI_FRAME_ASCII=1 TUI_COLS=40 tui_frame_box "T" "body")"
    out="$(_strip "$out")"
    assert_ok    grep -q '[+|-]' <<<"$out"
    assert_fails grep -q '[│┌└]' <<<"$out"
}

#[test]
it_uses_plain_ascii_in_a_locale_that_cannot_show_the_others() {
    TUI_TTY=1
    local out
    out="$(LC_ALL=C LC_CTYPE=C LANG=C TUI_COLS=40 tui_frame_box "T" "body")"
    out="$(_strip "$out")"
    # Box characters in a non-UTF-8 locale render as several bytes of noise,
    # which reads as corruption to somebody already worried about corruption.
    assert_fails grep -q '[│┌└]' <<<"$out"
    # And the positive half, or producing nothing at all would pass.
    assert_ok grep -q '[+|-]' <<<"$out"
}

#[test]
it_uses_plain_ascii_on_the_linux_console() {
    TUI_TTY=1
    local out
    out="$(TERM=linux LANG=en_US.UTF-8 TUI_COLS=40 tui_frame_box "T" "body")"
    out="$(_strip "$out")"
    # Before a font is loaded the console cannot draw them, and that console is
    # exactly where a recovery tool gets used.
    assert_fails grep -q '[│┌└]' <<<"$out"
    assert_ok    grep -q '[+|-]' <<<"$out"
}

#[test]
it_lines_up_in_ascii_too() {
    TUI_TTY=1
    local out w; out="$(TUI_FRAME_ASCII=1 TUI_COLS=64 tui_frame_box "A title" "body" "more")"
    w="$(_widths "$out")"
    assert_eq "$(grep -c . <<<"$w")" "1"
}

# --- foreign output -------------------------------------------------------------

#[test]
it_leaves_another_programs_output_alone() {
    TUI_TTY=1
    local out
    TUI_COLS=40
    out="$(tui_frame_open "Ours"; tui_frame_foreign printf 'theirs %s\n' "verbatim"; tui_frame_close)"
    # Not indented, not bordered, not cut. Reformatting somebody else's output
    # is how the line that mattered gets truncated.
    assert_ok grep -qx 'theirs verbatim' <<<"$(_strip "$out")"
}

#[test]
it_passes_back_what_the_foreign_command_returned() {
    TUI_TTY=0
    tui_frame_foreign true  >/dev/null 2>&1; assert_eq "$?" "0"
    tui_frame_foreign false >/dev/null 2>&1; assert_eq "$?" "1"
    tui_frame_foreign bash -c 'exit 42' >/dev/null 2>&1; assert_eq "$?" "42"
}

#[test]
it_reopens_the_frame_after_foreign_output() {
    TUI_TTY=1
    local out
    out="$(TUI_COLS=40; tui_frame_open "Ours"; tui_frame_foreign true; tui_frame_say "back inside"; tui_frame_close)"
    assert_ok grep -q 'back inside' <<<"$(_strip "$out")"
    # Two tops and two bottoms: the frame closed around the foreign call and
    # opened again after it.
    assert_eq "$(grep -c '[┌+]' <<<"$(_strip "$out")")" "2"
}

# --- being used wrongly ----------------------------------------------------------

#[test]
it_says_a_line_even_with_no_frame_open() {
    TUI_TTY=1
    local out; out="$(tui_frame_close; tui_frame_say "orphan")"
    assert_ok grep -q 'orphan' <<<"$(_strip "$out")"
}

#[test]
it_does_not_mind_being_closed_twice() {
    TUI_TTY=1
    local out; out="$(TUI_COLS=40; tui_frame_open T; tui_frame_close; tui_frame_close)"
    # One bottom border, not two.
    assert_eq "$(grep -c '[└+]' <<<"$(_strip "$out")")" "1"
}

#[test]
it_survives_a_terminal_size_that_is_not_a_number() {
    TUI_TTY=1
    # stty and $COLUMNS both hand over rubbish sometimes, and under set -u an
    # arithmetic context turns rubbish into a crash.
    local out; out="$(TUI_COLS=wide tui_frame_box "T" "body" 2>&1)"
    assert_ok test -n "$out"
    assert_fails grep -qi 'unbound\|syntax error' <<<"$out"
}

#[test]
it_survives_an_empty_body() {
    TUI_TTY=1
    local out; out="$(TUI_COLS=40 tui_frame_box "Just a title")"
    assert_eq "$(grep -c . <<<"$(_strip "$out")")" "2"
}

# --- state that exists before it is needed --------------------------------------
#
# The open flag used to be set before the branch that created the glyphs, so a
# frame opened before tui_probe, saying "reading config" as the first thing a
# tool says, left the flag claiming a frame was open with nothing behind it.
# The next line drawn died on an unbound variable, under set -u, on the way in.

#[test]
it_survives_a_frame_opened_before_the_terminal_was_probed() {
    local out rc
    out="$(set -u
        . "$NUTSHELL_INIT"
        . "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
        . "${BASH_SOURCE[0]%/*}/../libs/tui/frame.sh"
        tui_frame_open "Starting up"
        tui_frame_say  "reading config"
        TUI_TTY=1
        tui_frame_say  "config ok"
        tui_frame_close
        printf 'survived\n' 2>&1)" 
    rc=$?
    assert_ok    grep -q 'survived' <<<"$out"
    assert_fails grep -q 'unbound'  <<<"$out"
    assert_eq "$rc" "0"
}

#[test]
it_has_usable_glyphs_before_anything_opens_a_frame() {
    # Reading them, not drawing with them. The first version of this test never
    # opened a frame, so it never reached a glyph, and it passed against the
    # code that crashed, which makes it a test of nothing.
    local out
    out="$(set -u
        . "$NUTSHELL_INIT"
        . "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
        . "${BASH_SOURCE[0]%/*}/../libs/tui/frame.sh"
        printf 'v=[%s] h=[%s] tl=[%s] ell=[%s]\n' \
            "$_TUI_F_V" "$_TUI_F_H" "$_TUI_F_TL" "$_TUI_F_ELL"
    2>&1)"
    assert_fails grep -q 'unbound' <<<"$out"
    assert_fails grep -q 'v=\[\]'  <<<"$out"
    assert_fails grep -q 'h=\[\]'  <<<"$out"
    assert_ok    grep -q 'ell='    <<<"$out"
}

# --- cutting a line, in the locale the fallback exists for -----------------------

#[test]
it_cuts_with_a_mark_the_terminal_can_actually_draw() {
    TUI_TTY=1
    local out
    # An ellipsis is three bytes of UTF-8. Putting one inside an ASCII border
    # is the mojibake the ASCII border exists to avoid, arriving by the door
    # nobody was watching.
    out="$(TUI_FRAME_ASCII=1 TUI_COLS=40 tui_frame_box "T" "$(printf 'x%.0s' {1..200})")"
    assert_fails grep -q '…' <<<"$out"
    assert_ok    grep -q '\.\.\.' <<<"$out"
}

#[test]
it_uses_the_nicer_mark_when_the_terminal_can_draw_it() {
    TUI_TTY=1
    local out
    out="$(LC_ALL=en_US.UTF-8 TERM=xterm TUI_COLS=40 tui_frame_box "T" "$(printf 'x%.0s' {1..200})")"
    assert_ok grep -q '…' <<<"$out"
}

#[test]
it_does_not_cut_a_character_in_half() {
    TUI_TTY=1
    local body out
    body="$(printf '\xc3\xa9%.0s' {1..60})"
    out="$(LC_ALL=C LC_CTYPE=C LANG=C TUI_COLS=40 tui_frame_box 'T' "$body" 2>&1)"
    # Decoded rather than grepped. A lone lead byte is what a split character
    # leaves behind, and the byte-class greps that look like they would find it
    # do not. Checked: they match nothing either way.
    assert_ok python3 -c '
import sys
raw = sys.stdin.buffer.read()
raw.decode("utf-8")           # raises if the cut landed inside a character
' <<<"$out"
}

#[test]
it_has_a_detector_that_notices_a_split_character() {
    # The positive control for the test above, since the obvious grep for this
    # is silently powerless and passed on code that was actually broken.
    assert_fails python3 -c '
import sys
sys.stdin.buffer.read().decode("utf-8")
' <<<"$(printf 'xxx\xc3 |')"
}

#[test]
it_keeps_a_utf8_title_from_widening_the_box() {
    TUI_TTY=1
    local out w
    out="$(LC_ALL=en_US.UTF-8 TUI_COLS=60 tui_frame_box "Lähdön tarkistus" "runko" "pitkä rivi")"
    w="$(_widths "$out")"
    # The reason tui_frame_vis exists, and the input it was never given.
    assert_eq "$(grep -c . <<<"$w")" "1"
}

# --- several lines in one call ---------------------------------------------------

#[test]
it_frames_each_line_of_a_multi_line_string() {
    TUI_TTY=1
    local out
    out="$(TUI_COLS=40 tui_frame_box "T" "$(printf 'first\nsecond')")"
    out="$(_strip "$out")"
    # The obvious thing to hand this is a captured command's output. Treated as
    # one line, the first row loses its right border and the second loses its
    # left.
    assert_eq "$(grep -c . <<<"$out")" "4"
    assert_ok grep -q '│ first'  <<<"$out"
    assert_ok grep -q '│ second' <<<"$out"
}

#[test]
it_lines_up_when_a_body_line_contains_newlines() {
    TUI_TTY=1
    local out w
    out="$(TUI_COLS=48 tui_frame_box "T" "$(printf 'a\nbb\nccc')")"
    w="$(_widths "$out")"
    assert_eq "$(grep -c . <<<"$w")" "1"
}

# --- colour ------------------------------------------------------------------------

#[test]
it_writes_no_colour_when_the_terminal_said_no_colour() {
    TUI_TTY=1
    # The colour variables are set here on purpose. Left as the library found
    # them they are already empty, so the test would pass without the module
    # doing anything, and would be proving the wrong library's behaviour.
    local DIM=$'\033[2m' BOLD=$'\033[1m' NC=$'\033[0m'
    local out
    TUI_COLOR=0
    out="$(TUI_COLS=40 tui_frame_box "T" "body")"
    assert_fails grep -q $'\x1b' <<<"$out"

    # And the other way, or this proves only that nothing is ever coloured.
    TUI_COLOR=1
    out="$(TUI_COLS=40 tui_frame_box "T" "body")"
    assert_ok grep -q $'\x1b' <<<"$out"
}

# A POSIX shell to check against, or nothing. `sh` on macOS is bash in POSIX
# mode and draws the box perfectly, so testing against it proves nothing.
_frame_posix_sh() {
    local cand
    for cand in dash ash yash busybox-sh; do
        command -v "$cand" >/dev/null 2>&1 || continue
        # It has to refuse a bashism, or it is bash wearing a different name.
        printf 'declare -A x\n' > "${TMPDIR:-/tmp}/tui-fp.$$"
        if ! "$cand" -c ". '${TMPDIR:-/tmp}/tui-fp.$$'" >/dev/null 2>&1; then
            rm -f "${TMPDIR:-/tmp}/tui-fp.$$"; printf '%s' "$cand"; return 0
        fi
        rm -f "${TMPDIR:-/tmp}/tui-fp.$$"
    done
    return 1
}

#[test]
# The glyphs are real characters under a POSIX shell, not the escape text.
#
# This is the case that shipped. The corners were `┌` and friends handed
# to `printf '%b'`, and `%b` understands `\uHHHH` in bash and nowhere else:
# under `dash` it passes the six characters straight through. Every corner drew
# as the literal `┌` and every width count was six where one was assumed,
# so `tui_cut` was wrong too.
#
# It was invisible because `term.sh` does not parse under a POSIX shell yet, so
# `tui_unicode_ok` returns 127 there and the ASCII branch is taken by accident.
# The moment `term.sh` follows onto the floor, the accident stops.
#
# So this drives `_tui_frame_glyphs` directly with the unicode branch forced,
# rather than drawing a frame and hoping the branch was reached. A test that
# only exercises the path that already works is what let this through.
it_uses_real_glyphs_under_a_posix_shell() {
    local sh; sh="$(_frame_posix_sh)" || { skip "no strict POSIX shell here"; return 0; }
    local root="${BASH_SOURCE[0]%/*}/.."

    local got
    got="$("$sh" -c '
        # `frame.sh` returns early unless nutshell is loaded, and loading
        # nutshell under a POSIX shell is a different problem. The guard only
        # wants `use` to exist, and nothing in the glyph path calls it.
        use() { return 0; }
        . "$1"/libs/tui/frame.sh 2>/dev/null
        _tui_frame_unicode_ok() { return 0; }
        TUI_FRAME_ASCII=0
        _tui_frame_glyphs
        printf "%s%s%s" "$_TUI_F_TL" "$_TUI_F_H" "$_TUI_F_ELL"
    ' _ "$root" 2>/dev/null)"

    # The escape text must not survive into the output.
    assert_not_contains "$got" 'u250c'
    assert_not_contains "$got" '\'

    # And it is the same bytes bash produces from the same code.
    local want
    want="$(bash -c '
        # `frame.sh` returns early unless nutshell is loaded, and loading
        # nutshell under a POSIX shell is a different problem. The guard only
        # wants `use` to exist, and nothing in the glyph path calls it.
        use() { return 0; }
        . "$1"/libs/tui/frame.sh 2>/dev/null
        _tui_frame_unicode_ok() { return 0; }
        TUI_FRAME_ASCII=0
        _tui_frame_glyphs
        printf "%s%s%s" "$_TUI_F_TL" "$_TUI_F_H" "$_TUI_F_ELL"
    ' _ "$root" 2>/dev/null)"
    assert_eq "$got" "$want"
}

#[test]
# The corner is one character, which is what every width calculation assumes.
#
# The escape-text bug made it six, and a byte count is the cheapest way to say
# so without depending on how the shell counts characters.
it_draws_a_corner_that_is_one_character_wide() {
    local sh; sh="$(_frame_posix_sh)" || { skip "no strict POSIX shell here"; return 0; }
    local root="${BASH_SOURCE[0]%/*}/.."

    local n
    n="$("$sh" -c '
        # `frame.sh` returns early unless nutshell is loaded, and loading
        # nutshell under a POSIX shell is a different problem. The guard only
        # wants `use` to exist, and nothing in the glyph path calls it.
        use() { return 0; }
        . "$1"/libs/tui/frame.sh 2>/dev/null
        _tui_frame_unicode_ok() { return 0; }
        TUI_FRAME_ASCII=0
        _tui_frame_glyphs
        printf "%s" "$_TUI_F_TL"
    ' _ "$root" 2>/dev/null | wc -c | tr -d ' ')"

    # Three bytes of UTF-8, one character. Six would be the escape text.
    assert_eq "$n" "3"
}
