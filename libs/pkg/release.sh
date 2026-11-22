#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/pkg/release - The release rung of pkg::ensure
# =============================================================================
# Part of the-whole-shebang. Sourced by `ensure.sh` under bash, never on its own.
#
# A static binary a project publishes on its forge is the one install that works
# the same on every machine that can run it, and it is the only way to get a
# tool whose package of the same name is a different program (`yq` is two).
# This is that install, held to one rule: **nothing is placed that was not
# checked first.** The file is fetched, its sha256 is compared with the one the
# recipe carries for this os and arch, it is taken out of its archive where it
# is one, and the recipe's probe runs on it where it was unpacked. Only then is
# it moved into the recipe's directory. A refusal at any step leaves that
# directory as it was, a file already there included: it is kept aside while the
# new one is placed and put back if `deps` then does not find the new one.
#
# A recipe directory that is on PATH but behind another binary of the same name
# (an image's python yq ahead of ~/.local/bin) cannot make the placed file the one
# found. The rung then places nothing, says in PKG_WHY which path shadows it, and
# leaves the directory alone. A directory off PATH is put first, so it wins.
#
# Recipe fields this reads, beside the ones `pkg_recipe` documents:
#   release=<url>           the asset, with `{os}` and `{arch}` for the machine
#   sha256_<os>_<arch>=...  one per platform, `os_name` and `os_arch` spellings
#   osname_<os>=<word>      how the asset spells an os (`macos` is `darwin`)
#   archname_<arch>=<word>  how it spells an arch (`x86_64` is `amd64`)
#   member=<name>           the asset is an archive; this is the file to take
#   path=<dir>              where it goes, `$HOME/.local/bin` when absent
# =============================================================================

use http os

# `verify_digest` is the three-answer check this rung needs; nothing but a
# match counts here. `pkg_sha256_is` reads this to know it is loaded.
. "${_PKG_DIR}/../verify/digest.sh" && _PKG_HAS_VERIFY=1

#[pub]
# The digest the recipe carries for a platform, or nothing.
# Usage: pkg_release_digest <bin> [os] [arch]
pkg_release_digest() {
    _pkg_get "$1" "sha256_${2:-$(os_name)}_${3:-$(os_arch)}"
    printf '%s' "$_pg"
}

#[pub]
# The release's url for a platform, the template filled with the spellings the
# recipe gives, or the machine's own where it gives none.
# Usage: pkg_release_url <bin> [os] [arch] -> https://.../yq_linux_amd64
pkg_release_url() {
    local b="$1" o="${2:-$(os_name)}" a="${3:-$(os_arch)}" t
    _pkg_get "$b" release; t="$_pg"
    [ -n "$t" ] || return 1
    _pkg_get "$b" "osname_${o}";   o="${_pg:-$o}"
    _pkg_get "$b" "archname_${a}"; a="${_pg:-$a}"
    t="${t//'{os}'/$o}"
    printf '%s' "${t//'{arch}'/$a}"
}

# Which unpack variant this machine has, as the gate in `lib.nut` picks it:
# libarchive where something answers to it, the unzip and tar pair otherwise.
_pkg_unpack_load() {
    [ "$(type -t unpack_extract)" = "function" ] && return 0
    . "${_PKG_DIR}/../unpack/libarchive.sh"
    _unpack_libarchive_bin >/dev/null && return 0
    . "${_PKG_DIR}/../unpack/split.sh"
}

# Fetch, check and unpack into <work>, which the caller removes. Sets _PR_FILE
# to the file that is the binary.
_pkg_release_fetch() {
    local b="$1" url="$2" sum="$3" work="$4" member asset="$4/asset"
    http_ready || { _pkg_why "release: no curl or wget to fetch ${url}"; return 1; }
    http_download "$url" "$asset" || { _pkg_why "release: could not fetch ${url}"; return 1; }
    verify_digest "$asset" "$sum" || {
        _pkg_why "release: the digest of ${url} did not match what the recipe pins, or could not be checked"
        return 1; }
    _pkg_get "$b" member; member="$_pg"
    _PR_FILE="$asset"
    [ -n "$member" ] || return 0
    _pkg_unpack_load
    unpack_extract "$asset" "$work/out" "$member" >/dev/null 2>&1 || {
        _pkg_why "release: no ${member} could be taken out of ${url##*/}"; return 1; }
    _PR_FILE="$work/out/$member"
}

# The recipe's probe on the unplaced file, which has to be what `deps` finds
# under the binary's name while it is asked, so the stage is put first on PATH
# for the question and taken off again, and what `deps` learned is dropped.
_pkg_release_probe() {
    local b="$1" stage="$2" probe rc=0 was="$PATH"
    _pkg_get "$b" probe; probe="$_pg"
    [ -n "$probe" ] || return 0
    PATH="$stage:$PATH"; export PATH; deps_forget "$b"
    "$probe" "$stage/$b" >/dev/null 2>&1 || rc=$?
    PATH="$was"; export PATH; deps_forget "$b"
    [ "$rc" -eq 0 ] || _pkg_why "release: the probe refused the ${b} fetched, which is too old or unusable"
    return "$rc"
}

# The binary `deps` finds under <bin>'s name that comes before <dest> on PATH,
# which a file placed in <dest> would not outrank. Prints its path and returns 0;
# returns 1 where <dest> is off PATH (it is put first, so it wins) or already
# the first place the name is found.
# Usage: _pkg_release_shadow <bin> <dest>
_pkg_release_shadow() {
    local b="$1" dest="$2" cur e IFS=:
    case ":$PATH:" in *":$dest:"*) ;; *) return 1 ;; esac
    deps_forget "$b"
    cur="$(deps_path "$b")" || return 1
    [ "${cur%/*}" = "$dest" ] && return 1
    for e in $PATH; do
        [ "$e" = "$dest" ] && return 1
        [ "$e" = "${cur%/*}" ] && { printf '%s' "$cur"; return 0; }
    done
    return 1
}

# Put the staged file in <dest>, keeping what was there in <work>/prev so that a
# refusal after the move can put it back. Returns 1 with nothing changed where
# the keeping or the copy fails.
# Usage: _pkg_release_place <bin> <dest> <work>
_pkg_release_place() {
    local b="$1" dest="$2" work="$3"
    mkdir -p "$dest" || return 1
    [ ! -e "$dest/$b" ] || cp -p "$dest/$b" "$work/prev" || return 1
    cp "$work/stage/$b" "$dest/.$b.part" && mv -f "$dest/.$b.part" "$dest/$b"
}

# Undo `_pkg_release_place`: what was there comes back, or the file goes where
# nothing was.
_pkg_release_unplace() {
    local b="$1" dest="$2" work="$3"
    if [ -e "$work/prev" ]; then
        cp -p "$work/prev" "$dest/.$b.part" && mv -f "$dest/.$b.part" "$dest/$b"
    else
        rm -f "$dest/$b"
    fi
}

# Make <bin> be there from the recipe's release. Returns 0 with PKG_PATH set.
# Usage: _pkg_release <bin>
_pkg_release() {
    local b="$1" url sum dest work rc=1 was="$PATH" shadow
    _pkg_get "$b" release
    [ -n "$_pg" ] || { _pkg_why "no release recipe"; return 1; }
    sum="$(pkg_release_digest "$b")"
    [ -n "$sum" ] || { _pkg_why "no release digest for $(os_name)_$(os_arch)"; return 1; }
    url="$(pkg_release_url "$b")"
    _pkg_get "$b" path; dest="${_pg:-$HOME/.local/bin}"
    work="$(mktemp -d)" || { _pkg_why "release: no temporary directory"; return 1; }
    mkdir -p "$work/stage"
    if _pkg_release_fetch "$b" "$url" "$sum" "$work" &&
       cp "$_PR_FILE" "$work/stage/$b" && chmod +x "$work/stage/$b" &&
       _pkg_release_probe "$b" "$work/stage"; then
        if shadow="$(_pkg_release_shadow "$b" "$dest")"; then
            _pkg_why "release: ${shadow} shadows ${dest}/${b} on PATH, so a ${b} placed in ${dest} would not be the one found; ${dest} is as it was"
        elif _pkg_release_place "$b" "$dest" "$work"; then
            case ":$PATH:" in *":$dest:"*) ;; *) PATH="$dest:$PATH"; export PATH ;; esac
            if _pkg_good "$b" 1; then rc=0
            else
                _pkg_release_unplace "$b" "$dest" "$work"
                PATH="$was"; export PATH; deps_forget "$b"
                _pkg_why "release: the ${b} placed in ${dest} is not what deps finds, and ${dest} is as it was"
            fi
        else _pkg_why "release: could not place the ${b} in ${dest}"
        fi
    fi
    rm -rf "$work" "$dest/.$b.part"
    return "$rc"
}
