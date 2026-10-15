"""Turn RA's awards (Web API) and events (v2 JSON:API) into domain models.

Tolerant like :mod:`parse`: missing values get safe defaults, and only payloads with the wrong
overall shape raise :class:`ApiPayloadError`.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from cheevos.core.errors import ApiPayloadError
from cheevos.core.models import Award, AwardCounts, AwardType, EventInfo, EventTier
from cheevos.core.ra_client.parse import _int, _object, _str, parse_time

_GAME_AWARDS = frozenset({AwardType.MASTERY, AwardType.GAME_BEATEN})


def _award(row: Mapping[str, Any], position: int) -> Award | None:
    """Parse one ``VisibleUserAwards`` entry.

    Args:
        row: The raw entry.
        position: Its index in RA's list (the profile's order).

    Returns:
        The award, or ``None`` for an unknown type or a game award without a game.
    """
    try:
        kind = AwardType(_str(row.get("AwardType")))
    except ValueError:
        return None
    data = _int(row.get("AwardData"))
    if kind in _GAME_AWARDS and data <= 0:
        return None
    display_tier = row.get("display_award_tier")
    return Award(
        type=kind,
        data=data,
        extra=_int(row.get("AwardDataExtra")),
        title=_str(row.get("Title")),
        console_name=_str(row.get("ConsoleName")),
        image_icon=_str(row.get("ImageIcon")),
        awarded_at=parse_time(row.get("AwardedAt")),
        console_id=_int(row.get("ConsoleID")),
        display_order=_int(row.get("DisplayOrder")),
        position=position,
        display_tier=None if display_tier is None else _int(display_tier),
    )


def parse_awards(data: object) -> tuple[AwardCounts, list[Award]]:
    """Parse ``API_GetUserAwards``.

    Args:
        data: Decoded JSON.

    Returns:
        The counters and the visible awards of every known type, in RA's order.

    Raises:
        ApiPayloadError: If the payload has the wrong shape.
    """
    payload = _object(data, "user awards")
    counts = AwardCounts(
        mastered=_int(payload.get("MasteryAwardsCount")),
        completed=_int(payload.get("CompletionAwardsCount")),
        beaten_hardcore=_int(payload.get("BeatenHardcoreAwardsCount")),
        beaten_softcore=_int(payload.get("BeatenSoftcoreAwardsCount")),
    )
    rows = payload.get("VisibleUserAwards") or []
    if not isinstance(rows, list):
        raise ApiPayloadError("user awards: 'VisibleUserAwards' is not a list")
    awards = [
        award
        for position, row in enumerate(rows)
        if (award := _award(_object(row, "award"), position)) is not None
    ]
    return counts, awards


def media_path(url: object) -> str:
    """Turn an image URL from RA's v2 API into a path on its media host.

    Args:
        url: E.g. ``"https://media.retroachievements.org/Images/122638.png"``.

    Returns:
        ``"/Images/122638.png"``, or ``""`` when it isn't a media-host URL.
    """
    text = _str(url)
    prefix = "https://media.retroachievements.org/"
    return "/" + text[len(prefix) :] if text.startswith(prefix) else ""


def parse_events(data: object) -> tuple[list[EventInfo], int]:
    """Parse a page of RA's v2 ``events`` resource, with its ``awards`` included (JSON:API).

    Args:
        data: Decoded JSON.

    Returns:
        The events (each with its tiers, lowest first) and the number of the last page.

    Raises:
        ApiPayloadError: If the payload has the wrong shape.
    """
    payload = _object(data, "events")
    resources, included = payload.get("data"), payload.get("included") or []
    if not isinstance(resources, list) or not isinstance(included, list):
        raise ApiPayloadError("events: 'data' or 'included' is not a list")
    tiers: dict[str, EventTier] = {}
    for raw in included:
        resource = _object(raw, "event award")
        if resource.get("type") != "event-awards":
            continue
        fields = _object(resource.get("attributes") or {}, "event award attributes")
        tiers[_str(resource.get("id"))] = EventTier(
            tier=_int(fields.get("tierIndex")),
            label=_str(fields.get("label")),
            points=_int(fields.get("pointsRequired")),
            image=media_path(fields.get("badgeUrl")),
        )
    events = []
    for raw in resources:
        resource = _object(raw, "event")
        event_id = _int(resource.get("id"))
        if event_id <= 0:
            continue
        fields = _object(resource.get("attributes") or {}, "event attributes")
        links = _object(resource.get("relationships") or {}, "event relationships")
        awards = _object(links.get("awards") or {}, "event awards").get("data") or []
        if not isinstance(awards, list):
            raise ApiPayloadError("events: 'awards' is not a list")
        own = [
            tiers[key] for item in awards if (key := _str(_object(item, "link").get("id"))) in tiers
        ]
        events.append(
            EventInfo(
                event_id=event_id,
                title=_str(fields.get("title")),
                image=media_path(fields.get("badgeUrl")),
                tiers=tuple(sorted(own, key=lambda tier: tier.tier)),
            )
        )
    page = _object(_object(payload.get("meta") or {}, "events meta").get("page") or {}, "page")
    return events, max(_int(page.get("lastPage"), 1), 1)


def parse_event_points(data: object) -> tuple[dict[int, int], int]:
    """Sum a page of RA's v2 ``event-achievements`` by event (JSON:API).

    Args:
        data: Decoded JSON, with each achievement's ``achievementPoints`` and ``event``.

    Returns:
        Points per event ID on this page, and the number of the last page.

    Raises:
        ApiPayloadError: If the payload has the wrong shape.
    """
    payload = _object(data, "event achievements")
    resources = payload.get("data")
    if not isinstance(resources, list):
        raise ApiPayloadError("event achievements: 'data' is not a list")
    points: dict[int, int] = {}
    for raw in resources:
        resource = _object(raw, "event achievement")
        links = _object(resource.get("relationships") or {}, "event achievement relationships")
        event = _object(links.get("event") or {}, "event link").get("data")
        event_id = _int(_object(event, "event").get("id")) if event is not None else 0
        if event_id <= 0:
            continue
        fields = _object(resource.get("attributes") or {}, "event achievement attributes")
        points[event_id] = points.get(event_id, 0) + _int(fields.get("achievementPoints"))
    page = _object(_object(payload.get("meta") or {}, "meta").get("page") or {}, "page")
    return points, max(_int(page.get("lastPage"), 1), 1)
