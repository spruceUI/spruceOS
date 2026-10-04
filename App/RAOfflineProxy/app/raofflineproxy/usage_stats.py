from __future__ import annotations

import atexit
import contextlib
import json
import logging
import os
import threading
import time
from typing import Optional

try:
    import fcntl
except ImportError:  # pragma: no cover - non-POSIX dev machines
    fcntl = None

from .config import CONFIG_DIR, ensure_config_dir, load_config, save_config

LOGGER = logging.getLogger("raofflineproxy")

USAGE_STATS_FILE = CONFIG_DIR / "usage_stats.json"
USAGE_STATS_LOCK_FILE = CONFIG_DIR / "usage_stats.lock"
KEY_LAST_REPORTED_AT = "last_reported_at"
CONFIG_KEY_CONSENT = "usage_stats_consent"
CONFIG_KEY_CONSENT_VERSION = "usage_stats_consent_version"
# Bump when the usage report starts collecting a new kind of data, so users who agreed to the
# old scope are asked again. Users who declined are not asked again.
USAGE_STATS_CONSENT_VERSION = 1
# The menu, the CLI and the service each count in memory and merge into the shared file at most
# this often, so bulk caching doesn't write the SD card on every request.
FLUSH_INTERVAL_SECONDS = 30.0
CONSENT_CACHE_SECONDS = 30.0
HTTP_TOO_MANY_REQUESTS = 429
# Same fixed window length as the caching budget (cache_budget.CACHE_BUDGET_WINDOW_MS); not
# imported from there so network.py can use this module without pulling in storage.
WINDOW_MS = 30 * 60 * 1000

# Shared by the SDL menu and the CLI (usage-stats-status --json), so frontends that bring their
# own UI, like spruce, ask with the same wording.
CONSENT_TITLE = "Help improve RAOfflineProxy"
CONSENT_ACCEPT = "Share statistics"
CONSENT_DECLINE = "No thanks"
CONSENT_MESSAGE = (
    "Sharing anonymous statistics once a day would really help me understand how many people "
    "use RAOfflineProxy and how well caching works.\n\n"
    "Sent: app version, device, OS, cache numbers.\n"
    "Never sent: username, password, achievements."
)
PRIVACY_POLICY_URL = "https://raofflineproxy.com/privacy-policy.html"

SOURCE_EMULATOR = "emulator"
SOURCE_AWARD_SYNC = "award_sync"
SOURCE_BACKGROUND = "background"
SOURCE_APP = "app"

MAX_REQUESTS_PER_WINDOW = "max_requests_per_window"
FAILURES_NETWORK = "failures_network"
FAILURES_SERVER = "failures_server"
RATE_LIMITED = "rate_limited"
BATCHES = "batches"
BATCHES_TIME_LIMITED = "batches_time_limited"
BATCH_MS_TOTAL = "batch_ms_total"
QUEUE_CACHED = "queue_cached"
QUEUE_NO_MATCH = "queue_no_match"
QUEUE_EMPTIED = "queue_emptied"
QUEUE_FAILED = "queue_failed"

@contextlib.contextmanager
def _file_lock():
    """Shared by every process on the device: the menu, the CLI and the proxy service."""
    ensure_config_dir()
    with USAGE_STATS_LOCK_FILE.open("a+") as handle:
        if fcntl is not None:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            if fcntl is not None:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def requests_key(source: str) -> str:
    return f"requests_{source}"


def resolve_consent(granted: Optional[bool], granted_version: int, current_version: int = USAGE_STATS_CONSENT_VERSION) -> Optional[bool]:
    if granted is True and granted_version < current_version:
        return None
    return granted


def load_consent(config_data: Optional[dict] = None) -> Optional[bool]:
    data = load_config() if config_data is None else config_data
    granted = data.get(CONFIG_KEY_CONSENT)
    if not isinstance(granted, bool):
        return None
    version = data.get(CONFIG_KEY_CONSENT_VERSION)
    return resolve_consent(granted, version if isinstance(version, int) else 0)


def consent_status(config_data: Optional[dict] = None) -> dict:
    """What a frontend needs to show the consent prompt itself: consent is None while the user
    hasn't answered, or agreed to an older consent version and has to be asked again."""
    return {
        "consent": load_consent(config_data),
        "consent_version": USAGE_STATS_CONSENT_VERSION,
        "title": CONSENT_TITLE,
        "message": CONSENT_MESSAGE,
        "accept": CONSENT_ACCEPT,
        "decline": CONSENT_DECLINE,
        "privacy_policy_url": PRIVACY_POLICY_URL,
    }


def consent_status_label(consent: Optional[bool]) -> str:
    if consent is None:
        return "unanswered"
    return "enabled" if consent else "disabled"


def save_consent(granted: bool) -> None:
    data = load_config()
    data[CONFIG_KEY_CONSENT] = granted
    data[CONFIG_KEY_CONSENT_VERSION] = USAGE_STATS_CONSENT_VERSION
    save_config(data)
    _recorder.forget_consent()
    if not granted:
        clear()


class PendingCounters:
    """Counts of one process since its last flush. The busiest 30-minute window is tracked per
    process, the same fixed window length the caching budget uses."""

    def __init__(self, window_ms: int = WINDOW_MS) -> None:
        self.window_ms = window_ms
        self.values: dict[str, int] = {}
        self.window_start: Optional[int] = None
        self.window_requests = 0

    def add(self, key: str, by: int = 1) -> None:
        if by:
            self.values[key] = self.values.get(key, 0) + by

    def record_request(self, source: str, status_code: Optional[int], now_ms: int) -> None:
        self.add(requests_key(source))
        start = self.window_start
        if start is None or now_ms < start or now_ms - start >= self.window_ms:
            self.window_start = now_ms
            self.window_requests = 1
        else:
            self.window_requests += 1
        self.values[MAX_REQUESTS_PER_WINDOW] = max(self.values.get(MAX_REQUESTS_PER_WINDOW, 0), self.window_requests)
        if status_code is None:
            self.add(FAILURES_NETWORK)
        elif status_code == HTTP_TOO_MANY_REQUESTS:
            self.add(RATE_LIMITED)
        elif status_code >= 500:
            self.add(FAILURES_SERVER)

    def record_batch(self, cached: int, no_match: int, stop: str, time_limited: bool, duration_ms: int) -> None:
        sent_requests = cached + no_match > 0 or time_limited or stop in ("failed", "rate_limited")
        if not sent_requests:
            return
        self.add(BATCHES)
        self.add(BATCH_MS_TOTAL, max(0, duration_ms))
        self.add(QUEUE_CACHED, cached)
        self.add(QUEUE_NO_MATCH, no_match)
        if time_limited:
            self.add(BATCHES_TIME_LIMITED)
        if stop == "failed":
            self.add(QUEUE_FAILED)
        if stop == "empty":
            self.add(QUEUE_EMPTIED)

    def take(self) -> dict[str, int]:
        values = self.values
        self.values = {}
        return values


def merge_counters(stored: dict, pending: dict[str, int]) -> dict:
    merged = dict(stored)
    for key, value in pending.items():
        current = merged.get(key, 0)
        current = current if isinstance(current, int) else 0
        merged[key] = max(current, value) if key.startswith("max_") else current + value
    return merged


def reportable(stored: dict) -> dict[str, int]:
    return {
        key: value
        for key, value in stored.items()
        if key != KEY_LAST_REPORTED_AT and isinstance(value, int) and value > 0
    }


def after_report(stored: dict, reported: dict[str, int], reported_at: int) -> dict:
    """Removes what the report sent and keeps whatever was merged while it was in flight."""
    remaining = {}
    for key, value in stored.items():
        if key == KEY_LAST_REPORTED_AT or not isinstance(value, int):
            continue
        sent = reported.get(key, 0)
        left = 0 if key.startswith("max_") and key in reported else value - sent
        if left > 0:
            remaining[key] = left
    remaining[KEY_LAST_REPORTED_AT] = reported_at
    return remaining


def _load_unlocked() -> dict:
    try:
        data = json.loads(USAGE_STATS_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _save_unlocked(data: dict) -> None:
    ensure_config_dir()
    temp_path = USAGE_STATS_FILE.with_suffix(".json.tmp")
    temp_path.write_text(json.dumps(data, sort_keys=True), encoding="utf-8")
    os.replace(temp_path, USAGE_STATS_FILE)


class _Recorder:
    def __init__(self) -> None:
        self._mutex = threading.Lock()
        self._pending = PendingCounters()
        self._last_flush = time.monotonic()
        self._consent: Optional[bool] = None
        self._consent_checked_at = 0.0

    def forget_consent(self) -> None:
        with self._mutex:
            self._consent_checked_at = 0.0
            if load_consent() is not True:
                self._pending = PendingCounters()

    def _consented(self) -> bool:
        now = time.monotonic()
        if now - self._consent_checked_at >= CONSENT_CACHE_SECONDS:
            self._consent = load_consent()
            self._consent_checked_at = now
        return self._consent is True

    def record_request(self, source: str, status_code: Optional[int]) -> None:
        with self._mutex:
            if not self._consented():
                return
            self._pending.record_request(source, status_code, int(time.time() * 1000))
            self._flush_if_due()

    def record_batch(self, cached: int, no_match: int, stop: str, time_limited: bool, duration_ms: int) -> None:
        with self._mutex:
            if not self._consented():
                return
            self._pending.record_batch(cached, no_match, stop, time_limited, duration_ms)
            self._flush_locked()

    def flush(self) -> None:
        with self._mutex:
            self._flush_locked()

    def _flush_if_due(self) -> None:
        if time.monotonic() - self._last_flush >= FLUSH_INTERVAL_SECONDS:
            self._flush_locked()

    def _flush_locked(self) -> None:
        self._last_flush = time.monotonic()
        pending = self._pending.take()
        if not pending:
            return
        with _file_lock():
            _save_unlocked(merge_counters(_load_unlocked(), pending))


_recorder = _Recorder()


def _safely(action, *args) -> None:
    # Runs on proxy and caching request paths: counting must never make a request fail.
    try:
        action(*args)
    except Exception as exc:
        LOGGER.warning("Usage counter update failed: %s", exc)


def record_request(source: str, status_code: Optional[int]) -> None:
    _safely(_recorder.record_request, source, status_code)


def record_batch(cached: int, no_match: int, stop: str, time_limited: bool, duration_ms: int) -> None:
    _safely(_recorder.record_batch, cached, no_match, stop, time_limited, duration_ms)


def flush() -> None:
    _safely(_recorder.flush)


def snapshot() -> dict:
    flush()
    with _file_lock():
        return _load_unlocked()


def commit_report(reported: dict[str, int], reported_at: int) -> None:
    with _file_lock():
        _save_unlocked(after_report(_load_unlocked(), reported, reported_at))


def last_reported_at() -> int:
    with _file_lock():
        value = _load_unlocked().get(KEY_LAST_REPORTED_AT, 0)
    return value if isinstance(value, int) else 0


def clear() -> None:
    with _file_lock():
        try:
            USAGE_STATS_FILE.unlink()
        except FileNotFoundError:
            pass


atexit.register(flush)
