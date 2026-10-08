"""Thread-safe sync status shared between the sync thread and the UI."""

from __future__ import annotations

import dataclasses
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from enum import Enum


class Phase(Enum):
    """Where a sync is, in order. The last three are final."""

    IDLE = "idle"
    PREFLIGHT = "preflight"
    PROFILE = "profile"
    LIBRARY = "library"
    AWARDS = "awards"
    DETAILS = "details"
    MEDIA = "media"
    DONE = "done"
    FAILED = "failed"
    CANCELLED = "cancelled"


FINAL_PHASES = frozenset({Phase.IDLE, Phase.DONE, Phase.FAILED, Phase.CANCELLED})


class Failure(Enum):
    """Why a sync stopped early; drives the status line shown to the user."""

    OFFLINE = "offline"
    AUTH = "auth"
    NETWORK = "network"
    RATE_LIMITED = "rate-limited"
    ERROR = "error"


@dataclass(frozen=True, slots=True)
class SyncStatus:
    """Immutable snapshot of a sync.

    Attributes:
        phase: Current phase.
        done: Items finished in the current phase.
        total: Items planned in the current phase (0 when not countable).
        current: What is being fetched, e.g. a game title.
        eta_seconds: Estimated seconds left in the current phase, if known.
        failure: Reason for a failed sync.
        details_fetched: Game detail requests made this sync.
        media_fetched: Images downloaded this sync.
        finished_at: Wall-clock time the sync ended (final phases only).
        retry_at: Wall-clock time RA asked us to wait until (``RATE_LIMITED`` failures only,
            when RA said).
    """

    phase: Phase = Phase.IDLE
    done: int = 0
    total: int = 0
    current: str = ""
    eta_seconds: float | None = None
    failure: Failure | None = None
    details_fetched: int = 0
    media_fetched: int = 0
    finished_at: float | None = None
    retry_at: float | None = None

    @property
    def running(self) -> bool:
        """Whether a sync is in progress."""
        return self.phase not in FINAL_PHASES


class ProgressTracker:
    """Holds the latest :class:`SyncStatus`; the sync thread writes, the UI reads snapshots.

    Args:
        clock: Monotonic clock used for ETA estimates.
    """

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._lock = threading.Lock()
        self._status = SyncStatus()
        self._clock = clock
        self._phase_started = clock()

    def snapshot(self) -> SyncStatus:
        """Return the current status."""
        with self._lock:
            return self._status

    def reset(self) -> None:
        """Forget the previous sync (before starting a new one)."""
        with self._lock:
            self._status = SyncStatus()

    def phase(self, phase: Phase, *, total: int = 0) -> None:
        """Enter a phase, resetting its counters.

        Args:
            phase: The new phase.
            total: Items planned in it.
        """
        with self._lock:
            self._phase_started = self._clock()
            self._status = dataclasses.replace(
                self._status, phase=phase, done=0, total=total, current="", eta_seconds=None
            )

    def add_total(self, count: int) -> None:
        """Plan more items in the current phase (found while it runs).

        Args:
            count: Items to add.
        """
        with self._lock:
            status = self._status
            self._status = dataclasses.replace(status, total=status.total + count)

    def working_on(self, current: str) -> None:
        """Report the item being fetched.

        Args:
            current: Human-readable item, e.g. a game title.
        """
        with self._lock:
            self._status = dataclasses.replace(self._status, current=current)

    def advance(self, *, detail: bool = False, media: bool = False) -> None:
        """Count one finished item and update the ETA from the phase's average pace.

        Args:
            detail: The item was a game detail request.
            media: The item was an image download.
        """
        with self._lock:
            status = self._status
            done = status.done + 1
            elapsed = self._clock() - self._phase_started
            remaining = max(status.total - done, 0)
            eta = elapsed / done * remaining if status.total else None
            self._status = dataclasses.replace(
                status,
                done=done,
                eta_seconds=eta,
                details_fetched=status.details_fetched + int(detail),
                media_fetched=status.media_fetched + int(media),
            )

    def finish(
        self,
        phase: Phase,
        *,
        failure: Failure | None = None,
        at: float,
        retry_at: float | None = None,
    ) -> None:
        """Enter a final phase.

        Args:
            phase: ``DONE``, ``FAILED`` or ``CANCELLED``.
            failure: Reason, for ``FAILED``.
            at: Wall-clock end time.
            retry_at: When RA allows requests again, for a ``RATE_LIMITED`` failure.
        """
        with self._lock:
            self._status = dataclasses.replace(
                self._status,
                phase=phase,
                failure=failure,
                current="",
                eta_seconds=None,
                finished_at=at,
                retry_at=retry_at,
            )
