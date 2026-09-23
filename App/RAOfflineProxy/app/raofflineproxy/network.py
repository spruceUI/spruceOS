from __future__ import annotations

import json
import logging
import os
import ssl
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from .config import FALLBACK_USER_AGENT, upstream_host
from .utils import proxy_user_agent

LOGGER = logging.getLogger("raofflineproxy")
REDACTED_QUERY_KEYS = {"p", "t", "token", "password"}
REACHABILITY_INTERVAL_SECONDS = 30.0
PROBE_ATTEMPTS = 3
PROBE_RETRY_DELAY_SECONDS = 1.0
HTTP_TOO_MANY_REQUESTS = 429
HTTP_GET_MAX_429_RETRIES = 4
HTTP_GET_INITIAL_429_BACKOFF_SECONDS = 2.0
HTTP_GET_MAX_429_BACKOFF_SECONDS = 15.0
RA_MIN_REQUEST_INTERVAL_SECONDS = 0.3
SCAN_BATCH_SIZE = 50
SCAN_BATCH_COOLDOWN_SECONDS = 30.0


def apply_scan_batch_cooldown(scanned: int) -> bool:
    if scanned > 0 and scanned % SCAN_BATCH_SIZE == 0:
        LOGGER.info(
            "Scan batch cooldown after %d scanned, sleeping %.1fs",
            scanned,
            SCAN_BATCH_COOLDOWN_SECONDS,
        )
        time.sleep(SCAN_BATCH_COOLDOWN_SECONDS)
        return True
    return False


class RequestThrottle:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._last_request_at = 0.0

    def wait(self, action: str | None = None) -> None:
        with self._lock:
            now = time.monotonic()
            elapsed = now - self._last_request_at
            delay = max(0.0, RA_MIN_REQUEST_INTERVAL_SECONDS - elapsed)
            if delay > 0.0:
                LOGGER.debug(
                    "Throttling RetroAchievements request action=%s delay=%.3fs",
                    action or "unknown",
                    delay,
                )
                time.sleep(delay)
            self._last_request_at = time.monotonic()

    def reset(self) -> None:
        with self._lock:
            self._last_request_at = 0.0


class ReachabilityTracker:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._reachable = False
        self._checked_at = 0.0

    def current(self) -> tuple[bool, float]:
        with self._lock:
            return self._reachable, self._checked_at

    def mark(self, reachable: bool, checked_at: float | None = None) -> bool:
        timestamp = checked_at if checked_at is not None else time.monotonic()
        with self._lock:
            changed = self._reachable != reachable
            self._reachable = reachable
            self._checked_at = timestamp
            return changed

    def reset(self) -> None:
        with self._lock:
            self._reachable = False
            self._checked_at = 0.0


_reachability_tracker = ReachabilityTracker()
_request_throttle = RequestThrottle()


def redacted_url(url: str) -> str:
    parsed = urlsplit(url)
    query = urlencode(
        [
            (key, "<redacted>" if key.lower() in REDACTED_QUERY_KEYS else value)
            for key, value in parse_qsl(parsed.query, keep_blank_values=True)
        ]
    )
    return urlunsplit(
        (parsed.scheme, parsed.netloc, parsed.path, query, parsed.fragment)
    )


def read_response_bytes(response: object) -> bytes:
    return response.read()


def detect_charset(content_type: str | None, default: str = "utf-8") -> str:
    if not content_type:
        return default

    for part in content_type.split(";"):
        piece = part.strip()
        if piece.lower().startswith("charset="):
            return piece.split("=", 1)[1].strip() or default
    return default


def decode_response_body(body: bytes, content_type: str | None) -> str:
    return body.decode(detect_charset(content_type), errors="strict")


def response_content_type(response: object) -> str | None:
    headers = getattr(response, "headers", None)
    if headers is None:
        return None
    return headers.get("Content-Type")


def configured_ssl_context() -> ssl.SSLContext:
    cafile = os.environ.get("RAOFFLINEPROXY_CA_FILE") or os.environ.get("SSL_CERT_FILE")
    capath = os.environ.get("SSL_CERT_DIR")
    if cafile or capath:
        return ssl.create_default_context(cafile=cafile or None, capath=capath or None)
    return ssl.create_default_context()


def build_api_url(base: str, action: str, params: dict[str, str]) -> str:
    query = urllib.parse.urlencode({"r": action, **params})
    return f"{base.rstrip('/')}/dorequest.php?{query}"


def reachability_state() -> tuple[bool, float]:
    return _reachability_tracker.current()


def is_retroachievements_reachable() -> bool:
    reachable, _checked_at = _reachability_tracker.current()
    return reachable


def mark_retroachievements_reachable(checked_at: float | None = None) -> bool:
    return _reachability_tracker.mark(True, checked_at)


def mark_retroachievements_unreachable(checked_at: float | None = None) -> bool:
    return _reachability_tracker.mark(False, checked_at)


def reset_retroachievements_reachability_for_tests() -> None:
    _reachability_tracker.reset()


def reset_request_throttle_for_tests() -> None:
    _request_throttle.reset()


def should_probe_retroachievements(
    force: bool = False, now: float | None = None
) -> bool:
    if force:
        return True

    current_time = now if now is not None else time.monotonic()
    reachable, checked_at = _reachability_tracker.current()
    if checked_at == 0.0:
        return True
    if not reachable:
        return True
    return (current_time - checked_at) >= REACHABILITY_INTERVAL_SECONDS


def has_active_network_interface() -> bool:
    net_path = Path("/sys/class/net")
    if not net_path.exists():
        return True
    for iface_path in net_path.iterdir():
        if iface_path.name == "lo":
            continue
        if _interface_is_active(iface_path):
            return True
    return False


def _interface_is_active(iface_path: Path) -> bool:
    try:
        operstate = (iface_path / "operstate").read_text().strip()
    except OSError:
        return False

    if operstate == "up":
        return True
    # operstate is "unknown" for drivers that never set carrier, so fall back to
    # the carrier flag rather than calling the device offline.
    if operstate != "unknown":
        return False

    try:
        return (iface_path / "carrier").read_text().strip() == "1"
    except OSError:
        return False


def probe_retroachievements(
    config_data: dict,
    user_agent: str | None = None,
    force: bool = False,
    now: float | None = None,
) -> bool:
    current_time = now if now is not None else time.monotonic()
    if not should_probe_retroachievements(force=force, now=current_time):
        return is_retroachievements_reachable()

    if not has_active_network_interface():
        _log_probe_failure("no active network interface")
        mark_retroachievements_unreachable(current_time)
        return False

    upstream = upstream_host(config_data)
    parsed = urlsplit(upstream)
    url = f"{parsed.scheme}://{parsed.netloc}/"
    # Only forced probes (startup, background monitor) retry: request-path probes run
    # on every request while unreachable and must not stall the emulator.
    attempts = PROBE_ATTEMPTS if force else 1
    reason = "unknown"
    for attempt in range(attempts):
        if attempt > 0:
            time.sleep(PROBE_RETRY_DELAY_SECONDS)
        reachable, reason = _head_upstream(url, user_agent)
        if reachable:
            mark_retroachievements_reachable(current_time)
            return True

    _log_probe_failure(reason)
    mark_retroachievements_unreachable(current_time)
    return False


def _head_upstream(url: str, user_agent: str | None) -> tuple[bool, str]:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": proxy_user_agent(user_agent or FALLBACK_USER_AGENT),
            "Accept-Encoding": "identity",
        },
        method="HEAD",
    )
    try:
        with urllib.request.urlopen(
            request, timeout=5, context=configured_ssl_context()
        ) as response:
            if 200 <= response.status < 500:
                return True, ""
            return False, f"HTTP {response.status}"
    except Exception as error:
        return False, str(error)


def _log_probe_failure(reason: str) -> None:
    # Only on the way from reachable to unreachable: a device that stays offline
    # probes every 15s and would otherwise fill the log with the same line.
    reachable, checked_at = _reachability_tracker.current()
    if checked_at == 0.0 or reachable:
        LOGGER.info("RetroAchievements probe failed: %s", reason)


def http_get(url: str, user_agent: str) -> str:
    action = api_action_from_url(url)

    for attempt in range(HTTP_GET_MAX_429_RETRIES + 1):
        if action is not None:
            _request_throttle.wait(f"GET {action}")

        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": user_agent,
                "Accept-Encoding": "identity",
            },
            method="GET",
        )

        try:
            with urllib.request.urlopen(
                request, timeout=10, context=configured_ssl_context()
            ) as response:
                body = read_response_bytes(response)
                mark_retroachievements_reachable()
                return decode_response_body(body, response_content_type(response))
        except urllib.error.HTTPError as error:
            if error.code >= 500:
                mark_retroachievements_unreachable()
            else:
                mark_retroachievements_reachable()

            if (
                error.code == HTTP_TOO_MANY_REQUESTS
                and attempt < HTTP_GET_MAX_429_RETRIES
            ):
                retry_after = retry_after_seconds(error, attempt)
                LOGGER.warning(
                    "GET hit 429 for %s; retrying in %.3fs (attempt %s/%s)",
                    action or redacted_url(url),
                    retry_after,
                    attempt + 1,
                    HTTP_GET_MAX_429_RETRIES,
                )
                time.sleep(retry_after)
                continue

            api_error = describe_api_error(error)
            if api_error:
                # HTTPError.reason is a read-only view of .msg, and .msg is what
                # str(error) renders, so this is the only way to make the
                # message callers surface carry RA's actual reason.
                error.msg = api_error
            LOGGER.warning(
                "GET failed status=%s reason=%s ua=%s url=%s",
                error.code,
                error.reason,
                user_agent,
                redacted_url(url),
            )
            raise
        except urllib.error.URLError as error:
            mark_retroachievements_unreachable()
            LOGGER.warning(
                "GET connection failed reason=%s url=%s",
                error.reason,
                redacted_url(url),
            )
            raise
        except Exception:
            mark_retroachievements_unreachable()
            LOGGER.exception("GET failed url=%s", redacted_url(url))
            raise

    raise RuntimeError("http_get exceeded retry loop")


def http_get_bytes(url: str, user_agent: str) -> tuple[bytes, str] | None:
    """Fetches url and returns (body_bytes, content_type), or None on failure."""
    request = urllib.request.Request(
        url,
        headers={"User-Agent": user_agent},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=10, context=configured_ssl_context()) as response:
            return response.read(), response_content_type(response) or "application/octet-stream"
    except Exception:
        return None


def describe_api_error(error: urllib.error.HTTPError) -> str | None:
    """Extracts RetroAchievements' own error text from a failed response.

    RA answers dorequest.php failures with a JSON body carrying a machine
    readable Code and a human readable Error. Without this the caller only ever
    sees "HTTP Error 403: Forbidden", which hides the actual cause.
    """
    try:
        payload = json.loads(error.read().decode("utf-8", errors="replace"))
    except Exception:
        return None

    if not isinstance(payload, dict):
        return None

    code = payload.get("Code")
    message = payload.get("Error")
    if code and message:
        return f"{code}: {message}"
    return code or message or None


def api_action_from_url(url: str) -> str | None:
    return (
        urlsplit(url).query.split("r=", 1)[1].split("&", 1)[0]
        if "r=" in urlsplit(url).query
        else None
    )


def retry_after_seconds(error: urllib.error.HTTPError, attempt: int) -> float:
    header_value = (error.headers.get("Retry-After") or "").strip()
    header_seconds = float(header_value) if header_value.isdigit() else None
    if header_seconds is not None and header_seconds > 0:
        return min(header_seconds, HTTP_GET_MAX_429_BACKOFF_SECONDS)

    return min(
        HTTP_GET_INITIAL_429_BACKOFF_SECONDS * (2**attempt),
        HTTP_GET_MAX_429_BACKOFF_SECONDS,
    )


def http_post(
    url: str, body: str, headers: dict[str, str] | None = None
) -> tuple[int, str, str]:
    request_headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept-Encoding": "identity",
    }
    if headers:
        request_headers.update(headers)

    request = urllib.request.Request(
        url,
        data=body.encode("utf-8"),
        headers=request_headers,
        method="POST",
    )

    try:
        with urllib.request.urlopen(
            request, timeout=15, context=configured_ssl_context()
        ) as response:
            response_body = read_response_bytes(response)
            mark_retroachievements_reachable()
            return (
                response.status,
                response.reason,
                decode_response_body(response_body, response_content_type(response)),
            )
    except urllib.error.HTTPError as error:
        response_body = error.read()
        if error.code >= 500:
            mark_retroachievements_unreachable()
        else:
            mark_retroachievements_reachable()
        LOGGER.warning(
            "POST failed status=%s reason=%s url=%s",
            error.code,
            error.reason,
            redacted_url(url),
        )
        return (
            error.code,
            error.reason,
            decode_response_body(response_body, error.headers.get("Content-Type")),
        )
    except urllib.error.URLError as error:
        mark_retroachievements_unreachable()
        LOGGER.warning(
            "POST connection failed reason=%s url=%s",
            error.reason,
            redacted_url(url),
        )
        raise
    except Exception:
        mark_retroachievements_unreachable()
        LOGGER.exception("POST failed url=%s", redacted_url(url))
        raise


def online_check(config_data: dict) -> bool:
    return probe_retroachievements(config_data, user_agent=FALLBACK_USER_AGENT)


def build_forward_headers(headers: dict[str, str]) -> dict[str, str]:
    skip_headers = {
        "host",
        "content-length",
        "connection",
        "transfer-encoding",
        "accept-encoding",
    }
    forwarded: dict[str, str] = {}

    for key, value in headers.items():
        lower = key.lower()
        if lower in skip_headers:
            continue
        if lower == "user-agent":
            forwarded[key] = proxy_user_agent(value)
        else:
            forwarded[key] = value

    if "User-Agent" not in forwarded and "user-agent" not in forwarded:
        forwarded["User-Agent"] = proxy_user_agent(FALLBACK_USER_AGENT)

    return forwarded
