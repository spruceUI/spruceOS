"""How each award reads and looks, after RA's profile tooltips (.agents/product.md, "Awards").

Every view of the Awards screen (carousel, grid, list) uses the same text: a title, a
description (the condition it was awarded for) and the date, plus RA's frame around its image.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass

from cheevos.core.awards import award_image, event_badge, is_event, threshold
from cheevos.core.models import Award, AwardKind, AwardType, EventInfo
from cheevos.ui import format as fmt
from cheevos.ui import strings
from cheevos.ui.pyui.image_frames import Frame

_PATREON_TIER = 2  # RA's $2 tier, drawn with a holographic border


@dataclass(frozen=True, slots=True)
class AwardText:
    """An award as the screen shows it.

    Attributes:
        title: First line: the game, event or site award's title.
        description: Second line: what it was awarded for.
        date: When it was earned (kept whole after the description).
        frame: RA's border around its image (``None``: plain).
        image: The image's cache key and its path on RA's hosts (``""``: none).
    """

    title: str
    description: str
    date: str
    frame: Frame | None
    image: tuple[str, str]


def describe(award: Award, events: Mapping[int, EventInfo]) -> AwardText:
    """Describe a gallery award.

    Args:
        award: The award.
        events: Fetched event details, by event ID.

    Returns:
        Its text.
    """
    date = fmt.local_date(award.awarded_at)
    if award.kind is not None:  # a game's mastery or completion (old events' too)
        mastered = award.kind is AwardKind.MASTERED
        label = strings.AWARD_LABELS[award.kind.value]
        frame = Frame.GOLD if mastered else None
        return AwardText(award.title, label, date, frame, award_image(award))
    if is_event(award):
        info = events.get(award.data)
        badge = event_badge(award, info)
        if badge.points is not None:
            template = strings.EVENT_POINT if badge.points == 1 else strings.EVENT_POINTS
            text = template.format(points=fmt.number(badge.points))
        else:
            text = strings.EVENT_COMPLETED if badge.known else strings.EVENT_AWARD
        return AwardText(badge.title, text, date, Frame.GOLD, award_image(award, info))
    title, text = _site_text(award)
    holo = award.type is AwardType.PATREON and award.extra == _PATREON_TIER
    return AwardText(title, text, date, Frame.HOLO if holo else Frame.GOLD, award_image(award))


def _site_text(award: Award) -> tuple[str, str]:
    """Return a site award's title and description: RA's title, and the reason in short.

    Args:
        award: A site award (not an event's).

    Returns:
        ``(title, description)``.
    """
    count = threshold(award)
    shown = fmt.number(count) if count is not None else ""
    if award.type is AwardType.PLAYTEST:
        return strings.PLAYTEST, award.title
    if award.type is AwardType.UNLOCKS_YIELD:
        text = strings.UNLOCKS_YIELD_TEXT.format(count=shown) if shown else strings.DEVELOPER_TEXT
        return strings.UNLOCKS_YIELD, text
    if award.type is AwardType.POINTS_YIELD:
        text = strings.POINTS_YIELD_TEXT.format(count=shown) if shown else strings.DEVELOPER_TEXT
        return strings.POINTS_YIELD, text
    if award.type is AwardType.PATREON:
        tier = award.extra == _PATREON_TIER
        return strings.PATREON, strings.PATREON_TIER_TEXT if tier else strings.PATREON_TEXT
    if award.type is AwardType.MEDIA:
        text = strings.MEDIA_TEXT.format(count=shown) if shown else strings.MEDIA_ANY_TEXT
        return strings.MEDIA, text
    return strings.LEGEND, strings.LEGEND_TEXT
