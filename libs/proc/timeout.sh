#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/proc/timeout - Run one command under a time limit, and stop it cleanly
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# coreutils has `timeout` and macOS does not, and neither knows what a caller
# wants from Ctrl-C in the middle of a long run of steps: that the step running
# now ends, and the run around it gets to write down what it had. So this runs
# the command in a process group of its own, which a limit or an interrupt can
# end whole (a cargo build is a tree of processes, and killing only its root
# leaves the rest compiling), and tells the two apart in the exit status.
#
#   124  the limit was reached, as coreutils says it
#   130  Ctrl-C arrived while it ran; PROC_INTERRUPTED is then 1
#
# Standard input is closed for the command: it is in a background process group,
# and one that reads the terminal is stopped by the kernel, which looks like a
# hang. Its output goes where the caller's goes.
#
# Usage:
#   use shebang::proc::timeout
#
#   proc_timeout 600 cargo mock bench run hash-mix
#   case $? in 124) echo "timed out" ;; 130) echo "stopped" ;; esac
# =============================================================================

[[ -n "${_SHEBANG_PROC_TIMEOUT_SH:-}" ]] && return 0
readonly _SHEBANG_PROC_TIMEOUT_SH=1

# Set by an interrupt during a run, and left set, so a caller running many steps
# reads it once after each and stops starting new ones.
declare -g PROC_INTERRUPTED=0
# How long a command is given between the polite signal and the final one.
declare -g PROC_GRACE="${PROC_GRACE:-5}"

#[pub]
# Run <command> for at most <seconds>. Returns its status, 124 on the limit, 130
# on Ctrl-C. A limit of 0 means none.
# Usage: proc_timeout <seconds> <command> [args...]
proc_timeout() {
    local secs="$1"; shift
    local mark; mark="$(mktemp)" || return 1
    rm -f "$mark"
    local had_m=0; [[ $- == *m* ]] && had_m=1
    set -m
    "$@" </dev/null &
    local pid=$! dog=""
    if (( secs > 0 )); then
        ( sleep "$secs"; : > "$mark"; kill -TERM -- "-$pid" 2>/dev/null
          sleep "$PROC_GRACE"; kill -KILL -- "-$pid" 2>/dev/null ) >/dev/null 2>&1 &
        dog=$!
    fi
    (( had_m )) || set +m

    local prev; prev="$(trap -p INT)"
    _PROC_INT_NOW=0
    trap 'PROC_INTERRUPTED=1; _PROC_INT_NOW=1; kill -INT -- "-'"$pid"'" 2>/dev/null' INT

    local rc
    while :; do
        wait "$pid"; rc=$?
        # A trapped signal ends `wait` early with a status over 128 while the
        # command is still going; wait again until it has really ended.
        kill -0 "$pid" 2>/dev/null || break
        if (( _PROC_INT_NOW )); then
            sleep "$PROC_GRACE"; kill -KILL -- "-$pid" 2>/dev/null
        fi
    done

    if [[ -n "$dog" ]]; then kill -- "-$dog" 2>/dev/null; wait "$dog" 2>/dev/null; fi
    # A stopped command's group can outlive its leader: a child forked in the
    # moment the signal arrived. The group id lasts while any member does, so
    # what is left of it is ended too.
    if [[ -e "$mark" ]] || (( _PROC_INT_NOW )); then kill -KILL -- "-$pid" 2>/dev/null; fi
    if [[ -n "$prev" ]]; then eval "$prev"; else trap - INT; fi

    if [[ -e "$mark" ]]; then rm -f "$mark"; return 124; fi
    (( _PROC_INT_NOW )) && return 130
    return "$rc"
}
