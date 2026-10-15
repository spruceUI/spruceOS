"""Requests to RA's v2 JSON:API: events' award tiers and what events are worth.

The v1 awards list names an event award's tier but not its label, points or badge, and
neither API states what a whole event is worth (.agents/retroachievements.md, "Event tiers").
The v2 API is paged; the client passes a function that GETs one page's JSON with the key.
"""

from __future__ import annotations

from collections.abc import Callable, Iterable
from typing import Any
from urllib.parse import urlencode

from cheevos.core.models import EventInfo
from cheevos.core.ra_client.parse_awards import parse_event_points, parse_events

# GETs a v2 path (with its query) and returns the decoded JSON; the second argument names
# the resource for logs and errors.
GetJson = Callable[[str, str], Any]

EVENT_PAGE = 50  # events per request (the API's default page size)
_EVENT_PAGES = 10  # filtered to EVENT_PAGE IDs, events fit one page; never loop for long
EVENT_ACHIEVEMENT_PAGE = 100  # event achievements per request
_EVENT_ACHIEVEMENT_PAGES = 30  # at most 3,000 event achievements at a time


def fetch_events(get: GetJson, event_ids: Iterable[int]) -> list[EventInfo]:
    """Fetch events with their award tiers (``/v2/events``, tiers included).

    Args:
        get: GETs one page.
        event_ids: Event IDs (an event award's ``AwardData``).

    Returns:
        The events RA knows and shows (others are left out).
    """
    found: list[EventInfo] = []
    for chunk in _chunks(event_ids):
        number = last = 1
        while number <= min(last, _EVENT_PAGES):
            query = {"filter[id]": chunk, "include": "awards", "page[size]": EVENT_PAGE}
            query["page[number]"] = number
            page, last = parse_events(get(f"/v2/events?{urlencode(query)}", "v2/events"))
            found += page
            number += 1
    return found


def fetch_event_points(get: GetJson, event_ids: Iterable[int]) -> dict[int, int]:
    """Add up what events are worth: their published achievements' points.

    RA describes an event tier by its points only when the tier needs fewer points than the
    whole event (its event game's ``points_total``), which no API states.

    Args:
        get: GETs one page.
        event_ids: Event IDs.

    Returns:
        Points per event ID (events without published achievements are left out).
    """
    totals: dict[int, int] = {}
    for chunk in _chunks(event_ids):
        number = last = 1
        while number <= min(last, _EVENT_ACHIEVEMENT_PAGES):
            query = {
                "filter[eventId]": chunk,
                "fields[event-achievements]": "achievementPoints,event",
                "page[size]": EVENT_ACHIEVEMENT_PAGE,
                "page[number]": number,
            }
            data = get(f"/v2/event-achievements?{urlencode(query)}", "v2/event-achievements")
            page, last = parse_event_points(data)
            for event_id, points in page.items():
                totals[event_id] = totals.get(event_id, 0) + points
            number += 1
    return totals


def _chunks(event_ids: Iterable[int]) -> list[str]:
    """Split IDs into comma-separated filters of :data:`EVENT_PAGE` IDs each.

    Args:
        event_ids: Event IDs.

    Returns:
        The filters, in ID order.
    """
    ids = sorted(set(event_ids))
    return [
        ",".join(str(event_id) for event_id in ids[start : start + EVENT_PAGE])
        for start in range(0, len(ids), EVENT_PAGE)
    ]
