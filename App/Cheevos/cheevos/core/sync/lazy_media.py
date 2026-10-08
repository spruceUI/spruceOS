"""Fetch missing images in the background while the user browses (.agents/sync-and-storage.md).

Badges outside the sync's badge scope (or with scope "None") and anything a sync has not
reached yet are requested here when a screen first needs them. A single daemon worker
downloads them one at a time over its own keep-alive connection and stores them in the image
cache; the UI notices through :attr:`LazyMediaFetcher.version` and re-renders.

What's on screen goes first: a request jumps ahead of everything waiting, and the next page's
images (``later``) wait behind it. When the screen moves on, the UI drops what's still waiting.
"""

from __future__ import annotations

import logging
import sqlite3
import threading
import time
from collections import deque
from collections.abc import Callable
from typing import Protocol

from cheevos.core.errors import CheevosError, NetworkError

logger = logging.getLogger(__name__)

_POLL_SECONDS = 0.5  # idle wake-up interval; requests and close() wake the worker at once


class MediaSource(Protocol):
    """Downloads files from RA's media host (implemented by ``RaClient``)."""

    def media(self, path: str) -> bytes:
        """Return the file at ``path`` on the media host."""
        ...


class MediaStore(Protocol):
    """Stores image blobs (implemented by ``MediaCache``)."""

    def put(self, key: str, data: bytes) -> None:
        """Store ``data`` under ``key``."""
        ...


# (client, media cache, close). Opened on the worker thread: SQLite connections are per-thread.
MediaSession = tuple[MediaSource, MediaStore, Callable[[], None]]


class LazyMediaFetcher:
    """Background downloader for images the UI asked for but the cache lacks.

    Args:
        open_session: Creates the client and image cache; called once, on the worker thread.
        clock: Monotonic clock used for the offline backoff.
        offline_backoff: Seconds to ignore requests after a network failure.
        max_queue: Maximum waiting requests. When full, a request for the screen drops the last
            one waiting, and a ``later`` one is ignored (either can be requested again).
    """

    def __init__(
        self,
        open_session: Callable[[], MediaSession],
        *,
        clock: Callable[[], float] = time.monotonic,
        offline_backoff: float = 60.0,
        max_queue: int = 500,
    ) -> None:
        self._open_session = open_session
        self._clock = clock
        self._offline_backoff = offline_backoff
        self._max_queue = max_queue
        self._lock = threading.Lock()
        self._waiting: deque[str] = deque()  # next to download first
        self._paths: dict[str, str] = {}  # waiting key -> media-host path
        self._urgent = 0  # waiting keys up front, requested since the worker last took one
        self._stored: set[str] = set()  # downloaded this session
        self._failed: set[str] = set()  # permanently unavailable this session
        self._in_flight: str | None = None
        self._version = 0
        self._backoff_until: float | None = None
        self._disabled = False
        self._stop = threading.Event()
        self._wake = threading.Event()
        self._thread: threading.Thread | None = None

    @property
    def version(self) -> int:
        """Number of images stored so far; changes whenever a new image becomes available."""
        with self._lock:
            return self._version

    def pending(self) -> int:
        """Return the number of waiting plus in-flight requests."""
        with self._lock:
            return len(self._waiting) + (1 if self._in_flight is not None else 0)

    def request(self, key: str, media_path: str, *, later: bool = False) -> None:
        """Ask for an image to be downloaded and cached (non-blocking, thread-safe).

        An image for the screen goes ahead of everything waiting, after the others requested
        since the worker last took one, so one screen's rows keep their order. Asking again for
        a waiting image moves it up the same way. A ``later`` image (the next page) waits at
        the back and moves nothing.

        Ignored when the key is in flight, stored or known to be missing on RA; during the
        offline backoff; after :meth:`close`; or, for ``later``, when the queue is full.

        Args:
            key: Image cache key.
            media_path: Path on the media host, e.g. ``"/Badge/198102.png"``.
            later: Prefetch: wanted soon, but not on screen yet.
        """
        with self._lock:
            if self._disabled or self._stop.is_set() or self._in_backoff():
                return
            if key == self._in_flight or key in self._stored or key in self._failed:
                return
            if later:
                if key in self._paths or len(self._waiting) >= self._max_queue:
                    return
                self._waiting.append(key)
            else:
                self._jump_queue(key)
            self._paths[key] = media_path
            self._ensure_worker()
        self._wake.set()

    def drop_waiting(self) -> None:
        """Forget every request not started yet (the screen moved on; thread-safe)."""
        with self._lock:
            self._drain()

    def _jump_queue(self, key: str) -> None:
        """Put ``key`` ahead of everything waiting except this burst's earlier keys (lock held).

        Args:
            key: Image cache key, possibly waiting already.
        """
        if key in self._paths:
            position = self._waiting.index(key)
            if position < self._urgent:
                return  # already up front
            del self._waiting[position]
        elif len(self._waiting) >= self._max_queue:
            del self._paths[self._waiting.pop()]
            self._urgent = min(self._urgent, len(self._waiting))
        self._waiting.insert(self._urgent, key)
        self._urgent += 1

    def close(self, timeout: float = 2.0) -> None:
        """Stop the worker and release its session.

        Args:
            timeout: Seconds to wait for the worker to finish its current download.
        """
        self._stop.set()
        self._wake.set()
        if self._thread is not None:
            self._thread.join(timeout)

    def _in_backoff(self) -> bool:
        """Report whether requests are paused after a network failure (lock held).

        Returns:
            ``True`` while the backoff lasts; clears it once expired.
        """
        if self._backoff_until is None:
            return False
        if self._clock() < self._backoff_until:
            return True
        self._backoff_until = None
        return False

    def _ensure_worker(self) -> None:
        """Start the worker thread on the first request (lock held)."""
        if self._thread is None:
            self._thread = threading.Thread(target=self._run, name="cheevos-media", daemon=True)
            self._thread.start()

    def _run(self) -> None:
        """Worker body: open the session, then download queued images until closed."""
        session = self._open()
        if session is None:
            return
        client, media, close = session
        try:
            while not self._stop.is_set():
                self._wake.clear()
                item = self._take()
                if item is None:
                    self._wake.wait(_POLL_SECONDS)
                    continue
                self._fetch(client, media, *item)
        finally:
            try:
                close()
            except (CheevosError, OSError, sqlite3.Error):
                logger.exception("Closing the image session failed")

    def _take(self) -> tuple[str, str] | None:
        """Pop the next request and mark it in flight in one step (so ``pending`` never dips).

        Returns:
            ``(key, media path)``, or ``None`` when nothing is waiting.
        """
        with self._lock:
            if not self._waiting:
                return None
            key = self._waiting.popleft()
            self._urgent = 0  # what's requested from now on goes ahead of the rest
            self._in_flight = key
            return key, self._paths.pop(key)

    def _open(self) -> MediaSession | None:
        """Open the session; disable the fetcher if that is impossible.

        Returns:
            The session, or ``None`` when it could not be opened.
        """
        try:
            return self._open_session()
        except (CheevosError, OSError, sqlite3.Error):
            logger.exception("Background image downloads disabled")
            with self._lock:
                self._disabled = True
                self._drain()
            return None

    def _fetch(self, client: MediaSource, media: MediaStore, key: str, path: str) -> None:
        """Download one image and store it, classifying failures.

        Args:
            client: Media downloader.
            media: Image store.
            key: Cache key.
            path: Media-host path.
        """
        try:
            media.put(key, client.media(path))
        except NetworkError as exc:
            logger.info("Image downloads paused (offline): %s", exc)
            self._enter_backoff(key)
        except CheevosError as exc:
            logger.warning("Image %s unavailable: %s", key, exc)
            with self._lock:
                self._failed.add(key)
        except sqlite3.Error:
            logger.exception("Could not store image %s", key)  # may be requested again
        else:
            with self._lock:
                self._stored.add(key)
                self._version += 1
        finally:
            with self._lock:
                self._in_flight = None

    def _enter_backoff(self, key: str) -> None:
        """Pause requests after a network failure and drop everything waiting.

        Args:
            key: The in-flight key that failed; it may be requested again after the backoff.
        """
        with self._lock:
            self._backoff_until = self._clock() + self._offline_backoff
            self._drain()

    def _drain(self) -> None:
        """Drop every waiting request; each may be requested again (lock held)."""
        self._waiting.clear()
        self._paths.clear()
        self._urgent = 0
