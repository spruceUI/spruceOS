"""User settings, stored as plain JSON in ``Saves/cheevos/settings.json`` (.agents/product.md).

Loading never fails: a missing or corrupt file gives the defaults, and each invalid or missing
key falls back to its own default. Unknown keys are ignored. Saving is atomic.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any

from cheevos.core.files import write_text_atomic

logger = logging.getLogger(__name__)

RECENT_DAYS_CHOICES = (7, 30, 90)


class DescriptionHiding(Enum):
    """Which locked achievements hide their description (spoilers).

    RA has no spoiler flag; its type tags are the closest data: progression and win-condition
    achievements are the story beats and the ending. Sets without type tags (mostly older ones)
    hide nothing in ``STORY`` mode.
    """

    OFF = "off"
    STORY = "story"  # progression and win-condition achievements
    ALL = "all"


class BadgeScope(Enum):
    """Which games' badges a sync downloads."""

    ON_DEVICE_AND_RECENT = "on-device-and-recent"
    ALL = "all"
    NONE = "none"


@dataclass(frozen=True, slots=True)
class Settings:
    """User-adjustable settings.

    Attributes:
        badge_scope: Which games' badges sync downloads.
        recent_days: Window that makes a game "recent" (one of 7, 30, 90).
        hide_descriptions: Which locked achievements hide their description (spoilers).
        auto_sync: Sync automatically when the app opens and the network is up.
        game_list_details: The games list shows console and last activity instead of
            progress bars (toggled with Select).
    """

    badge_scope: BadgeScope = BadgeScope.ON_DEVICE_AND_RECENT
    recent_days: int = 30
    hide_descriptions: DescriptionHiding = DescriptionHiding.OFF
    auto_sync: bool = True
    game_list_details: bool = False


DEFAULTS = Settings()


def _badge_scope(raw: object) -> BadgeScope:
    """Parse a badge scope value.

    Args:
        raw: Value from JSON.

    Returns:
        The scope, or the default for anything unrecognised.
    """
    try:
        return BadgeScope(raw)
    except ValueError:
        return DEFAULTS.badge_scope


def _recent_days(raw: object) -> int:
    """Parse the recent-window value.

    Args:
        raw: Value from JSON.

    Returns:
        One of :data:`RECENT_DAYS_CHOICES`, or the default.
    """
    if isinstance(raw, int) and not isinstance(raw, bool) and raw in RECENT_DAYS_CHOICES:
        return raw
    return DEFAULTS.recent_days


def _flag(raw: object, *, default: bool) -> bool:
    """Parse a boolean value strictly (no truthiness).

    Args:
        raw: Value from JSON.
        default: Value to use when ``raw`` is not a boolean.

    Returns:
        The boolean.
    """
    return raw if isinstance(raw, bool) else default


def _hiding(data: dict[str, Any]) -> DescriptionHiding:
    """Parse the spoiler setting, accepting the older on/off form.

    Args:
        data: Decoded settings JSON.

    Returns:
        The setting, or the default for anything unrecognised.
    """
    raw = data.get("hide_descriptions")
    try:
        return DescriptionHiding(raw)
    except ValueError:
        legacy = data.get("hide_locked_descriptions")  # before 2026-10-05: a boolean
        if isinstance(legacy, bool):
            return DescriptionHiding.ALL if legacy else DescriptionHiding.OFF
        return DEFAULTS.hide_descriptions


def settings_from_dict(data: dict[str, Any]) -> Settings:
    """Build settings from decoded JSON, defaulting each invalid or missing key.

    Args:
        data: Decoded JSON object.

    Returns:
        The settings.
    """
    return Settings(
        badge_scope=_badge_scope(data.get("badge_scope")),
        recent_days=_recent_days(data.get("recent_days")),
        hide_descriptions=_hiding(data),
        auto_sync=_flag(data.get("auto_sync"), default=DEFAULTS.auto_sync),
        game_list_details=_flag(data.get("game_list_details"), default=DEFAULTS.game_list_details),
    )


def settings_to_dict(settings: Settings) -> dict[str, Any]:
    """Convert settings to a JSON-ready dict with a stable key order.

    Args:
        settings: Settings to convert.

    Returns:
        The dict.
    """
    return {
        "badge_scope": settings.badge_scope.value,
        "recent_days": settings.recent_days,
        "hide_descriptions": settings.hide_descriptions.value,
        "auto_sync": settings.auto_sync,
        "game_list_details": settings.game_list_details,
    }


def load_settings(path: Path) -> Settings:
    """Load settings, falling back to defaults for anything missing or invalid.

    Args:
        path: ``settings.json``.

    Returns:
        The settings (defaults when the file is missing or corrupt).
    """
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return DEFAULTS
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        logger.warning("Ignoring unreadable settings file %s: %s", path, exc)
        return DEFAULTS
    if not isinstance(data, dict):
        logger.warning("Ignoring settings file %s: not a JSON object", path)
        return DEFAULTS
    return settings_from_dict(data)


def save_settings(path: Path, settings: Settings) -> None:
    """Save settings atomically.

    Args:
        path: ``settings.json``; its directory is created if needed.
        settings: Settings to save.
    """
    text = json.dumps(settings_to_dict(settings), indent=4) + "\n"
    write_text_atomic(path, text)
