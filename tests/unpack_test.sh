#!/usr/bin/env bash
# Tests for getting a named file out of whatever a release published.
#
# The subject is a specific way this goes wrong quietly. An extractor that
# cannot read the archive is not a signal anybody sees: the last arm treats the
# file as a bare binary, copies it under the wanted name with mode 0755, and
# reports the install as done. The failure surfaces later, somewhere else, as
# `Exec format error`.
#
# So most of what is below is about the refusals rather than about extracting,
# and every positive case has a negative beside it.

use test

# **Each variant is sourced by its own test, not through `use`.** The point of
# the module is that `lib.nut` picks between two implementations by what the
# machine has, so a suite that went through `use` would exercise whichever one
# this machine happens to select and say nothing at all about the other. The
# harness runs every test in its own subshell, so sourcing a different file per
# test is safe and the definitions do not leak between them.
_up_libarchive() { . "${BASH_SOURCE[0]%/*}/../libs/unpack/libarchive.sh"; }
_up_split()      { . "${BASH_SOURCE[0]%/*}/../libs/unpack/split.sh"; }

_up_setup() {
    UPROOT="$(mktemp -d)"
    mkdir -p "$UPROOT/src/linux" "$UPROOT/out"
    printf '#!/bin/sh\necho payload\n' > "$UPROOT/src/linux/thing"
}
_up_end() { rm -rf "$UPROOT"; unset UPROOT; }

#[test]
it_takes_the_named_file_out_of_a_tarball_through_libarchive() {
    _up_libarchive
    _up_setup
    tar -cf "$UPROOT/a.tar" -C "$UPROOT/src" .
    assert_ok unpack_reads "$UPROOT/a.tar"
    assert_ok unpack_extract "$UPROOT/a.tar" "$UPROOT/out" thing
    assert_contains "$(cat "$UPROOT/out/thing")" "echo payload"
    _up_end
}

#[test]
it_takes_the_named_file_out_of_a_zip_through_libarchive() {
    _up_libarchive
    # The format GNU tar cannot read, which is the whole reason the gate
    # prefers libarchive. Skipped only where nothing here can build a zip to
    # test against, and the suffix test below covers the machine either way.
    _up_setup
    command -v zip >/dev/null 2>&1 || { _up_end; return 0; }
    ( cd "$UPROOT/src" && zip -qr "$UPROOT/a.zip" . )
    assert_ok unpack_reads "$UPROOT/a.zip"
    assert_ok unpack_extract "$UPROOT/a.zip" "$UPROOT/out" thing
    assert_contains "$(cat "$UPROOT/out/thing")" "echo payload"
    _up_end
}

#[test]
it_finds_the_file_wherever_it_sits_inside_through_libarchive() {
    _up_libarchive
    # An archive holding `linux/kanata` is as ordinary as one holding `kanata`,
    # and a project is free to change which between releases.
    _up_setup
    mkdir -p "$UPROOT/src/deep/deeper"
    printf '#!/bin/sh\necho deep\n' > "$UPROOT/src/deep/deeper/buried"
    tar -cf "$UPROOT/b.tar" -C "$UPROOT/src" .
    assert_ok unpack_extract "$UPROOT/b.tar" "$UPROOT/out" buried
    assert_contains "$(cat "$UPROOT/out/buried")" "echo deep"
    _up_end
}

#[test]
it_refuses_rather_than_guessing_when_the_name_is_not_inside_through_libarchive() {
    _up_libarchive
    # Taking the only executable in there is how a machine ends up with an
    # installer stub instead of the tool.
    _up_setup
    tar -cf "$UPROOT/c.tar" -C "$UPROOT/src" .
    assert_fails unpack_extract "$UPROOT/c.tar" "$UPROOT/out" not-in-there
    assert_fails test -e "$UPROOT/out/not-in-there"
    _up_end
}

#[test]
it_says_no_to_a_file_it_cannot_read_through_libarchive() {
    _up_libarchive
    _up_setup
    printf 'this is not an archive in any format\n' > "$UPROOT/plain"
    assert_fails unpack_reads "$UPROOT/plain"
    assert_fails unpack_reads "$UPROOT/does-not-exist"
    _up_end
}

#[test]
it_wants_all_three_arguments_through_libarchive() {
    _up_libarchive
    _up_setup
    tar -cf "$UPROOT/d.tar" -C "$UPROOT/src" .
    assert_fails unpack_extract
    assert_fails unpack_extract "$UPROOT/d.tar"
    assert_fails unpack_extract "$UPROOT/d.tar" "$UPROOT/out"
    _up_end
}

# The control that makes the rest mean something: an extractor that reported
# success on a file it never opened would pass every positive case above.
#[test]
it_does_not_report_success_on_an_empty_extraction_through_libarchive() {
    _up_libarchive
    _up_setup
    : > "$UPROOT/empty.tar"
    assert_fails unpack_extract "$UPROOT/empty.tar" "$UPROOT/out" thing
    assert_fails test -e "$UPROOT/out/thing"
    _up_end
}

#[test]
it_takes_the_named_file_out_of_a_tarball_through_the_split_pair() {
    _up_split
    _up_setup
    tar -cf "$UPROOT/a.tar" -C "$UPROOT/src" .
    assert_ok unpack_reads "$UPROOT/a.tar"
    assert_ok unpack_extract "$UPROOT/a.tar" "$UPROOT/out" thing
    assert_contains "$(cat "$UPROOT/out/thing")" "echo payload"
    _up_end
}

#[test]
it_takes_the_named_file_out_of_a_zip_through_the_split_pair() {
    _up_split
    # The format GNU tar cannot read, which is the whole reason the gate
    # prefers libarchive. Skipped only where nothing here can build a zip to
    # test against, and the suffix test below covers the machine either way.
    _up_setup
    command -v zip >/dev/null 2>&1 || { _up_end; return 0; }
    ( cd "$UPROOT/src" && zip -qr "$UPROOT/a.zip" . )
    assert_ok unpack_reads "$UPROOT/a.zip"
    assert_ok unpack_extract "$UPROOT/a.zip" "$UPROOT/out" thing
    assert_contains "$(cat "$UPROOT/out/thing")" "echo payload"
    _up_end
}

#[test]
it_finds_the_file_wherever_it_sits_inside_through_the_split_pair() {
    _up_split
    # An archive holding `linux/kanata` is as ordinary as one holding `kanata`,
    # and a project is free to change which between releases.
    _up_setup
    mkdir -p "$UPROOT/src/deep/deeper"
    printf '#!/bin/sh\necho deep\n' > "$UPROOT/src/deep/deeper/buried"
    tar -cf "$UPROOT/b.tar" -C "$UPROOT/src" .
    assert_ok unpack_extract "$UPROOT/b.tar" "$UPROOT/out" buried
    assert_contains "$(cat "$UPROOT/out/buried")" "echo deep"
    _up_end
}

#[test]
it_refuses_rather_than_guessing_when_the_name_is_not_inside_through_the_split_pair() {
    _up_split
    # Taking the only executable in there is how a machine ends up with an
    # installer stub instead of the tool.
    _up_setup
    tar -cf "$UPROOT/c.tar" -C "$UPROOT/src" .
    assert_fails unpack_extract "$UPROOT/c.tar" "$UPROOT/out" not-in-there
    assert_fails test -e "$UPROOT/out/not-in-there"
    _up_end
}

#[test]
it_says_no_to_a_file_it_cannot_read_through_the_split_pair() {
    _up_split
    _up_setup
    printf 'this is not an archive in any format\n' > "$UPROOT/plain"
    assert_fails unpack_reads "$UPROOT/plain"
    assert_fails unpack_reads "$UPROOT/does-not-exist"
    _up_end
}

#[test]
it_wants_all_three_arguments_through_the_split_pair() {
    _up_split
    _up_setup
    tar -cf "$UPROOT/d.tar" -C "$UPROOT/src" .
    assert_fails unpack_extract
    assert_fails unpack_extract "$UPROOT/d.tar"
    assert_fails unpack_extract "$UPROOT/d.tar" "$UPROOT/out"
    _up_end
}

# The control that makes the rest mean something: an extractor that reported
# success on a file it never opened would pass every positive case above.
#[test]
it_does_not_report_success_on_an_empty_extraction_through_the_split_pair() {
    _up_split
    _up_setup
    : > "$UPROOT/empty.tar"
    assert_fails unpack_extract "$UPROOT/empty.tar" "$UPROOT/out" thing
    assert_fails test -e "$UPROOT/out/thing"
    _up_end
}

# The arm that produced the original defect, reached deliberately.
#
# It is unreachable on any machine whose `tar` is bsdtar, which is every mac and
# anything with libarchive, so the mutation that removed it changed nothing and
# the suite stayed green. That is precisely the hole the whole module exists to
# close, reproduced inside its own tests: a branch nobody can enter is a branch
# nobody has checked.
#
# Both tools are stubbed to fail, so the archive is real and unreadable and the
# last arm is the one that runs.
#[test]
the_split_pair_refuses_when_neither_of_its_tools_can_read_it() {
    _up_setup
    . "${BASH_SOURCE[0]%/*}/../libs/unpack/split.sh"
    tar -cf "$UPROOT/e.tar" -C "$UPROOT/src" .

    mkdir -p "$UPROOT/stub"
    printf '#!/bin/sh\nexit 1\n' > "$UPROOT/stub/tar"
    printf '#!/bin/sh\nexit 1\n' > "$UPROOT/stub/unzip"
    chmod +x "$UPROOT/stub/tar" "$UPROOT/stub/unzip"
    local saved="$PATH"; PATH="$UPROOT/stub:$PATH"; hash -r 2>/dev/null || true

    assert_fails unpack_reads "$UPROOT/e.tar"
    assert_fails unpack_extract "$UPROOT/e.tar" "$UPROOT/out" thing
    assert_fails test -e "$UPROOT/out/thing"

    PATH="$saved"; hash -r 2>/dev/null || true
    _up_end
}

# The control for it: with the stubs gone the same archive extracts, so the
# test above is measuring the stubs rather than a broken fixture.
#[test]
the_same_archive_extracts_once_the_stubs_are_out_of_the_way() {
    _up_setup
    . "${BASH_SOURCE[0]%/*}/../libs/unpack/split.sh"
    tar -cf "$UPROOT/f.tar" -C "$UPROOT/src" .
    assert_ok unpack_extract "$UPROOT/f.tar" "$UPROOT/out" thing
    assert_contains "$(cat "$UPROOT/out/thing")" "echo payload"
    _up_end
}
