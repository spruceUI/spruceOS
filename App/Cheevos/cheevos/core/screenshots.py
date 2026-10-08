"""Unlock screenshots saved by RetroArch (.agents/integration.md).

With ``cheevos_auto_screenshot = true`` RetroArch writes
``<screenshot_directory>/<rom basename>-cheevo-<achievementID>.png``. The index maps achievement
IDs to those files, ignoring RA's warning pseudo-achievement.
"""

from __future__ import annotations

import logging
import re
from pathlib import Path

from cheevos.core.credentials import read_retroarch_setting
from cheevos.core.models import WARNING_ACHIEVEMENT_ID
from cheevos.platform.paths import Paths

logger = logging.getLogger(__name__)

_SCREENSHOT_NAME = re.compile(r"^.+-cheevo-(\d+)\.png$", re.IGNORECASE)


def screenshot_directory(paths: Paths) -> Path:
    """Return the directory RetroArch saves screenshots to.

    RetroArch marks "use the default" with ``default``, an empty value or a ``:``-prefixed
    (relative to the RetroArch dir) path; only an absolute path overrides Spruce's default.

    Args:
        paths: Resolved paths.

    Returns:
        The configured absolute directory, or ``Saves/screenshots``.
    """
    value = read_retroarch_setting(paths.retroarch_config, "screenshot_directory")
    if value and value.startswith("/"):
        return Path(value)
    return paths.default_screenshot_dir


class ScreenshotIndex:
    """Achievement ID to unlock screenshot, rescanned lazily when the directory changes.

    Args:
        directory: Screenshot directory (may not exist yet).
    """

    def __init__(self, directory: Path) -> None:
        self._directory = directory
        self._scanned_mtime: float | None = None
        self._index: dict[int, Path] = {}

    def _directory_mtime(self) -> float | None:
        """Return the directory's modification time, or ``None`` if it is missing."""
        try:
            return self._directory.stat().st_mtime
        except OSError:
            return None

    def _refresh(self) -> None:
        """Rescan if the directory's mtime changed since the last scan."""
        mtime = self._directory_mtime()
        if mtime is None:
            self._index = {}
            self._scanned_mtime = None
            return
        if mtime == self._scanned_mtime:
            return
        self._index = self._scan()
        self._scanned_mtime = mtime
        logger.debug("Indexed %d unlock screenshots in %s", len(self._index), self._directory)

    def _scan(self) -> dict[int, Path]:
        """Build the index from the directory listing; the newest file wins per achievement.

        Returns:
            Achievement ID to screenshot path.
        """
        index: dict[int, Path] = {}
        newest: dict[int, float] = {}
        try:
            entries = list(self._directory.iterdir())
        except OSError as exc:
            logger.warning("Cannot list screenshots in %s: %s", self._directory, exc)
            return index
        for path in entries:
            match = _SCREENSHOT_NAME.match(path.name)
            if match is None:
                continue
            achievement_id = int(match.group(1))
            if achievement_id == WARNING_ACHIEVEMENT_ID:
                continue
            try:
                mtime = path.stat().st_mtime
            except OSError:
                continue
            if achievement_id not in newest or mtime > newest[achievement_id]:
                newest[achievement_id] = mtime
                index[achievement_id] = path
        return index

    def lookup(self, achievement_id: int) -> Path | None:
        """Return the unlock screenshot for an achievement.

        Args:
            achievement_id: RA achievement ID.

        Returns:
            The newest matching screenshot, or ``None``.
        """
        self._refresh()
        return self._index.get(achievement_id)

    def count(self) -> int:
        """Return how many achievements have a screenshot."""
        self._refresh()
        return len(self._index)
