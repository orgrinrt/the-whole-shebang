#!/usr/bin/env bash
# Taking a named file out of an archive, where libarchive is not there.
#
# The fallback, and it is two tools rather than one because neither covers the
# ground alone: GNU `tar` does not read zip, and `unzip` reads nothing else. A
# machine reaching this variant is one with no libarchive at all, which on
# Artix means no `pacman`, so it is a machine nobody here has. It exists so the
# module is not a single point of failure and so the gate has something to fall
# to.
#
# **The hole this shape has is the whole reason for the gate above it.** The
# install path used to be exactly this, unzip then GNU tar, with no libarchive
# arm and no check that either could read the file. On a machine without
# `unzip` a zip fell past both and was copied as though it were the binary, so
# `kanata` landed as 2.2MB of `Zip archive data` at `~/.local/bin/kanata`,
# reported as installed, mode 0755, and said `Exec format error` the first time
# anybody ran it. Nothing in the run said otherwise.

use log

#[pub]
# Whether either tool here can read that file.
# Usage: unpack_reads <file>
unpack_reads() {
    local file="${1:-}"
    [ -r "$file" ] || return 1
    if command -v unzip >/dev/null 2>&1 && unzip -tqq -- "$file" >/dev/null 2>&1; then return 0; fi
    tar -tf "$file" >/dev/null 2>&1
}

#[pub]
# Pull one named file out of an archive, into a directory.
# Usage: unpack_extract <archive> <dest dir> <name to find>
unpack_extract() {
    local file="${1:-}" dir="${2:-}" want="${3:-}" found
    [ -n "$file" ] && [ -n "$dir" ] && [ -n "$want" ] || {
        log_error "unpack_extract: wants an archive, a destination and a name"; return 2; }
    mkdir -p "${dir}/x" || return 1

    if command -v unzip >/dev/null 2>&1 && unzip -tqq -- "$file" >/dev/null 2>&1; then
        unzip -qo -- "$file" -d "${dir}/x" >/dev/null 2>&1 || {
            log_error "unpack: ${file##*/} did not extract"; return 1; }
    elif tar -tf "$file" >/dev/null 2>&1; then
        tar -xf "$file" -C "${dir}/x" 2>/dev/null || {
            log_error "unpack: ${file##*/} did not extract"; return 1; }
    else
        log_error "unpack: nothing here reads ${file##*/}"
        log_error "unpack: this machine has no libarchive, and ${file##*/} is not a format unzip or GNU tar covers"
        return 1
    fi

    found="$(find "${dir}/x" -type f -name "$want" -print 2>/dev/null | head -1)"
    [ -n "$found" ] || {
        log_error "unpack: no ${want} anywhere inside ${file##*/}"; return 1; }
    cp "$found" "${dir}/${want}"
}
