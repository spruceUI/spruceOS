from __future__ import annotations

import json
from dataclasses import dataclass, replace

from . import cache_keys
from .storage import Storage, current_millis

CACHE_BUDGET_LIMIT = 100
CACHE_BUDGET_WINDOW_MS = 30 * 60 * 1000
# The first games of a window go out at once, so a small run feels instant; the rest is spread
# over the window instead of sent as one burst, which RetroAchievements answers with a 429.
CACHE_BURST_GAMES = 20
CACHE_PACE_SECONDS = CACHE_BUDGET_WINDOW_MS / CACHE_BUDGET_LIMIT / 1000
# Bounds how long one batch runs, so a bulk run hands the rest to the proxy service. A whole
# window, so a paced batch can still use the full budget.
CACHE_BATCH_MAX_MS = CACHE_BUDGET_WINDOW_MS


@dataclass(frozen=True)
class BudgetWindow:
    """One budget window: used counts games cached; lookups for ROMs RetroAchievements doesn't
    know are free. paused_until holds the queue back after a 429, so no new batch starts before
    then, and outlives the window."""

    window_start: int = 0
    used: int = 0
    paused_until: int = 0

    def current(self, now: int, window_ms: int = CACHE_BUDGET_WINDOW_MS) -> BudgetWindow:
        # A clock that jumped backwards starts a fresh window instead of blocking caching until
        # it catches up again.
        if now < self.window_start or now - self.window_start >= window_ms:
            return BudgetWindow(window_start=now, paused_until=self.paused_until)
        return self

    def charge(self, now: int, games: int, window_ms: int = CACHE_BUDGET_WINDOW_MS) -> BudgetWindow:
        window = self.current(now, window_ms)
        return replace(window, used=window.used + games)

    def remaining(
        self,
        now: int,
        limit: int = CACHE_BUDGET_LIMIT,
        window_ms: int = CACHE_BUDGET_WINDOW_MS,
    ) -> int:
        if now < self.paused_until:
            return 0
        return max(0, limit - self.current(now, window_ms).used)

    def next_available_at(
        self,
        now: int,
        limit: int = CACHE_BUDGET_LIMIT,
        window_ms: int = CACHE_BUDGET_WINDOW_MS,
    ) -> int:
        window = self.current(now, window_ms)
        window_opens_at = now if window.used < limit else window.window_start + window_ms
        return max(self.paused_until, window_opens_at)

    def to_json(self) -> str:
        return json.dumps(
            {
                "windowStart": self.window_start,
                "used": self.used,
                "pausedUntil": self.paused_until,
            },
            separators=(",", ":"),
        )

    @staticmethod
    def from_json(body: str | None) -> BudgetWindow:
        try:
            payload = json.loads(body or "")
            return BudgetWindow(
                window_start=int(payload.get("windowStart", 0)),
                used=int(payload.get("used", 0)),
                paused_until=int(payload.get("pausedUntil", 0)),
            )
        except Exception:
            return BudgetWindow()


def load(storage: Storage) -> BudgetWindow:
    entry = storage.get_cache(cache_keys.CACHE_BUDGET)
    return BudgetWindow.from_json(entry["responseBody"] if entry is not None else None)


def save(storage: Storage, window: BudgetWindow) -> None:
    storage.upsert_cache(cache_keys.CACHE_BUDGET, window.to_json())


def charge_game(storage: Storage, now: int | None = None) -> None:
    save(storage, load(storage).charge(now or current_millis(), games=1))


def pause_until(storage: Storage, until: int) -> None:
    window = load(storage)
    if until > window.paused_until:
        save(storage, replace(window, paused_until=until))


def used(storage: Storage, now: int | None = None) -> int:
    return load(storage).current(now or current_millis()).used


def remaining(storage: Storage, now: int | None = None) -> int:
    return load(storage).remaining(now or current_millis())


def next_available_at(storage: Storage, now: int | None = None) -> int:
    return load(storage).next_available_at(now or current_millis())
