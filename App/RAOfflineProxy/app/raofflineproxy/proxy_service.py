from __future__ import annotations

import json
import logging
import os
from collections.abc import Sequence
from pathlib import Path
import socket
import socketserver
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler
from urllib.parse import urlsplit

from . import cache_keys, log_uploader, storage_corruption
from .auth import resolve_credentials
from .boot import adopt_listen_socket
from .award_signing import sign_award
from .config import (
    DATABASE_FILE,
    FALLBACK_USER_AGENT,
    RA_MEDIA_HOST,
    image_caching_enabled,
    proxy_host,
    proxy_port,
    upstream_host,
)
from .flusher import flush_pending_awards
from .lowerdeck import ensure_ra_proxy_chained, stop_ra_proxy_chain
from .image_cache import (
    IMAGE_PATH_PREFIXES,
    resolve_cached_static_asset,
    rewrite_image_urls,
    schedule_image_download,
)
from .network import (
    build_forward_headers,
    decode_response_body,
    http_get_bytes,
    http_post,
    is_retroachievements_reachable,
    mark_retroachievements_unreachable,
    probe_retroachievements,
    read_response_bytes,
    response_content_type,
)
from .rom_cache import (
    build_achievement_game_ids,
    build_unlocks_array,
    cache_session,
    cache_unlocks,
    filter_warning_achievement_ids,
    filter_warning_achievements_for_action,
    merged_unlock_ids,
    refresh_game_patch,
)
from .state import save_online_state
from .storage import Storage, current_millis, migrate_user_case_in_cache_keys
from .utils import (
    canonical_reason_phrase,
    extract_action,
    extract_request_param,
    is_hardcore_request,
    parse_form_params,
    proxy_user_agent,
    redact_form_tokens,
    redact_query_tokens,
    self_user_agent,
    sha256_hex,
)

LOGGER = logging.getLogger("raofflineproxy")
MAX_REQUEST_BODY_BYTES = 1_048_576
SOCKET_TIMEOUT_SECONDS = 30

AWARD_ACTIONS = {"awardachievement", "submitlbentry"}
FAKE_OFFLINE_SUCCESS_ACTIONS = {"ping", "postactivity"}
ALWAYS_TRY_UPSTREAM_ACTIONS = {"login", "login2"}


def is_static_asset_request(path: str) -> bool:
    clean_path = path.split("?", 1)[0]
    return any(clean_path.startswith(prefix) for prefix in IMAGE_PATH_PREFIXES)


def guess_content_type(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".png":
        return "image/png"
    if suffix in {".jpg", ".jpeg"}:
        return "image/jpeg"
    if suffix == ".gif":
        return "image/gif"
    if suffix == ".webp":
        return "image/webp"
    return "application/octet-stream"


def cache_key_for_request(path: str, body: str) -> str:
    action = extract_action(path, body) or "unknown"
    game_id = (
        extract_request_param(path, body, "g")
        or extract_request_param(path, body, "i")
        or ""
    )
    hash_value = extract_request_param(path, body, "m") or ""
    user = cache_keys.normalize_user(extract_request_param(path, body, "u") or "")
    hardcore = extract_request_param(path, body, "h") or ""

    if action == "gameid":
        return cache_keys.game_id(hash_value)
    if action in {"login", "login2"}:
        return cache_keys.login(user)
    if action == "achievementsets":
        return cache_keys.achievementsets(hash_value or game_id or "unknown", user)
    if action == "startsession":
        return cache_keys.start_session(game_id, user)
    if action == "patch":
        return cache_keys.patch(game_id, user)
    if action == "unlocks":
        return cache_keys.unlocks(game_id, user)
    if hardcore:
        return f"{action}:{game_id}:{user}:{hardcore}"
    return f"{action}:{game_id}:{user}"


def should_cache_response(response_body: str) -> bool:
    return '"Success":true' in response_body or '"Success": true' in response_body


def should_cache_action(action: str | None, path: str) -> bool:
    return (
        action is not None
        and path.startswith("/dorequest.php")
        and action != "startsession"
    )


def response_bytes(code: int, body: str, reason: str | None = None) -> bytes:
    text = body.encode("utf-8")
    reason_phrase = reason or canonical_reason_phrase(code)
    head = (
        f"HTTP/1.1 {code} {reason_phrase}\r\n"
        f"Content-Type: application/json\r\n"
        f"Content-Length: {len(text)}\r\n"
        f"Connection: close\r\n\r\n"
    ).encode("utf-8")
    return head + text


def raw_response_bytes(
    code: int,
    body: bytes,
    content_type: str | None,
    reason: str | None = None,
) -> bytes:
    reason_phrase = reason or canonical_reason_phrase(code)
    mime_type = content_type or "application/octet-stream"
    head = (
        f"HTTP/1.1 {code} {reason_phrase}\r\n"
        f"Content-Type: {mime_type}\r\n"
        f"Content-Length: {len(body)}\r\n"
        f"Connection: close\r\n\r\n"
    ).encode("utf-8")
    return head + body


def ok_json(body: str) -> bytes:
    return response_bytes(200, body, "OK")


def error_json(code: int, message: str) -> bytes:
    return response_bytes(
        code,
        json.dumps({"Success": False, "Error": message}, separators=(",", ":")),
        message,
    )


def game_id_cache_miss() -> bytes:
    return ok_json(
        json.dumps(
            {
                "Success": False,
                "Error": "Game not cached. Launch this game while online first.",
                "GameID": 0,
            },
            separators=(",", ":"),
        )
    )


def _start_image_downloads(
    downloads: list[tuple[str, str]],
    user_agent: str | None,
    game_id: int | None,
) -> None:
    ua = user_agent or FALLBACK_USER_AGENT
    for orig_url, img_path in downloads:
        schedule_image_download(orig_url, img_path, ua, game_id)


class ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


class ProxyRequestHandler(BaseHTTPRequestHandler):
    server: "ProxyRuntimeServer"

    def setup(self) -> None:
        super().setup()
        self.request.settimeout(SOCKET_TIMEOUT_SECONDS)

    def do_GET(self) -> None:
        self._handle_request()

    def do_POST(self) -> None:
        self._handle_request()

    def log_message(self, format: str, *args) -> None:
        LOGGER.debug(format, *args)

    def _handle_request(self) -> None:
        if self.client_address[0] not in {"127.0.0.1", "::1"}:
            self.wfile.write(error_json(403, "loopback_only"))
            return

        if self.command not in {"GET", "POST"}:
            self.wfile.write(error_json(405, "method not allowed"))
            return

        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length > MAX_REQUEST_BODY_BYTES:
            self.wfile.write(error_json(413, "request body too large"))
            return

        body = self.rfile.read(content_length).decode("utf-8") if content_length else ""
        headers = {key: value for key, value in self.headers.items()}

        LOGGER.info(
            "Request: %s %s body=%s online=%s",
            self.command,
            redact_query_tokens(self.path),
            redact_form_tokens(body),
            self.server.is_online(),
        )

        response = self.server.process_proxy_request(
            self.command, self.path, body, headers
        )
        self.wfile.write(response)
        self.wfile.flush()
        # Close gracefully (FIN, not RST): shut down the write side and let
        # the client finish reading before the socket is torn down, rather
        # than an abrupt close that can reset the connection out from under
        # a client still draining its receive buffer.
        try:
            self.connection.shutdown(socket.SHUT_WR)
        except OSError:
            pass


class ProxyRuntimeServer(ThreadingTCPServer):
    def __init__(self, config_data: dict, storage: Storage):
        self.config_data = dict(config_data)
        self.storage = storage
        self.running = True
        self.has_internet = False
        self.flush_lock = threading.Lock()
        self.pending_award_lock = threading.Lock()
        host = proxy_host(self.config_data)
        port = proxy_port(self.config_data)
        inherited = adopt_listen_socket()
        super().__init__(
            (host, port),
            ProxyRequestHandler,
            bind_and_activate=inherited is None,
        )
        if inherited is not None:
            self.socket.close()
            self.socket = inherited
            self.server_address = self.socket.getsockname()

    def _proxy_base_url(self) -> str:
        cfg = getattr(self, "config_data", {})
        return f"http://{proxy_host(cfg)}:{proxy_port(cfg)}"

    def is_online(self) -> bool:
        self.refresh_reachability(force_probe=False)
        return self.has_internet and is_retroachievements_reachable()

    def refresh_reachability(self, force_probe: bool) -> bool:
        self.has_internet = probe_retroachievements(
            self.config_data,
            user_agent=self_user_agent(),
            force=force_probe,
        )
        if not self.has_internet:
            mark_retroachievements_unreachable()
            return False
        return is_retroachievements_reachable()

    def _forward_static_asset(self, path: str, headers: dict[str, str]) -> bytes:
        clean_path = path.split("?", 1)[0]
        url = f"{RA_MEDIA_HOST}{clean_path}"
        user_agent = headers.get("User-Agent") or headers.get("user-agent") or FALLBACK_USER_AGENT
        result = http_get_bytes(url, user_agent)
        if result is None:
            return raw_response_bytes(204, b"", "application/octet-stream", "No Content")
        body_bytes, content_type = result
        if body_bytes:
            schedule_image_download(url, clean_path, user_agent)
        return raw_response_bytes(200, body_bytes, content_type, "OK")

    def process_proxy_request(
        self, method: str, path: str, raw_body: str, headers: dict[str, str]
    ) -> bytes:
        if is_static_asset_request(path):
            if image_caching_enabled(getattr(self, "config_data", {})):
                cached_asset = resolve_cached_static_asset(path)
                if cached_asset is not None:
                    return raw_response_bytes(200, cached_asset.read_bytes(), guess_content_type(cached_asset), "OK")
                if self.is_online():
                    return self._forward_static_asset(path, headers)
            return raw_response_bytes(204, b"", "application/octet-stream", "No Content")

        user_agent = headers.get("User-Agent") or headers.get("user-agent")
        if user_agent:
            self.storage.upsert_cache(cache_keys.USER_AGENT, user_agent)

        action = extract_action(path, raw_body)
        if action in AWARD_ACTIONS:
            return self.handle_award_request(path, raw_body, headers)

        if action == "unlocks" and not self.is_online():
            game_id = extract_request_param(path, raw_body, "g")
            user = extract_request_param(path, raw_body, "u")
            if game_id and user:
                return ok_json(self.build_offline_unlocks_response(int(game_id), user))

        if action == "startsession" and not self.is_online():
            return self.handle_start_session(path, raw_body)

        if is_hardcore_request(path, raw_body):
            if not self.is_online():
                return error_json(503, "upstream unavailable")
            return self.forward_to_upstream(method, path, raw_body, headers)

        if action in FAKE_OFFLINE_SUCCESS_ACTIONS and not self.is_online():
            return ok_json('{"Success":true}')

        if action in ALWAYS_TRY_UPSTREAM_ACTIONS:
            upstream = self.forward_to_upstream_result(method, path, raw_body, headers)
            if upstream[0] in {"success", "http_error"}:
                status_code = upstream[1]
                reason = upstream[2]
                response_body_bytes = upstream[3]
                content_type = upstream[4]
                response_body = upstream[5]
                if response_body is not None and should_cache_response(response_body):
                    proxy_base_url = self._proxy_base_url()
                    rewritten_body, downloads = rewrite_image_urls(action, response_body, proxy_base_url)
                    if image_caching_enabled(self.config_data):
                        _start_image_downloads(downloads, user_agent, None)
                    key = cache_key_for_request(path, raw_body)
                    # Store the original body — the DB stays port-agnostic.
                    self.storage.upsert_cache(key, response_body)
                    response_body_bytes = rewritten_body.encode("utf-8")
                return raw_response_bytes(
                    status_code, response_body_bytes, content_type, reason
                )
            cached_login_response = self.handle_offline_login(path, raw_body, action)
            if cached_login_response is not None:
                return cached_login_response

        if self.is_online():
            return self.handle_online_request(method, path, raw_body, action, headers)

        return self.handle_offline_request(path, raw_body, action)

    def handle_offline_login(
        self, path: str, raw_body: str, action: str | None
    ) -> bytes | None:
        if action not in ALWAYS_TRY_UPSTREAM_ACTIONS:
            return None

        user = extract_request_param(path, raw_body, "u")
        if not user:
            return None

        cached = self.storage.get_cache(cache_keys.login(user))
        if cached is None:
            return None

        return ok_json(cached["responseBody"])

    def handle_award_request(
        self, path: str, raw_body: str, headers: dict[str, str]
    ) -> bytes:
        if is_hardcore_request(path, raw_body):
            return error_json(403, "hardcore_not_supported")

        if self.is_online():
            upstream = self.forward_to_upstream_result("POST", path, raw_body, headers)
            if upstream[0] == "success":
                self.schedule_post_award_refresh(path, raw_body, headers)
                return raw_response_bytes(
                    upstream[1], upstream[3], upstream[4], upstream[2]
                )
            if upstream[0] == "http_error":
                return raw_response_bytes(
                    upstream[1], upstream[3], upstream[4], upstream[2]
                )

        return self.queue_offline_award(path, raw_body, headers)

    def schedule_post_award_refresh(
        self, path: str, raw_body: str, headers: dict[str, str]
    ) -> None:
        refresh_thread = threading.Thread(
            target=self.refresh_caches_after_online_award,
            args=(path, raw_body, headers),
            daemon=True,
        )
        refresh_thread.start()

    def refresh_caches_after_online_award(
        self, path: str, raw_body: str, headers: dict[str, str]
    ) -> None:
        game_id = self.resolve_game_id_for_award(path, raw_body)
        user = extract_request_param(path, raw_body, "u")
        token = extract_request_param(path, raw_body, "t")
        if not game_id or not user or not token:
            return

        time.sleep(3)
        user_agent = headers.get("User-Agent") or FALLBACK_USER_AGENT
        credentials = {"user": user, "token": token}
        cache_unlocks(
            int(game_id),
            credentials,
            user_agent,
            self.config_data,
            self.storage,
        )
        cache_session(int(game_id), credentials, self.storage)

    def resolve_game_id_for_award(self, path: str, raw_body: str) -> str | None:
        game_id = extract_request_param(path, raw_body, "g")
        if game_id:
            return game_id

        achievement_id = int(extract_request_param(path, raw_body, "a") or "0")
        if achievement_id <= 0:
            return None

        achievement_game_ids = build_achievement_game_ids(
            self.storage.get_all_cache_by_prefix(cache_keys.PREFIX_PATCH),
            self.storage.get_all_cache_by_prefix(cache_keys.PREFIX_ACHIEVEMENTSETS),
        )
        resolved_game_id = achievement_game_ids.get(achievement_id)
        if resolved_game_id is None:
            return None
        return str(resolved_game_id)

    def handle_start_session(self, path: str, raw_body: str) -> bytes:
        game_id = extract_request_param(path, raw_body, "g")
        user = extract_request_param(path, raw_body, "u")
        if not game_id or not user:
            return error_json(400, "bad request")

        return ok_json(self.build_offline_start_session_response(int(game_id), user))

    def queue_offline_award(
        self, path: str, raw_body: str, headers: dict[str, str]
    ) -> bytes:
        queued = self.queue_award(path, raw_body, headers)
        if not queued:
            return error_json(500, "award_queue_failed")

        achievement_id = int(extract_request_param(path, raw_body, "a") or "0")
        score = self.fetch_cached_score(path, raw_body)
        return ok_json(
            json.dumps(
                {
                    "Success": True,
                    "Score": score,
                    "SoftcoreScore": 0,
                    "AchievementID": achievement_id,
                    "Error": "queued_offline",
                },
                separators=(",", ":"),
            )
        )

    def handle_online_request(
        self,
        method: str,
        path: str,
        raw_body: str,
        action: str | None,
        headers: dict[str, str],
    ) -> bytes:
        user_agent = headers.get("User-Agent") or headers.get("user-agent") or FALLBACK_USER_AGENT
        upstream = self.forward_to_upstream_result(method, path, raw_body, headers)
        if upstream[0] == "network_error":
            return self.handle_offline_request(path, raw_body, action)

        if upstream[0] != "success":
            return error_json(503, "upstream unavailable")

        status_code = upstream[1]
        reason = upstream[2]
        response_body_bytes = upstream[3]
        content_type = upstream[4]
        response_body = upstream[5]
        if action is None or not path.startswith("/dorequest.php"):
            return raw_response_bytes(
                status_code, response_body_bytes, content_type, reason
            )

        if response_body is None:
            return error_json(503, "invalid upstream response")

        response_body = filter_warning_achievements_for_action(action, response_body)

        if action == "startsession" and should_cache_response(response_body):
            game_id = extract_request_param(path, raw_body, "g")
            user = extract_request_param(path, raw_body, "u")
            if game_id and user:
                self.storage.upsert_cache(
                    cache_keys.start_session(game_id, user), response_body
                )
                self.refresh_unlocks_from_start_session(
                    int(game_id), user, response_body
                )

        if should_cache_response(response_body) and should_cache_action(action, path):
            proxy_base_url = self._proxy_base_url()
            game_id_str = extract_request_param(path, raw_body, "g")
            game_id_int = int(game_id_str) if game_id_str and game_id_str.isdigit() else None
            rewritten_body, downloads = rewrite_image_urls(action, response_body, proxy_base_url)
            if image_caching_enabled(self.config_data):
                _start_image_downloads(downloads, user_agent, game_id_int)
            key = cache_key_for_request(path, raw_body)

            self.storage.upsert_cache(key, response_body)
            if action == "patch":
                user = extract_request_param(path, raw_body, "u")
                token = extract_request_param(path, raw_body, "t")
                if game_id_str and user and token:
                    cache_unlocks(
                        int(game_id_str),
                        {"user": user, "token": token},
                        user_agent,
                        self.config_data,
                        self.storage,
                    )
            response_body = rewritten_body
        return response_bytes(status_code, response_body, reason)

    def refresh_unlocks_from_start_session(
        self, game_id: int, user: str, response_body: str
    ) -> None:
        try:
            payload = json.loads(response_body)
        except Exception:
            return

        unlock_entries = payload.get("Unlocks")
        if not isinstance(unlock_entries, Sequence) or isinstance(
            unlock_entries, (str, bytes, bytearray)
        ):
            return

        unlock_ids: list[int] = []
        for item in unlock_entries:
            if not isinstance(item, dict):
                continue
            achievement_id = item.get("ID")
            if isinstance(achievement_id, int) and achievement_id > 0:
                unlock_ids.append(achievement_id)

        unlock_ids = filter_warning_achievement_ids(unlock_ids)

        self.storage.upsert_cache(
            cache_keys.unlocks(game_id, user),
            json.dumps(
                {"Success": True, "UserUnlocks": unlock_ids},
                separators=(",", ":"),
            ),
        )

    def handle_offline_request(
        self, path: str, raw_body: str, action: str | None
    ) -> bytes:
        if not should_cache_action(action, path):
            return error_json(503, "offline")

        if action == "unlocks":
            game_id = extract_request_param(path, raw_body, "g")
            user = extract_request_param(path, raw_body, "u")
            if game_id and user:
                return ok_json(self.build_offline_unlocks_response(int(game_id), user))

        key = cache_key_for_request(path, raw_body)
        cached = self.storage.get_cache(key) or self.storage.get_cache_by_prefix(
            f"{key}:"
        )
        if cached is not None:
            proxy_base_url = self._proxy_base_url()
            rewritten_body, _ = rewrite_image_urls(action, cached["responseBody"], proxy_base_url)
            return ok_json(filter_warning_achievements_for_action(action, rewritten_body))

        if action == "gameid":
            LOGGER.warning(
                "Offline gameid cache miss requestedKey=%s sampleKeys=%s",
                key,
                [
                    entry["cacheKey"]
                    for entry in self.storage.get_all_cache_by_prefix(
                        cache_keys.PREFIX_GAMEID
                    )[:10]
                ],
            )
            return game_id_cache_miss()

        if action == "achievementsets":
            hash_value = extract_request_param(path, raw_body, "m")
            fallback_game_id = extract_request_param(
                path, raw_body, "g"
            ) or extract_request_param(path, raw_body, "i")
            user = extract_request_param(path, raw_body, "u") or ""
            proxy_base_url = self._proxy_base_url()
            if hash_value and user:
                cached = self.storage.get_cache(
                    cache_keys.achievementsets(hash_value, user)
                )
                if cached is not None:
                    rewritten_body, _ = rewrite_image_urls(action, cached["responseBody"], proxy_base_url)
                    return ok_json(filter_warning_achievements_for_action(action, rewritten_body))
            if fallback_game_id and user:
                cached = self.storage.get_cache(
                    cache_keys.achievementsets(fallback_game_id, user)
                )
                if cached is not None:
                    rewritten_body, _ = rewrite_image_urls(action, cached["responseBody"], proxy_base_url)
                    return ok_json(filter_warning_achievements_for_action(action, rewritten_body))

        return error_json(503, "no cached response")

    def build_offline_unlocks_response(self, game_id: int, user: str) -> str:
        entry = self.storage.get_cache(cache_keys.unlocks(game_id, user))
        payload: dict = {"Success": True, "UserUnlocks": []}
        if entry is not None:
            try:
                payload = json.loads(entry["responseBody"])
            except Exception:
                payload = {"Success": True, "UserUnlocks": []}

        payload["Success"] = True
        payload["UserUnlocks"] = merged_unlock_ids(self.storage, game_id, user)
        return json.dumps(payload, separators=(",", ":"))

    def build_offline_start_session_response(self, game_id: int, user: str) -> str:
        entry = self.storage.get_cache(cache_keys.start_session(game_id, user))
        server_now = int(time.time())
        payload: dict = {
            "Success": True,
            "ServerNow": server_now,
            "HardcoreUnlocks": [],
        }
        if entry is not None:
            try:
                payload = json.loads(entry["responseBody"])
            except Exception:
                payload = {
                    "Success": True,
                    "ServerNow": server_now,
                    "HardcoreUnlocks": [],
                }

        server_now = int(payload.get("ServerNow", server_now) or server_now)
        cached_start_session_unlock_ids = filter_warning_achievement_ids([
            int(item.get("ID", 0))
            for item in payload.get("Unlocks", [])
            if isinstance(item, dict) and int(item.get("ID", 0) or 0) > 0
        ])
        payload["Success"] = True
        payload.setdefault("HardcoreUnlocks", [])
        payload["Unlocks"] = self.build_merged_start_session_unlocks(
            game_id, user, server_now, cached_start_session_unlock_ids
        )
        return json.dumps(payload, separators=(",", ":"))

    def build_merged_start_session_unlocks(
        self,
        game_id: int,
        user: str,
        server_now: int,
        cached_start_session_unlock_ids: list[int],
    ) -> list[dict]:
        merged_ids = merged_unlock_ids(self.storage, game_id, user)
        if not merged_ids:
            merged_ids = list(cached_start_session_unlock_ids)
        else:
            seen_ids = set(merged_ids)
            for achievement_id in cached_start_session_unlock_ids:
                if achievement_id <= 0 or achievement_id in seen_ids:
                    continue
                merged_ids.append(achievement_id)
                seen_ids.add(achievement_id)

        return [
            {"ID": achievement_id, "When": server_now} for achievement_id in merged_ids
        ]

    def forward_to_upstream(
        self, method: str, path: str, raw_body: str, headers: dict[str, str]
    ) -> bytes:
        upstream = self.forward_to_upstream_result(method, path, raw_body, headers)
        if upstream[0] == "success":
            return raw_response_bytes(
                upstream[1], upstream[3], upstream[4], upstream[2]
            )
        if upstream[0] == "http_error":
            return raw_response_bytes(
                upstream[1], upstream[3], upstream[4], upstream[2]
            )
        return error_json(503, "upstream unavailable")

    def forward_to_upstream_result(
        self, method: str, path: str, raw_body: str, headers: dict[str, str]
    ) -> tuple[str, int, str, bytes, str | None, str | None]:
        url = f"{upstream_host(self.config_data)}{path}"
        request_headers = build_forward_headers(headers)
        try:
            if method == "POST":
                status, reason, response_body = http_post(
                    url, raw_body, request_headers
                )
                response_bytes_body = response_body.encode("utf-8")
                content_type = "application/json"
            else:
                import urllib.request

                request = urllib.request.Request(
                    url, headers=request_headers, method="GET"
                )
                try:
                    with urllib.request.urlopen(request, timeout=15) as response:
                        status = response.status
                        reason = response.reason
                        response_bytes_body = read_response_bytes(response)
                        content_type = response_content_type(response)
                        if path.startswith("/dorequest.php"):
                            response_body = decode_response_body(
                                response_bytes_body, content_type
                            )
                        else:
                            response_body = ""
                except Exception as error:
                    if hasattr(error, "read"):
                        status = getattr(error, "code", 500)
                        reason = getattr(
                            error, "reason", canonical_reason_phrase(status)
                        )
                        response_bytes_body = error.read()
                        content_type = getattr(error, "headers", {}).get("Content-Type")
                        if path.startswith("/dorequest.php"):
                            response_body = decode_response_body(
                                response_bytes_body, content_type
                            )
                        else:
                            response_body = ""
                    else:
                        raise

            if 200 <= status < 300:
                return (
                    "success",
                    status,
                    reason,
                    response_bytes_body,
                    content_type,
                    response_body,
                )
            return (
                "http_error",
                status,
                reason,
                response_bytes_body,
                content_type,
                response_body,
            )
        except Exception as error:
            mark_retroachievements_unreachable()
            LOGGER.error("Upstream request failed: %s", error)
            return (
                "network_error",
                503,
                "Service Unavailable",
                json.dumps({"Success": False, "Error": str(error)}).encode("utf-8"),
                "application/json",
                json.dumps({"Success": False, "Error": str(error)}),
            )

    def queue_award(self, path: str, raw_body: str, headers: dict[str, str]) -> bool:
        achievement_id = int(extract_request_param(path, raw_body, "a") or "0")
        pending_award_lock = getattr(self, "pending_award_lock", None)
        if pending_award_lock is None:
            pending_award_lock = threading.Lock()
            self.pending_award_lock = pending_award_lock

        with pending_award_lock:
            if achievement_id > 0 and self.storage.pending_award_exists(achievement_id):
                LOGGER.info(
                    "Offline award already queued: achievementId=%s",
                    achievement_id,
                )
                return True

            if achievement_id > 0 and self.is_already_unlocked_award(path, raw_body):
                LOGGER.info(
                    "Offline award already unlocked: achievementId=%s",
                    achievement_id,
                )
                return True

            prev_hash = (self.storage.get_latest_pending_award() or {}).get(
                "payloadHash"
            ) or "genesis"
            queued_at = current_millis()
            payload_hash = sha256_hex(f"{achievement_id}|{path}|{raw_body}|{queued_at}")
            sign_input = f"{payload_hash}:{prev_hash}".encode("utf-8")
            signature = sign_award(sign_input)

            award = {
                "achievementId": achievement_id,
                "queryString": path,
                "requestBody": raw_body,
                "userAgent": headers.get("User-Agent")
                or headers.get("user-agent")
                or FALLBACK_USER_AGENT,
                "queuedAt": queued_at,
                "retryCount": 0,
                "lastError": None,
                "status": "pending",
                "payloadHash": payload_hash,
                "prevHash": prev_hash,
                "signature": signature,
                "signedAt": current_millis(),
            }
            self.storage.upsert_pending_award(award)
            LOGGER.info(
                "Queued offline award: achievementId=%s queuedAt=%s",
                achievement_id,
                queued_at,
            )
            return True

    def is_already_unlocked_award(self, path: str, raw_body: str) -> bool:
        achievement_id = int(extract_request_param(path, raw_body, "a") or "0")
        user = extract_request_param(path, raw_body, "u")
        if achievement_id <= 0 or not user:
            return False

        achievement_game_ids = self.build_cached_achievement_game_ids()
        game_id = achievement_game_ids.get(achievement_id)
        if game_id is None:
            return False

        cached_unlocks = self.storage.get_cache(cache_keys.unlocks(game_id, user))
        if cached_unlocks is None:
            return False

        try:
            payload = json.loads(cached_unlocks["responseBody"])
        except Exception:
            return False

        unlock_ids = payload.get("UserUnlocks")
        if not isinstance(unlock_ids, list):
            return False

        return achievement_id in filter_warning_achievement_ids(
            [item for item in unlock_ids if isinstance(item, int)]
        )

    def build_cached_achievement_game_ids(self) -> dict[int, int]:
        return build_achievement_game_ids(
            self.storage.get_all_cache_by_prefix(cache_keys.PREFIX_PATCH),
            self.storage.get_all_cache_by_prefix(cache_keys.PREFIX_ACHIEVEMENTSETS),
        )

    def fetch_cached_score(self, path: str, raw_body: str) -> int:
        user = extract_request_param(path, raw_body, "u")
        if not user:
            return 0
        cached = self.storage.get_cache(cache_keys.login(user))
        if cached is None:
            return 0
        try:
            payload = json.loads(cached["responseBody"])
            return int(payload.get("Score", 0))
        except Exception:
            return 0

    def flush_pending_awards(self) -> dict:
        with self.flush_lock:
            outcome = flush_pending_awards(self.storage, self.config_data)
            if outcome.total:
                LOGGER.info(
                    "Flush outcome: total=%s flushed=%s skipped_deleted=%s skipped_stale=%s pending_remaining=%s last_error=%s",
                    outcome.total,
                    outcome.flushed,
                    outcome.skipped_deleted,
                    outcome.skipped_stale,
                    outcome.pending_remaining,
                    outcome.last_error,
                )
            return {
                "flushed": outcome.flushed,
                "total": outcome.total,
                "skipped_deleted": outcome.skipped_deleted,
                "skipped_stale": outcome.skipped_stale,
                "pending_remaining": outcome.pending_remaining,
                "last_error": outcome.last_error,
            }


def _capture_file_inodes(paths: list[Path]) -> dict[Path, int]:
    inodes: dict[Path, int] = {}
    for path in paths:
        try:
            inodes[path] = path.stat().st_ino
        except OSError:
            continue
    return inodes


def _files_replaced_underneath(inodes: dict[Path, int]) -> bool:
    for path, inode in inodes.items():
        try:
            if path.stat().st_ino != inode:
                return True
        except OSError:
            return True
    return False


class ConnectivityMonitor(threading.Thread):
    def __init__(self, server: ProxyRuntimeServer, interval_seconds: int = 15):
        super().__init__(daemon=True)
        self.server = server
        self.interval_seconds = interval_seconds
        self.stop_event = threading.Event()
        self.watched_inodes = _capture_file_inodes([DATABASE_FILE])

    def stop(self) -> None:
        self.stop_event.set()

    def run(self) -> None:
        was_online = self.server.refresh_reachability(force_probe=True)
        save_online_state(was_online)
        while not self.stop_event.wait(self.interval_seconds):
            if self.watched_inodes and _files_replaced_underneath(self.watched_inodes):
                # A reinstall deleted our log/database out from under this
                # process while it kept them open; exit so the next
                # "start proxy" spawns a fresh process against current files
                # instead of silently running as an invisible orphan.
                LOGGER.error("Data files were deleted or replaced underneath this process; exiting")
                os._exit(1)
            is_online = self.server.refresh_reachability(force_probe=True)
            if is_online and not was_online:
                LOGGER.info("Connectivity restored; attempting flush")
                self.server.flush_pending_awards()
            if is_online != was_online:
                save_online_state(is_online)
            was_online = is_online


class PeriodicRefresh(threading.Thread):
    def __init__(
        self,
        server: ProxyRuntimeServer,
        interval_seconds: int = 3600,  # 1 hour
        cache_ttl_seconds: int = 60 * 24 * 3600,  # 60 days (matches Android)
    ):
        super().__init__(daemon=True)
        self.server = server
        self.interval_seconds = interval_seconds
        self.cache_ttl_seconds = cache_ttl_seconds
        self.stop_event = threading.Event()

    def stop(self) -> None:
        self.stop_event.set()

    def run(self) -> None:
        while not self.stop_event.wait(self.interval_seconds):
            if not self.server.is_online():
                continue
            user_agent = self_user_agent()
            credentials = resolve_credentials(
                self.server.storage,
                self.server.config_data,
                user_agent,
            )
            if credentials is None:
                continue
            patch_entries = self.server.storage.get_all_cache_by_prefix(
                cache_keys.PREFIX_PATCH
            )
            game_ids: list[int] = []
            for entry in patch_entries:
                game_id = cache_keys.parse_game_id_from_patch_key(entry["cacheKey"])
                if game_id is not None and game_id not in game_ids:
                    refresh_game_patch(
                        game_id,
                        credentials,
                        user_agent,
                        self.server.storage,
                        self.server.config_data,
                        cache_images=image_caching_enabled(self.server.config_data),
                    )
                    cache_unlocks(
                        game_id,
                        credentials,
                        user_agent,
                        self.server.config_data,
                        self.server.storage,
                    )
                    cache_session(game_id, credentials, self.server.storage)
                    game_ids.append(game_id)
            before = current_millis() - (self.cache_ttl_seconds * 1000)
            self.server.storage.evict_cache_older_than(before)


def retry_storage_corruption_report() -> None:
    # The menu only ever attempts this once (on first open after the incident) and shows
    # the user the outcome regardless of success, so it doesn't nag them again — if that
    # one attempt happened while offline, the report would otherwise never reach us. The
    # service retries silently on every startup until it actually gets through.
    incident = storage_corruption.load_incident()
    if incident is None or incident.get("reported"):
        return
    try:
        upload_id = log_uploader.report_storage_corruption(incident)
    except Exception as exc:
        LOGGER.warning("Storage corruption report retry failed: %s", exc)
        return
    storage_corruption.mark_reported(upload_id)


def run_proxy_service(
    config_data: dict, stop_event: threading.Event | None = None
) -> None:
    storage = Storage()
    # Bind the listening port before any other startup work: on boot-to-game
    # devices the emulator can reach its RetroAchievements login before the
    # service is fully up, and a refused connection disables achievements for
    # the whole session. Once the socket listens, those connections queue.
    server = ProxyRuntimeServer(config_data, storage)
    LOGGER.info(
        "Proxy listening host=%s port=%s",
        proxy_host(config_data),
        proxy_port(config_data),
    )
    ensure_ra_proxy_chained(config_data)
    connectivity_monitor = ConnectivityMonitor(server)
    periodic_refresh = PeriodicRefresh(server)

    try:
        serving_thread = threading.Thread(
            target=server.serve_forever,
            kwargs={"poll_interval": 0.5},
            daemon=True,
        )
        serving_thread.start()

        migrate_user_case_in_cache_keys(storage)
        initial_online = server.refresh_reachability(force_probe=True)
        save_online_state(initial_online)
        if initial_online:
            server.flush_pending_awards()
            retry_storage_corruption_report()
        connectivity_monitor.start()
        periodic_refresh.start()

        if stop_event is None:
            serving_thread.join()
        else:
            while not stop_event.wait(0.5):
                continue

        server.shutdown()
        serving_thread.join(timeout=5)
    finally:
        connectivity_monitor.stop()
        periodic_refresh.stop()
        stop_ra_proxy_chain()
        server.server_close()
        storage.close()
