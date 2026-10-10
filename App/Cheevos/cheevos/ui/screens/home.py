"""Home dashboard: profile and the entry points to every screen (sync status: bottom bar)."""

from __future__ import annotations

from collections.abc import Callable

from cheevos.core.storage.recent_feed import RecentFeedCache
from cheevos.core.sync.progress import Phase
from cheevos.ui import format as fmt
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui.views import MenuItem, choose
from cheevos.ui.screens.awards import show_awards
from cheevos.ui.screens.games import show_games
from cheevos.ui.screens.lists import show_recent
from cheevos.ui.screens.profile import show_profile
from cheevos.ui.screens.settings import show_settings


class Home:
    """Builds the home rows and refreshes them as a sync fills the cache.

    Args:
        ctx: App context.
    """

    def __init__(self, ctx: AppContext) -> None:
        self._ctx = ctx
        self._last_phase: Phase | None = None

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
        """Summarise mastered and beaten games."""
        counts = self._ctx.data.award_counts()
        mastered = counts.mastered + counts.completed if counts else 0
        beaten = counts.beaten_hardcore + counts.beaten_softcore if counts else 0
        text = strings.AWARDS_SUMMARY.format(mastered=mastered, beaten=beaten)
        icon = self._ctx.icon("crown")
        return MenuItem(strings.AWARDS, text, icon, str(mastered + beaten), "awards")

    # --- live refresh -------------------------------------------------------------------------

    def tick(self) -> list[MenuItem] | None:
        """Refresh rows when the sync moves to another phase (each one fills part of the cache).

        Returns:
            New rows, or ``None`` when nothing changed.
        """
        phase = self._ctx.sync.status().phase
        if phase is self._last_phase:
            return None
        self._last_phase = phase
        return self.items()

    # --- navigation ---------------------------------------------------------------------------

    def run(self) -> None:
        """Show the dashboard until B (which exits the app)."""
        routes: dict[str, Callable[[], object]] = {
            "profile": lambda: show_profile(self._ctx),
            "games": lambda: show_games(self._ctx),
            "recent": lambda: show_recent(self._ctx),
            "awards": lambda: show_awards(self._ctx),
            "settings": lambda: show_settings(self._ctx),
        }
        selected = 0
        while choice := choose(
            strings.APP_TITLE, self.items(), selected=selected, on_tick=self.tick, full_status=True
        ):
            selected = choice.index
            routes[choice.item.key]()
