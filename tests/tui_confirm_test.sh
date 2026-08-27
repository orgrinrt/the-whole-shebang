#!/usr/bin/env bash
# Tests for the confirmations.
#
# The property that matters is the refusal, not the acceptance. Every one of
# these has to say no when it cannot ask, when the answer is empty, and when
# the answer is nearly right, because a confirmation that can be passed by
# accident is worse than none: it moves the blame without moving the risk.

use test

. "${BASH_SOURCE[0]%/*}/../libs/tui/term.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/key.sh"
. "${BASH_SOURCE[0]%/*}/../libs/tui/confirm.sh"

# The suite has no terminal, so the tty branch is exercised by forcing the flag
# and feeding stdin. That is honest: TUI_TTY is the module's own idea of
# whether it can ask, and every function reads it.
answer() {  # answer <input> <fn> [args...]
    local input="$1"; shift
    TUI_TTY=1
    "$@" <<< "$input" >/dev/null 2>&1
    local rc=$?
    TUI_TTY=0
    return $rc
}

# --- refusing when it cannot ask ---------------------------------------------

#[test]
it_refuses_every_confirmation_with_no_terminal() {
    # The one that matters most. An unattended run must not be able to fall
    # into a destructive branch because nothing was there to say no.
    TUI_TTY=0
    assert_fails tui_confirm "proceed?"
    assert_fails tui_confirm_typed "wipe?" ERASE
    assert_fails tui_confirm_name "destroy" /dev/sdb
}

#[test]
it_refuses_with_no_terminal_even_when_the_right_answer_is_on_stdin() {
    # The control for the test above: refusing must come from having no
    # terminal, not from failing to read the answer.
    TUI_TTY=0
    assert_fails tui_confirm       "proceed?" <<< "y"
    assert_fails tui_confirm_typed "wipe?" ERASE <<< "ERASE"
}

# --- yes or no ---------------------------------------------------------------

#[test]
it_accepts_the_spellings_of_yes() {
    assert_ok answer "y"   tui_confirm "?"
    assert_ok answer "Y"   tui_confirm "?"
    assert_ok answer "yes" tui_confirm "?"
    assert_ok answer "YES" tui_confirm "?"
    assert_ok answer "Yes" tui_confirm "?"
}

#[test]
it_defaults_to_no_on_an_empty_answer() {
    # Leaning on return is the commonest way a tired person answers. It has to
    # land on the harmless outcome.
    assert_fails answer "" tui_confirm "?"
}

#[test]
it_treats_anything_else_as_no() {
    assert_fails answer "n"     tui_confirm "?"
    assert_fails answer "no"    tui_confirm "?"
    assert_fails answer "maybe" tui_confirm "?"
    assert_fails answer "ye"    tui_confirm "?"
    assert_fails answer "yep"   tui_confirm "?"
}

# --- typed word --------------------------------------------------------------

#[test]
it_accepts_the_exact_word() {
    assert_ok answer "ERASE" tui_confirm_typed "?" "ERASE"
}

#[test]
it_rejects_the_wrong_case() {
    # A word answerable in lower case is a word answerable without reading it.
    assert_fails answer "erase" tui_confirm_typed "?" "ERASE"
    assert_fails answer "Erase" tui_confirm_typed "?" "ERASE"
}

#[test]
it_rejects_a_nearly_right_word() {
    assert_fails answer "ERAS"    tui_confirm_typed "?" "ERASE"
    assert_fails answer "ERASEE"  tui_confirm_typed "?" "ERASE"
    assert_fails answer " ERASE"  tui_confirm_typed "?" "ERASE"
    assert_fails answer "ERASE "  tui_confirm_typed "?" "ERASE"
    assert_fails answer ""        tui_confirm_typed "?" "ERASE"
    assert_fails answer "y"       tui_confirm_typed "?" "ERASE"
}

# --- typed name --------------------------------------------------------------

#[test]
it_accepts_the_exact_name() {
    assert_ok answer "/dev/sdb" tui_confirm_name "destroy" "/dev/sdb"
}

#[test]
it_rejects_a_different_device() {
    # The actual failure this defends against is not "did not mean yes", it is
    # "meant yes about a different disk". These two names differ by one byte.
    assert_fails answer "/dev/sda"  tui_confirm_name "destroy" "/dev/sdb"
    assert_fails answer "/dev/sdb1" tui_confirm_name "destroy" "/dev/sdb"
    assert_fails answer "sdb"       tui_confirm_name "destroy" "/dev/sdb"
    assert_fails answer "yes"       tui_confirm_name "destroy" "/dev/sdb"
    assert_fails answer ""          tui_confirm_name "destroy" "/dev/sdb"
}

#[test]
it_shows_the_detail_lines_it_was_given() {
    # The name alone is not enough to decide by; the size and model are what
    # tell a person whether it is the disk they meant.
    TUI_TTY=1
    local out
    out="$(tui_confirm_name "destroy" "/dev/sdb" "62.0 GB" "Kingston DataTraveler" <<< "/dev/sdb" 2>&1)"
    TUI_TTY=0
    assert_contains "$out" "62.0 GB"
    assert_contains "$out" "Kingston DataTraveler"
}

# --- the override ------------------------------------------------------------

#[test]
it_can_be_told_to_assume_yes() {
    TUI_TTY=0
    TUI_CONFIRM_ASSUME_YES=1
    assert_ok tui_confirm       "?"
    assert_ok tui_confirm_typed "?" "ERASE"
    assert_ok tui_confirm_name  "destroy" "/dev/sdb"
    TUI_CONFIRM_ASSUME_YES=0
}

#[test]
it_does_not_assume_yes_by_default() {
    # The control for the override. Without it, every acceptance test above
    # would pass against a module that always said yes.
    assert_eq "$TUI_CONFIRM_ASSUME_YES" "0"
    TUI_TTY=0
    assert_fails tui_confirm "?"
}

#[test]
it_is_safe_to_source_twice() {
    assert_ok . "${BASH_SOURCE[0]%/*}/../libs/tui/confirm.sh"
}
