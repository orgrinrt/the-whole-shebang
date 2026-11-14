#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/host/fingerprint - What this machine is, for a result to carry
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# A timing means nothing without the machine it was taken on, so a run records
# the machine beside every result: the system and its kernel, the C library, the
# CPU and its cores (performance and efficiency apart where the CPU has both), the
# instruction set features a build can use, memory, and the power source and the
# frequency governor where they can be read without root.
#
# Read from files and from `sysctl`, never from a tool that needs installing. The
# root the files are read under and the sysctl answers are both replaceable, so a
# test feeds a musl box or an M1 from a fixture.
#
# POSIX on purpose, since the preflight on a bare machine runs it before anything
# else is installed.
#
# Usage:
#   use shebang::host::fingerprint
#
#   host_fingerprint            # sets the HOST_* fields
#   host_fingerprint_print      # key=value, one a line, stable order
#   host_label                  # linux-x86_64-intel-core-i7-1165g7
# =============================================================================

[ -n "${_SHEBANG_HOST_FINGERPRINT_SH:-}" ] && return 0
_SHEBANG_HOST_FINGERPRINT_SH=1

if ! command -v use >/dev/null 2>&1; then
    printf 'host: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use os

# The root /proc, /sys, /etc and /lib are read under, and a file of `name: value`
# lines standing in for sysctl. Both empty on a real machine.
HOST_ROOT="${HOST_ROOT:-}"
HOST_SYSCTL_FILE="${HOST_SYSCTL_FILE:-}"

# The fields, in the order they are printed.
_HOST_FIELDS="os distro kernel arch libc virt cpu cpus cores pcores ecores isa mem power governor rust_target"

# The ISA features worth naming, on both families. A bench result that differs
# between two machines is most often explained by one of these.
_HOST_ISA_X86="sse4_2 avx avx2 fma bmi2 avx512f avx512bw avx512vl avx512_vnni sha_ni aes vaes"
_HOST_ISA_ARM="neon asimd crc32 sha2 sha3 atomics fp16 dotprod sve sve2 i8mm bf16"

_host_sysctl() {
    if [ -n "$HOST_SYSCTL_FILE" ]; then
        sed -n "s/^$1: //p" "$HOST_SYSCTL_FILE" | head -n 1
    else
        sysctl -n "$1" 2>/dev/null
    fi
}
_host_read() { [ -r "${HOST_ROOT}$1" ] && head -n 1 "${HOST_ROOT}$1" 2>/dev/null; }

_host_linux_cpu() {
    local info="${HOST_ROOT}/proc/cpuinfo" flags f
    HOST_CPU="$(awk -F": *" '/^(model name|Model|Hardware)[ \t]*:/ { print $2; exit }' "$info" 2>/dev/null)"
    HOST_CPUS="$(grep -c '^processor' "$info" 2>/dev/null)"
    HOST_CORES="$(sed -n 's/^core id[[:space:]]*: //p' "$info" 2>/dev/null | sort -u | wc -l | tr -d ' ')"
    [ "${HOST_CORES:-0}" -gt 0 ] || HOST_CORES="$HOST_CPUS"
    # Intel hybrid parts list their two kinds of core under these two names.
    HOST_PCORES="$(_host_cpulist_count "/sys/devices/cpu_core/cpus")"
    HOST_ECORES="$(_host_cpulist_count "/sys/devices/cpu_atom/cpus")"
    flags=" $(awk -F": *" '/^(flags|Features)[ \t]*:/ { print $2; exit }' "$info" 2>/dev/null) "
    HOST_ISA=""
    for f in $_HOST_ISA_X86 $_HOST_ISA_ARM; do
        case "$flags" in *" $f "*) HOST_ISA="${HOST_ISA}${HOST_ISA:+ }$f" ;; esac
    done
    HOST_MEM="$(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\) kB/\1/p' "${HOST_ROOT}/proc/meminfo" 2>/dev/null)"
    [ -n "$HOST_MEM" ] && HOST_MEM=$(( HOST_MEM * 1024 ))
    HOST_GOVERNOR="$(_host_read /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
}

# `0-3,8-11` is eight. Empty when the file is not there.
_host_cpulist_count() {
    local list n=0 r a b
    list="$(_host_read "$1")" || return 0
    [ -n "$list" ] || return 0
    for r in $(printf '%s' "$list" | tr ',' ' '); do
        a="${r%-*}" b="${r#*-}"
        n=$(( n + b - a + 1 ))
    done
    printf '%s' "$n"
}

_host_macos_cpu() {
    local f
    HOST_CPU="$(_host_sysctl machdep.cpu.brand_string)"
    HOST_CPUS="$(_host_sysctl hw.logicalcpu)"
    HOST_CORES="$(_host_sysctl hw.physicalcpu)"
    HOST_PCORES="$(_host_sysctl hw.perflevel0.physicalcpu)"
    HOST_ECORES="$(_host_sysctl hw.perflevel1.physicalcpu)"
    HOST_MEM="$(_host_sysctl hw.memsize)"
    HOST_ISA=""
    if [ "$HOST_ARCH" = "aarch64" ] || [ "$HOST_ARCH" = "arm64" ]; then
        # Every Apple arm64 has these; the rest are asked for one by one.
        HOST_ISA="neon asimd"
        for f in FEAT_CRC32:crc32 FEAT_AES:aes FEAT_SHA256:sha2 FEAT_SHA3:sha3 \
                 FEAT_LSE:atomics FEAT_FP16:fp16 FEAT_DotProd:dotprod FEAT_I8MM:i8mm FEAT_BF16:bf16; do
            [ "$(_host_sysctl "hw.optional.arm.${f%%:*}")" = "1" ] && HOST_ISA="$HOST_ISA ${f#*:}"
        done
    else
        local feats; feats=" $(_host_sysctl machdep.cpu.features) $(_host_sysctl machdep.cpu.leaf7_features) "
        feats="$(printf '%s' "$feats" | tr 'A-Z.' 'a-z_')"
        for f in $_HOST_ISA_X86; do
            case "$feats" in *" $f "*|*" ${f%_*}${f##*_} "*) HOST_ISA="${HOST_ISA}${HOST_ISA:+ }$f" ;; esac
        done
    fi
    HOST_GOVERNOR=""
}

_host_libc() {
    case "$HOST_OS" in macos) printf 'darwin'; return 0 ;; esac
    local f
    for f in "${HOST_ROOT}"/lib/ld-musl-*.so.1; do [ -e "$f" ] && { printf 'musl'; return 0; }; done
    for f in "${HOST_ROOT}"/lib*/ld-linux*.so.* "${HOST_ROOT}"/lib/*/ld-linux*.so.*; do
        [ -e "$f" ] && { printf 'glibc'; return 0; }
    done
    printf 'unknown'
}

_host_power() {
    local d t on st seen=0
    if [ "$HOST_OS" = "macos" ]; then
        case "$(pmset -g batt 2>/dev/null | head -n 1)" in
            *"AC Power"*) printf 'ac' ;; *"Battery Power"*) printf 'battery' ;; *) printf 'unknown' ;;
        esac
        return 0
    fi
    for d in "${HOST_ROOT}"/sys/class/power_supply/*; do
        [ -r "$d/type" ] || continue
        t="$(head -n 1 "$d/type")"
        case "$t" in
            Mains|USB) on="$(head -n 1 "$d/online" 2>/dev/null)"; [ "$on" = 1 ] && { printf 'ac'; return 0; } ;;
            Battery)   st="$(head -n 1 "$d/status" 2>/dev/null)"; seen=1
                       [ "$st" = "Discharging" ] && { printf 'battery'; return 0; } ;;
        esac
    done
    [ "$seen" = 1 ] && printf 'ac' || printf 'unknown'
}

#[pub]
# Read the machine into the HOST_* fields: HOST_OS, HOST_DISTRO, HOST_KERNEL,
# HOST_ARCH, HOST_LIBC, HOST_VIRT, HOST_CPU, HOST_CPUS, HOST_CORES, HOST_PCORES,
# HOST_ECORES, HOST_ISA, HOST_MEM (bytes), HOST_POWER, HOST_GOVERNOR, HOST_RUST_TARGET.
# Usage: host_fingerprint
host_fingerprint() {
    HOST_OS="${HOST_OS_OVERRIDE:-$(os_name)}"
    HOST_ARCH="${HOST_ARCH_OVERRIDE:-$(uname -m 2>/dev/null)}"
    [ "$HOST_ARCH" = "arm64" ] && HOST_ARCH="aarch64"
    HOST_KERNEL="${HOST_KERNEL_OVERRIDE:-$(uname -r 2>/dev/null)}"
    HOST_DISTRO="$(sed -n 's/^ID=//p' "${HOST_ROOT}/etc/os-release" 2>/dev/null | tr -d '"' | head -n 1)"
    [ "$HOST_OS" = "macos" ] && HOST_DISTRO="macos-$(sw_vers -productVersion 2>/dev/null)"
    HOST_PCORES="" HOST_ECORES=""
    case "$HOST_OS" in
        macos) _host_macos_cpu ;;
        *)     _host_linux_cpu ;;
    esac
    HOST_LIBC="$(_host_libc)"
    HOST_VIRT="bare"
    { [ -e "${HOST_ROOT}/.dockerenv" ] || [ -e "${HOST_ROOT}/run/.containerenv" ] ||
      grep -qE 'docker|lxc|kubepods|containerd' "${HOST_ROOT}/proc/1/cgroup" 2>/dev/null; } && HOST_VIRT="container"
    HOST_POWER="$(_host_power)"
    case "$HOST_OS-$HOST_LIBC" in
        macos-*)     HOST_RUST_TARGET="${HOST_ARCH}-apple-darwin" ;;
        linux-musl)  HOST_RUST_TARGET="${HOST_ARCH}-unknown-linux-musl" ;;
        linux-*)     HOST_RUST_TARGET="${HOST_ARCH}-unknown-linux-gnu" ;;
        *)           HOST_RUST_TARGET="" ;;
    esac
}

#[pub]
# The fields as `key=value` lines, in a fixed order, so two runs diff cleanly.
# Usage: host_fingerprint_print
host_fingerprint_print() {
    local k v up
    for k in $_HOST_FIELDS; do
        up="$(printf '%s' "$k" | tr 'a-z' 'A-Z')"
        eval "v=\"\${HOST_${up}:-}\""
        printf '%s=%s\n' "$k" "$v"
    done
}

#[pub]
# A name for this machine made of what it is rather than what it is called, so a
# result path or a branch carries no hostname: os, arch, and the CPU model.
# Usage: host_label -> linux-x86_64-intel-core-i7-1165g7
host_label() {
    [ -n "${HOST_OS:-}" ] || host_fingerprint
    printf '%s-%s-%s' "$HOST_OS" "$HOST_ARCH" "$(printf '%s' "${HOST_CPU:-unknown}" |
        tr 'A-Z' 'a-z' | sed -e 's/(r)//g' -e 's/(tm)//g' -e 's/ cpu / /g' -e 's/@.*$//' \
            -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//')"
}
