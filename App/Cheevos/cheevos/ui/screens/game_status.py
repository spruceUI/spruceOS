"""Show progress and handle Start for a single-game launch from Spruce."""

from __future__ import annotations

import math
from collections.abc import Callable
from pathlib import Path

from cheevos.core.sync.detail_fetch import FetchState
from cheevos.core.sync.progress import Failure
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui.status_bar import BarStatus
from cheevos.ui.screens.status import SyncBar


class GameSyncBar(SyncBar):
    """Route status and Start to one game instead of the account-wide sync.

    Args:
        ctx: Shared app context.
        icons: Bottom-bar icons.
        enter_key: Ask for a replacement API key and refresh this game.
        game_id: The game opened from Spruce.
    """

    def __init__(
        self, ctx: AppContext, icons: Path, enter_key: Callable[[], None], game_id: int
    ) -> None:
        super().__init__(ctx, icons, enter_key)
        self._game_id = game_id

    def status(self, detailed: bool) -> BarStatus | None:  # noqa: FBT001 — status source
        """Show the target game's request, failure or refresh hint on every screen."""
        state = self._ctx.details.status(self._game_id)
        if state is None or state.state is FetchState.DONE:
            return BarStatus("", action=strings.GAME_REFRESH)
        if state.state is FetchState.WAITING:
            return BarStatus(
                strings.LOADING_ACHIEVEMENTS, self._icon("reload"), strings.SYNC_CANCEL, live=True
            )
        if state.state is FetchState.CANCELLED:
            return BarStatus(strings.SYNC_CANCELLED, self._icon("reload"), strings.GAME_REFRESH)
        if state.failure is Failure.AUTH:
            return BarStatus(strings.SYNC_AUTH, self._icon("lock"), strings.ENTER_KEY)
        if state.failure is Failure.RATE_LIMITED and state.retry_at is not None:
            left = math.ceil((state.retry_at - self._ctx.clock()) / 60)
            if left > 0:
                return BarStatus(
                    strings.SYNC_RATE_LIMITED.format(minutes=left), self._icon("cloud")
                )
        return BarStatus(strings.GAME_REFRESH_FAILED, self._icon("cloud"), strings.SYNC_RETRY)

    def press_start(self) -> None:
        """Cancel this game's request, replace a rejected key or refresh its progress."""
        state = self._ctx.details.status(self._game_id)
        if state is not None and state.state is FetchState.WAITING:
            self._ctx.details.cancel(self._game_id)
        elif state is not None and state.failure is Failure.AUTH:
            self._enter_key()
        else:
            self._ctx.start_sync()
