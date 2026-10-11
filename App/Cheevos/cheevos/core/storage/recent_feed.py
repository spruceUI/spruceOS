"""Store a bounded recent-unlock snapshot in data.db's existing metadata table.

The versioned payload keeps updates atomic and avoids rebuilding users' downloaded game
sets for a new SQL schema. Feed rows never mark a complete achievement set as downloaded.
"""

from __future__ import annotations

import dataclasses
import hashlib
import json
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Protocol

from cheevos.core.models import (
    RECENT_UNLOCK_COUNT,
    Achievement,
    AchievementType,
    GameProgress,
    RecentUnlock,
)

FEED_KEY = "recent_unlock_feed"
_VERSION = 1


class Metadata(Protocol):
    """Read and atomically write metadata (implemented by DataCache)."""

    def get_meta(self, key: str) -> str | None:
        """Return a stored value, or None."""
        ...

    def set_meta(self, key: str, value: str | None) -> None:
        """Replace a stored value in one transaction."""
        ...


@dataclass(frozen=True, slots=True)
class RecentFeed:
    """Keep a complete feed and the library state it represents.

    Attributes:
        entries: At most 100 entries, newest first.
        fingerprint: Library fingerprint, for detecting new unlocks and resets.
        synced_at: When the snapshot was downloaded (app time).
    """

    entries: tuple[RecentUnlock, ...]
    fingerprint: str
    synced_at: int


def library_fingerprint(games: Sequence[GameProgress]) -> str:
    """Fingerprint unlock-bearing games, ignoring ordinary play activity."""
    states = sorted(
        (game.game_id, game.fingerprint) for game in games if game.earned or game.earned_hardcore
    )
    return hashlib.sha256(json.dumps(states).encode()).hexdigest()


class RecentFeedCache:
    """Read and replace a recent-unlock snapshot on the owning cache thread.

    Args:
        data: The account's data cache.
    """

    def __init__(self, data: Metadata) -> None:
        self._data = data

    def save(self, feed: RecentFeed) -> None:
        """Replace the feed only after its newest entries are fully covered."""
        payload = {
            "version": _VERSION,
            "fingerprint": feed.fingerprint,
            "synced_at": feed.synced_at,
            "entries": [_encode(entry) for entry in feed.entries[:RECENT_UNLOCK_COUNT]],
        }
        self._data.set_meta(FEED_KEY, json.dumps(payload))

    def load(self) -> RecentFeed | None:
        """Return the stored snapshot, or None for absent, corrupt or unknown versions."""
        raw = self._data.get_meta(FEED_KEY)
        if raw is None:
            return None
        try:
            payload = json.loads(raw)
            if payload["version"] != _VERSION or len(payload["entries"]) > RECENT_UNLOCK_COUNT:
                return None
            entries = tuple(_entry(row) for row in payload["entries"])
            return RecentFeed(entries, str(payload["fingerprint"]), int(payload["synced_at"]))
        except (KeyError, TypeError, ValueError, AttributeError):
            return None


def _encode(entry: RecentUnlock) -> dict:
    """Encode the nested definition with its type tag stored as an RA string."""
    row = dataclasses.asdict(entry)
    kind = entry.achievement.type
    row["achievement"]["type"] = kind.value if kind else None
    return row


def _entry(row: dict) -> RecentUnlock:
    """Decode one definition, restoring its type enum and checking its unlock date."""
    fields = dict(row["achievement"])
    fields["type"] = AchievementType(fields["type"]) if fields["type"] else None
    achievement = Achievement(**fields)
    if achievement.achievement_id <= 0 or not isinstance(achievement.unlocked_at, int):
        raise ValueError("invalid cached unlock")
    return RecentUnlock(achievement, row["game_title"], row["game_icon"], row["console_name"])
