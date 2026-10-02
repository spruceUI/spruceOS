from __future__ import annotations

import contextlib
import threading
import time

RATE_LIMIT_PAUSE_MS = 10 * 60 * 1000

_lock = threading.Lock()
_paused_until = 0
_local = threading.local()


class RateLimitedError(RuntimeError):
    pass


def current_millis() -> int:
    return int(time.time() * 1000)


def in_background() -> bool:
    """True while the cache queue or the periodic refresh sends requests on this thread: a 429
    then stops that work instead of being retried."""
    return getattr(_local, "depth", 0) > 0


@contextlib.contextmanager
def background():
    _local.depth = getattr(_local, "depth", 0) + 1
    try:
        yield
    finally:
        _local.depth -= 1


def on_rate_limited(retry_after_ms: int | None, now: int | None = None) -> None:
    """Pauses background work for at least ten minutes, longer if the server's Retry-After asks."""
    global _paused_until
    until = (now if now is not None else current_millis()) + max(
        RATE_LIMIT_PAUSE_MS, retry_after_ms or 0
    )
    with _lock:
        _paused_until = max(_paused_until, until)


def paused_until(now: int | None = None) -> int | None:
    current = now if now is not None else current_millis()
    with _lock:
        return _paused_until if _paused_until > current else None


def reset_for_tests() -> None:
    global _paused_until
    with _lock:
        _paused_until = 0
