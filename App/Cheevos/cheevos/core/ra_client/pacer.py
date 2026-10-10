"""Space Web API requests for one API key, across every client and thread.

RA limits requests per key (.agents/retroachievements.md, "Rate limit"). Measured on 2026-10-06:
requests 0.3 s apart (about 2.6 per second) drew HTTP 429 after about 18 of them, then
``Retry-After: 600``; one request per second drew none in 20 minutes. The current defaults
allow a short burst, then keep to one request every three seconds for extra headroom. It's a
token bucket (in GCRA form): after an idle spell up to ``burst`` requests start ``spacing``
apart, and the bucket refills at one request per ``interval``. Media uses a separate pacer
with no burst. An interval of zero disables normal pacing for recorded fixtures.

The sync, on-demand fetches and the key check each have their own client, so they share one
:class:`Pacer` that keeps their combined pace. A pacer only schedules: :meth:`Pacer.reserve`
returns how long the caller must wait, and the caller waits in a way it can interrupt.
"""

from __future__ import annotations

import threading
import time
from collections.abc import Callable

from cheevos.core.errors import RateLimitedError

API_INTERVAL = 3.0  # seconds per request once the burst is used
API_BURST = 3  # requests allowed after an idle spell
API_SPACING = 1.0  # seconds between requests within a burst
MEDIA_INTERVAL = 0.25  # seconds between media downloads
LONG_PAUSE = 10.0  # RA asking for a longer pause stops work instead of waiting it out


class Pacer:
    """Hands out request slots: a short burst, then one per ``interval`` (thread-safe).

    Args:
        interval: Seconds per request at the steady pace (the bucket's refill time). 0 turns
            pacing off (recorded fixtures).
        burst: Requests allowed in a row after an idle spell; 1 spaces every request by
            ``interval``.
        spacing: Minimum seconds between two request starts within a burst (never more than
            ``interval``).
        clock: Monotonic clock.
        long_pause: Pauses longer than this make :meth:`reserve` raise instead of waiting.
    """

    def __init__(
        self,
        interval: float = API_INTERVAL,
        *,
        burst: int = API_BURST,
        spacing: float = API_SPACING,
        clock: Callable[[], float] = time.monotonic,
        long_pause: float = LONG_PAUSE,
    ) -> None:
        self._interval = interval
        self._tolerance = max(burst - 1, 0) * interval  # how far ahead of the pace a burst runs
        self._spacing = min(spacing, interval)
        self._clock = clock
        self._long_pause = long_pause
        self._lock = threading.Lock()
        self._due: float | None = None  # when the bucket would be full again (GCRA's "TAT")
        self._last_start: float | None = None
        self._paused_until: float | None = None

    @property
    def enabled(self) -> bool:
        """Whether normal request spacing is enabled (429 pauses still apply)."""
        return self._interval > 0.0

    def reserve(self) -> float:
        """Take the next request slot.

        Returns:
            Seconds the caller must wait before starting its request (0 when it may start now).

        Raises:
            RateLimitedError: RA asked for a pause longer than ``long_pause``; carries the
                seconds left.
        """
        with self._lock:
            now = self._clock()
            paused = self._paused_until if self._paused_until is not None else now
            if paused - now > self._long_pause:
                raise RateLimitedError(paused - now)
            due = self._due if self._due is not None else now
            start = max(now, paused, due - self._tolerance)
            if self._last_start is not None:
                start = max(start, self._last_start + self._spacing)
            self._due = max(due, start) + self._interval
            self._last_start = start
            return start - now

    def pause(self, seconds: float) -> None:
        """Start no request for ``seconds`` (RA answered HTTP 429), and no burst after it.

        Args:
            seconds: Length of the pause, from now.
        """
        with self._lock:
            now = self._clock()
            until = now + max(seconds, 0.0)
            if self._paused_until is None or until > self._paused_until:
                self._paused_until = until
            # Resume at the steady pace: the bucket starts empty when the pause ends.
            self._due = max(self._due if self._due is not None else now, until + self._tolerance)
