#!/usr/bin/env bash
# Tests for getting a binary onto a machine.
#
# Every rung is driven by a fake: a package manager that is a script writing the
# binary into a directory on PATH, a mount table read from a file, a user recipe
# that is a function. So what is tested is the ladder, which rung is tried, which
# is skipped and why, and that the answer is asked again after an install, rather
# than whether apk works.

use test

. "${BASH_SOURCE[0]%/*}/../libs/pkg/ensure.sh"

_p_setup() {
    T="$(mktemp -d)"
    mkdir -p "$T/bin" "$T/home"
    printf 'rootfs / ext4 rw,relatime 0 0\n' > "$T/mounts.rw"
    printf 'rootfs / btrfs ro,relatime 0 0\n' > "$T/mounts.ro"
    # A package manager that installs whatever it is asked for as an empty
    # executable, and records the call.
    printf '#!/bin/sh\nshift 2\nfor p; do printf "#!/bin/sh\\n" > "%s/bin/$p"; chmod +x "%s/bin/$p"; done\necho "$@" >> "%s/apk.calls"\n' \
        "$T" "$T" "$T" > "$T/bin/apk"
    chmod +x "$T/bin/apk"
    PATH="$T/bin:$PATH"; export PATH
    PKG_MANAGERS="apk" PKG_MOUNTS="$T/mounts.rw" PKG_LOG="$T/log"
    _pkg_mgr_install() { "$T/bin/apk" add --no-cache "${@:2}"; }
    priv_is_root() { return 0; }
}
_p_end() { rm -rf "$T"; unset T; }

_user_install() { printf '#!/bin/sh\n' > "$T/home/zzpkg"; chmod +x "$T/home/zzpkg"; }
_never() { return 1; }

#[test]
it_says_present_for_a_binary_already_there() {
    _p_setup
    pkg_ensure sh; assert_eq "$?" "0"
    assert_eq "$PKG_HOW" "present"
    _p_end
}

#[test]
it_installs_with_the_package_manager_and_asks_again() {
    _p_setup
    pkg_recipe zzpkg apk=zzpkg
    pkg_ensure zzpkg; assert_eq "$?" "0"
    assert_eq "$PKG_HOW" "system:apk"
    assert_eq "$PKG_PATH" "$T/bin/zzpkg"
    assert_contains "$(cat "$T/apk.calls")" "zzpkg"
    _p_end
}

#[test]
it_skips_the_manager_on_a_read_only_root_and_goes_to_the_user_rung() {
    _p_setup
    PKG_MOUNTS="$T/mounts.ro"
    pkg_recipe zzpkg user=_user_install path="$T/home"
    pkg_ensure zzpkg; assert_eq "$?" "0"
    assert_eq "$PKG_HOW" "user"
    assert_eq "$PKG_PATH" "$T/home/zzpkg"
    assert_eq "$(cat "$T/apk.calls" 2>/dev/null)" ""
    _p_end
}

#[test]
it_refuses_a_found_binary_the_probe_rejects() {
    _p_setup
    PKG_MANAGERS="nosuchmanager"
    pkg_recipe sh probe=_never
    pkg_ensure sh; assert_eq "$?" "1"
    assert_contains "$PKG_WHY" "too old or unusable"
    assert_contains "$PKG_WHY" "no package manager"
    _p_end
}

#[test]
it_names_every_rung_when_nothing_works() {
    _p_setup
    PKG_MANAGERS="nosuchmanager"
    pkg_ensure zzpkg; assert_eq "$?" "1"
    assert_contains "$PKG_WHY" "no package manager"
    assert_contains "$PKG_WHY" "no user recipe"
    assert_contains "$PKG_WHY" "no source recipe"
    _p_end
}

#[test]
it_falls_through_a_failed_install_to_the_source_rung() {
    _p_setup
    pkg_recipe zzpkg apk=not-the-right-name source=_user_install path="$T/home"
    pkg_ensure zzpkg; assert_eq "$?" "0"
    assert_eq "$PKG_HOW" "source"
    _p_end
}

#[test]
it_plans_without_installing() {
    _p_setup
    pkg_recipe zzpkg apk=zzpkg
    assert_contains "$(pkg_plan sh)" "sh: present at"
    assert_eq "$(pkg_plan zzpkg)" "zzpkg: would install with apk (zzpkg)"
    assert_eq "$([ -e "$T/bin/zzpkg" ] && echo made)" ""
    PKG_MANAGERS="nosuchmanager"
    pkg_plan zzpkg >/dev/null; assert_eq "$?" "1"
    _p_end
}

#[test]
it_reads_a_read_only_usr_as_read_only_too() {
    _p_setup
    printf 'rootfs / ext4 rw 0 0\n/dev/x /usr squashfs ro,nodev 0 0\n' > "$T/mounts.usr"
    PKG_MOUNTS="$T/mounts.usr"
    pkg_manager_usable apk; assert_eq "$?" "1"
    assert_contains "$PKG_WHY" "read-only"
    PKG_MOUNTS="$T/mounts.rw"
    pkg_manager_usable apk; assert_eq "$?" "0"
    _p_end
}
