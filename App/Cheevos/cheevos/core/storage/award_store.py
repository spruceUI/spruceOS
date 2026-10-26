"""Awards and events in the data cache (``data.db``; mixed into :class:`DataCache`).

The awards are RA's visible list, kept in its order (``position``); event details come from
RA's v2 API and are kept for offline browsing (.agents/sync-and-storage.md).
"""

from __future__ import annotations

import dataclasses
import json
import logging
import sqlite3
from collections.abc import Iterable

from cheevos.core.awards import GalleryCounts, gallery_counts
from cheevos.core.models import Award, AwardCounts, AwardKind, AwardType, EventInfo, EventTier
from cheevos.core.storage.schema import AWARD_COLUMNS, award_filter, award_from_row, award_row

logger = logging.getLogger(__name__)

_AWARD_COUNTS_KEY = "award_counts"
_GALLERY_COUNTS_KEY = "gallery_counts"


class AwardStore:
    """Award and event storage for :class:`~cheevos.core.storage.data_cache.DataCache`.

    Attributes:
        _db: The cache's connection (set by the cache).
    """

    _db: sqlite3.Connection

    def _stored(self, key: str, kind: type[AwardCounts] | type[GalleryCounts]) -> object | None:
        """Read counters stored as JSON in ``meta``, ignoring unreadable ones.

        Args:
            key: Meta key.
            kind: The counters' dataclass.

        Returns:
            The counters, or ``None`` if never stored (or unreadable).
        """
        row = self._db.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
        if row is None:
            return None
        try:
            return kind(**json.loads(row[0]))
        except (TypeError, ValueError):
            logger.warning("Stored %s are unreadable; ignoring them", key.replace("_", " "))
            return None

    def save_awards(self, counts: AwardCounts, awards: list[Award]) -> None:
        """Replace the stored awards and award counters.

        Args:
            counts: Counters from RA.
            awards: Visible awards from RA, of every type.
        """
        insert = (
            f"INSERT INTO awards ({AWARD_COLUMNS}) "  # noqa: S608
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        )
        shown = gallery_counts(awards)
        with self._db:
            self._db.execute("DELETE FROM awards")
            self._db.executemany(insert, [award_row(award) for award in awards])
            self._db.executemany(
                "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
                [
                    (_AWARD_COUNTS_KEY, json.dumps(dataclasses.asdict(counts))),
                    (_GALLERY_COUNTS_KEY, json.dumps(dataclasses.asdict(shown))),
                ],
            )

    def award_counts(self) -> AwardCounts | None:
        """Return RA's award counters, without reading the awards.

        Returns:
            The counters, or ``None`` if awards were never synced.
        """
        counts = self._stored(_AWARD_COUNTS_KEY, AwardCounts)
        return counts if isinstance(counts, AwardCounts) else None

    def gallery_counts(self) -> GalleryCounts | None:
        """Return how many awards each gallery shows, without reading them (home summary).

        Returns:
            The counts, or ``None`` if awards were never synced.
        """
        counts = self._stored(_GALLERY_COUNTS_KEY, GalleryCounts)
        return counts if isinstance(counts, GalleryCounts) else None

    def awards(
        self, kind: AwardKind | None = None, *, gallery: bool = False
    ) -> tuple[AwardCounts | None, list[Award]]:
        """Return the award counters and visible awards, in RA's order.

        Reading 3,904 awards takes 0.27 s on a Miyoo Mini+, so callers read only what they use.

        Args:
            kind: Only game awards of this kind (the profile's stats).
            gallery: Leave out beaten awards, which the galleries never show (most of a big
                account's awards).

        Returns:
            ``(counts, awards)``; counts is ``None`` if awards were never synced.
        """
        counts = self.award_counts()
        if kind is not None:
            where, params = award_filter(kind)
        elif gallery:
            where, params = "WHERE type != ? ", (AwardType.GAME_BEATEN.value,)
        else:
            where, params = "", ()
        rows = self._db.execute(
            f"SELECT {AWARD_COLUMNS} FROM awards {where}ORDER BY position, rowid",  # noqa: S608
            params,
        ).fetchall()
        return counts, [award_from_row(row) for row in rows]

    def save_events(self, events: Iterable[EventInfo], asked: Iterable[int], at: int) -> None:
        """Store events' details, replacing what was known about every event asked for.

        Args:
            events: The events RA returned.
            asked: Every event ID requested: those RA didn't return are remembered as
                fetched, without details, so they aren't asked for at every sync.
            at: When they were fetched.
        """
        found = {event.event_id: event for event in events}
        rows = [
            (event_id, event.title, event.image, event.points, at)
            if (event := found.get(event_id)) is not None
            else (event_id, "", "", None, at)
            for event_id in set(asked) | set(found)
        ]
        tiers = [
            (event.event_id, tier.tier, tier.label, tier.points, tier.image)
            for event in found.values()
            for tier in event.tiers
        ]
        with self._db:
            self._db.executemany("DELETE FROM events WHERE event_id = ?", [(r[0],) for r in rows])
            self._db.executemany("INSERT INTO events VALUES (?, ?, ?, ?, ?)", rows)
            self._db.executemany("INSERT OR REPLACE INTO event_tiers VALUES (?, ?, ?, ?, ?)", tiers)

    def event_fetch_times(self) -> dict[int, int]:
        """Return when each known event was last fetched.

        Returns:
            Event ID to time.
        """
        rows = self._db.execute("SELECT event_id, fetched_at FROM events").fetchall()
        return {row[0]: row[1] for row in rows}

    def events(self) -> dict[int, EventInfo]:
        """Return every event fetched with details (offline browsing uses these).

        Returns:
            Event ID to event, with its tiers.
        """
        tiers: dict[int, list[EventTier]] = {}
        for row in self._db.execute(
            "SELECT event_id, tier, label, points, image FROM event_tiers ORDER BY event_id, tier"
        ):
            tiers.setdefault(row[0], []).append(EventTier(row[1], row[2], row[3], row[4]))
        rows = self._db.execute(
            "SELECT event_id, title, image, points FROM events WHERE title != ''"
        )
        return {
            row[0]: EventInfo(row[0], row[1], row[2], tuple(tiers.get(row[0], ())), row[3])
            for row in rows
        }
