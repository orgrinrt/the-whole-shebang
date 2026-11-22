#!/usr/bin/env bash
# Tests for the release rung of pkg::ensure: a binary fetched from a forge
# release, checked against a digest written into the recipe, and placed only
# when the recipe's probe accepts it.
#
# The release is a directory served by `file://`, so nothing here needs the
# network. Every digest below is a literal, hashed once by hand from the fixture
# text next to it, never read back from the code under test: a rung that hashed
# the wrong file would otherwise agree with itself.
#
# What is asserted is mostly what is NOT left behind. A wrong digest or a probe
# that says no has to leave the destination directory empty, since a binary
# placed and then complained about is a binary somebody runs.

use test deps os

. "${BASH_SOURCE[0]%/*}/../libs/pkg/ensure.sh"
. "${BASH_SOURCE[0]%/*}/../libs/pkg/recipes.sh"

# printf '#!/bin/sh\necho payload\n' | sha256sum
_R_PAYLOAD_SUM="4aafca87353c0dbc0f75207f2cecf1bfc5c8b0e88724c5f70dbe84f4dc9d45cd"
# printf '#!/bin/sh\necho "yq (https://github.com/mikefarah/yq/) version v4.44.3"\n' | sha256sum
_R_MIKEFARAH_SUM="4e00c5d14ea4c7b23987c1893f73bcfbae3ca050c2e873fd8b10844cfc683fbf"
# printf '#!/bin/sh\necho "yq 3.4.3"\n' | sha256sum
_R_PYTHON_SUM="b978a80566fd92757670535d0cd7de2455da23e83d9e25ab1d048bc4f4b42dd5"
_R_ZEROES="0000000000000000000000000000000000000000000000000000000000000000"

# The machine's own yq is mikefarah's, which would answer `present` before any
# rung ran. A PATH of symlinks to what the rung needs, and no yq, takes it out.
_r_setup() {
    T="$(mktemp -d)"
    mkdir -p "$T/bin" "$T/sys" "$T/srv" "$T/home"
    local n p
    for n in sh bash env uname cat sed grep head tr mktemp chmod mkdir mv cp rm find dirname \
             basename sha256sum shasum sort wc awk id cut tee ls tar unzip curl wget ln which; do
        for p in /usr/bin/$n /bin/$n; do [ -x "$p" ] && { ln -s "$p" "$T/sys/$n"; break; }; done
    done
    _R_PATH="$PATH"
    PATH="$T/bin:$T/sys"; export PATH
    PKG_MANAGERS="nosuchmanager" PKG_LOG="$T/log"
    deps_forget yq zzpkg
}
_r_end() { PATH="$_R_PATH"; export PATH; deps_forget yq zzpkg; rm -rf "$T"; unset T _R_PATH; }

_r_serve() { printf '%s' "$2" > "$T/srv/$1"; }
_r_here() { printf '%s_%s' "$(os_name)" "$(os_arch)"; }

# A recipe for `zzpkg` served from the fixture directory, digest for this machine.
_r_recipe() {
    pkg_recipe zzpkg "release=file://$T/srv/zzpkg" "sha256_$(_r_here)=$1" "path=$T/home"
}

#[test]
it_installs_from_a_release_when_the_digest_matches() {
    _r_setup
    _r_serve zzpkg $'#!/bin/sh\necho payload\n'
    _r_recipe "$_R_PAYLOAD_SUM"
    pkg_ensure zzpkg; assert_eq "$?" "0"
    assert_eq "$PKG_HOW" "release"
    assert_eq "$PKG_PATH" "$T/home/zzpkg"
    assert_eq "$("$T/home/zzpkg")" "payload"
    _r_end
}

#[test]
it_refuses_a_release_with_a_wrong_digest_and_places_nothing() {
    _r_setup
    _r_serve zzpkg $'#!/bin/sh\necho payload\n'
    _r_recipe "$_R_ZEROES"
    pkg_ensure zzpkg; assert_eq "$?" "1"
    assert_contains "$PKG_WHY" "release"
    assert_contains "$PKG_WHY" "digest"
    assert_eq "$(ls -A "$T/home")" ""
    _r_end
}

#[test]
it_refuses_a_release_with_no_digest_for_this_machine() {
    _r_setup
    _r_serve zzpkg $'#!/bin/sh\necho payload\n'
    pkg_recipe zzpkg "release=file://$T/srv/zzpkg" "sha256_plan9_mips=$_R_PAYLOAD_SUM" "path=$T/home"
    pkg_ensure zzpkg; assert_eq "$?" "1"
    assert_contains "$PKG_WHY" "no release digest for $(_r_here)"
    assert_eq "$(ls -A "$T/home")" ""
    _r_end
}

#[test]
it_refuses_a_release_that_cannot_be_fetched() {
    _r_setup
    _r_recipe "$_R_PAYLOAD_SUM"
    pkg_ensure zzpkg; assert_eq "$?" "1"
    assert_contains "$PKG_WHY" "could not fetch"
    assert_eq "$(ls -A "$T/home")" ""
    _r_end
}

#[test]
it_fills_the_url_template_from_the_machine_and_the_recipes_spellings() {
    _r_setup
    _r_serve "zzpkg_$(os_name)_spelt" $'#!/bin/sh\necho payload\n'
    pkg_recipe zzpkg "release=file://$T/srv/zzpkg_{os}_{arch}" "archname_$(os_arch)=spelt" \
        "sha256_$(_r_here)=$_R_PAYLOAD_SUM" "path=$T/home"
    pkg_ensure zzpkg; assert_eq "$?" "0"
    assert_eq "$PKG_HOW" "release"
    _r_end
}

#[test]
it_takes_the_named_file_out_of_a_release_archive() {
    _r_setup
    mkdir -p "$T/pack/zzpkg-1.0"
    printf '#!/bin/sh\necho payload\n' > "$T/pack/zzpkg-1.0/zzpkg"
    tar -cf "$T/srv/zzpkg.tar" -C "$T/pack" .
    local sum
    if deps_has sha256sum; then sum="$(sha256sum < "$T/srv/zzpkg.tar")"; else sum="$(shasum -a 256 < "$T/srv/zzpkg.tar")"; fi
    pkg_recipe zzpkg "release=file://$T/srv/zzpkg.tar" "member=zzpkg" \
        "sha256_$(_r_here)=${sum%% *}" "path=$T/home"
    pkg_ensure zzpkg; assert_eq "$?" "0"
    assert_eq "$PKG_HOW" "release"
    assert_eq "$("$T/home/zzpkg")" "payload"
    _r_end
}

#[test]
it_refuses_an_archive_that_lacks_the_named_file_and_places_nothing() {
    _r_setup
    mkdir -p "$T/pack"
    printf 'x\n' > "$T/pack/other"
    tar -cf "$T/srv/zzpkg.tar" -C "$T/pack" .
    local sum
    if deps_has sha256sum; then sum="$(sha256sum < "$T/srv/zzpkg.tar")"; else sum="$(shasum -a 256 < "$T/srv/zzpkg.tar")"; fi
    pkg_recipe zzpkg "release=file://$T/srv/zzpkg.tar" "member=zzpkg" \
        "sha256_$(_r_here)=${sum%% *}" "path=$T/home"
    pkg_ensure zzpkg; assert_eq "$?" "1"
    assert_contains "$PKG_WHY" "release"
    assert_eq "$(ls -A "$T/home")" ""
    _r_end
}

#[test]
it_installs_the_yq_recipe_when_the_probe_says_mikefarah() {
    _r_setup
    _r_serve yq $'#!/bin/sh\necho "yq (https://github.com/mikefarah/yq/) version v4.44.3"\n'
    pkg_recipe yq "release=file://$T/srv/yq" "sha256_$(_r_here)=$_R_MIKEFARAH_SUM" "path=$T/home"
    pkg_ensure yq; assert_eq "$?" "0"
    assert_eq "$PKG_HOW" "release"
    assert_eq "$PKG_PATH" "$T/home/yq"
    assert_eq "$(deps_variant yq)" "mikefarah"
    _r_end
}

#[test]
it_fails_the_rung_when_the_yq_probe_says_python_and_leaves_nothing() {
    _r_setup
    _r_serve yq $'#!/bin/sh\necho "yq 3.4.3"\n'
    pkg_recipe yq "release=file://$T/srv/yq" "sha256_$(_r_here)=$_R_PYTHON_SUM" "path=$T/home"
    pkg_ensure yq; assert_eq "$?" "1"
    assert_contains "$PKG_WHY" "probe"
    assert_eq "$(ls -A "$T/home")" ""
    _r_end
}

#[test]
it_rejects_a_python_yq_already_on_the_path_and_installs_mikefarahs() {
    _r_setup
    printf '#!/bin/sh\necho "yq 3.4.3"\n' > "$T/bin/yq"; chmod +x "$T/bin/yq"
    deps_forget yq zzpkg
    _r_serve yq $'#!/bin/sh\necho "yq (https://github.com/mikefarah/yq/) version v4.44.3"\n'
    pkg_recipe yq "release=file://$T/srv/yq" "sha256_$(_r_here)=$_R_MIKEFARAH_SUM" "path=$T/home"
    pkg_ensure yq; assert_eq "$?" "0"
    assert_eq "$PKG_HOW" "release"
    assert_eq "$PKG_PATH" "$T/home/yq"
    _r_end
}

#[test]
it_pins_the_real_yq_release_for_every_platform_it_names() {
    # Literals from the `checksums` file published beside the release, column
    # SHA-256 per `checksums_hashes_order`: yq v4.44.3.
    assert_eq "$(pkg_release_url yq linux x86_64)" "https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64"
    assert_eq "$(pkg_release_url yq linux arm64)"  "https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_arm64"
    assert_eq "$(pkg_release_url yq macos x86_64)" "https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_darwin_amd64"
    assert_eq "$(pkg_release_url yq macos arm64)"  "https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_darwin_arm64"
    assert_eq "$(pkg_release_digest yq linux x86_64)" "a2c097180dd884a8d50c956ee16a9cec070f30a7947cf4ebf87d5f36213e9ed7"
    assert_eq "$(pkg_release_digest yq linux arm64)"  "0e7e1524f68d91b3ff9b089872d185940ab0fa020a5a9052046ef10547023156"
    assert_eq "$(pkg_release_digest yq macos x86_64)" "216ddfa03e7ba0e5aba00b236ec78324b5bfc49b610db254fe92310878baea20"
    assert_eq "$(pkg_release_digest yq macos arm64)"  "559a594ef7a6ebc5b81a67b7717fb3accedd266d8fa7d8352da7fec9e463f48b"
}

#[test]
it_plans_a_release_install_without_fetching() {
    _r_setup
    _r_recipe "$_R_PAYLOAD_SUM"
    assert_contains "$(pkg_plan zzpkg)" "would install from the release"
    assert_eq "$(ls -A "$T/home")" ""
    _r_end
}

#[test]
it_leaves_a_good_yq_in_the_destination_alone_when_a_python_yq_shadows_it() {
    # The image case: a python yq first on PATH, ~/.local/bin after it, and
    # mikefarah's already in ~/.local/bin. The rung cannot make the good one be
    # the one found, so it refuses and leaves what was there, byte for byte.
    _r_setup
    local old=$'#!/bin/sh\necho "yq (https://github.com/mikefarah/yq/) version v4.40.0"'
    printf '#!/bin/sh\necho "yq 3.4.3"\n' > "$T/bin/yq"; chmod +x "$T/bin/yq"
    printf '%s\n' "$old" > "$T/home/yq"; chmod +x "$T/home/yq"
    PATH="$T/bin:$T/home:$T/sys"; export PATH
    deps_forget yq
    _r_serve yq $'#!/bin/sh\necho "yq (https://github.com/mikefarah/yq/) version v4.44.3"\n'
    pkg_recipe yq "release=file://$T/srv/yq" "sha256_$(_r_here)=$_R_MIKEFARAH_SUM" "path=$T/home"
    pkg_ensure yq; assert_eq "$?" "1"
    assert_contains "$PKG_WHY" "$T/bin/yq"
    assert_contains "$PKG_WHY" "shadow"
    assert_eq "$(cat "$T/home/yq")" "$old"
    assert_eq "$(ls -A "$T/home")" "yq"
    _r_end
}

#[test]
it_replaces_a_bad_yq_in_the_destination_when_the_destination_comes_first_on_the_path() {
    _r_setup
    printf '#!/bin/sh\necho "yq 3.4.3"\n' > "$T/home/yq"; chmod +x "$T/home/yq"
    PATH="$T/home:$T/bin:$T/sys"; export PATH
    deps_forget yq
    _r_serve yq $'#!/bin/sh\necho "yq (https://github.com/mikefarah/yq/) version v4.44.3"\n'
    pkg_recipe yq "release=file://$T/srv/yq" "sha256_$(_r_here)=$_R_MIKEFARAH_SUM" "path=$T/home"
    pkg_ensure yq; assert_eq "$?" "0"
    assert_eq "$PKG_HOW" "release"
    assert_eq "$PKG_PATH" "$T/home/yq"
    assert_contains "$("$T/home/yq" --version)" "v4.44.3"
    _r_end
}

#[test]
it_keeps_the_file_that_was_there_when_a_refused_probe_follows_a_placement() {
    # A recipe whose probe passes the stage and fails the placed file: the only
    # way the placed file is found and refused is a probe that reads its place.
    _r_setup
    local old=$'#!/bin/sh\necho old'
    printf '%s\n' "$old" > "$T/home/zzpkg"; chmod +x "$T/home/zzpkg"
    _r_serve zzpkg $'#!/bin/sh\necho payload\n'
    _zz_probe() { case "$1" in "$T/home/"*) return 1 ;; *) return 0 ;; esac; }
    pkg_recipe zzpkg "release=file://$T/srv/zzpkg" "sha256_$(_r_here)=$_R_PAYLOAD_SUM" \
        "path=$T/home" "probe=_zz_probe"
    pkg_ensure zzpkg; assert_eq "$?" "1"
    assert_contains "$PKG_WHY" "placed in $T/home"
    assert_eq "$(cat "$T/home/zzpkg")" "$old"
    assert_eq "$(ls -A "$T/home")" "zzpkg"
    unset -f _zz_probe
    _r_end
}
