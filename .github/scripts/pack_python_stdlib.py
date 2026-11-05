#!/usr/bin/env python3
"""Pack each bundled Python's pure stdlib into a sourceless lib/python310.zip.

Python 3.10 lists <prefix>/lib/python310.zip on its default sys.path ahead of
lib/python3.10, so the interpreters load the stdlib from the zip with no
environment change on the device. One zip replaces roughly 700 small files per
interpreter, and an SD card install pays per file, not per byte.

The zip is written as python310.zip.new. An update must never overwrite the zip
a running Python (the updater itself) imports from: zipimport keeps the old
table of contents and would read the new file at the old offsets. The device
moves the staged zip into place at boot, before anything starts Python; see
activate_python_stdlib_zip in spruce/scripts/runtimeHelper.sh.

The zip holds legacy-layout .pyc only (no sources): with no .py beside it,
zipimport loads the bytecode without a staleness check, and nothing tries to
write __pycache__ onto the card for the stdlib. Entries are stored, not
deflated, so the release 7z still compresses them.

Run this with CPython 3.10. The .pyc inside must carry 3.10's bytecode magic;
any 3.10.x writes the same one.

The release workflows' translate_path and activate_python_stdlib_zip mirror
LOOSE_ENTRIES and LOOSE_PREFIXES; change them together.
"""

from __future__ import annotations

import argparse
import compileall
import shutil
import sys
import tempfile
import zipfile
from collections.abc import Sequence
from pathlib import Path

STDLIB_DIR_NAME = "python3.10"
ZIP_NAME = "python310.zip"
STAGED_ZIP_NAME = ZIP_NAME + ".new"
REQUIRED_VERSION = (3, 10)

# os.py stays loose: it is the landmark Python uses to find its prefix.
# lib-dynload and site-packages hold native and third-party code; __pycache__
# is only ever stale device output.
LOOSE_ENTRIES = frozenset({"os.py", "lib-dynload", "site-packages", "__pycache__"})
LOOSE_PREFIXES = ("config-3.10",)


class PackError(Exception):
    """A stdlib tree could not be packed."""


def is_zipped_entry(name: str) -> bool:
    """Return whether a top-level stdlib entry belongs in the zip."""
    return name not in LOOSE_ENTRIES and not name.startswith(LOOSE_PREFIXES)


def zipped_entries(stdlib_dir: Path) -> list[Path]:
    """List the top-level entries of a stdlib directory that go into the zip."""
    return sorted(p for p in stdlib_dir.iterdir() if is_zipped_entry(p.name))


def stage_entries(entries: Sequence[Path], staging: Path) -> None:
    """Copy entries into a staging directory, leaving out existing bytecode."""
    ignore = shutil.ignore_patterns("__pycache__", "*.pyc")
    for entry in entries:
        target = staging / entry.name
        if entry.is_dir():
            shutil.copytree(entry, target, ignore=ignore)
        elif entry.suffix != ".pyc":
            shutil.copy2(entry, target)


def write_stored_zip(staging: Path, zip_path: Path) -> tuple[int, int]:
    """Write staged files to a stored zip, preferring .pyc over its source.

    A .py that failed to compile (deliberately broken test data) is stored as
    is; zipimport can still read it.

    Returns:
        The number of members written and how many of them are sources.
    """
    members = 0
    sources = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_STORED) as archive:
        for path in sorted(p for p in staging.rglob("*") if p.is_file()):
            if path.suffix == ".py" and path.with_suffix(".pyc").exists():
                continue
            archive.write(path, path.relative_to(staging).as_posix())
            members += 1
            sources += path.suffix == ".py"
    return members, sources


def remove_entries(entries: Sequence[Path]) -> None:
    """Delete zipped entries from the source tree."""
    for entry in entries:
        if entry.is_dir():
            shutil.rmtree(entry)
        else:
            entry.unlink()


def pack(lib_dir: Path, remove_sources: bool) -> Path:
    """Pack lib_dir/python3.10 into lib_dir/python310.zip.new.

    Args:
        lib_dir: An interpreter's lib directory, e.g. spruce/bin/python/lib.
        remove_sources: Delete the zipped entries from the tree afterwards.

    Returns:
        The path of the zip written.

    Raises:
        PackError: The interpreter is not 3.10, or lib_dir has no stdlib.
    """
    if sys.version_info[:2] != REQUIRED_VERSION:
        raise PackError(
            f"needs CPython {REQUIRED_VERSION[0]}.{REQUIRED_VERSION[1]} for matching "
            f"bytecode, running {sys.version_info[0]}.{sys.version_info[1]}"
        )
    stdlib_dir = lib_dir / STDLIB_DIR_NAME
    if not (stdlib_dir / "os.py").is_file():
        raise PackError(f"no stdlib at {stdlib_dir}: expected {stdlib_dir / 'os.py'}")

    entries = zipped_entries(stdlib_dir)
    zip_path = lib_dir / STAGED_ZIP_NAME
    with tempfile.TemporaryDirectory() as tmp:
        staging = Path(tmp)
        stage_entries(entries, staging)
        # ddir names each module by its place in the zip; without it,
        # tracebacks on the device would show this temporary directory.
        compileall.compile_dir(staging, ddir=ZIP_NAME, quiet=1, legacy=True)
        members, sources = write_stored_zip(staging, zip_path)

    if remove_sources:
        remove_entries(entries)
    print(
        f"{zip_path}: {members} members ({sources} uncompiled sources), "
        f"{zip_path.stat().st_size} bytes, from {len(entries)} top-level entries"
    )
    return zip_path


def main(argv: Sequence[str] | None = None) -> int:
    """Pack the stdlib of every lib directory given on the command line."""
    parser = argparse.ArgumentParser(
        description="Pack each bundled Python's pure stdlib into lib/python310.zip.new."
    )
    parser.add_argument(
        "lib_dirs", nargs="+", type=Path, help="interpreter lib directories"
    )
    parser.add_argument(
        "--remove-sources",
        action="store_true",
        help="delete the zipped entries from the tree after packing",
    )
    args = parser.parse_args(argv)
    try:
        for lib_dir in args.lib_dirs:
            pack(lib_dir, args.remove_sources)
    except PackError as error:
        print(f"pack_python_stdlib: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
