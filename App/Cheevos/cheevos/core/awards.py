"""The profile's award galleries, after RA's own renderer (.agents/retroachievements.md, "Awards").

RA's profile page (RAWeb ``site-award.php``) splits the visible awards into three galleries:

- Game Awards: masteries and completions of games;
- Event Awards: event awards, and masteries of the old event games (console "Events");
- Site Awards: event awards that count as site awards, playtests, and the site's own badges
  (developer and media contributions, Patreon, Certified Legend).

Beaten awards appear in none of them: the renderer skips them, although the API returns them
(they stay milestones in Games and the profile's statistics). Unknown types are skipped too.
Each gallery keeps RA's order, the player's own arrangement, and the galleries follow each
other in the order of their first award.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass

from cheevos.core.models import Award, AwardGroup, AwardType, EventInfo
from cheevos.core.storage.media_cache import award_key, icon_key

EVENTS_CONSOLE = "Events"
_EVENT_TYPES = frozenset({AwardType.EVENT, AwardType.SITE_EVENT})
_HARDCORE = 1

# PlayerBadge's thresholds in RAWeb, by tier: developer unlocks, developer points, screenshots.
_UNLOCK_THRESHOLDS = (100, 250, 500, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000)
_UNLOCK_THRESHOLDS += (250_000, 500_000, 1_000_000, 2_500_000, 5_000_000)
_POINT_THRESHOLDS = (1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000)
_POINT_THRESHOLDS += (1_000_000, 2_500_000, 5_000_000, 10_000_000, 25_000_000, 50_000_000)
_MEDIA_THRESHOLDS = (10, 30, 100, 300, 1_000, 3_000)
# The site's own badge art, on RA's static host (client.media picks the host by path).
_SITE_ART = "/assets/images/badge/"


def group(award: Award) -> AwardGroup | None:
    """Return the gallery an award appears in on RA's profile.

    Args:
        award: A visible award.

    Returns:
        Its gallery, or ``None`` when the profile doesn't show it (beaten awards, a playtest
        without an image, unknown types).
    """
    if award.type is AwardType.MASTERY:
        return AwardGroup.EVENT if award.console_name == EVENTS_CONSOLE else AwardGroup.GAME
    if award.type is AwardType.EVENT:
        return AwardGroup.EVENT
    if award.type is AwardType.GAME_BEATEN:
        return None
    if award.type is AwardType.PLAYTEST and not award.image_icon:
        return None
    return AwardGroup.SITE


def is_event(award: Award) -> bool:
    """Whether an award is an event's (shown with the event or the site awards)."""
    return award.type in _EVENT_TYPES


def gallery(awards: Iterable[Award]) -> list[Award]:
    """Return the awards RA's profile galleries show, in RA's order.

    A game with both a mastery and a completion keeps the mastery (RA's own query does this
    already). Only those are merged: event and site awards are never matched by ID.

    Args:
        awards: Visible awards, any order.

    Returns:
        The gallery's awards, by ``position``.
    """
    shown = sorted((a for a in awards if group(a) is not None), key=lambda a: a.position)
    mastered = {a.data for a in shown if a.type is AwardType.MASTERY and a.extra == _HARDCORE}
    return [
        a
        for a in shown
        if not (a.type is AwardType.MASTERY and a.extra != _HARDCORE and a.data in mastered)
    ]


def site_order(awards: Sequence[Award]) -> list[Award]:
    """Order awards like the profile: galleries by their first award, RA's order in each.

    Args:
        awards: Gallery awards (see :func:`gallery`).

    Returns:
        A new list.
    """
    first: dict[AwardGroup | None, int] = {}
    for award in sorted(awards, key=lambda a: a.position):
        first.setdefault(group(award), award.position)
    return sorted(awards, key=lambda a: (first[group(a)], a.position))


@dataclass(frozen=True, slots=True)
class GalleryCounts:
    """How many awards each gallery shows (visible awards only), for the home summary.

    Attributes:
        mastered: Mastered games.
        completed: Completed games.
        events: Event awards.
        site: Site awards.
    """

    mastered: int = 0
    completed: int = 0
    events: int = 0
    site: int = 0

    @property
    def total(self) -> int:
        """Every award in the galleries."""
        return self.mastered + self.completed + self.events + self.site


def gallery_counts(awards: Iterable[Award]) -> GalleryCounts:
    """Count the galleries' awards.

    Args:
        awards: Visible awards.

    Returns:
        The counts.
    """
    shown = gallery(awards)
    games = [a for a in shown if group(a) is AwardGroup.GAME]
    mastered = sum(1 for a in games if a.extra == _HARDCORE)
    return GalleryCounts(
        mastered=mastered,
        completed=len(games) - mastered,
        events=sum(1 for a in shown if group(a) is AwardGroup.EVENT),
        site=sum(1 for a in shown if group(a) is AwardGroup.SITE),
    )


@dataclass(frozen=True, slots=True)
class EventBadge:
    """What an event award shows, resolved like the profile's tooltip.

    Attributes:
        title: The event's title, with the earned tier's label where RA adds one.
        points: Points the earned tier needs, when RA words the award by them; ``None`` when
            it was awarded for completing the event, or nothing is known about it.
        image: Badge path on the media host: the tier the player chose to show.
        known: The event's details were fetched (otherwise only the title and image are RA's).
    """

    title: str
    points: int | None
    image: str
    known: bool


def event_badge(award: Award, info: EventInfo | None) -> EventBadge:
    """Resolve an event award's title, condition and image (RAWeb ``RenderAward``).

    The image follows the tier the player chose to show; the text always follows the tier
    actually earned. RA adds the tier's label and points only when the tier needs fewer points
    than the whole event; when that total is unknown, the tier is described by its points,
    which is always true (.agents/retroachievements.md, "Event tiers").

    Args:
        award: An event or site-event award.
        info: The event's details, or ``None`` until they are fetched.

    Returns:
        The badge.
    """
    if info is None:
        return EventBadge(award.title, None, award.image_icon, known=False)
    display = award.display_tier if award.display_tier is not None else award.extra
    shown = info.tier(display)
    image = shown.image if shown is not None and shown.image else award.image_icon or info.image
    title = info.title or award.title
    earned = info.tier(award.extra)
    if earned is None or (info.points is not None and earned.points >= info.points):
        return EventBadge(title, None, image, known=True)
    label, game_title = earned.label, award.title or title
    if label != game_title and label.startswith(game_title):
        label = label[len(game_title) :].lstrip(" -:")
    if not title.endswith(label):
        title = f"{title} - {label}"
    return EventBadge(title, earned.points, image, known=True)


def threshold(award: Award) -> int | None:
    """Return what a contribution badge's tier stands for (unlocks, points or screenshots).

    Args:
        award: A site award.

    Returns:
        The threshold, or ``None`` for other awards and unknown tiers.
    """
    if award.type is AwardType.UNLOCKS_YIELD:
        table, tier = _UNLOCK_THRESHOLDS, award.data
    elif award.type is AwardType.POINTS_YIELD:
        table, tier = _POINT_THRESHOLDS, award.data
    elif award.type is AwardType.MEDIA:
        table, tier = _MEDIA_THRESHOLDS, award.extra
    else:
        return None
    return table[tier] if 0 <= tier < len(table) else None


def site_image(award: Award) -> str:
    """Return a site award's badge path (the site's own art lives on its static host).

    Args:
        award: A site award (not an event's).

    Returns:
        The path, or ``""`` when there is none.
    """
    if award.type is AwardType.UNLOCKS_YIELD:
        return f"{_SITE_ART}contribYield-{award.data}.png"
    if award.type is AwardType.POINTS_YIELD:
        return f"{_SITE_ART}contribPoints-{award.data}.png"
    if award.type is AwardType.MEDIA:
        tier = award.display_tier if award.display_tier is not None else award.extra
        return f"{_SITE_ART}mediaContrib-{tier}.png"
    if award.type is AwardType.PATREON:
        return f"{_SITE_ART}patreon.png"
    if award.type is AwardType.LEGEND:
        return f"{_SITE_ART}legend.png"
    return award.image_icon


def award_image(award: Award, info: EventInfo | None = None) -> tuple[str, str]:
    """Return an award's image: its cache key and its path on RA's hosts.

    Args:
        award: A gallery award.
        info: The event's details, for an event award (its tiers have their own badges).

    Returns:
        ``(cache key, path)``; the path is ``""`` when RA has no image for it.
    """
    if award.game_id is not None:  # masteries, the old event games' too: the game's icon
        return icon_key(award.game_id), award.image_icon
    path = event_badge(award, info).image if is_event(award) else site_image(award)
    return award_key(path), path
