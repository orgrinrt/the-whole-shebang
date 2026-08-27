#!/usr/bin/env bash
# Tests for the key reader.
#
# Fed from a redirect rather than a terminal, which works because the reader
# takes stdin and does not care where it came from. Process substitution keeps
# it in the current shell, so TUI_KEY survives for the assertion; a pipe would
# fork and the variable would never come back.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/key.sh"

# Feed bytes in, get the name out.
key_of() {
    tui_key_read < <(printf '%b' "$1") >/dev/null 2>&1
    printf '%s' "$TUI_KEY"
}

# --- the sequence table, tested directly -------------------------------------

#[test]
it_names_the_arrows() {
    assert_eq "$(_tui_key_from_csi A)" "up"
    assert_eq "$(_tui_key_from_csi B)" "down"
    assert_eq "$(_tui_key_from_csi C)" "right"
    assert_eq "$(_tui_key_from_csi D)" "left"
}

#[test]
it_accepts_both_spellings_of_home_and_end() {
    # Terminals genuinely disagree here. Handling one spelling and not the
    # other is the bug this pins.
    assert_eq "$(_tui_key_from_csi H)"  "home"
    assert_eq "$(_tui_key_from_csi 1~)" "home"
    assert_eq "$(_tui_key_from_csi 7~)" "home"
    assert_eq "$(_tui_key_from_csi F)"  "end"
    assert_eq "$(_tui_key_from_csi 4~)" "end"
    assert_eq "$(_tui_key_from_csi 8~)" "end"
}

#[test]
it_names_paging_and_editing_keys() {
    assert_eq "$(_tui_key_from_csi 5~)" "pgup"
    assert_eq "$(_tui_key_from_csi 6~)" "pgdn"
    assert_eq "$(_tui_key_from_csi 2~)" "insert"
    assert_eq "$(_tui_key_from_csi 3~)" "delete"
    assert_eq "$(_tui_key_from_csi Z)"  "shift-tab"
}

#[test]
it_says_unknown_rather_than_guessing() {
    # The control for the whole table. Without it every assertion above would
    # hold for a function that returned the same answer to everything.
    assert_eq "$(_tui_key_from_csi 'Q')"     "unknown"
    assert_eq "$(_tui_key_from_csi '99;9R')" "unknown"
}

# --- reading real bytes ------------------------------------------------------

#[test]
it_reads_an_arrow_sequence_end_to_end() {
    assert_eq "$(key_of '\033[A')" "up"
    assert_eq "$(key_of '\033[B')" "down"
}

#[test]
it_reads_the_application_cursor_form() {
    # Terminals in application mode send ESC O A rather than ESC [ A. A reader
    # that only knew the bracket form would break inside less, vim and ssh.
    assert_eq "$(key_of '\033OA')" "up"
}

#[test]
it_treats_a_lone_escape_as_escape() {
    # The hard case: indistinguishable from a sequence start except by waiting.
    assert_eq "$(key_of '\033')" "esc"
}

#[test]
it_reads_alt_as_escape_then_letter() {
    assert_eq "$(key_of '\033x')" "alt-x"
}

#[test]
it_names_the_control_characters() {
    assert_eq "$(key_of '\n')"    "enter"
    assert_eq "$(key_of '\r')"    "enter"
    assert_eq "$(key_of '\t')"    "tab"
    assert_eq "$(key_of '\003')"  "ctrl-c"
    assert_eq "$(key_of '\004')"  "ctrl-d"
    assert_eq "$(key_of '\177')"  "backspace"
    assert_eq "$(key_of ' ')"     "space"
}

#[test]
it_passes_an_ordinary_letter_through() {
    assert_eq "$(key_of 'a')" "a"
    assert_eq "$(key_of 'Z')" "Z"
    assert_eq "$(key_of '7')" "7"
}

#[test]
it_reports_end_of_input() {
    # A caller looping on this needs a way to stop that is not an error.
    assert_fails tui_key_read < /dev/null
}

# --- meaning -----------------------------------------------------------------

#[test]
it_folds_every_spelling_of_down_together() {
    TUI_KEY="down"; assert_eq "$(tui_key_motion)" "down"
    TUI_KEY="j";    assert_eq "$(tui_key_motion)" "down"
    TUI_KEY="tab";  assert_eq "$(tui_key_motion)" "down"
    TUI_KEY=$'\016'; assert_eq "$(tui_key_motion)" "down"
}

#[test]
it_folds_every_spelling_of_up_together() {
    TUI_KEY="up";        assert_eq "$(tui_key_motion)" "up"
    TUI_KEY="k";         assert_eq "$(tui_key_motion)" "up"
    TUI_KEY="shift-tab"; assert_eq "$(tui_key_motion)" "up"
    TUI_KEY=$'\020';     assert_eq "$(tui_key_motion)" "up"
}

#[test]
it_folds_left_and_right() {
    TUI_KEY="h"; assert_eq "$(tui_key_motion)" "left"
    TUI_KEY="l"; assert_eq "$(tui_key_motion)" "right"
}

#[test]
it_passes_a_non_motion_key_through_unchanged() {
    # The control for the folding: a function that answered "down" to
    # everything would satisfy the tests above.
    TUI_KEY="a";     assert_eq "$(tui_key_motion)" "a"
    TUI_KEY="enter"; assert_eq "$(tui_key_motion)" "enter"
}

#[test]
it_knows_accept_from_cancel() {
    TUI_KEY="enter";  assert_ok    tui_key_is_accept
    TUI_KEY="space";  assert_ok    tui_key_is_accept
    TUI_KEY="esc";    assert_fails tui_key_is_accept
    TUI_KEY="esc";    assert_ok    tui_key_is_cancel
    TUI_KEY="q";      assert_ok    tui_key_is_cancel
    TUI_KEY="ctrl-c"; assert_ok    tui_key_is_cancel
    TUI_KEY="enter";  assert_fails tui_key_is_cancel
}

#[test]
it_does_not_treat_an_ordinary_key_as_either_answer() {
    # Without this, both predicates could simply return true.
    TUI_KEY="a"
    assert_fails tui_key_is_accept
    assert_fails tui_key_is_cancel
}

#[test]
it_is_safe_to_source_twice() {
    assert_ok . "${BASH_SOURCE[0]%/*}/../libs/tui/key.sh"
}

# --- the same answer without a subshell --------------------------------------
#
# The absorb loop reads this every key, and a command substitution is a fork.
# `tools/absorb-cost-report` measures what one costs; the property asserted
# here is the one that makes the loop able to avoid it, which is that the
# answer survives in the caller's own shell.

#[test]
it_leaves_the_motion_in_a_variable() {
    TUI_MOTION=""
    TUI_KEY="j"
    tui_key_motion_now
    # No `$( )` anywhere above. A function that only printed would leave this
    # empty, which is precisely the failure being guarded against.
    assert_eq "$TUI_MOTION" "down"
}

#[test]
it_maps_every_key_to_the_motion_it_should() {
    # A literal table, not the other form of the same function.
    #
    # This used to call `tui_key_motion_now` and assert `$TUI_MOTION` equalled
    # `$(tui_key_motion)`. `tui_key_motion` is `tui_key_motion_now; printf
    # '%s' "$TUI_MOTION"`, so that compared a variable against itself: with the
    # whole `case` replaced by `TUI_MOTION=XXXX` it still passed while seven
    # sibling tests failed. Twenty-nine keys of it, which reads as thorough and
    # constrained nothing.
    local pair k want
    for pair in \
        'up:up' 'k:up' 'shift-tab:up' $'\020:up' \
        'down:down' 'j:down' 'tab:down' $'\016:down' \
        'left:left' 'h:left' $'\002:left' \
        'right:right' 'l:right' $'\006:right' \
        'enter:enter' 'q:q' '/:/' '?:?' '[:[' ']:]' \
        'home:home' 'end:end' 'pgup:pgup' 'pgdn:pgdn' \
        'ctrl-up:ctrl-up' 'ctrl-down:ctrl-down' 'alt-x:alt-x' \
        'esc:esc' 'backspace:backspace' ':'
    do
        k="${pair%:*}"; want="${pair#*:}"
        TUI_KEY="$k"; TUI_MOTION=""
        tui_key_motion_now
        assert_eq "$TUI_MOTION" "$want"
    done
}

#[test]
it_gives_the_same_answer_printed_as_it_leaves_in_the_variable() {
    # Worth one case rather than twenty-nine: the printing form is built on the
    # other, so this says they are still wired together and nothing more.
    TUI_KEY="k"; TUI_MOTION=""
    tui_key_motion_now
    assert_eq "$(tui_key_motion)" "$TUI_MOTION"
    assert_eq "$TUI_MOTION" "up"
}

#[test]
it_passes_through_a_key_that_is_not_movement() {
    TUI_KEY="enter"; tui_key_motion_now; assert_eq "$TUI_MOTION" "enter"
    TUI_KEY="q";     tui_key_motion_now; assert_eq "$TUI_MOTION" "q"
    TUI_KEY="";      tui_key_motion_now; assert_eq "$TUI_MOTION" ""
}

#[test]
it_overwrites_the_last_answer_rather_than_keeping_it() {
    # A loop reads this repeatedly. A stale value from the previous key would
    # absorb a keystroke that was meant to act on a row.
    TUI_KEY="down"; tui_key_motion_now
    TUI_KEY="enter"; tui_key_motion_now
    assert_eq "$TUI_MOTION" "enter"
}
