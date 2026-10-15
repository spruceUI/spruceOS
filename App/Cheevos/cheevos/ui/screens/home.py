"""Home dashboard: profile and the entry points to every screen (sync status: bottom bar)."""

from __future__ import annotations

from cheevos.core.awards import GalleryCounts
from cheevos.core.storage.recent_feed import RecentFeedCache
from cheevos.core.sync.progress import Phase
from cheevos.ui import format as fmt
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui.views import MenuItem, choose


def awards_summary(counts: GalleryCounts) -> str:
    """Describe the Awards screen in a line, leaving out empty galleries.

    Args:
        counts: Visible awards per gallery.

    Returns:
        E.g. ``"12 mastered · 3 completed · 5 events"``.
    """
    events = strings.AWARDS_EVENTS.format(count=fmt.number(counts.events))
    parts = [
        (counts.mastered, strings.AWARDS_MASTERED.format(count=fmt.number(counts.mastered))),
        (counts.completed, strings.AWARDS_COMPLETED.format(count=fmt.number(counts.completed))),
        (counts.events, strings.AWARDS_EVENT if counts.events == 1 else events),
        (counts.site, strings.AWARDS_SITE.format(count=fmt.number(counts.site))),
    ]
    return " · ".join(text for count, text in parts if count) or strings.AWARDS_NONE


class Home:
    """Builds the home rows and refreshes them as a sync fills the cache.

    Args:
        ctx: App context.
        sync_when_shown: Start a sync once Home is on screen (the "sync when the app opens"
            setting). Started earlier, the sync's first imports (the engine, the RA client)
            would compete with the first frame (.agents/device.md, "Start-up").
    """

    def __init__(self, ctx: AppContext, *, sync_when_shown: bool = False) -> None:
        self._ctx = ctx
        self._last_phase: Phase | None = None
        self._sync_pending = sync_when_shown

    # --- rows ---------------------------------------------------------------------------------

    def items(self) -> list[MenuItem]:
        """Build all home rows from the cache."""
        rows = [self._profile_row(), self._games_row(), self._recent_row(), self._awards_row()]
        rows.append(
            MenuItem(
                strings.SETTINGS,
                strings.SETTINGS_SUMMARY,
                self._ctx.icon("sliders"),
                key="settings",
            )
        )
        return rows

    def _profile_row(self) -> MenuItem:
        """Describe the account (avatar, points, rank)."""
        profile = self._ctx.data.load_profile()
        if profile is None:
            return MenuItem(
                self._ctx.credentials.username,
                strings.WAITING_FOR_SYNC,
                self._ctx.icon("user"),
                key="profile",
            )
        points = strings.PROFILE_POINTS.format(
            hardcore=fmt.number(profile.hardcore_points),
            softcore=fmt.number(profile.softcore_points),
            retro=fmt.number(profile.retro_points),
        )
        rank = strings.RANK.format(rank=fmt.number(profile.rank)) if profile.rank else ""
        return MenuItem(
            profile.username,
            points,
            lambda: self._ctx.media.avatar(profile),
            rank or strings.UNRANKED,
            "profile",
        )

    def _games_row(self) -> MenuItem:
        """Summarise the library."""
        count, finished = self._ctx.data.game_counts()
        text = strings.GAMES_SUMMARY.format(count=count, finished=finished)
        return MenuItem(strings.GAMES, text, self._ctx.icon("gamepad"), str(count), "games")

    def _recent_row(self) -> MenuItem:
        """Show the latest unlock."""
        latest = self._ctx.data.recent_unlocks(1)
        if not latest:
            text = strings.NOTHING_UNLOCKED
        else:
            game = self._ctx.data.game(latest[0].game_id)
            title = game.title if game else ""
            feed = RecentFeedCache(self._ctx.data).load()
            if feed and feed.entries:
                title = feed.entries[0].game_title
            text = f"{latest[0].title} · {title}" if title else latest[0].title
        return MenuItem(strings.RECENT, text, self._ctx.icon("clock"), key="recent")

    def _awards_row(self) -> MenuItem:
        """Summarise the Awards screen's galleries: game, event and site badges."""
        counts = self._ctx.data.gallery_counts() or GalleryCounts()
        icon = self._ctx.icon("crown")
        total = fmt.number(counts.total)
        return MenuItem(strings.AWARDS, awards_summary(counts), icon, total, "awards")

    # --- live refresh -------------------------------------------------------------------------

    def tick(self) -> list[MenuItem] | None:
        """Refresh rows when the sync moves to another phase (each one fills part of the cache).

        Returns:
            New rows, or ``None`` when nothing changed.
        """
        self._start_pending_sync()  # the first tick comes after the first frame
        phase = self._ctx.sync.status().phase
        if phase is self._last_phase:
            return None
        self._last_phase = phase
        return self.items()

    # --- navigation ---------------------------------------------------------------------------

    def run(self) -> None:
        """Show the dashboard until B (which exits the app)."""
        selected = 0
        while choice := choose(
            strings.APP_TITLE, self.items(), selected=selected, on_tick=self.tick, full_status=True
        ):
            selected = choice.index
            self._start_pending_sync()  # a row opened before the first tick
            _open(self._ctx, choice.item.key)

    def _start_pending_sync(self) -> None:
        """Start the sync asked for at start-up, once."""
        if self._sync_pending:
            self._sync_pending = False
            self._ctx.start_sync()


def _open(ctx: AppContext, key: str) -> None:
    """Open the screen behind a home row, importing it the first time.

    Home's first frame needs none of these screens, and together they take about 0.2 s to
    import on a Mini (.agents/device.md, "Start-up").

    Args:
        ctx: App context.
        key: The row's key.
    """
    if key == "profile":
        from cheevos.ui.screens.profile import show_profile

        show_profile(ctx)
    elif key == "games":
        from cheevos.ui.screens.games import show_games

        show_games(ctx)
    elif key == "recent":
        from cheevos.ui.screens.lists import show_recent

        show_recent(ctx)
    elif key == "awards":
        from cheevos.ui.screens.awards import show_awards

        show_awards(ctx)
    elif key == "settings":
        from cheevos.ui.screens.settings import show_settings

        show_settings(ctx)
