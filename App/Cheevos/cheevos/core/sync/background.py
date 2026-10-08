"""Run syncs on a worker thread while the UI keeps going (.agents/sync-and-storage.md)."""

from __future__ import annotations

import logging
import threading
from collections.abc import Callable

from cheevos.core.clock import network_clock
from cheevos.core.errors import CheevosError
from cheevos.core.sync.engine import SyncDeps, SyncEngine, SyncOptions
from cheevos.core.sync.progress import Failure, Phase, ProgressTracker, SyncStatus

logger = logging.getLogger(__name__)


class BackgroundSync:
    """Runs syncs on a worker thread; the UI polls :meth:`status` on its input ticks.

    Args:
        open_deps: Creates the sync collaborators; called on the worker thread with the
            sync's cancel event (its client's waits stop when it is set).
        online: Connectivity check passed to the engine.
        clock: App time shared with the transport and UI.
    """

    def __init__(
        self,
        open_deps: Callable[[threading.Event], SyncDeps],
        *,
        online: Callable[[], bool],
        clock: Callable[[], float] = network_clock.now,
    ) -> None:
        self._open_deps = open_deps
        self._online = online
        self._clock = clock
        self._tracker = ProgressTracker()
        self._cancel = threading.Event()
        self._thread: threading.Thread | None = None

    def status(self) -> SyncStatus:
        """Return the latest status snapshot."""
        return self._tracker.snapshot()

    def start(self, options: SyncOptions) -> bool:
        """Start a sync unless one is running.

        Args:
            options: What to sync.

        Returns:
            ``True`` if a new sync started.
        """
        if self._thread is not None and self._thread.is_alive():
            return False
        self._cancel.clear()
        self._tracker.reset()
        self._tracker.phase(Phase.PREFLIGHT)
        self._thread = threading.Thread(
            target=self._work, args=(options,), name="cheevos-sync", daemon=True
        )
        self._thread.start()
        return True

    def cancel(self) -> None:
        """Ask a running sync to stop: at once while it waits, else after the current request."""
        self._cancel.set()

    @property
    def cancelling(self) -> bool:
        """Whether a cancel was requested and the sync has not stopped yet."""
        return self._cancel.is_set() and self.status().running

    def join(self, timeout: float | None = None) -> None:
        """Wait for the worker to finish.

        Args:
            timeout: Maximum seconds to wait.
        """
        if self._thread is not None:
            self._thread.join(timeout)

    def _work(self, options: SyncOptions) -> None:
        """Worker body: open collaborators, run the engine, always release them.

        Args:
            options: What to sync.
        """
        try:
            deps = self._open_deps(self._cancel)
        except CheevosError:
            logger.exception("Could not start sync")
            self._tracker.finish(Phase.FAILED, failure=Failure.ERROR, at=self._clock())
            return
        try:
            engine = SyncEngine(
                deps, self._tracker, self._cancel, online=self._online, clock=self._clock
            )
            engine.run(options)
        finally:
            deps.close()
