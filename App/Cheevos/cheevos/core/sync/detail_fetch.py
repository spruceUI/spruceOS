"""Fetch a game's achievements when the user opens it (.agents/sync-and-storage.md).

A sync keeps the achievement lists of the working set only (on-device and recent games). Opening
any other game asks this worker for its list. A single daemon thread fetches one game at a time,
the latest request first, through its own client and data-cache connection. The client shares
the app's request pacer, so the worker and a running sync stay within RA's limit together. Each
game is stored in one transaction, as the sync does.

The UI polls :meth:`DetailFetcher.status` while it shows a loading page.
"""

from __future__ import annotations

import logging
import sqlite3
import threading
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass
from enum import Enum
from typing import Protocol

from cheevos.core.clock import network_clock
from cheevos.core.errors import (
    AuthError,
    CheevosError,
    NetworkError,
    RateLimitedError,
    RequestCancelledError,
)
from cheevos.core.models import GameDetail, GameProgress
from cheevos.core.sync.engine import RATE_LIMIT_PAUSE, RATE_LIMITED_UNTIL_KEY
from cheevos.core.sync.progress import Failure

logger = logging.getLogger(__name__)

_POLL_SECONDS = 0.5  # idle wake-up interval; requests and close() wake the worker at once


class DetailSource(Protocol):
    """Fetches a game's details from RA (implemented by ``RaClient``)."""

    def game_detail(self, game_id: int) -> GameDetail:
        """Return the game's achievements with the user's unlocks."""
        ...


class DetailStore(Protocol):
    """Reads and stores games (implemented by ``DataCache``)."""

    def game(self, game_id: int) -> GameProgress | None:
        """Return a game from the library."""
        ...

    def save_game_detail(self, detail: GameDetail, *, fingerprint: str, synced_at: int) -> None:
        """Store a game's achievements."""
        ...

    def get_meta(self, key: str) -> str | None:
        """Read a cache metadata value."""
        ...

    def set_meta(self, key: str, value: str | None) -> None:
        """Write a cache metadata value."""
        ...


# (client, data cache, close). Opened on the worker thread, which passes its stop event so the
# client's waits end when the app closes.
DetailSession = tuple[DetailSource, DetailStore, Callable[[], None]]


class FetchState(Enum):
    """Where a requested game is."""

    WAITING = "waiting"  # queued or being fetched
    DONE = "done"
    FAILED = "failed"


@dataclass(frozen=True, slots=True)
class FetchStatus:
    """A requested game's state.

    Attributes:
        state: Where it is.
        failure: Why it failed (``FAILED`` only).
        retry_at: When RA allows requests again (``RATE_LIMITED`` only, when known).
    """

    state: FetchState
    failure: Failure | None = None
    retry_at: float | None = None


_WAITING = FetchStatus(FetchState.WAITING)
_DONE = FetchStatus(FetchState.DONE)


class DetailFetcher:
    """Background fetcher for the achievement lists of games the user opens.

    Args:
        open_session: Creates the client and data cache; called on the worker thread with its
            stop event, again after RA rejects the key (the user may have entered a new one).
        clock: App clock (epoch seconds).
        online: Refreshes app time before checking a stored RA pause, when supplied.
    """

    def __init__(
        self,
        open_session: Callable[[threading.Event], DetailSession],
        *,
        clock: Callable[[], float] = network_clock.now,
        online: Callable[[], bool] | None = None,
    ) -> None:
        self._open_session = open_session
        self._clock = clock
        self._online = online
        self._lock = threading.Lock()
        self._waiting: deque[int] = deque()  # next to fetch first
        self._statuses: dict[int, FetchStatus] = {}
        self._stop = threading.Event()
        self._wake = threading.Event()
        self._thread: threading.Thread | None = None

    def request(self, game_id: int) -> None:
        """Ask for a game's achievements (non-blocking, thread-safe).

        The latest request goes first, even for a game already waiting. A failed game is tried
        again; a fetched one isn't. Ignored after :meth:`close`.

        Args:
            game_id: RA game ID.
        """
        with self._lock:
            if self._stop.is_set():
                return
            status = self._statuses.get(game_id)
            if status is not None and status.state is FetchState.DONE:
                return
            if game_id in self._waiting:
                self._waiting.remove(game_id)
            elif status is not None and status.state is FetchState.WAITING:
                return  # being fetched right now
            self._statuses[game_id] = _WAITING
            self._waiting.appendleft(game_id)
            if self._thread is None:
                self._thread = threading.Thread(
                    target=self._run, name="cheevos-details", daemon=True
                )
                self._thread.start()
        self._wake.set()

    def status(self, game_id: int) -> FetchStatus | None:
        """Return a requested game's state, or ``None`` if it was never requested."""
        with self._lock:
            return self._statuses.get(game_id)

    def close(self, timeout: float = 2.0) -> None:
        """Stop the worker (interrupting a wait for a request slot) and release its session.

        Args:
            timeout: Seconds to wait for a request in flight.
        """
        self._stop.set()
        self._wake.set()
        if self._thread is not None:
            self._thread.join(timeout)

    def _run(self) -> None:
        """Worker body: fetch requested games until closed."""
        session: DetailSession | None = None
        try:
            while not self._stop.is_set():
                self._wake.clear()
                game_id = self._take()
                if game_id is None:
                    self._wake.wait(_POLL_SECONDS)
                    continue
                if session is None:
                    session = self._open(game_id)
                    if session is None:
                        continue
                if not self._fetch(session, game_id):  # the key was rejected: start afresh
                    self._close(session)
                    session = None
        finally:
            if session is not None:
                self._close(session)

    def _take(self) -> int | None:
        """Pop the next requested game, or ``None`` when nothing is waiting."""
        with self._lock:
            return self._waiting.popleft() if self._waiting else None

    def _open(self, game_id: int) -> DetailSession | None:
        """Open a session, failing ``game_id`` if that is impossible.

        Args:
            game_id: The game about to be fetched.

        Returns:
            The session, or ``None``.
        """
        try:
            return self._open_session(self._stop)
        except (CheevosError, OSError, sqlite3.Error):
            logger.exception("Could not open a session to load a game's achievements")
            self._finish(game_id, FetchStatus(FetchState.FAILED, Failure.ERROR))
            return None

    def _fetch(self, session: DetailSession, game_id: int) -> bool:
        """Fetch and store one game, recording how it went.

        Args:
            session: Client and data cache.
            game_id: RA game ID.

        Returns:
            ``False`` when RA rejected the key (the session should be reopened).
        """
        client, data, _ = session
        now = self._clock()
        until = _float(data.get_meta(RATE_LIMITED_UNTIL_KEY))
        if until is not None and self._online is not None:
            if not self._online():
                self._finish(game_id, FetchStatus(FetchState.FAILED, Failure.NETWORK))
                return True
            now = self._clock()
        if until is not None and until > now:
            self._finish(game_id, FetchStatus(FetchState.FAILED, Failure.RATE_LIMITED, until))
            return True
        try:
            game = data.game(game_id)
            detail = client.game_detail(game_id)
            fingerprint = game.fingerprint if game is not None else ""
            data.save_game_detail(detail, fingerprint=fingerprint, synced_at=int(self._clock()))
        except RequestCancelledError:
            self._finish(game_id, None)  # closing: nobody is waiting any more
        except AuthError:
            self._finish(game_id, FetchStatus(FetchState.FAILED, Failure.AUTH))
            return False
        except RateLimitedError as exc:
            now = self._clock()
            pause = exc.retry_after if exc.retry_after is not None else RATE_LIMIT_PAUSE
            data.set_meta(RATE_LIMITED_UNTIL_KEY, str(int(now + pause)))  # the sync waits too
            self._finish(game_id, FetchStatus(FetchState.FAILED, Failure.RATE_LIMITED, now + pause))
        except NetworkError as exc:
            logger.info("Could not load game %d: %s", game_id, exc)
            self._finish(game_id, FetchStatus(FetchState.FAILED, Failure.NETWORK))
        except (CheevosError, sqlite3.Error):
            logger.exception("Could not load game %d", game_id)
            self._finish(game_id, FetchStatus(FetchState.FAILED, Failure.ERROR))
        else:
            logger.info("Loaded game %d on request", game_id)
            self._finish(game_id, _DONE)
        return True

    def _finish(self, game_id: int, status: FetchStatus | None) -> None:
        """Record a game's outcome (``None`` forgets it, so it can be requested again).

        Args:
            game_id: RA game ID.
            status: The outcome.
        """
        with self._lock:
            if status is None:
                self._statuses.pop(game_id, None)
            else:
                self._statuses[game_id] = status

    @staticmethod
    def _close(session: DetailSession) -> None:
        """Release a session, logging (not raising) failures.

        Args:
            session: The session.
        """
        try:
            session[2]()
        except (CheevosError, OSError, sqlite3.Error):
            logger.exception("Closing the game-loading session failed")


def _float(raw: str | None) -> float | None:
    """Parse a stored number.

    Args:
        raw: The stored text.

    Returns:
        The number, or ``None`` when missing or unreadable.
    """
    try:
        return float(raw) if raw is not None else None
    except ValueError:
        return None
