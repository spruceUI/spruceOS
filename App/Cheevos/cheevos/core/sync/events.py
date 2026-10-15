"""Fetch the details of the events the player has awards for (.agents/sync-and-storage.md).

The v1 awards list names an event award's tier; its label, its points, its badge and what the
whole event is worth come from RA's v2 API (.agents/retroachievements.md, "Event tiers").
Events are fetched when first seen, when an award was earned since they were fetched, and
after :data:`EVENT_REFRESH`. If the v2 API refuses or answers oddly, the awards still show
with RA's own titles and images; network failures and RA's pauses stop the sync as usual.
"""

from __future__ import annotations

import logging
import threading
from dataclasses import replace

from cheevos.core.awards import gallery, is_event
from cheevos.core.errors import ApiPayloadError, AuthError, RequestCancelledError
from cheevos.core.models import Award, EventInfo
from cheevos.core.ra_client.client import RaClient
from cheevos.core.storage.data_cache import DataCache
from cheevos.core.sync.planner import DAY

logger = logging.getLogger(__name__)

EVENT_REFRESH = 30 * DAY  # tiers rarely change: refetch them like stale game details


def stale_events(awards: list[Award], fetched: dict[int, int], now: int) -> list[int]:
    """Return the events whose details should be fetched.

    Args:
        awards: The visible awards.
        fetched: When each known event was last fetched.
        now: Current time.

    Returns:
        Event IDs, in order.
    """
    return sorted(
        {
            award.data
            for award in gallery(awards)
            if is_event(award)
            and (
                (at := fetched.get(award.data)) is None
                or now - at > EVENT_REFRESH
                or (award.awarded_at or 0) > at
            )
        }
    )


def sync_events(
    client: RaClient, data: DataCache, awards: list[Award], now: int, cancel: threading.Event
) -> None:
    """Fetch and store the details of new, re-earned or stale events.

    Args:
        client: RA client.
        data: The data cache.
        awards: The visible awards.
        now: Current time.
        cancel: Set to stop before the next request.

    Raises:
        RequestCancelledError: The sync was cancelled.
    """
    wanted = stale_events(awards, data.event_fetch_times(), now)
    if not wanted:
        return
    if cancel.is_set():
        raise RequestCancelledError
    try:
        events = client.events(wanted)
    except (AuthError, ApiPayloadError) as exc:
        logger.warning("Event details unavailable: %s", exc)
        return
    data.save_events(with_points(client, events, awards, cancel), wanted, now)


def with_points(
    client: RaClient, events: list[EventInfo], awards: list[Award], cancel: threading.Event
) -> list[EventInfo]:
    """Add what each event is worth, where an earned tier's wording depends on it.

    Args:
        client: RA client.
        events: Fetched events.
        awards: The visible awards.
        cancel: Set to stop before the next request.

    Returns:
        The events, with their points where RA's v2 API gave them.

    Raises:
        RequestCancelledError: The sync was cancelled.
    """
    earned = {(award.data, award.extra) for award in awards if is_event(award)}
    tiered = [
        event.event_id
        for event in events
        if any((event.event_id, tier.tier) in earned for tier in event.tiers)
    ]
    if not tiered:
        return events
    if cancel.is_set():
        raise RequestCancelledError
    try:
        totals = client.event_points(tiered)
    except (AuthError, ApiPayloadError) as exc:
        logger.warning("Event points unavailable: %s", exc)
        return events
    return [replace(event, points=totals.get(event.event_id)) for event in events]
