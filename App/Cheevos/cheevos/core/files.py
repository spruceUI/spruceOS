"""Small file helpers shared by modules that write user data."""

from __future__ import annotations

import logging
import os
from pathlib import Path

logger = logging.getLogger(__name__)


def write_text_atomic(path: Path, text: str, *, mode: int | None = None) -> None:
    """Write ``text`` to ``path`` atomically: temp file, flush + fsync, then rename.

    A power cut mid-write leaves either the old file or the new one, never a truncated file.

    Args:
        path: Destination file; parent directories are created.
        text: Content (UTF-8).
        mode: Optional permission bits applied to the file (best-effort, e.g. ``0o600``).
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    with temp.open("w", encoding="utf-8") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    if mode is not None:
        try:
            temp.chmod(mode)
        except OSError:
            logger.debug("Could not chmod %s (FAT32 has no permissions)", temp)
    temp.replace(path)
