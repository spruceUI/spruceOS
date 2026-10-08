"""Composition root: wire credentials, caches, sync, lazy media and screens, then run home.

Shared by the device entry point (``cheevos.__main__``) and the desktop runner, which differ
only in the :class:`AppEnvironment` they pass (real HTTPS vs. recorded fixtures).
"""

from __future__ import annotations

import logging
import shutil
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import TypeVar

from cheevos.core.clock import network_clock
from cheevos.core.errors import AuthError, CheevosError
from cheevos.core.models import Unlock
from cheevos.core.net import is_online
from cheevos.core.proxy import ProxyReader
from cheevos.core.ra_client.client import RaClient
from cheevos.core.ra_client.pacer import API_INTERVAL, Pacer
from cheevos.core.ra_client.transport import HttpTransport, Transport
from cheevos.core.screenshots import ScreenshotIndex, screenshot_directory
from cheevos.core.settings import load_settings
from cheevos.core.storage.data_cache import DataCache
from cheevos.core.storage.media_cache import MediaCache
from cheevos.core.sync.background import BackgroundSync
from cheevos.core.sync.detail_fetch import DetailFetcher, DetailSession
from cheevos.core.sync.engine import SyncDeps
from cheevos.core.sync.lazy_media import LazyMediaFetcher, MediaSession
from cheevos.core.sync.session import Credentials, make_client, open_sync_deps
from cheevos.platform.paths import Paths
from cheevos.ui.context import AppContext
from cheevos.ui.media import MediaResolver
from cheevos.ui.pyui import generated, primitives, status_bar, title_bar, visible_images
from cheevos.ui.screens.home import Home
from cheevos.ui.screens.setup import change_key, ensure_credentials
from cheevos.ui.screens.status import SyncBar

logger = logging.getLogger(__name__)
_T = TypeVar("_T")

_RES = Path(__file__).resolve().parent / "res"
_LARGE_SCREEN_WIDTH = 1000
_SHUTDOWN_TIMEOUT = 3.0


@dataclass(frozen=True, slots=True)
class AppEnvironment:
    """How the app reaches the outside world.

    Attributes:
        paths: Device paths.
        transport_factory: Creates an HTTP transport (one per thread).
        online: Connectivity check.
        clock: App time, updated by RA responses in the real environment.
        auto_sync: Overrides the "sync when the app opens" setting when not ``None``.
        api_interval: Seconds between Web API requests, shared by every client (recorded
            fixtures need no pacing).
    """

    paths: Paths
    transport_factory: Callable[[], Transport] = HttpTransport
    online: Callable[[], bool] = is_online
    clock: Callable[[], float] = network_clock.now
    auto_sync: bool | None = None
    api_interval: float = API_INTERVAL


def _icons_dir(*, bar: bool = False) -> Path:
    """Pick the outline-icon size for this screen.

    Args:
        bar: Bottom-bar icons (24 px below 1000 px screen width, 48 px above) rather than
            list and fallback sources (96 px, 144 px above). PyUI fits the larger sources
            into the theme's icon column so rounded outlines stay clean.

    Returns:
        The icon directory.
    """
    width, _ = primitives.screen_size()
    large = width >= _LARGE_SCREEN_WIDTH
    if bar:
        return _RES / "icons" / ("48" if large else "24")
    return _RES / "icons" / ("144" if large else "96")


def _validator(env: AppEnvironment, pacer: Pacer) -> Callable[[str, str], bool | None]:
    """Build the API-key check used by setup and settings.

    Args:
        env: App environment.
        pacer: The app's shared request pacer.

    Returns:
        ``(username, key) -> True | False | None`` (``None``: RA unreachable).
    """

    def validate(username: str, key: str) -> bool | None:
        """Ask RA whether ``key`` is valid for ``username`` (anything but a rejection: unknown)."""
        client = make_client(
            env.paths, Credentials(username, key), env.transport_factory(), pacer=pacer
        )
        try:
            return client.validate_key()
        except AuthError:
            return False
        except CheevosError as exc:  # unreachable, rate limited or an odd answer
            logger.warning("Could not verify the API key: %s", exc)
            return None

    return validate


class _OnDemand:
    """Blocking RA requests made when the user asks ("See more"), paced with everything else.

    Each call returns ``None`` when offline or when RA fails.

    Args:
        env: App environment.
        ctx_ref: One-element list holding the context (for the current credentials).
        pacer: The app's shared request pacer.
    """

    def __init__(self, env: AppEnvironment, ctx_ref: list[AppContext], pacer: Pacer) -> None:
        self._env = env
        self._ctx_ref = ctx_ref
        self._pacer = pacer

    def unlocks(self, start: int, end: int) -> list[Unlock] | None:
        """Fetch the user's unlocks between ``start`` and ``end``."""
        return self._call("recent unlocks", lambda client: client.unlocks_between(start, end))

    def first_unlock(self, since: int) -> int | None:
        """Find the user's first hardcore unlock, looking from ``since`` (registration)."""
        return self._call(
            "the first unlock", lambda client: client.first_unlock(since, int(self._env.clock()))
        )

    def _call(self, what: str, request: Callable[[RaClient], _T]) -> _T | None:
        """Run ``request`` with a fresh client, or return ``None`` if that's impossible.

        Args:
            what: What is fetched, for the log.
            request: The request.

        Returns:
            Its result, or ``None``.
        """
        env = self._env
        credentials = self._ctx_ref[0].credentials
        client = make_client(env.paths, credentials, env.transport_factory(), pacer=self._pacer)
        try:
            return request(client)
        except CheevosError:
            logger.warning("Could not fetch %s", what, exc_info=True)
            return None


def _media_session(
    env: AppEnvironment, ctx_ref: list[AppContext], pacer: Pacer
) -> Callable[[], MediaSession]:
    """Build the lazy fetcher's session factory (runs on the fetcher's thread).

    Args:
        env: App environment.
        ctx_ref: One-element list holding the context (set once it exists).
        pacer: The app's shared request pacer (images use the client's media pacer).

    Returns:
        A factory returning ``(client, media cache, close)``.
    """

    def open_session() -> MediaSession:
        """Open a client and an image-cache connection for the fetcher thread."""
        credentials = ctx_ref[0].credentials
        client = make_client(env.paths, credentials, env.transport_factory(), pacer=pacer)
        media = MediaCache.open(env.paths.media_db, env.paths.media_scratch)
        return client, media, media.close

    return open_session


def _detail_session(
    env: AppEnvironment, ctx_ref: list[AppContext], pacer: Pacer
) -> Callable[[threading.Event], DetailSession]:
    """Build the game-loading worker's session factory (runs on the worker's thread).

    Reads the credentials each time, so a key entered after a rejection is used.

    Args:
        env: App environment.
        ctx_ref: One-element list holding the context.
        pacer: The app's shared request pacer.

    Returns:
        A factory taking the worker's stop event and returning ``(client, data cache, close)``.
    """

    def open_session(stop: threading.Event) -> DetailSession:
        """Open a client (its waits end with ``stop``) and a data-cache connection."""
        credentials = ctx_ref[0].credentials
        transport = env.transport_factory()
        client = make_client(env.paths, credentials, transport, pacer=pacer, cancel=stop)
        data = DataCache.open(env.paths.data_db, credentials.username)

        def close() -> None:
            """Release the cache connection and the socket."""
            data.close()
            close_transport = getattr(transport, "close", None)
            if close_transport is not None:
                close_transport()

        return client, data, close

    return open_session


def _sync_deps(
    env: AppEnvironment, ctx_ref: list[AppContext], pacer: Pacer
) -> Callable[[threading.Event], SyncDeps]:
    """Build the background sync's collaborator factory (runs on the sync thread).

    Reads the credentials when each sync starts, so a key changed in Settings applies to the
    next sync.

    Args:
        env: App environment.
        ctx_ref: One-element list holding the context.
        pacer: The app's shared request pacer.

    Returns:
        The factory, called with the sync's cancel event.
    """

    def open_deps(cancel: threading.Event) -> SyncDeps:
        """Open the sync's client and caches; its waits stop when ``cancel`` is set."""
        credentials = ctx_ref[0].credentials
        transport = env.transport_factory()
        return open_sync_deps(env.paths, credentials, transport, pacer=pacer, cancel=cancel)

    return open_deps


def run(*, started_at: float, env: AppEnvironment) -> None:
    """Run the app until the user leaves the home screen.

    Args:
        started_at: ``time.monotonic()`` at process start (for the start-up log line).
        env: App environment.
    """
    paths = env.paths
    icons = _icons_dir()
    pacer = Pacer(env.api_interval)  # one per app run: every client shares the key's pace
    validate = _validator(env, pacer)
    # Nothing to sync before setup ends, but its screens need the bar for their hints.
    with status_bar.installed(lambda _detailed: None, lambda: None):
        credentials = ensure_credentials(paths, validate)
        if credentials is None:
            return
        settings = load_settings(paths.settings_file)
    ctx_ref: list[AppContext] = []
    on_demand = _OnDemand(env, ctx_ref, pacer)
    try:
        data = DataCache.open(paths.data_db, credentials.username)
        media_cache = MediaCache.open(paths.media_db, paths.media_scratch)
    except CheevosError:
        logger.exception("Could not open the caches")
        return
    fetcher = LazyMediaFetcher(_media_session(env, ctx_ref, pacer))
    details = DetailFetcher(
        _detail_session(env, ctx_ref, pacer), clock=env.clock, online=env.online
    )
    sync = BackgroundSync(_sync_deps(env, ctx_ref, pacer), online=env.online, clock=env.clock)
    ctx = AppContext(
        paths=paths,
        credentials=credentials,
        settings=settings,
        data=data,
        media_cache=media_cache,
        media=MediaResolver(media_cache, icons, fetcher, visible_images.image_demand),
        sync=sync,
        details=details,
        proxy=ProxyReader(paths),
        screenshots=ScreenshotIndex(screenshot_directory(paths)),
        icons=icons,
        validate_key=validate,
        fetch_unlocks=on_demand.unlocks,
        fetch_first_unlock=on_demand.first_unlock,
        clock=env.clock,
        refresh_time=env.online,
    )
    ctx_ref.append(ctx)
    if settings.auto_sync if env.auto_sync is None else env.auto_sync:
        ctx.start_sync()
    logger.info("UI ready after %.2fs", time.monotonic() - started_at)
    generated.use_scratch(paths.scaled_scratch)
    visible_images.track_images(lambda: ctx.media.version, ctx.media.new_window)
    bar = SyncBar(ctx, _icons_dir(bar=True), lambda: change_key(ctx))
    try:
        with status_bar.installed(bar.status, bar.press_start), title_bar.installed():
            Home(ctx).run()
    finally:
        sync.cancel()
        sync.join(_SHUTDOWN_TIMEOUT)
        details.close()
        fetcher.close()
        data.close()
        media_cache.close()
        # Extracted and enlarged images live in RAM (tmpfs) on devices; give it back.
        shutil.rmtree(paths.media_scratch, ignore_errors=True)
        shutil.rmtree(paths.scaled_scratch, ignore_errors=True)
