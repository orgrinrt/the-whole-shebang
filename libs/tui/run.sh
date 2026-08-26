#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/run - Running something that owns the screen
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Depends on tui/term and tui/key, and nothing else in the collection.
#
# The temptation is to frame a running command's output inside the interface,
# scrolling it in a pane. That is the wrong trade for this kind of tool. A
# package install, an fsck or a chroot shell wants the whole terminal, its own
# colours, its own progress bars, and the user's real scrollback afterwards.
# Boxing it costs all of that to gain a border.
#
# So the screen is handed back for the duration and taken again after. Output
# goes where output goes, and the user can scroll up to it later, which is the
# first thing anyone does when something failed.
#
# What is added around it is small and worth having: a header saying what is
# about to run, the exit status stated in words rather than left implicit, and
# a pause afterwards so a failure is read rather than flashing past on the way
# back to the menu.
#
# Usage:
#   use shebang::tui::run
#
#   tui_run "Rebuilding the initramfs" mkinitcpio -P
#   tui_run_quiet "Probing disks" smartctl --scan     # no pause when it works
# =============================================================================

[[ -n "${_SHEBANG_TUI_RUN_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_RUN_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use color

declare -gi TUI_RUN_STATUS=0

# Wait for any key. Separate so the pause can be suppressed in tests and in
# unattended runs without threading a flag through everything.
_tui_run_pause() {
    tui_is_tty || return 0
    [[ "${TUI_RUN_NO_PAUSE:-0}" == "1" ]] && return 0
    printf '\n%spress any key%s ' "$DIM" "$NC"
    tui_raw_on
    tui_key_read >/dev/null 2>&1
    tui_raw_off
    printf '\n'
}

_tui_run_verdict() {
    if (( $1 == 0 )); then
        printf '\n%sdone%s\n' "$GREEN" "$NC"
    else
        # The number is included because it is the thing worth searching for
        # when the message above it turns out not to be the real reason.
        printf '\n%sfailed, exit %d%s\n' "$RED" "$1" "$NC"
    fi
}

#[pub]
# Run a command with the terminal handed back, then pause on the result.
#
# The pause happens whether it worked or not, because "it said done" is
# information the user came for as much as a failure is.
# Usage: tui_run <title> <command> [args...] -> sets TUI_RUN_STATUS, returns it
tui_run() {
    local title="$1"; shift
    TUI_RUN_STATUS=0
    tui_suspend _tui_run_body "$title" "$@" || TUI_RUN_STATUS=$?
    return $TUI_RUN_STATUS
}

#[pub]
# The same, but only pause when it fails. For the many small probes a
# diagnostic screen fires off, where stopping on every success is friction.
# Usage: tui_run_quiet <title> <command> [args...] -> sets TUI_RUN_STATUS
tui_run_quiet() {
    local title="$1"; shift
    TUI_RUN_STATUS=0
    tui_suspend _tui_run_body_quiet "$title" "$@" || TUI_RUN_STATUS=$?
    return $TUI_RUN_STATUS
}

_tui_run_body() {
    local title="$1" rc=0; shift
    printf '%s%s%s\n\n' "$BOLD" "$title" "$NC"
    "$@" || rc=$?
    _tui_run_verdict "$rc"
    _tui_run_pause
    return $rc
}

_tui_run_body_quiet() {
    local title="$1" rc=0; shift
    printf '%s%s%s\n\n' "$BOLD" "$title" "$NC"
    "$@" || rc=$?
    if (( rc != 0 )); then
        _tui_run_verdict "$rc"
        _tui_run_pause
    fi
    return $rc
}
