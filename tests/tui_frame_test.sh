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

# Every visible line of some framed output, styling stripped.
_lines() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' <<<"$1" | grep -c . ; }
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
it_lines_up_at_every_terminal_width() {
    TUI_TTY=1
    local c out w
    for c in 20 24 40 60 80 100 120 200; do
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
it_stays_readable_on_an_absurdly_narrow_terminal() {
    TUI_TTY=1
    # Serial consoles and phones over ssh are real. It must not divide by
    # anything or produce negative padding.
    local out; out="$(TUI_COLS=10 tui_frame_box "T" "body")"
    assert_ok test -n "$out"
    assert_eq "$(grep -c . <<<"$(_strip "$out")")" "3"
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
it_cuts_a_long_line_rather_than_wrapping_it() {
    TUI_TTY=1
    local out; out="$(TUI_COLS=40 tui_frame_box "T" "$(printf 'x%.0s' {1..200})")"
    # Four lines would mean it wrapped and broke the right border.
    assert_eq "$(grep -c . <<<"$(_strip "$out")")" "3"
}

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
