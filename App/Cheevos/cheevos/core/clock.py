"""Keep app time from RA's HTTP Date without changing the device's system clock."""

from __future__ import annotations

import threading
import time
from collections.abc import Callable
from email.utils import parsedate_to_datetime

MIN_SERVER_YEAR = 2026


class ServerClock:
    """Advance RA's last reported time with a monotonic clock, shared across workers.

    Until RA answers, use the system clock. Only the API host supplies samples: cached
    media responses may have old Date headers (.agents/sync-and-storage.md).

    Args:
        wall_clock: System time before a server sample is available.
        monotonic: Elapsed time unaffected by NTP or manual system-clock changes.
    """

    def __init__(
        self,
        *,
        wall_clock: Callable[[], float] = time.time,
        monotonic: Callable[[], float] = time.monotonic,
    ) -> None:
        self._wall_clock = wall_clock
        self._monotonic = monotonic
        self._lock = threading.Lock()
        self._sample: tuple[float, float] | None = None

    def now(self) -> float:
        """Return epoch seconds, using RA time once it has answered."""
        with self._lock:
            if self._sample is None:
                return self._wall_clock()
            epoch, received = self._sample
            return epoch + self._monotonic() - received

    def observe_date(self, value: str | None) -> None:
        """Accept a valid HTTP Date; ignore missing, malformed or implausibly old values."""
        if not value:
            return
        try:
            date = parsedate_to_datetime(value)
            if date.tzinfo is None or date.year < MIN_SERVER_YEAR:
                return
            epoch = date.timestamp()
        except (ValueError, TypeError, OverflowError):
            return
        with self._lock:
            self._sample = (epoch, self._monotonic())


network_clock = ServerClock()
