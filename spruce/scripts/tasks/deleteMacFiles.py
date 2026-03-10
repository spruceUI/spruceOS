#!/usr/bin/env python3
"""Delete macOS junk files from the SD card."""

import os
import shutil

SDCARD = "/mnt/SDCARD"

JUNK_NAMES = {
    ".DS_Store",
    ".DocumentRevisions-V100",
    ".Spotlight-V100",
    ".TemporaryItems",
    ".Trashes",
    ".fseventsd",
    ".VolumeIcon.icns",
    "__MACOSX",
    ".apdisk",
}

# AppleDouble magic bytes: 00 05 16 07
APPLE_DOUBLE_MAGIC = b"\x00\x05\x16\x07"


def is_apple_double(path):
    """Check if a file has the AppleDouble header."""
    try:
        with open(path, "rb") as f:
            return f.read(4) == APPLE_DOUBLE_MAGIC
    except (OSError, IOError):
        return False


def should_delete(name, path):
    if name in JUNK_NAMES:
        return True
    if name.startswith("._"):
        return True
    if os.path.isfile(path) and is_apple_double(path):
        return True
    return False


def clean(root):
    deleted = 0
    for dirpath, dirnames, filenames in os.walk(root, topdown=True):
        # Check directories (iterate copy since we may modify dirnames)
        for d in list(dirnames):
            full = os.path.join(dirpath, d)
            if should_delete(d, full):
                shutil.rmtree(full, ignore_errors=True)
                dirnames.remove(d)
                deleted += 1

        for f in filenames:
            full = os.path.join(dirpath, f)
            if should_delete(f, full):
                try:
                    os.remove(full)
                except OSError:
                    pass
                deleted += 1

    return deleted


if __name__ == "__main__":
    count = clean(SDCARD)
    print(f"Deleted {count} macOS junk file(s).")
