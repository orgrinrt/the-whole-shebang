#!/usr/bin/env bash
# Taking a named file out of an archive, through libarchive.
#
# The variant the gate picks first, because libarchive reads everything a
# release is likely to publish: tar, gzip, bzip2, xz, zstd, zip, 7z, cpio, ar,
# iso9660 and cab. One tool, no format table, nothing to install.
#
# **It is on both machines already and neither of them chose it.** On Artix it
# is `bsdtar`, from the `libarchive` package `pacman` itself depends on, so a
# machine that can install software has it by construction. On macOS it is
# `/usr/bin/tar`, which is bsdtar under the other name. `bsdtar` and libarchive
# are not two things to write two paths for; the first is the second's command
# line.

use log

# Where the extractor is, since it answers to two names.
#
# Not a `command -v bsdtar` at each call. The gate in `lib.nut` has already
# established that one of them exists, and this only has to say which.
_unpack_libarchive_bin() {
    if command -v bsdtar >/dev/null 2>&1; then printf 'bsdtar'; return 0; fi
    if tar --version 2>&1 | head -1 | grep -qi 'bsdtar\|libarchive'; then printf 'tar'; return 0; fi
    return 1
}

#[pub]
# Whether this can read that file at all.
#
# Asked rather than sniffed. Comparing the first bytes against a table of magic
# numbers is a table that is wrong the day somebody publishes for a format it
# does not list, and the extractor already knows the answer.
# Usage: unpack_reads <file>
unpack_reads() {
    local file="${1:-}" bin
    [ -r "$file" ] || return 1
    bin="$(_unpack_libarchive_bin)" || return 1
    "$bin" -tf "$file" >/dev/null 2>&1
}

#[pub]
# Pull one named file out of an archive, into a directory.
#
# **Searched rather than assumed flat.** An archive holding `linux/kanata` is as
# ordinary as one holding `kanata`, and a project is free to change which
# between releases, so the name is looked for anywhere inside.
#
# **A miss is a failure and never a guess.** Picking the only executable in
# there is how a machine ends up with an installer stub instead of the tool.
# Usage: unpack_extract <archive> <dest dir> <name to find>
unpack_extract() {
    local file="${1:-}" dir="${2:-}" want="${3:-}" bin found
    [ -n "$file" ] && [ -n "$dir" ] && [ -n "$want" ] || {
        log_error "unpack_extract: wants an archive, a destination and a name"; return 2; }
    bin="$(_unpack_libarchive_bin)" || {
        log_error "unpack: no libarchive here, which the gate should have caught"; return 2; }

    mkdir -p "${dir}/x" || return 1
    "$bin" -xf "$file" -C "${dir}/x" 2>/dev/null || {
        log_error "unpack: ${file##*/} did not extract"; return 1; }

    found="$(find "${dir}/x" -type f -name "$want" -print 2>/dev/null | head -1)"
    [ -n "$found" ] || {
        log_error "unpack: no ${want} anywhere inside ${file##*/}"; return 1; }
    cp "$found" "${dir}/${want}"
}
