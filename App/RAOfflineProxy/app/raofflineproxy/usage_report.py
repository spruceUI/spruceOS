from __future__ import annotations

import contextlib
import hashlib
import json
import logging
import os
import time
import urllib.request
from typing import Optional

try:
    import fcntl
except ImportError:  # pragma: no cover - non-POSIX dev machines
    fcntl = None

from . import cache_keys, cache_queue, log_uploader, usage_stats
from .config import CONFIG_DIR, ensure_config_dir, load_config
from .network import configured_ssl_context
from .storage import PENDING_AWARD_STATUS_PENDING, Storage

LOGGER = logging.getLogger("raofflineproxy")

DEFAULT_REPORT_URL = "https://ud63psmdb5.execute-api.eu-central-1.amazonaws.com/usage/ping"
REPORT_URL_ENV = "RAOFFLINEPROXY_USAGE_URL"
# Mirrors config.json's upstream_host override, so test setups can point the report elsewhere
# without having to get an environment variable into the proxy service.
CONFIG_KEY_REPORT_URL = "usage_report_url"
BUILD_ENV = "RAOFFLINEPROXY_BUILD"
REPORT_LOCK_FILE = CONFIG_DIR / "usage_report.lock"
REQUEST_TIMEOUT_SECONDS = 10
DAY_MS = 24 * 60 * 60 * 1000
CLIENT_ID_SALT = "raofflineproxy-usage:"
# Bump when an existing field changes meaning, so the backend can tell old reports from new ones.
USAGE_SCHEMA_VERSION = 1


def report_url(config_data: Optional[dict] = None) -> str:
    from_env = os.environ.get(REPORT_URL_ENV)
    if from_env is not None:
        return from_env
    data = load_config() if config_data is None else config_data
    configured = data.get(CONFIG_KEY_REPORT_URL)
    return configured if isinstance(configured, str) else DEFAULT_REPORT_URL


def client_id(username: str) -> str:
    """Same ID as the Android app, so one person on both platforms is counted once. The backend
    re-keys it with a secret that rotates every month."""
    return hashlib.sha256((CLIENT_ID_SALT + username.strip().lower()).encode("utf-8")).hexdigest()


def is_report_due(last_reported_at: int, now_ms: int) -> bool:
    """One report per UTC calendar day, matching the backend's day rows. A clock that jumped to
    another day also counts as a new day."""
    return last_reported_at <= 0 or last_reported_at // DAY_MS != now_ms // DAY_MS


def count_bucket(count: int) -> str:
    for limit, label in (
        (1, "0"),
        (10, "1-9"),
        (50, "10-49"),
        (100, "50-99"),
        (250, "100-249"),
        (500, "250-499"),
        (1000, "500-999"),
        (2500, "1000-2499"),
    ):
        if count < limit:
            return label
    return "2500+"


def age_bucket(age_ms: Optional[int]) -> str:
    if age_ms is None:
        return "none"
    hours = age_ms // 3_600_000
    if hours < 1:
        return "<1h"
    if hours < 6:
        return "1-6h"
    if hours < 24:
        return "6-24h"
    if hours < 24 * 7:
        return "1-7d"
    return "7d+"


def build_payload(
    username: str,
    metadata: dict,
    build: str,
    gauges: dict,
    counters: dict,
) -> dict:
    emulators = metadata.get("emulator") or []
    return {
        "schema_version": USAGE_SCHEMA_VERSION,
        "consent_version": usage_stats.USAGE_STATS_CONSENT_VERSION,
        "client_id": client_id(username),
        "platform": "linux",
        "os": metadata.get("os", "Linux"),
        "os_version": metadata.get("os_version", "unknown"),
        "device": metadata.get("device", "unknown"),
        "app_version": metadata.get("app_version", "unknown"),
        "build": build,
        "emulators": list(emulators) if isinstance(emulators, list) else [str(emulators)],
        "gauges": {
            "cached_games": count_bucket(gauges.get("cached_games", 0)),
            "queued_games": count_bucket(gauges.get("queued_games", 0)),
            "oldest_queued": age_bucket(gauges.get("oldest_queued_age_ms")),
            "pending_awards": count_bucket(gauges.get("pending_awards", 0)),
        },
        "counters": counters,
    }


def load_gauges(storage: Storage, now_ms: int) -> dict:
    oldest = cache_queue.oldest(storage)
    pending = [
        award
        for award in storage.get_pending_awards()
        if award.get("status", PENDING_AWARD_STATUS_PENDING) == PENDING_AWARD_STATUS_PENDING
    ]
    return {
        "cached_games": storage.count_cache_by_prefix(cache_keys.PREFIX_PATCH),
        "queued_games": cache_queue.count(storage),
        "oldest_queued_age_ms": None if oldest is None else max(0, now_ms - oldest.queued_at),
        "pending_awards": len(pending),
    }


@contextlib.contextmanager
def _report_lock():
    """Held for a whole report so the menu and the service never send the same counters twice."""
    ensure_config_dir()
    with REPORT_LOCK_FILE.open("a+") as handle:
        if fcntl is None:
            yield True
            return
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            yield False
            return
        try:
            yield True
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def _send(payload: dict, url: str) -> bool:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(
        request, timeout=REQUEST_TIMEOUT_SECONDS, context=configured_ssl_context()
    ) as response:
        return 200 <= response.status < 300


def report_if_due(storage: Storage, now_ms: Optional[int] = None) -> bool:
    """Sends at most one report per UTC day, only with consent. Counters are only cleared once the
    backend accepted them. Never raises: callers run this from the service's threads and the
    menu."""
    try:
        return _report(storage, int(time.time() * 1000) if now_ms is None else now_ms)
    except Exception as exc:
        LOGGER.warning("Usage report skipped: %s", exc)
        return False


def _report(storage: Storage, now_ms: int) -> bool:
    config_data = load_config()
    url = report_url(config_data)
    if not url or usage_stats.load_consent(config_data) is not True:
        return False
    with _report_lock() as acquired:
        if not acquired or not is_report_due(usage_stats.last_reported_at(), now_ms):
            return False
        credentials = storage.load_login_credentials()
        if credentials is None:
            return False
        counters = usage_stats.reportable(usage_stats.snapshot())
        payload = build_payload(
            credentials["user"],
            log_uploader.device_metadata(),
            os.environ.get(BUILD_ENV, "release"),
            load_gauges(storage, now_ms),
            counters,
        )
        if not _send(payload, url):
            LOGGER.warning("Usage report rejected by the backend")
            return False
        usage_stats.commit_report(counters, now_ms)
        LOGGER.info("Usage report sent")
        return True
