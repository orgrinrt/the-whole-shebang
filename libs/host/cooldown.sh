#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/host/cooldown - Wait for the machine to cool before the next thing
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# A bench run right after another one measures the first one's heat as much as
# its own work: the clock is down and the fans are up. So between two steps this
# waits until the hottest sensor the system exposes is back under a threshold,
# never less than a minimum and never more than a maximum.
#
# What can be read differs. Linux has thermal zones and hwmon, readable by
# anybody. macOS gives no temperature without root, and what it does give is
# whether the CPU is being held back (`pmset -g therm`), so there the wait is for
# the speed limit to be back at 100. Where neither is readable the wait is the
# minimum, fixed, and the result says so.
#
# POSIX. The clock and the sleep are replaceable so a test runs in no time.
#
# Usage:
#   use shebang::host::cooldown
#
#   host_cooldown 30 300 55        # at least 30s, at most 300s, until under 55 C
#   printf '%s after %ss\n' "$HOST_COOL_HOW" "$HOST_COOL_WAITED"
# =============================================================================

[ -n "${_SHEBANG_HOST_COOLDOWN_SH:-}" ] && return 0
_SHEBANG_HOST_COOLDOWN_SH=1

use deps

HOST_ROOT="${HOST_ROOT:-}"
# How the last wait ended: `temp` (under the threshold), `throttle` (no longer
# held back), `max` (gave up at the maximum), `fixed` (nothing readable).
HOST_COOL_HOW="" HOST_COOL_WAITED=0 HOST_COOL_TEMP=""
# One second of waiting. A function, so a test can count instead of sleep.
HOST_SLEEP="${HOST_SLEEP:-sleep}"

#[pub]
# The hottest temperature readable without root, in whole degrees C, or nothing.
# Usage: host_temp_c -> 47
host_temp_c() {
    local f v max=""
    for f in "${HOST_ROOT}"/sys/class/thermal/thermal_zone*/temp "${HOST_ROOT}"/sys/class/hwmon/hwmon*/temp*_input; do
        [ -r "$f" ] || continue
        v="$(head -n 1 "$f" 2>/dev/null)"
        case "$v" in ''|*[!0-9]*) continue ;; esac
        # Millidegrees in both places; a sensor reporting 0 is a sensor not wired.
        [ "$v" -gt 0 ] || continue
        v=$(( v / 1000 ))
        { [ -z "$max" ] || [ "$v" -gt "$max" ]; } && max="$v"
    done
    [ -n "$max" ] && printf '%s' "$max"
}

#[pub]
# The CPU speed limit macOS reports, 100 when nothing holds it back, or nothing
# where it is not reported.
# Usage: host_speed_limit -> 100
host_speed_limit() {
    deps_has pmset || return 0
    deps_run pmset -g therm 2>/dev/null | sed -n 's/.*CPU_Speed_Limit[^0-9]*\([0-9]*\).*/\1/p' | head -n 1
}

#[pub]
# Wait for the machine to cool. Sets HOST_COOL_HOW, HOST_COOL_WAITED (seconds)
# and HOST_COOL_TEMP (the last reading, empty where none).
# Usage: host_cooldown <min seconds> <max seconds> <threshold C> [poll seconds]
host_cooldown() {
    local min="${1:-0}" max="${2:-0}" thr="${3:-60}" poll="${4:-5}" waited=0 t l
    [ "$max" -ge "$min" ] || max="$min"
    while [ "$waited" -lt "$min" ]; do "$HOST_SLEEP" 1; waited=$(( waited + 1 )); done
    t="$(host_temp_c)"; l=""
    [ -n "$t" ] || l="$(host_speed_limit)"
    if [ -z "$t" ] && [ -z "$l" ]; then
        HOST_COOL_HOW="fixed" HOST_COOL_WAITED="$waited" HOST_COOL_TEMP=""
        return 0
    fi
    while :; do
        if [ -n "$t" ]; then
            [ "$t" -le "$thr" ] && { HOST_COOL_HOW="temp"; break; }
        else
            [ "${l:-100}" -ge 100 ] && { HOST_COOL_HOW="throttle"; break; }
        fi
        [ "$waited" -ge "$max" ] && { HOST_COOL_HOW="max"; break; }
        local i=0
        while [ "$i" -lt "$poll" ] && [ "$waited" -lt "$max" ]; do
            "$HOST_SLEEP" 1; waited=$(( waited + 1 )); i=$(( i + 1 ))
        done
        if [ -n "$t" ]; then t="$(host_temp_c)"; [ -n "$t" ] || t="$thr"
        else l="$(host_speed_limit)"; fi
    done
    HOST_COOL_WAITED="$waited" HOST_COOL_TEMP="$t"
}
