#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/pkg/recipes - Recipes for tools worth pinning
# =============================================================================
# Part of the-whole-shebang. Built on `pkg::ensure`, which has to be sourced first.
# https://github.com/orgrinrt/the-whole-shebang
#
# A recipe here is a tool that more than one project of ours installs, written
# once. Sourcing this file declares them; `pkg_ensure <tool>` then does the rest.
#
#   use shebang::pkg::ensure
#   use shebang::pkg::recipes
#   pkg_ensure yq || printf '%s\n' "$PKG_WHY" >&2
# =============================================================================

if [ -z "${_SHEBANG_PKG_ENSURE_SH:-}" ]; then
    printf 'pkg: source pkg::ensure before pkg::recipes\n' >&2
    return 1
fi

# Whether the `yq` found is mikefarah's, the one that reads TOML, and the one
# `deps` found rather than another of the same name earlier on the path. Two
# programs are called yq, and the python one cannot do what any caller of this
# recipe wants. Given the path `pkg_ensure` found or unpacked.
# Usage: pkg_probe_yq <path>
pkg_probe_yq() {
    [ "$(deps_path yq)" = "$1" ] && [ "$(deps_variant yq)" = "mikefarah" ]
}

# yq 4, mikefarah's, from its forge release.
#
# The system rung is switched off where the distribution's `yq` is the python
# one (apt, dnf, zypper, xbps, port) and left to the managers whose package of
# that name is mikefarah's. The probe refuses a wrong one in any case.
#
# The digests are the SHA-256 column of the `checksums` file published with the
# release, by `checksums_hashes_order`:
#   https://github.com/mikefarah/yq/releases/download/v4.44.3/checksums
#   https://github.com/mikefarah/yq/releases/download/v4.44.3/checksums_hashes_order
pkg_recipe yq brew=yq apk=yq pacman=go-yq apt=- dnf=- zypper=- xbps=- port=- \
    probe=pkg_probe_yq path="$HOME/.local/bin" \
    release="https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_{os}_{arch}" \
    osname_macos=darwin archname_x86_64=amd64 archname_arm64=arm64 \
    sha256_linux_x86_64=a2c097180dd884a8d50c956ee16a9cec070f30a7947cf4ebf87d5f36213e9ed7 \
    sha256_linux_arm64=0e7e1524f68d91b3ff9b089872d185940ab0fa020a5a9052046ef10547023156 \
    sha256_macos_x86_64=216ddfa03e7ba0e5aba00b236ec78324b5bfc49b610db254fe92310878baea20 \
    sha256_macos_arm64=559a594ef7a6ebc5b81a67b7717fb3accedd266d8fa7d8352da7fec9e463f48b
