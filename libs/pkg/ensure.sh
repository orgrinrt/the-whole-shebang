#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/pkg/ensure - Make a binary be there, however this machine allows
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# nutshell's `deps` answers whether a tool is here and where. This is the other
# half: when it is not, get it, by the best way this machine has, and say which
# way that was. Four rungs, tried in order, each one only where it can work:
#
#   system  the machine's package manager, where there is one and it can be used:
#           root or a way to become root, and a root filesystem that is writable.
#           SteamOS has pacman and a read-only root, so this rung is skipped there.
#   release a static binary the project publishes on its forge: fetched, checked
#           against a sha256 the recipe pins per os and arch, unpacked where it is an
#           archive, probed, and only then placed. See release.sh. Bash only.
#   user    an install into the home directory that the recipe names (rustup-init),
#           which needs no root at all.
#   source  a build from source, the fallback that works wherever a C compiler is.
#
# A recipe is data the caller gives, one per binary: the package name for each
# manager, the release url and digests, the functions for the user and source
# rungs, and the probe that says whether a found binary is good enough (bash 3.2
# is found and is not, and neither is the python yq).
#
# POSIX on purpose, bar the release rung. The first thing a tool on a bare machine
# has to get is a bash new enough for nutshell, and that has to happen before there
# is one. Sourced from a POSIX shell with nutshell's `deps`, `os` and `priv` loaded,
# it works the same as under `use shebang::pkg::ensure`, and the release rung says
# it needs bash where it is not one.
#
# Usage:
#   use shebang::pkg::ensure
#
#   pkg_recipe git apt=git apk=git pacman=git brew=git
#   pkg_recipe cargo user=install_rustup path="$HOME/.cargo/bin"
#   pkg_ensure git || printf '%s\n' "$PKG_WHY" >&2
#   pkg_plan cargo          # what pkg_ensure would do, doing nothing
# =============================================================================

[ -n "${_SHEBANG_PKG_ENSURE_SH:-}" ] && return 0
_SHEBANG_PKG_ENSURE_SH=1

if ! command -v use >/dev/null 2>&1; then
    printf 'pkg: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

use deps os priv key log

# The release rung is bash's: `http` and `verify::digest` are. Under a POSIX shell the
# rung is absent and says so, and the other three work as before.
_PKG_HAS_VERIFY=""
if [ -n "${BASH_VERSION:-}" ]; then
    use super::pkg::release
fi

# What a run found, for the caller to read. `PKG_HOW` is `present`, `system:<manager>`,
# `user` or `source`; `PKG_WHY` carries each rung's reason when none worked.
PKG_HOW="" PKG_PATH="" PKG_WHY=""
# Where an install's own output goes. A package manager is loud, and a run board
# above it is the thing a person is reading.
PKG_LOG="${PKG_LOG:-/dev/stderr}"
# The mount table read for a read-only root, a variable so a test can give one.
PKG_MOUNTS="${PKG_MOUNTS:-/proc/mounts}"

# The managers, in the order they are looked for, and how each installs. One list,
# read by detection and by the install, so the two cannot disagree.
_PKG_MANAGERS="brew apt dnf pacman apk zypper xbps port"
_pkg_mgr_bin() {
    case "$1" in
        apt) printf 'apt-get' ;; xbps) printf 'xbps-install' ;; *) printf '%s' "$1" ;;
    esac
}
_pkg_mgr_root() { case "$1" in brew) return 1 ;; *) return 0 ;; esac; }

# The install, as words. Non-interactive everywhere, since nobody is there to type
# yes once the run has started.
_pkg_mgr_install() {
    local m="$1"; shift
    case "$m" in
        brew)   brew install "$@" ;;
        apt)    priv_run "install $*" apt-get update -q &&
                priv_run "install $*" env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@" ;;
        dnf)    priv_run "install $*" dnf install -y "$@" ;;
        pacman) priv_run "install $*" pacman -S --noconfirm --needed "$@" ;;
        apk)    priv_run "install $*" apk add --no-cache "$@" ;;
        zypper) priv_run "install $*" zypper --non-interactive install "$@" ;;
        xbps)   priv_run "install $*" xbps-install -y "$@" ;;
        port)   priv_run "install $*" port -N install "$@" ;;
        *)      return 2 ;;
    esac
}

# One more reason, the way each rung says why it did not work.
_pkg_why() { PKG_WHY="${PKG_WHY}${PKG_WHY:+; }$1"; }

# Recipe fields, stored under a key nutshell's `nut_key` makes safe for a name.
_pkg_get() { nut_key "$1" || return 1; eval "_pg=\"\${_PKG_R_${_nk}_$2:-}\""; }
_pkg_set() { nut_key "$1" || return 1; eval "_PKG_R_${_nk}_$2=\$3"; }

#[pub]
# Say how a binary is got. Fields: one per manager (`apt=`, `apk=`, `brew=`...,
# `-` for none), `user=<function>`, `source=<function>`, `probe=<function>` (given
# the found path, returns 0 when it is good enough), `path=<dir>` (where the user
# or source rung puts it, put on PATH before asking again). A manager with no field
# installs a package of the binary's own name.
# Usage: pkg_recipe <bin> <field>=<value>...
pkg_recipe() {
    local b="$1" kv; shift
    for kv in "$@"; do
        case "$kv" in
            *=*) _pkg_set "$b" "${kv%%=*}" "${kv#*=}" ;;
            *)   log_error "pkg_recipe ${b}: '${kv}' is not field=value"; return 2 ;;
        esac
    done
}

#[pub]
# The package manager this machine has, by nutshell's `deps`, or nothing.
# Usage: pkg_manager -> brew | apt | dnf | pacman | apk | zypper | xbps | port
pkg_manager() {
    local m
    for m in ${PKG_MANAGERS:-$_PKG_MANAGERS}; do
        deps_has "$(_pkg_mgr_bin "$m")" && { printf '%s' "$m"; return 0; }
    done
    return 1
}

# A root or /usr mounted read-only, which is SteamOS, and an immutable distro too.
_pkg_root_ro() {
    [ -r "$PKG_MOUNTS" ] || return 1
    local _dev mnt _fs opts _rest
    while read -r _dev mnt _fs opts _rest; do
        case "$mnt" in /|/usr) ;; *) continue ;; esac
        case ",$opts," in *,ro,*) return 0 ;; esac
    done < "$PKG_MOUNTS"
    return 1
}

#[pub]
# Can the manager be used here, now, unattended or with the person at the terminal.
# Sets PKG_WHY to the reason when it cannot.
# Usage: pkg_manager_usable <manager>
pkg_manager_usable() {
    local m="$1"
    deps_has "$(_pkg_mgr_bin "$m")" || { PKG_WHY="no ${m}"; return 1; }
    _pkg_mgr_root "$m" || {
        priv_is_root && { PKG_WHY="${m} refuses to run as root"; return 1; }
        return 0
    }
    _pkg_root_ro && { PKG_WHY="${m}: the root filesystem is read-only"; return 1; }
    priv_is_root && return 0
    priv_how >/dev/null || { PKG_WHY="${m} needs root, and there is no sudo or doas"; return 1; }
    if priv_needs_password && ! { [ -t 0 ] || [ -t 2 ]; }; then
        PKG_WHY="${m} needs a root password, and there is no terminal to type it on"
        return 1
    fi
    return 0
}

# Ask again, because `deps_has` remembers a miss for the life of the process and an
# install is exactly what changes the answer. Sets `_pg` to the path.
_pkg_reask() { deps_forget "$1"; deps_has "$1" || return 1; _pg="$(deps_path "$1")"; }

# Found, and good enough by the recipe's probe. Sets PKG_PATH.
_pkg_good() {
    local b="$1" fresh="${2:-0}" p=""
    if [ "$fresh" = 1 ]; then _pkg_reask "$b" || return 1; p="$_pg"
    else deps_has "$b" || return 1; p="$(deps_path "$b")"; fi
    _pkg_get "$b" probe
    if [ -n "$_pg" ] && ! "$_pg" "$p" >/dev/null 2>&1; then
        PKG_WHY="${PKG_WHY}${PKG_WHY:+; }${p} is too old or unusable"
        return 1
    fi
    PKG_PATH="$p"
}

# The recipe's directory on PATH, once.
_pkg_path_add() {
    _pkg_get "$1" path
    [ -n "$_pg" ] || return 0
    case ":$PATH:" in *":$_pg:"*) ;; *) PATH="$_pg:$PATH"; export PATH ;; esac
}

#[pub]
# Make <bin> be there. Returns 0 with PKG_HOW and PKG_PATH set, or 1 with PKG_WHY
# naming why each rung did not work. Never prompts except where priv_run would.
# Usage: pkg_ensure <bin>
pkg_ensure() {
    local b="$1" m pkgs rung;  PKG_HOW="" PKG_PATH="" PKG_WHY=""
    _pkg_path_add "$b"
    _pkg_good "$b" && { PKG_HOW="present"; return 0; }

    if m="$(pkg_manager)"; then
        _pkg_get "$b" "$m"; pkgs="${_pg:-$b}"
        if [ "$pkgs" = "-" ]; then PKG_WHY="${PKG_WHY}${PKG_WHY:+; }${m} has no package"
        elif pkg_manager_usable "$m"; then
            # shellcheck disable=SC2086 # a field may name several packages
            if _pkg_mgr_install "$m" $pkgs >>"$PKG_LOG" 2>&1 && _pkg_good "$b" 1; then
                PKG_HOW="system:${m}"; return 0
            fi
            PKG_WHY="${PKG_WHY}${PKG_WHY:+; }${m} install of ${pkgs} did not give a usable ${b}"
        fi
    else
        PKG_WHY="${PKG_WHY}${PKG_WHY:+; }no package manager"
    fi

    _pkg_get "$b" release
    if [ -z "$_pg" ]; then :
    elif [ -z "$_PKG_HAS_VERIFY" ]; then _pkg_why "the release rung needs bash"
    elif _pkg_release "$b"; then PKG_HOW="release"; return 0
    fi

    for rung in user source; do
        _pkg_get "$b" "$rung"
        [ -n "$_pg" ] || { PKG_WHY="${PKG_WHY}${PKG_WHY:+; }no ${rung} recipe"; continue; }
        if "$_pg" >>"$PKG_LOG" 2>&1 && _pkg_good "$b" 1; then
            PKG_HOW="$rung"; return 0
        fi
        PKG_WHY="${PKG_WHY}${PKG_WHY:+; }the ${rung} install did not give a usable ${b}"
    done
    return 1
}

#[pub]
# What pkg_ensure would do, as one line, doing nothing. Returns 0 when one of the
# rungs would be tried with a fair chance, 1 when none can be.
# Usage: pkg_plan <bin> -> "git: present at /usr/bin/git"
pkg_plan() {
    local b="$1" m pkgs rung; PKG_WHY=""
    _pkg_path_add "$b"
    _pkg_good "$b" && { printf '%s: present at %s\n' "$b" "$PKG_PATH"; return 0; }
    if m="$(pkg_manager)"; then
        _pkg_get "$b" "$m"; pkgs="${_pg:-$b}"
        if [ "$pkgs" != "-" ] && pkg_manager_usable "$m"; then
            printf '%s: would install with %s (%s)\n' "$b" "$m" "$pkgs"; return 0
        fi
    fi
    _pkg_get "$b" release
    if [ -n "$_pg" ] && [ -n "$_PKG_HAS_VERIFY" ] && [ -n "$(pkg_release_digest "$b")" ]; then
        printf '%s: would install from the release %s\n' "$b" "$(pkg_release_url "$b")"; return 0
    fi
    for rung in user source; do
        _pkg_get "$b" "$rung"
        [ -n "$_pg" ] && { printf '%s: would install from the %s recipe\n' "$b" "$rung"; return 0; }
    done
    printf '%s: missing, and no way here to get it%s\n' "$b" "${PKG_WHY:+ (${PKG_WHY})}"
    return 1
}

#[pub]
# Is the file's sha256 this one. Through `verify::digest` where it is loaded,
# which needs bash, and through whichever of sha256sum and shasum `deps` finds
# where it is not, so the POSIX stage before bash checks a download too. No way
# to hash is a refusal, never a pass.
# Usage: pkg_sha256_is <file> <sha256>
pkg_sha256_is() {
    local got=""
    if [ -n "$_PKG_HAS_VERIFY" ]; then
        verify_digest "$1" "$2"; return $(( $? != 0 ))
    fi
    if deps_has sha256sum; then got="$(sha256sum < "$1")"
    elif deps_has shasum; then got="$(shasum -a 256 < "$1")"
    else return 1; fi
    [ "${got%% *}" = "$2" ]
}

#[pub]
# The source rung's usual shape: fetch a release tarball, check its digest, build
# with configure and make into a prefix in the home directory. Needs a C compiler
# and make, which no rung can bootstrap from nothing, and says so when absent.
# Usage: pkg_build_tarball <url> <sha256> [prefix] [configure args...]
pkg_build_tarball() {
    local url sum prefix t work src rc
    url="$1" sum="$2" prefix="${3:-$HOME/.local}"; shift 3 2>/dev/null || shift $#
    for t in cc make tar; do
        deps_has "$t" || { printf 'a build from source needs %s, which is not here\n' "$t"; return 1; }
    done
    work="$(mktemp -d)" || return 1
    if deps_has curl; then curl -fsSL -o "$work/src.tar.gz" "$url"
    elif deps_has wget; then wget -q -O "$work/src.tar.gz" "$url"
    else printf 'no curl or wget to fetch %s\n' "$url"; rm -rf "$work"; return 1; fi || {
        printf 'could not fetch %s\n' "$url"; rm -rf "$work"; return 1; }
    pkg_sha256_is "$work/src.tar.gz" "$sum" || {
        printf 'the digest of %s did not match, or could not be checked here\n' "$url"
        rm -rf "$work"; return 1; }
    deps_run tar -xzf "$work/src.tar.gz" -C "$work" || { rm -rf "$work"; return 1; }
    src="$(ls -d "$work"/*/ | head -n 1)"
    ( cd "$src" && ./configure --prefix="$prefix" "$@" && make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" && make install )
    rc=$?; rm -rf "$work"; return "$rc"
}
