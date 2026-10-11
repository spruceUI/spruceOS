"""Sync status for the bottom bar, and the Start action (sync, cancel, retry) on every screen.

After RA rejected the key, retrying can't help, so Start offers to enter a new key instead.

Every screen shows progress while a sync runs and the result for a few seconds after it ends.
Home and settings (``choose(full_status=True)``) also show the last result with a Start hint
when idle.
"""

from __future__ import annotations

import math
from collections.abc import Callable
from pathlib import Path

from cheevos.core.sync.engine import LAST_SYNC_KEY
from cheevos.core.sync.progress import Failure, Phase, SyncStatus
from cheevos.ui import format as fmt
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui.status_bar import BarStatus

RESULT_SECONDS = 5.0  # a finished sync's result stays on every screen this long

_FAILURES = {
    Failure.OFFLINE: (strings.SYNC_OFFLINE, "cloud"),
    Failure.AUTH: (strings.SYNC_AUTH, "lock"),
    Failure.NETWORK: (strings.SYNC_UNAVAILABLE, "cloud"),
    Failure.RATE_LIMITED: (strings.SYNC_UNAVAILABLE, "cloud"),
    Failure.ERROR: (strings.SYNC_ERROR, "debug"),
}


def progress_text(status: SyncStatus) -> str:
    """Describe a running sync.

    Args:
        status: A running sync's status.

    Returns:
        E.g. "Games 3/12".
    """
    if status.phase is Phase.DETAILS and status.total:
        done = min(status.done + 1, status.total)
        return strings.SYNC_RUNNING_ITEM.format(done=done, total=status.total)
    if status.phase is Phase.RECENT and status.done:
        return strings.SYNC_RUNNING_RECENT.format(done=status.done)
    if status.phase is Phase.MEDIA and status.total:
        return strings.SYNC_RUNNING_IMAGES.format(done=status.done, total=status.total)
    return strings.SYNC_PHASES.get(status.phase.value, "")


class SyncBar:
    """Builds the bottom-bar status from the sync state and handles Start.

    Args:
        ctx: App context.
        icons: Directory of icons sized for the bottom bar.
        enter_key: Asks for a new key (and syncs with it); Start runs it after a rejection.
    """

    def __init__(self, ctx: AppContext, icons: Path, enter_key: Callable[[], None]) -> None:
        self._ctx = ctx
        self._icons = icons
        self._enter_key = enter_key
        self._seen: SyncStatus | None = None
        self._last_sync: str | None = None

    def _icon(self, name: str) -> Path:
        """Return a bar-sized icon.

        Args:
            name: Icon name.

        Returns:
            Its path.
        """
        return self._icons / f"{name}.png"

    def status(self, detailed: bool) -> BarStatus | None:  # noqa: FBT001 — status_bar callback
        """Describe the sync for the bottom bar (called on every frame).

        Args:
            detailed: The screen shows the idle status and hints too (home, settings).

        Returns:
            The status, or ``None`` to leave the bar to the theme.
        """
        state = self._ctx.sync.status()
        if state != self._seen:  # re-read the last sync time only when something happened
            self._seen = state
            self._last_sync = self._ctx.data.get_meta(LAST_SYNC_KEY)
        if state.running:
            return self._progress(state, detailed=detailed)
        finished = state.finished_at
        fresh = finished is not None and 0 <= self._ctx.clock() - finished < RESULT_SECONDS
        if not (detailed or fresh):
            return None
        return self._result(state, detailed=detailed, fresh=fresh)

    def _progress(self, state: SyncStatus, *, detailed: bool) -> BarStatus:
        """Describe a running sync.

        Args:
            state: Its status.
            detailed: Add the Cancel hint.

        Returns:
            The bar status.
        """
        if self._ctx.sync.cancelling:
            return BarStatus(strings.SYNC_CANCELLING, self._icon("reload"))
        action = strings.SYNC_CANCEL if detailed else ""
        return BarStatus(progress_text(state), self._icon("reload"), action, live=True)

    def _result(self, state: SyncStatus, *, detailed: bool, fresh: bool) -> BarStatus:
        """Describe the last sync: its failure, a fresh cancel, or when data was last synced.

        Args:
            state: Status of the last (finished) sync, or the idle status.
            detailed: Add the Sync or Retry hint.
            fresh: The sync ended moments ago.

        Returns:
            The bar status.
        """
        if state.phase is Phase.FAILED and state.failure is not None:
            text, icon = _FAILURES[state.failure]
            action = strings.ENTER_KEY if state.failure is Failure.AUTH else strings.SYNC_RETRY
            wait = self._rate_limit_wait(state)
            if wait is not None:  # retrying before RA's time is up would fail again
                text, action = strings.SYNC_RATE_LIMITED.format(minutes=wait), ""
            return BarStatus(text, self._icon(icon), action if detailed else "")
        action = strings.SYNC if detailed else ""
        if state.phase is Phase.CANCELLED and fresh:
            return BarStatus(strings.SYNC_CANCELLED, self._icon("reload"), action)
        if self._last_sync is None:
            return BarStatus(strings.SYNC_NEVER, self._icon("reload"), action)
        ago = fmt.ago(int(self._last_sync), self._ctx.clock())
        return BarStatus(strings.SYNC_DONE_AGO.format(ago=ago), self._icon("check"), action)

    def _rate_limit_wait(self, state: SyncStatus) -> int | None:
        """Return the minutes left before RA allows requests again, after a rate limit.

        Args:
            state: A failed sync's status.

        Returns:
            Whole minutes, rounded up, or ``None`` when there's no wait left (or RA didn't say).
        """
        if state.failure is not Failure.RATE_LIMITED or state.retry_at is None:
            return None
        left = state.retry_at - self._ctx.clock()
        return math.ceil(left / 60) if left > 0 else None

    def press_start(self) -> None:
        """Start a sync, cancel the running one, or ask for a new key after a rejection."""
        state = self._ctx.sync.status()
        if state.running:
            self._ctx.sync.cancel()
        elif state.phase is Phase.FAILED and state.failure is Failure.AUTH:
            self._enter_key()
        else:
            self._ctx.start_sync()
