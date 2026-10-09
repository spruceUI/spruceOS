"""Everything screens need, bundled once by the app and passed to every screen."""

from __future__ import annotations

import logging
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass, field, replace
from pathlib import Path

from cheevos.core.clock import network_clock
from cheevos.core.local_games import on_device_game_ids
from cheevos.core.models import PendingAward, Unlock
from cheevos.core.proxy import ProxyReader
from cheevos.core.screenshots import ScreenshotIndex
from cheevos.core.settings import Settings, save_settings
from cheevos.core.storage.data_cache import DataCache
from cheevos.core.storage.media_cache import MediaCache
from cheevos.core.sync.background import BackgroundSync
from cheevos.core.sync.detail_fetch import DetailFetcher
from cheevos.core.sync.engine import FULL_SINCE_KEY, SyncOptions
from cheevos.core.sync.session import Credentials
from cheevos.platform.paths import Paths
from cheevos.ui.media import MediaResolver

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class AppContext:
    """Shared state for the UI thread.

    Attributes:
        paths: Device paths.
        credentials: Signed-in account.
        settings: Current settings (replaced by :meth:`update_settings`).
        data: RA data cache (UI-thread connection).
        media_cache: Image cache (UI-thread connection).
        media: Image resolver with lazy fetching.
        sync: Background sync runner.
        details: Fetches the achievements of games the user opens, when not cached.
        proxy: RAOfflineProxy reader.
        screenshots: Unlock screenshot index.
        icons: Directory of outline icons sized for this screen.
        validate_key: Checks a Web API key with RA (``None`` result: unreachable).
        fetch_unlocks: Fetches the user's unlocks in a time window, blocking (``None``:
            offline or RA unreachable).
        fetch_first_unlock: Finds the user's first hardcore unlock from a start time,
            blocking (``None``: offline, RA unreachable, or none).
        clock: Wall clock.
        refresh_time: Refreshes app time and connectivity before on-demand date queries.
    """

    paths: Paths
    credentials: Credentials
    settings: Settings
    data: DataCache
    media_cache: MediaCache
    media: MediaResolver
    sync: BackgroundSync
    details: DetailFetcher
    proxy: ProxyReader
    screenshots: ScreenshotIndex
    icons: Path
    validate_key: Callable[[str, str], bool | None]
    fetch_unlocks: Callable[[int, int], list[Unlock] | None]
    fetch_first_unlock: Callable[[int], int | None]
    clock: Callable[[], float] = network_clock.now
    refresh_time: Callable[[], bool] = field(default=lambda: True, repr=False)
    _on_device: set[int] | None = field(default=None, repr=False)

    def icon(self, name: str) -> Path:
        """Return a bundled outline icon.

        Args:
            name: Icon name, e.g. ``"trophy"``.

        Returns:
            The icon path.
        """
        return self.icons / f"{name}.png"

    def start_sync(self, *, full: bool = False) -> bool:
        """Start a background sync with the current settings.

        Args:
            full: Start "Download every game".

        Returns:
            ``True`` if a new sync started (``False`` if one is already running).
        """
        options = SyncOptions(
            full=full,
            badge_scope=self.settings.badge_scope,
            recent_days=self.settings.recent_days,
        )
        return self.sync.start(options)

    def full_download_pending(self) -> bool:
        """Whether "Download every game" started and hasn't finished (later syncs resume it)."""
        return self.data.get_meta(FULL_SINCE_KEY) is not None

    def stop_full_download(self) -> None:
        """Stop "Download every game" for good: later syncs go back to the working set."""
        self.data.set_meta(FULL_SINCE_KEY, None)
        if self.sync.status().running:
            self.sync.cancel()  # a running one would carry on with its plan

    def update_settings(self, settings: Settings) -> None:
        """Replace and persist the settings.

        Args:
            settings: New settings.
        """
        self.settings = settings
        save_settings(self.paths.settings_file, settings)

    def on_device_ids(self) -> set[int]:
        """Return RA game IDs with a ROM on this SD card (computed once per app run)."""
        if self._on_device is None:
            self._on_device = on_device_game_ids(self.proxy)
        return self._on_device

    def proxy_active(self) -> bool:
        """Whether RAOfflineProxy is installed and turned on."""
        return self.proxy.installed() and self.proxy.enabled()

    def pending_by_game(self) -> dict[int, int]:
        """Count queued RAOfflineProxy unlocks per game that RA doesn't know about yet.

        Returns:
            Game ID to number of unlocks waiting to sync (unlocks whose game is unknown are
            left out).
        """
        pending = self.pending_awards()
        if not pending:
            return {}
        synced = self.data.unlocked_among(pending)
        counts = Counter(
            award.game_id
            for award in pending.values()
            if award.game_id is not None and award.achievement_id not in synced
        )
        return dict(counts)

    def pending_awards(self) -> dict[int, PendingAward]:
        """Return unlocks waiting in RAOfflineProxy's queue, by achievement ID.

        Each unlock's game comes from the synced achievement lists, or else from the proxy's
        cached ``patch`` data, which RetroArch 1.22 no longer requests (.agents/integration.md).
        """
        if not self.proxy_active():
            return {}
        awards = self.proxy.pending_awards(self.credentials.username)
        games = self.data.achievement_games(award.achievement_id for award in awards)
        return {
            award.achievement_id: replace(
                award, game_id=games.get(award.achievement_id, award.game_id)
            )
            for award in awards
        }
