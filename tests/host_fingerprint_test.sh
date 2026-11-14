#!/usr/bin/env bash
# Tests for reading what a machine is.
#
# The live machine is checked for the fields any Linux has, and the rest is fed
# from fixtures: a musl box with a battery, an Intel hybrid part, and an M1 from
# a file of sysctl answers. The label is checked for carrying no hostname.

use test

. "${BASH_SOURCE[0]%/*}/../libs/host/fingerprint.sh"

_f_root() {
    R="$(mktemp -d)"
    mkdir -p "$R/proc" "$R/lib" "$R/etc" "$R/sys/class/power_supply/BAT0" \
             "$R/sys/devices/system/cpu/cpu0/cpufreq" "$R/sys/devices/cpu_core" "$R/sys/devices/cpu_atom"
    printf 'processor\t: 0\nmodel name\t: 12th Gen Intel(R) Core(TM) i7-1260P\ncore id\t\t: 0\nflags\t\t: fpu sse4_2 avx avx2 fma bmi2 sha_ni\n' > "$R/proc/cpuinfo"
    printf 'processor\t: 1\ncore id\t\t: 1\n' >> "$R/proc/cpuinfo"
    printf 'MemTotal:       16000000 kB\n' > "$R/proc/meminfo"
    printf 'ID=alpine\n' > "$R/etc/os-release"
    : > "$R/lib/ld-musl-x86_64.so.1"
    printf 'Battery\n' > "$R/sys/class/power_supply/BAT0/type"
    printf 'Discharging\n' > "$R/sys/class/power_supply/BAT0/status"
    printf 'powersave\n' > "$R/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
    printf '0-3\n' > "$R/sys/devices/cpu_core/cpus"
    printf '4-11\n' > "$R/sys/devices/cpu_atom/cpus"
}

#[test]
it_reads_the_live_linux_machine() {
    host_fingerprint
    assert_eq "$HOST_OS" "linux"
    assert_ne "${HOST_CPUS:-0}" "0"
    assert_ne "${HOST_MEM:-}" ""
    assert_contains "$HOST_RUST_TARGET" "-unknown-linux-"
    assert_contains "$(host_fingerprint_print)" "rust_target="
}

#[test]
it_reads_a_musl_box_on_battery_from_a_fixture() {
    _f_root
    HOST_ROOT="$R" HOST_OS_OVERRIDE=linux HOST_ARCH_OVERRIDE=x86_64 host_fingerprint
    assert_eq "$HOST_LIBC" "musl"
    assert_eq "$HOST_RUST_TARGET" "x86_64-unknown-linux-musl"
    assert_eq "$HOST_DISTRO" "alpine"
    assert_eq "$HOST_POWER" "battery"
    assert_eq "$HOST_GOVERNOR" "powersave"
    assert_eq "$HOST_CPUS" "2"
    assert_eq "$HOST_CORES" "2"
    assert_eq "$HOST_PCORES" "4"
    assert_eq "$HOST_ECORES" "8"
    assert_eq "$HOST_ISA" "sse4_2 avx avx2 fma bmi2 sha_ni"
    assert_eq "$HOST_MEM" "16384000000"
    rm -rf "$R"
}

#[test]
it_reads_glibc_where_the_loader_is_glibc() {
    _f_root
    rm "$R/lib/ld-musl-x86_64.so.1"; mkdir -p "$R/lib64"; : > "$R/lib64/ld-linux-x86-64.so.2"
    HOST_ROOT="$R" HOST_OS_OVERRIDE=linux HOST_ARCH_OVERRIDE=x86_64 host_fingerprint
    assert_eq "$HOST_LIBC" "glibc"
    assert_eq "$HOST_RUST_TARGET" "x86_64-unknown-linux-gnu"
    rm -rf "$R"
}

#[test]
it_reads_an_m1_from_sysctl_answers() {
    local s; s="$(mktemp)"
    printf '%s\n' "machdep.cpu.brand_string: Apple M1" "hw.logicalcpu: 8" "hw.physicalcpu: 8" \
        "hw.perflevel0.physicalcpu: 4" "hw.perflevel1.physicalcpu: 4" "hw.memsize: 8589934592" \
        "hw.optional.arm.FEAT_LSE: 1" "hw.optional.arm.FEAT_DotProd: 1" "hw.optional.arm.FEAT_SHA3: 0" > "$s"
    HOST_SYSCTL_FILE="$s" HOST_OS_OVERRIDE=macos HOST_ARCH_OVERRIDE=arm64 host_fingerprint
    assert_eq "$HOST_ARCH" "aarch64"
    assert_eq "$HOST_LIBC" "darwin"
    assert_eq "$HOST_RUST_TARGET" "aarch64-apple-darwin"
    assert_eq "$HOST_PCORES" "4"
    assert_eq "$HOST_ECORES" "4"
    assert_eq "$HOST_ISA" "neon asimd atomics dotprod"
    assert_eq "$(host_label)" "macos-aarch64-apple-m1"
    rm -f "$s"
}

#[test]
it_labels_by_what_the_machine_is_and_never_by_its_name() {
    _f_root
    HOST_ROOT="$R" HOST_OS_OVERRIDE=linux HOST_ARCH_OVERRIDE=x86_64 host_fingerprint
    assert_eq "$(host_label)" "linux-x86_64-12th-gen-intel-core-i7-1260p"
    assert_not_contains "$(host_label)" "$(uname -n)"
    rm -rf "$R"
}
