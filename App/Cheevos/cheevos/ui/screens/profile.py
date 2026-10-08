"""The profile on one page, after RA's own profile page, scrolled with the D-pad.

Top to bottom: the account (avatar, rank, points), last played, player stats and games per
console (the five most recently played). "[X] See more" adds RA's extra stats (points in the
last 7 and 30 days, points per week, average completion), a 30-day chart, and every console.
Only the recent points need a request to RA; it is made then, and the result is kept for
:data:`WINDOW_FRESH` seconds.

The page is a list of rows of known height (:mod:`page`).
"""

from __future__ import annotations

from cheevos.core.models import AwardKind, UnlockWindow, UserProfile
from cheevos.core.stats import (
    ConsoleProgress,
    PlayerStats,
    RecentPoints,
    console_progress,
    player_stats,
    recent_points,
    window_start,
)
from cheevos.ui import format as fmt
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui import primitives as ui
from cheevos.ui.pyui.primitives import Align, Button, Text
from cheevos.ui.screens import page
from cheevos.ui.screens.common import PADDING, busy, message
from cheevos.ui.screens.page import Row

AVATAR_SIZE = 96  # at 480 lines
GAME_ICON_SIZE = 48
REFERENCE_HEIGHT = 480
WINDOW_FRESH = 600  # seconds a fetched unlock window is reused before asking RA again
TOP_PERCENT_FROM = 100  # RA shows "top x%" only below rank 100
SMALL_RATE = 10  # points per week below this get a decimal
SHORT_CONSOLES = 5  # consoles shown before "See more" (the most recently played)
_KEYS = {Button.B, Button.X, Button.UP, Button.DOWN, Button.L1, Button.R1}


def rank_text(profile: UserProfile) -> str:
    """Describe the site rank like RA does: "#1,234 of 80,000 · top 2%".

    Args:
        profile: Account summary.

    Returns:
        The rank, or "Unranked".
    """
    if not profile.rank or not profile.total_ranked:
        return strings.UNRANKED
    rank, total = fmt.number(profile.rank), fmt.number(profile.total_ranked)
    if profile.rank <= TOP_PERCENT_FROM:
        return strings.RANK_OF.format(rank=rank, total=total)
    percent = fmt.percent(profile.rank / profile.total_ranked)
    return strings.RANK_TOP.format(rank=rank, total=total, percent=percent)


def _see_more(ctx: AppContext, profile: UserProfile) -> tuple[RecentPoints | None, int | None]:
    """Return what "See more" needs from RA, fetching what isn't stored yet.

    Args:
        ctx: App context.
        profile: Account summary (a mostly casual player counts casual unlocks too).

    Returns:
        Points earned lately (``None`` when never fetched and RA can't be reached), and the
        first hardcore unlock (fetched once, then stored; ``None`` when unknown).
    """
    now = int(ctx.clock())
    window = ctx.data.unlock_window()
    first = ctx.data.first_hardcore_unlock()
    fetch_window = window is None or not window.start <= now <= window.end + WINDOW_FRESH
    fetch_first = first is None and profile.hardcore_points > 0
    if fetch_window or fetch_first:
        busy(strings.PROFILE, strings.LOADING)
        reachable = ctx.refresh_time()
        now = int(ctx.clock())
        fetch_window = reachable and (
            window is None or not window.start <= now <= window.end + WINDOW_FRESH
        )
        fetch_first = reachable and fetch_first
    if fetch_window:
        start = window_start(now)
        unlocks = ctx.fetch_unlocks(start, now)
        if unlocks is not None:
            window = UnlockWindow(start, now, tuple(unlocks))
            ctx.data.save_unlock_window(window)
    if fetch_first:
        first = ctx.fetch_first_unlock(profile.member_since or 0)
        if first is not None:
            ctx.data.save_first_hardcore_unlock(first)
    if window is None:
        return None, first
    casual = profile.softcore_points > profile.hardcore_points
    return recent_points(window, casual_player=casual), first


def _percent(value: float | None) -> str:
    """Format an optional share.

    Args:
        value: Share between 0 and 1, or ``None``.

    Returns:
        The percentage, or a dash.
    """
    return fmt.percent(value) if value is not None else strings.UNKNOWN


def _per_week(rate: float | None) -> str:
    """Format points per week: a decimal for small scores, so 0.4 isn't shown as "0".

    Args:
        rate: Points per week, or ``None``.

    Returns:
        The rate, or a dash.
    """
    if rate is None:
        return strings.UNKNOWN
    if rate >= SMALL_RATE:
        return fmt.number(round(rate))
    shown = f"{rate:.1f}"
    return "0" if shown == "0.0" else shown


class _Page:
    """Builds the profile's rows for one screen size.

    Args:
        ctx: App context.
        profile: Account summary.
        area: Drawable area.
    """

    def __init__(self, ctx: AppContext, profile: UserProfile, area: ui.Area) -> None:
        self._ctx = ctx
        self._profile = profile
        self._area = area
        self._scale = ui.screen_size()[1] / REFERENCE_HEIGHT
        self._pair_height = ui.line_height(Text.BODY) + ui.line_height(Text.TITLE) + PADDING // 2

    def rows(
        self,
        stats: PlayerStats,
        consoles: list[ConsoleProgress],
        recent: RecentPoints | None,
        *,
        more: bool,
    ) -> list[Row]:
        """Lay out the page.

        Args:
            stats: Player stats.
            consoles: Progress per console, the most recently played first.
            recent: Recent points (with "See more"; ``None`` if RA couldn't be reached).
            more: Include the "See more" stats and chart.

        Returns:
            Rows, top to bottom.
        """
        profile = self._profile
        rows = [
            self._header(),
            self._pairs(
                [
                    (strings.STAT_HARDCORE, fmt.number(profile.hardcore_points)),
                    (strings.STAT_CASUAL, fmt.number(profile.softcore_points)),
                    (strings.STAT_RETRO, fmt.number(profile.retro_points)),
                ]
            ),
        ]
        if profile.last_game_title:
            rows += [self._heading(strings.SECTION_PLAYING), self._last_played()]
        rows.append(self._heading(strings.SECTION_STATS))
        rows += self._stats(stats)
        if more:
            rows += self._more(stats, recent)
        rows += self._consoles(consoles, more=more)
        return rows

    def _header(self) -> Row:
        """Avatar, name, rank, member since and last activity."""
        profile, ctx = self._profile, self._ctx
        size = round(AVATAR_SIZE * self._scale)
        lines = [
            rank_text(profile),
            strings.MEMBER_SINCE.format(date=fmt.local_date(profile.member_since)),
        ]
        if profile.rich_presence_at:
            lines.append(
                strings.LAST_ACTIVE.format(ago=fmt.ago(profile.rich_presence_at, ctx.clock()))
            )
        text = ui.line_height(Text.TITLE) + len(lines) * ui.line_height(Text.BODY)
        x = PADDING * 2 + size
        width = self._area.width - x - PADDING

        def draw(top: int) -> None:
            """Draw the header."""
            ui.image(ctx.media.avatar(profile), PADDING, top + PADDING // 2, size, size)
            y = top + PADDING // 2
            ui.text(profile.username, x, y, Text.TITLE, selected=True)
            y += ui.line_height(Text.TITLE)
            for line in lines:
                ui.text(ui.fit_text(line, Text.BODY, width), x, y)
                y += ui.line_height(Text.BODY)

        return Row(max(size, text) + PADDING, draw)

    def _pairs(self, pairs: list[tuple[str, str]]) -> Row:
        """Labels with their values beneath, in equal columns.

        Args:
            pairs: ``(label, value)`` per column.

        Returns:
            The row.
        """
        column = (self._area.width - PADDING * 2) // len(pairs)

        def draw(top: int) -> None:
            """Draw the columns."""
            for index, (label, value) in enumerate(pairs):
                x = PADDING + index * column
                ui.text(ui.fit_text(label, Text.BODY, column - PADDING), x, top)
                shown = ui.fit_text(value, Text.TITLE, column - PADDING)
                ui.text(shown, x, top + ui.line_height(Text.BODY), Text.TITLE)

        return Row(self._pair_height, draw)

    def _heading(self, title: str) -> Row:
        """A section title in the theme's highlight colour.

        Args:
            title: Section title.

        Returns:
            The row.
        """

        def draw(top: int) -> None:
            """Draw the heading."""
            ui.text(title, PADDING, top + PADDING // 2, Text.TITLE, selected=True)

        return Row(ui.line_height(Text.TITLE) + PADDING, draw, heading=True)

    def _last_played(self) -> Row:
        """The last game: icon, title, console and when, rich presence."""
        profile, ctx = self._profile, self._ctx
        size = round(GAME_ICON_SIZE * self._scale)
        x = PADDING * 2 + size
        width = self._area.width - x - PADDING
        when = fmt.ago(profile.rich_presence_at, ctx.clock())
        detail = " · ".join(part for part in (profile.last_game_console, when) if part)
        lines = [(profile.last_game_title, Text.TITLE), (detail, Text.BODY)]
        if profile.rich_presence:
            lines.append((profile.rich_presence, Text.BODY))
        text = sum(ui.line_height(role) for _line, role in lines)
        game_id, icon = profile.last_game_id or 0, profile.last_game_icon

        def draw(top: int) -> None:
            """Draw the last game."""
            ui.image(ctx.media.game_icon(game_id, icon), PADDING, top, size, size)
            y = top
            for line, role in lines:
                ui.text(ui.fit_text(line, role, width), x, y, role)
                y += ui.line_height(role)

        return Row(max(size, text) + PADDING // 2, draw)

    def _stats(self, stats: PlayerStats) -> list[Row]:
        """RA's "Player Stats": unlocks, games beaten, RetroRatio, started games beaten.

        Args:
            stats: Player stats.

        Returns:
            Two rows.
        """
        ratio = f"{stats.retro_ratio:.2f}" if stats.retro_ratio is not None else strings.UNKNOWN
        unlocks = strings.STAT_UNLOCKS_VALUE.format(
            hardcore=fmt.number(stats.unlocks_hardcore), casual=fmt.number(stats.unlocks_casual)
        )
        beaten = strings.STAT_BEATEN_VALUE.format(
            count=fmt.number(stats.games_beaten), retail=fmt.number(stats.games_beaten_retail)
        )
        started = _percent(stats.started_beaten)
        return [
            self._pairs([(strings.STAT_UNLOCKS, unlocks), (strings.STAT_BEATEN, beaten)]),
            self._pairs([(strings.STAT_RATIO, ratio), (strings.STAT_STARTED_BEATEN, started)]),
        ]

    def _more(self, stats: PlayerStats, recent: RecentPoints | None) -> list[Row]:
        """RA's "see more" stats and the 30-day chart.

        Args:
            stats: Player stats.
            recent: Recent points, or ``None`` when RA couldn't be reached.

        Returns:
            The rows.
        """
        week = fmt.number(recent.last_7_days) if recent else strings.UNKNOWN
        month = fmt.number(recent.last_30_days) if recent else strings.UNKNOWN
        completion = _percent(stats.average_completion)
        rows = [
            self._pairs([(strings.STAT_WEEK, week), (strings.STAT_MONTH, month)]),
            self._pairs(
                [
                    (strings.STAT_PER_WEEK, _per_week(stats.points_per_week)),
                    (strings.STAT_COMPLETION, completion),
                ]
            ),
        ]
        if recent is not None:
            rows.append(self._chart(recent))
        return rows

    def _chart(self, recent: RecentPoints) -> Row:
        """Points per day for the last 30 days, today on the right.

        Args:
            recent: Recent points.

        Returns:
            The row.
        """
        height = self._area.height // 3
        label = ui.line_height(Text.BODY)
        per_day = recent.per_day
        left, width = PADDING * 2, self._area.width - PADDING * 4
        slot = width // len(per_day)

        def draw(top: int) -> None:
            """Draw the chart (or say there was nothing to draw)."""
            bottom = top + height - label - PADDING // 2
            if not recent.last_30_days:
                middle = (top + bottom) // 2
                center = self._area.width // 2
                ui.text(strings.MONTH_EMPTY, center, middle, align=Align.MIDDLE_CENTER)
                return
            best = max(per_day)
            for day, points in enumerate(per_day):
                bar = round((bottom - top - PADDING) * points / best)
                x = left + day * slot
                ui.box(ui.track_color(), x + 1, bottom - 1, slot - 2, 1)
                if bar:
                    ui.box(ui.chart_color(), x + 1, bottom - bar, slot - 2, bar)
            ui.text(strings.MONTH_START, left, bottom + PADDING // 4)
            end = left + slot * len(per_day)
            ui.text(strings.MONTH_END, end, bottom + PADDING // 4, align=Align.TOP_RIGHT)

        return Row(height, draw)

    def _consoles(self, consoles: list[ConsoleProgress], *, more: bool) -> list[Row]:
        """Games played, beaten and mastered per console, with a total.

        Args:
            consoles: Progress per console, the most recently played first.
            more: Show every console ("See more"), not just the most recently played ones.

        Returns:
            The rows.
        """
        if not consoles:
            return []
        rows = [
            self._heading(strings.SECTION_CONSOLES),
            self._table_row(
                (strings.CONSOLE, strings.PLAYED, strings.BEATEN, strings.MASTERED), header=True
            ),
        ]
        if len(consoles) > 1:
            total = (
                strings.ALL_CONSOLES,
                fmt.number(sum(c.played for c in consoles)),
                fmt.number(sum(c.beaten for c in consoles)),
                fmt.number(sum(c.mastered for c in consoles)),
            )
            rows.append(self._table_row(total, header=True))
        shown = consoles if more else consoles[:SHORT_CONSOLES]
        rows += [
            self._table_row(
                (c.console_name, fmt.number(c.played), fmt.number(c.beaten), fmt.number(c.mastered))
            )
            for c in shown
        ]
        hidden = len(consoles) - len(shown)
        if hidden:
            template = strings.MORE_CONSOLE if hidden == 1 else strings.MORE_CONSOLES
            rows.append(self._note(template.format(count=fmt.number(hidden))))
        return rows

    def _note(self, text: str) -> Row:
        """A quiet line of text under a section.

        Args:
            text: The text.

        Returns:
            The row.
        """

        def draw(top: int) -> None:
            """Draw the note."""
            ui.text(text, PADDING, top)

        return Row(ui.line_height(Text.BODY) + PADDING // 4, draw)

    def _table_row(self, cells: tuple[str, str, str, str], *, header: bool = False) -> Row:
        """One table line: the console, then three right-aligned numbers.

        Args:
            cells: Console and counts.
            header: Draw in the highlight colour (column titles, the total).

        Returns:
            The row.
        """
        width = self._area.width - PADDING * 2
        number = width // 6
        name = width - number * 3

        def draw(top: int) -> None:
            """Draw the line."""
            label = ui.fit_text(cells[0], Text.BODY, name - PADDING)
            ui.text(label, PADDING, top, selected=header)
            for index, cell in enumerate(cells[1:]):
                right = PADDING + name + number * (index + 1)
                ui.text(cell, right, top, align=Align.TOP_RIGHT, selected=header)

        return Row(ui.line_height(Text.BODY) + PADDING // 4, draw)


def show_profile(ctx: AppContext) -> None:
    """Show the profile page until B; up/down and L1/R1 scroll, X shows more.

    Args:
        ctx: App context.
    """
    profile = ctx.data.load_profile()
    if profile is None:
        message(strings.PROFILE, [strings.WAITING_FOR_SYNC])
        return
    # Read once: 2,940 games take 0.27 s on a Miyoo Mini+, and the stats only use these awards.
    counts, awards = ctx.data.awards(AwardKind.BEATEN_HARDCORE)
    games = ctx.data.games()
    stats = player_stats(
        profile, games, counts, awards, ctx.data.first_hardcore_unlock(), ctx.clock()
    )
    consoles = console_progress(games)
    recent: RecentPoints | None = None
    more = False
    rows: list[Row] | None = None
    first = 0
    while True:
        hints = [] if more else [(Button.X, strings.HINT_SEE_MORE)]
        area = ui.begin(strings.PROFILE, hints)
        if rows is None:
            rows = _Page(ctx, profile, area).rows(stats, consoles, recent, more=more)
        first = page.clamp(first, rows, area)
        page.draw(rows, first, area)
        ui.end()
        pressed = ui.wait_for(_KEYS)
        if pressed is Button.B:
            return
        if pressed is Button.X and not more:
            recent, first_unlock = _see_more(ctx, profile)
            stats = player_stats(profile, games, counts, awards, first_unlock, ctx.clock())
            more, rows = True, None
        first = page.scroll(first, pressed, rows, area.height)
