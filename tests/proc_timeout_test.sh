#!/usr/bin/env bash
# Tests for running a command under a limit.
#
# Three endings have to stay apart, because a run of steps does something
# different after each: the command's own status, the limit (124), and Ctrl-C
# (130). And a stopped command has to be stopped whole, its children with it.

use test

. "${BASH_SOURCE[0]%/*}/../libs/proc/timeout.sh"

PROC_GRACE=1

#[test]
it_passes_the_commands_own_status_through() {
    proc_timeout 10 sh -c 'exit 7'; assert_eq "$?" "7"
    proc_timeout 0 true; assert_eq "$?" "0"
}

#[test]
it_says_124_at_the_limit_and_ends_the_children_too() {
    local t0; t0="$(date +%s)"
    proc_timeout 1 sh -c 'sleep 41 & sleep 41; wait'; assert_eq "$?" "124"
    assert_eq "$(( $(date +%s) - t0 < 5 ))" "1"
    sleep 0.2
    assert_eq "$(pgrep -f 'sleep 4[1]' | wc -l | tr -d ' ')" "0"
}

#[test]
it_says_130_on_an_interrupt_and_remembers_it() {
    local me=$BASHPID
    proc_timeout 20 sh -c "sleep 0.3; kill -INT $me; exec sleep 42"; assert_eq "$?" "130"
    assert_eq "$PROC_INTERRUPTED" "1"
    assert_eq "$(pgrep -f 'sleep 4[2]' | wc -l | tr -d ' ')" "0"
    # The next command is not reported as interrupted for an earlier one.
    proc_timeout 5 true; assert_eq "$?" "0"
}

#[test]
it_closes_standard_input_so_a_reader_does_not_hang() {
    proc_timeout 3 sh -c 'read -r x; exit 5'; assert_eq "$?" "5"
}
