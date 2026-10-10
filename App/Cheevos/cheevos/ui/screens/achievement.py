"""Achievement card: badge, unlock state, rarity, description and the unlock screenshot."""

from __future__ import annotations

from dataclasses import replace
from pathlib import Path

from cheevos.core.models import Achievement, AchievementType, GameDetail, PendingAward
from cheevos.core.settings import DescriptionHiding
from cheevos.ui import format as fmt
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui import primitives as ui
from cheevos.ui.pyui.primitives import Align, Button, Text
from cheevos.ui.screens.common import PADDING, fullscreen
from cheevos.ui.screens.rows import rarity

BADGE_SIZE = 96
STORY_TYPES = frozenset({AchievementType.PROGRESSION, AchievementType.WIN_CONDITION})
RULE_WIDTH = 3  # accent rule left of the description
RULE_INSET = 4  # lines up the rule with the first line's letters


def hides_description(
    mode: DescriptionHiding, achievement: Achievement, *, pending: PendingAward | None = None
) -> bool:
    """Whether the spoiler setting hides an achievement's description.

    Args:
        mode: The setting.
        achievement: The achievement.
        pending: Its RAOfflineProxy queue entry (unlocked on the device: never hidden).

    Returns:
        ``True`` to show the "hidden" placeholder instead.
    """
    if mode is DescriptionHiding.OFF or achievement.unlocked or pending is not None:
        return False
    return mode is DescriptionHiding.ALL or achievement.type in STORY_TYPES


def enrich_achievement(achievement: Achievement, detail: GameDetail) -> Achievement:
    """Add a game's definition and rarity without changing the feed's unlock mode or date."""
    match = next(
        (a for a in detail.achievements if a.achievement_id == achievement.achievement_id), None
    )
    return (
        replace(
            match,
            earned_at=achievement.earned_at,
            earned_hardcore_at=achievement.earned_hardcore_at,
        )
        if match
        else achievement
    )


def show_achievement(
    ctx: AppContext,
    achievement: Achievement,
    *,
    game_title: str,
    players: int | None,
    players_hardcore: int | None,
    pending: PendingAward | None = None,
) -> None:
    """Show the achievement card until B; A opens the screenshot, X reveals a hidden description.

    Both are hinted in the bottom bar.

    Args:
        ctx: App context.
        achievement: The achievement.
        game_title: Game title for the top bar.
        players: Distinct players of the game, or None while its details are missing.
        players_hardcore: Hardcore players of the game, or None when unknown.
        pending: RAOfflineProxy queue entry, if the unlock is waiting to sync.
    """
    screenshot = ctx.screenshots.lookup(achievement.achievement_id)
    hide = hides_description(ctx.settings.hide_descriptions, achievement, pending=pending)
    if players is None:
        ctx.details.request(achievement.game_id)
    while True:
        if players is None:
            detail = ctx.data.game_detail(achievement.game_id)
            if detail is not None:
                achievement = enrich_achievement(achievement, detail)
                players, players_hardcore = detail.num_distinct_players, detail.num_players_hardcore
        hints = [(Button.A, strings.HINT_FULL_SCREEN)] if screenshot is not None else []
        if hide:
            hints.append((Button.X, strings.HINT_REVEAL))
        area = ui.begin(game_title, hints)
        card = _Card(ctx, achievement, area, pending)
        card.header()
        card.status(players, players_hardcore)
        card.description(hidden=hide, leave_room=screenshot is not None)
        if screenshot is not None:
            card.screenshot(screenshot)
        ui.end()
        pressed = ui.wait_for({Button.A, Button.B, Button.X})
        if pressed is Button.B:
            return
        if pressed is Button.X:
            hide = False
        elif pressed is Button.A and screenshot is not None:
            fullscreen(screenshot, ctx.paths.scaled_scratch)


class _Card:
    """Lays out one frame of the achievement card.

    Args:
        ctx: App context.
        achievement: The achievement.
        area: Drawable area.
        pending: Queue entry, if pending.
    """

    def __init__(
        self,
        ctx: AppContext,
        achievement: Achievement,
        area: ui.Area,
        pending: PendingAward | None,
    ) -> None:
        self._ctx = ctx
        self._achievement = achievement
        self._area = area
        self._pending = pending
        self._x = PADDING * 2 + BADGE_SIZE
        self._y = area.y + PADDING

    def header(self) -> None:
        """Draw the badge, the title (up to two lines) and points."""
        achievement = self._achievement
        ui.image(
            self._ctx.media.badge(
                achievement, unlocked=achievement.unlocked or self._pending is not None
            ),
            PADDING,
            self._area.y + PADDING,
            BADGE_SIZE,
            BADGE_SIZE,
        )
        width = self._area.width - self._x - PADDING
        for line in ui.wrap(achievement.title, Text.TITLE, width)[:2]:
            ui.text(line, self._x, self._y, Text.TITLE, selected=True)
            self._y += ui.line_height(Text.TITLE)
        meta = strings.DETAIL_META.format(
            points=fmt.points(achievement.points), retro=fmt.number(achievement.retro_points)
        )
        if achievement.type is not None:
            meta += " · " + strings.TYPE_LABELS[achievement.type.value]
        self._line(meta)

    def status(self, players: int | None, players_hardcore: int | None) -> None:
        """Draw the unlock state and rarity lines.

        Args:
            players: Distinct players of the game.
            players_hardcore: Hardcore players of the game.
        """
        achievement = self._achievement
        if achievement.unlocked:
            mode = strings.MODE_HARDCORE if achievement.hardcore else strings.MODE_CASUAL
            when = fmt.local_datetime(achievement.unlocked_at)
            self._line(strings.DETAIL_UNLOCKED.format(mode=mode, when=when))
        elif self._pending is not None:
            when = fmt.local_datetime(self._pending.queued_at)
            self._line(strings.DETAIL_PENDING.format(when=when))
        else:
            self._line(strings.DETAIL_LOCKED)
        casual = strings.UNKNOWN if players is None else fmt.percent(rarity(achievement, players))
        hardcore = (
            strings.UNKNOWN
            if players_hardcore is None
            else fmt.percent(
                achievement.num_awarded_hardcore / players_hardcore if players_hardcore else 0
            )
        )
        self._line(
            strings.DETAIL_RARITY.format(
                casual=casual,
                hardcore=hardcore,
            )
        )

    def description(self, *, hidden: bool, leave_room: bool) -> None:
        """Draw the description, the card's main text: larger than the details, behind a rule.

        Uses the title font, or the body font when the title font would run off the card.

        Args:
            hidden: Show the "hidden" placeholder instead (spoiler setting).
            leave_room: Keep the right half free for the screenshot.
        """
        area = self._area
        top = max(self._y, area.y + PADDING * 2 + BADGE_SIZE)
        bottom = area.y + area.height - PADDING
        x = PADDING + RULE_WIDTH + PADDING
        width = area.width - x - PADDING - (area.width // 2 if leave_room else 0)
        text = strings.HIDDEN_DESCRIPTION if hidden else self._achievement.description
        role, lines = Text.BODY, ui.wrap(text, Text.BODY, width)
        if not hidden:
            title_lines = ui.wrap(text, Text.TITLE, width)
            if top + len(title_lines) * ui.line_height(Text.TITLE) <= bottom:
                role, lines = Text.TITLE, title_lines
        height = ui.line_height(role)
        lines = lines[: max((bottom - top) // height, 1)]
        ui.box(ui.accent_color(), PADDING, top + RULE_INSET, RULE_WIDTH, len(lines) * height)
        for index, line in enumerate(lines):
            ui.text(line, x, top + index * height, role)

    def screenshot(self, path: Path) -> None:
        """Draw the unlock screenshot in the bottom-right (A opens it full screen).

        Args:
            path: Screenshot file.
        """
        area = self._area
        right, bottom = area.width - PADDING, area.y + area.height - PADDING
        top = area.y + PADDING * 2 + BADGE_SIZE
        width, height = area.width // 2 - PADDING, bottom - top
        shown = ui.sharp_scaled(path, width, height, self._ctx.paths.scaled_scratch)
        ui.image(shown, right, top, width, height, Align.TOP_RIGHT)

    def _line(self, text: str) -> None:
        """Draw one body line in the right column and advance.

        Args:
            text: Line text.
        """
        ui.text(text, self._x, self._y)
        self._y += ui.line_height(Text.BODY)
