"""Read the newest unlocks without downloading complete game sets.

RA's date-range endpoint returns at most 500 rows, oldest first. Search backwards in
disjoint windows, narrowing a capped window before using it: its newest rows may be missing.
Bounds come from RA's library and profile dates, never the device's clock.
"""

from __future__ import annotations

from collections.abc import Callable

from cheevos.core.errors import ApiPayloadError
from cheevos.core.models import RECENT_UNLOCK_COUNT, RecentUnlock

MAX_REQUESTS = 64
INITIAL_WINDOW = 7 * 86_400
UnlockPage = tuple[list[RecentUnlock], bool]  # entries, possibly capped?


def fetch_recent_unlocks(
    fetch_page: Callable[[int, int], UnlockPage],
    *,
    start: int,
    end: int,
    count: int = RECENT_UNLOCK_COUNT,
    on_progress: Callable[[int], None] | None = None,
    initial_window: int = INITIAL_WINDOW,
) -> list[RecentUnlock]:
    """Fetch up to ``count`` distinct achievements, newest unlock first.

    Prefer the newest event per achievement; hardcore wins a same-second mode duplicate.
    A capped single second cannot be paged safely by this API, so fail rather than publish
    an incomplete feed. Callers keep their previous snapshot on any failure or cancellation.

    Args:
        fetch_page: Return parsed rows and whether the raw response hit RA's cap.
        start: Inclusive history floor (RA's registration date, or zero if unknown).
        end: Inclusive latest unlock date from RA's game list.
        count: Maximum number of distinct achievements.
        on_progress: Report distinct entries found, without claiming a known total.
        initial_window: Initial window width; small accounts can fit their whole history.

    Returns:
        Entries in descending unlock-date and achievement-ID order.

    Raises:
        ApiPayloadError: A capped timestamp or request budget prevents complete coverage.
    """
    if count <= 0 or end < start:
        return []
    entries: dict[int, RecentUnlock] = {}
    cursor, width = end, max(initial_window, 1)
    for _request in range(MAX_REQUESTS):
        first = max(start, cursor - width + 1)
        page, capped = fetch_page(first, cursor)
        if capped:
            if first == cursor:
                raise ApiPayloadError("recent unlocks: too many unlocks at one timestamp")
            width = max((cursor - first + 1) // 2, 1)
            continue
        _merge(entries, page, first, cursor)
        if on_progress is not None:
            on_progress(min(len(entries), count))
        if len(entries) >= count or first == start:
            return sorted(
                entries.values(),
                key=lambda entry: (
                    -(entry.achievement.unlocked_at or 0),
                    -entry.achievement.achievement_id,
                ),
            )[:count]
        cursor = first - 1
        width *= 2
    raise ApiPayloadError("recent unlocks: history coverage exceeded the request budget")


def _merge(
    entries: dict[int, RecentUnlock], page: list[RecentUnlock], start: int, end: int
) -> None:
    """Merge one complete window, ignoring invalid bounds and duplicate mode rows."""
    for entry in page:
        achievement = entry.achievement
        when = achievement.unlocked_at
        if when is None or not start <= when <= end:
            continue
        previous = entries.get(achievement.achievement_id)
        if previous is None or (when, achievement.hardcore) > (
            previous.achievement.unlocked_at or 0,
            previous.achievement.hardcore,
        ):
            entries[achievement.achievement_id] = entry
