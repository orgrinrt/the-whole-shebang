#!/usr/bin/env bash
# Tests for waiting until the machine has cooled.
#
# The sleep is a counter and the sensors are files, so a wait of minutes runs in
# no time. What is pinned is when the wait ends: never before the minimum, at the
# threshold once the minimum is past, at the maximum when it never cools, and at
# the minimum when nothing can be read.

use test deps

. "${BASH_SOURCE[0]%/*}/../libs/host/cooldown.sh"

_c_setup() {
    R="$(mktemp -d)"; mkdir -p "$R/sys/class/thermal/thermal_zone0" "$R/sys/class/hwmon/hwmon0"
    SLEPT=0
    _tick() { SLEPT=$(( SLEPT + 1 )); [[ -n "${COOL_AT:-}" && "$SLEPT" -ge "$COOL_AT" ]] && printf '40000\n' > "$R/sys/class/hwmon/hwmon0/temp1_input"; return 0; }
    HOST_SLEEP=_tick HOST_ROOT="$R"
    # `deps` finds a tool on the path and never a shell function, so the fake is a
    # program, and a miss `deps` remembered from an earlier test is forgotten.
    mkdir -p "$R/bin"; printf '#!/bin/sh\nexit 1\n' > "$R/bin/pmset"; chmod +x "$R/bin/pmset"
    _C_PATH="$PATH"; PATH="$R/bin:$PATH"; export PATH; deps_forget pmset
}

_c_end() { PATH="$_C_PATH"; export PATH; deps_forget pmset; rm -rf "$R"; }

#[test]
it_reads_the_hottest_sensor_in_whole_degrees() {
    _c_setup
    printf '45000\n' > "$R/sys/class/thermal/thermal_zone0/temp"
    printf '71500\n' > "$R/sys/class/hwmon/hwmon0/temp1_input"
    assert_eq "$(host_temp_c)" "71"
    _c_end
}

#[test]
it_waits_the_minimum_even_when_cool() {
    _c_setup
    printf '30000\n' > "$R/sys/class/thermal/thermal_zone0/temp"
    host_cooldown 10 100 55 5
    assert_eq "$HOST_COOL_HOW" "temp"
    assert_eq "$HOST_COOL_WAITED" "10"
    _c_end
}

#[test]
it_waits_until_the_threshold_once_past_the_minimum() {
    _c_setup
    printf '80000\n' > "$R/sys/class/hwmon/hwmon0/temp1_input"
    COOL_AT=23 host_cooldown 10 100 55 5
    assert_eq "$HOST_COOL_HOW" "temp"
    assert_eq "$HOST_COOL_WAITED" "25"
    assert_eq "$HOST_COOL_TEMP" "40"
    _c_end
}

#[test]
it_gives_up_at_the_maximum() {
    _c_setup
    printf '90000\n' > "$R/sys/class/hwmon/hwmon0/temp1_input"
    host_cooldown 5 30 55 7
    assert_eq "$HOST_COOL_HOW" "max"
    assert_eq "$HOST_COOL_WAITED" "30"
    _c_end
}

#[test]
it_waits_a_fixed_time_where_nothing_is_readable() {
    _c_setup
    host_cooldown 12 300 55
    assert_eq "$HOST_COOL_HOW" "fixed"
    assert_eq "$HOST_COOL_WAITED" "12"
    _c_end
}

#[test]
it_waits_for_the_speed_limit_where_only_that_is_readable() {
    _c_setup
    LIMIT=70
    printf '#!/bin/sh\nprintf "CPU_Speed_Limit \\t= %%s\\n" "$(cat "%s/limit")"\n' "$R" > "$R/bin/pmset"
    printf '%s\n' "$LIMIT" > "$R/limit"
    _tick() { SLEPT=$(( SLEPT + 1 )); [[ "$SLEPT" -ge 8 ]] && printf '100\n' > "$R/limit"; return 0; }
    host_cooldown 2 60 55 3
    assert_eq "$HOST_COOL_HOW" "throttle"
    assert_eq "$HOST_COOL_WAITED" "8"
    _c_end
}
