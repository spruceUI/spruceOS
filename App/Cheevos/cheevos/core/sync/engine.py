"""The sync engine: fetch from RA into the caches, incrementally and resumably.

Phases: preflight (network, rate limit) → profile → library (completion progress +
recently played) → awards → details (the working set's new games, changed and stale cached
games, and the games behind the newest unlocks; one commit per game) → media (avatar, game
icons, badges for the configured scope). See .agents/sync-and-storage.md.

An interrupted sync needs no explicit resume state: games whose details were not fetched keep
their old fingerprint (or none), so the next plan picks up exactly the remaining ones.
"""

from __future__ import annotations

import logging
import threading
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field

from cheevos.core.clock import network_clock
from cheevos.core.errors import (
    AuthError,
    CheevosError,
    NetworkError,
    RateLimitedError,
    RequestCancelledError,
)
from cheevos.core.models import GameProgress
from cheevos.core.ra_client.client import RaClient
from cheevos.core.settings import BadgeScope
from cheevos.core.storage.data_cache import DataCache
from cheevos.core.storage.media_cache import MediaCache, avatar_key, badge_key, icon_key
from cheevos.core.sync.planner import (
    DAY,
    RECENT_UNLOCK_COUNT,
    badge_game_ids,
    merge_library,
    plan_detail_fetches,
    unlock_candidates,
    working_set,
)
from cheevos.core.sync.progress import Failure, Phase, ProgressTracker, SyncStatus

logger = logging.getLogger(__name__)

MEDIA_BATCH = 25  # images per transaction: few commits on the SD's dirsync FAT32
LAST_SYNC_KEY = "last_sync_at"
# Set while a full re-sync is unfinished: details fetched before it are re-fetched.
FULL_SINCE_KEY = "full_resync_since"
# When RA allows requests again after asking for a long pause (wall clock, epoch seconds).
RATE_LIMITED_UNTIL_KEY = "rate_limited_until"
RATE_LIMIT_PAUSE = 60.0  # assumed pause when RA rate-limits without saying for how long


class SyncCancelledError(Exception):
    """Raised inside the engine when cancellation was requested (never escapes ``run``)."""


class _FailedError(Exception):
    """Raised inside the engine to stop with a :class:`Failure` (never escapes ``run``).

    Args:
        failure: The reason.
        retry_at: When RA allows requests again, for ``RATE_LIMITED``.
    """

    def __init__(self, failure: Failure, retry_at: float | None = None) -> None:
        super().__init__(failure.value)
        self.failure = failure
        self.retry_at = retry_at


@dataclass(frozen=True, slots=True)
class SyncOptions:
    """What one sync should do.

    Attributes:
        full: Start "Download every game": fetch every game's details, resuming in later
            syncs until done.
        badge_scope: Which games' badges to download.
        recent_days: Activity window for the working set and the badge scope's "recent".
    """

    full: bool = False
    badge_scope: BadgeScope = BadgeScope.ON_DEVICE_AND_RECENT
    recent_days: int = 30


@dataclass(slots=True)
class SyncDeps:
    """Collaborators for one sync, created on (and owned by) the sync thread.

    SQLite connections must stay on the thread that created them, so these are built inside
    the worker by :class:`BackgroundSync`'s factory.

    Attributes:
        client: RA client.
        data: RA data cache.
        media: Image cache.
        on_device: Returns RA game IDs with a ROM on this SD card.
        close: Releases everything above (connections, sockets).
    """

    client: RaClient
    data: DataCache
    media: MediaCache
    on_device: Callable[[], set[int]] = set
    close: Callable[[], None] = field(default=lambda: None)


class SyncEngine:
    """Runs one sync with the given collaborators.

    Args:
        deps: Client and caches.
        tracker: Progress sink read by the UI.
        cancel: Set to stop at the next request boundary.
        clock: Wall clock (epoch seconds).
        online: Connectivity check.
    """

    def __init__(
        self,
        deps: SyncDeps,
        tracker: ProgressTracker,
        cancel: threading.Event,
        *,
        clock: Callable[[], float] = network_clock.now,
        online: Callable[[], bool],
    ) -> None:
        self._deps = deps
        self._tracker = tracker
        self._cancel = cancel
        self._clock = clock
        self._online = online
        self._details_since = 0  # when the details phase began (games fetched since are fresh)

    def run(self, options: SyncOptions) -> SyncStatus:
        """Run every phase; never raises for expected failures.

        Args:
            options: What to sync.

        Returns:
            The final status (``DONE``, ``FAILED`` or ``CANCELLED``).
        """
        self._tracker.reset()
        try:
            self._preflight()
            self._sync_profile()
            games = self._sync_library()
            self._sync_awards()  # one request: the awards wall is complete before the details
            self._sync_details(games, options)
            self._sync_media(games, options)
        except (SyncCancelledError, RequestCancelledError):
            logger.info("Sync cancelled")
            self._tracker.finish(Phase.CANCELLED, at=self._clock())
        except _FailedError as stop:
            logger.info("Sync stopped: %s", stop.failure.value)
            self._tracker.finish(
                Phase.FAILED, failure=stop.failure, at=self._clock(), retry_at=stop.retry_at
            )
        except AuthError:
            logger.warning("Sync failed: API key rejected")
            self._tracker.finish(Phase.FAILED, failure=Failure.AUTH, at=self._clock())
        except RateLimitedError as exc:
            now = self._clock()
            pause = exc.retry_after if exc.retry_after is not None else RATE_LIMIT_PAUSE
            self._deps.data.set_meta(RATE_LIMITED_UNTIL_KEY, str(int(now + pause)))
            logger.warning("Sync stopped: RA asked us to wait %.0fs", pause)
            self._tracker.finish(
                Phase.FAILED, failure=Failure.RATE_LIMITED, at=now, retry_at=now + pause
            )
        except NetworkError as exc:
            logger.warning("Sync failed: network error: %s", exc)
            self._tracker.finish(Phase.FAILED, failure=Failure.NETWORK, at=self._clock())
        except CheevosError:
            logger.exception("Sync failed")
            self._tracker.finish(Phase.FAILED, failure=Failure.ERROR, at=self._clock())
        else:
            now = self._clock()
            self._deps.data.set_meta(LAST_SYNC_KEY, str(int(now)))
            self._deps.data.set_meta(FULL_SINCE_KEY, None)
            self._deps.data.set_meta(RATE_LIMITED_UNTIL_KEY, None)
            self._tracker.finish(Phase.DONE, at=now)
            status = self._tracker.snapshot()
            logger.info(
                "Sync done: %d game details, %d images",
                status.details_fetched,
                status.media_fetched,
            )
        return self._tracker.snapshot()

    def _check_cancel(self) -> None:
        """Stop if cancellation was requested.

        Raises:
            SyncCancelledError: When the cancel event is set.
        """
        if self._cancel.is_set():
            raise SyncCancelledError

    def _preflight(self) -> None:
        """Check connectivity and refresh app time before respecting RA's last pause.

        Raises:
            _FailedError: RA asked us to wait and the time isn't up, or no
                connection to RA.
        """
        self._tracker.phase(Phase.PREFLIGHT)
        if not self._online():
            raise _FailedError(Failure.OFFLINE)
        now = self._clock()
        until = self._rate_limited_until()
        if until is not None and until > now:
            raise _FailedError(Failure.RATE_LIMITED, retry_at=until)

    def _rate_limited_until(self) -> float | None:
        """Return when RA allows requests again, if a past sync was told to wait.

        Returns:
            The time, or ``None`` when there is none (or it can't be read).
        """
        raw = self._deps.data.get_meta(RATE_LIMITED_UNTIL_KEY)
        try:
            return float(raw) if raw is not None else None
        except ValueError:
            return None

    def _sync_profile(self) -> None:
        """Fetch and store the account summary."""
        self._check_cancel()
        self._tracker.phase(Phase.PROFILE)
        profile = self._deps.client.user_summary()
        self._deps.data.save_profile(profile, int(self._clock()))

    def _sync_library(self) -> list[GameProgress]:
        """Fetch completion progress and recently played games; store the merged library.

        Returns:
            The merged library, most recently active first.
        """
        self._check_cancel()
        self._tracker.phase(Phase.LIBRARY)
        progress = self._deps.client.completion_progress()
        self._check_cancel()
        recent = self._deps.client.recently_played()
        games = merge_library(progress, recent)
        self._deps.data.upsert_games(games)
        return games

    def _sync_details(self, games: list[GameProgress], options: SyncOptions) -> None:
        """Fetch details for the planned games, committing one game at a time.

        Without an unfinished "Download every game", new games are fetched only for the working
        set, then for the games holding the newest unlocks (so Recent unlocks is complete).

        Args:
            games: Merged library.
            options: Sync options (``full`` starts "Download every game").
        """
        now = int(self._clock())
        if options.full:
            self._deps.data.set_meta(FULL_SINCE_KEY, str(now))
        pending_full = self._deps.data.get_meta(FULL_SINCE_KEY)
        wanted = None
        if pending_full is None:
            recent_since = now - options.recent_days * DAY
            wanted = working_set(games, on_device=self._deps.on_device(), recent_since=recent_since)
        plan = plan_detail_fetches(
            games,
            self._deps.data.detail_states(),
            now=now,
            wanted=wanted,
            full=options.full,
            refetch_before=int(pending_full) if pending_full else None,
        )
        by_id = {game.game_id: game for game in games}
        self._details_since = now
        self._tracker.phase(Phase.DETAILS, total=len(plan))
        logger.info(
            "Detail plan: %d new, %d changed, %d stale",
            len(plan.never_fetched),
            len(plan.changed),
            len(plan.stale),
        )
        for game_id in plan.ordered:
            self._fetch_detail(by_id[game_id])
        if wanted is not None:
            self._cover_recent_unlocks(games)

    def _cover_recent_unlocks(self, games: list[GameProgress]) -> None:
        """Fetch uncached games, newest unlock first, until the newest unlocks are all cached.

        Args:
            games: Merged library.
        """
        states = self._deps.data.detail_states()
        cached = {game_id for game_id, (_, synced_at) in states.items() if synced_at is not None}
        fetched = 0
        for game in unlock_candidates(games, cached):
            cutoff = self._deps.data.nth_newest_unlock(RECENT_UNLOCK_COUNT)
            if cutoff is not None and (game.last_unlock_at or 0) <= cutoff:
                break
            self._tracker.add_total(1)
            self._fetch_detail(game)
            fetched += 1
        if fetched:
            logger.info("Fetched %d more games for recent unlocks", fetched)

    def _fetch_detail(self, game: GameProgress) -> None:
        """Fetch and store one game's details.

        Args:
            game: The game, from the library.
        """
        self._check_cancel()
        fingerprint, synced_at = self._deps.data.detail_state(game.game_id)
        if (
            synced_at is not None
            and synced_at > self._details_since  # same second: may be an earlier sync's
            and fingerprint == game.fingerprint
        ):
            self._tracker.advance()  # opened (and so fetched) after the plan was made
            return
        self._tracker.working_on(game.title)
        detail = self._deps.client.game_detail(game.game_id)
        self._deps.data.save_game_detail(
            detail, fingerprint=game.fingerprint, synced_at=int(self._clock())
        )
        self._tracker.advance(detail=True)

    def _sync_awards(self) -> None:
        """Fetch and store mastery/beaten awards."""
        self._check_cancel()
        self._tracker.phase(Phase.AWARDS)
        counts, awards = self._deps.client.awards()
        self._deps.data.save_awards(counts, awards)

    def _sync_media(self, games: list[GameProgress], options: SyncOptions) -> None:
        """Download missing images: avatar, game icons, and badges for the badge scope.

        Args:
            games: Merged library.
            options: Sync options (badge scope).
        """
        self._check_cancel()
        wanted = dict(self._media_wanted(games, options))
        missing = self._deps.media.missing(wanted)
        self._tracker.phase(Phase.MEDIA, total=len(missing))
        batch: list[tuple[str, bytes]] = []
        for key in missing:
            self._check_cancel()
            try:
                batch.append((key, self._deps.client.media(wanted[key])))
            except NetworkError:
                self._deps.media.put_many(batch)
                raise
            except CheevosError as exc:  # e.g. a badge RA no longer serves: skip it
                logger.warning("Skipping image %s: %s", key, exc)
            self._tracker.advance(media=True)
            if len(batch) >= MEDIA_BATCH:
                self._deps.media.put_many(batch)
                batch = []
        self._deps.media.put_many(batch)

    def _media_wanted(
        self, games: list[GameProgress], options: SyncOptions
    ) -> Iterator[tuple[str, str]]:
        """List the images this sync should have, as ``(cache key, media path)``.

        Args:
            games: Merged library.
            options: Sync options (badge scope).

        Yields:
            Cache key and media-host path pairs.
        """
        profile = self._deps.data.load_profile()
        if profile is not None and profile.user_pic:
            yield avatar_key(profile.username), profile.user_pic
        for game in games:
            if game.image_icon:
                yield icon_key(game.game_id), game.image_icon
        for game_id in self._badge_games(games, options):
            detail = self._deps.data.game_detail(game_id)
            for achievement in detail.achievements if detail else ():
                locked = not achievement.unlocked
                suffix = "_lock" if locked else ""
                path = f"/Badge/{achievement.badge_name}{suffix}.png"
                yield badge_key(achievement.badge_name, locked=locked), path

    def _badge_games(self, games: list[GameProgress], options: SyncOptions) -> list[int]:
        """Select the games whose badges belong in the cache for the configured scope.

        Args:
            games: Merged library.
            options: Sync options.

        Returns:
            Game IDs.
        """
        if options.badge_scope is BadgeScope.NONE:
            return []
        recent_since = int(self._clock()) - options.recent_days * DAY
        return badge_game_ids(
            games,
            on_device=self._deps.on_device(),
            include_all=options.badge_scope is BadgeScope.ALL,
            recent_since=recent_since,
        )
