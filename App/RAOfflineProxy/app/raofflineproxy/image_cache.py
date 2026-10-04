from __future__ import annotations

import contextlib
import json
import logging
import os
import shutil
import sys
import threading
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from .config import CONFIG_DIR

_IMAGE_DOWNLOAD_POOL_SIZE = 4
_LOWEST_PRIORITY = 19


def _lower_thread_priority() -> None:
    """Image downloads are best-effort, and a TLS handshake costs a handheld's single core
    hundreds of milliseconds: at the lowest priority it never stalls the menu or the proxy."""
    if not sys.platform.startswith("linux"):
        return
    try:
        os.setpriority(os.PRIO_PROCESS, threading.get_native_id(), _LOWEST_PRIORITY)
    except (AttributeError, OSError):
        pass


_image_download_executor = ThreadPoolExecutor(
    max_workers=_IMAGE_DOWNLOAD_POOL_SIZE, initializer=_lower_thread_priority
)
_inline_downloads = threading.local()
_pending_downloads: set[str] = set()
_pending_downloads_lock = threading.Lock()

LOGGER = logging.getLogger("raofflineproxy")
IMAGE_CACHE_DIR = CONFIG_DIR / "image_cache"
GAMES_DIR = IMAGE_CACHE_DIR / "games"
STATIC_DIR = IMAGE_CACHE_DIR / "static"

IMAGE_PATH_PREFIXES = ("/Badge/", "/Images/", "/UserPic/")


def game_image_dir(game_id: int) -> Path:
    return GAMES_DIR / str(game_id)


def extract_image_path(url: str) -> str | None:
    """
    Extracts the /path component from an RA image URL (e.g. /Badge/496014.png).
    Handles both full URLs (https://media.retroachievements.org/Badge/…) and
    relative paths (/Badge/…). Query strings are stripped.
    Returns None for blank input or unrecognised hosts.
    """
    if not url or not url.strip():
        return None
    if url.startswith("/"):
        return url.split("?", 1)[0]
    marker = "retroachievements.org"
    idx = url.find(marker)
    if idx == -1:
        return None
    after_host = url[idx + len(marker):].split("?", 1)[0]
    return after_host if after_host.startswith("/") else None


def _rewrite_icon_fields(
    obj: dict,
    proxy_base_url: str,
    downloads: list[tuple[str, str]],
) -> None:
    source_url = obj.get("ImageIconUrl") or obj.get("ImageIcon")
    if not source_url:
        return
    path = extract_image_path(source_url)
    if not path:
        return
    downloads.append((source_url, path))
    proxy_url = f"{proxy_base_url}{path}"
    if "ImageIconUrl" in obj:
        obj["ImageIconUrl"] = proxy_url
    if "ImageIcon" in obj:
        obj["ImageIcon"] = proxy_url


def _rewrite_url_field(
    obj: dict,
    key: str,
    proxy_base_url: str,
    downloads: list[tuple[str, str]],
) -> None:
    url = obj.get(key)
    if not url:
        return
    path = extract_image_path(url)
    if not path:
        return
    downloads.append((url, path))
    obj[key] = f"{proxy_base_url}{path}"


def _rewrite_achievement_badge_fields(
    achievements: list,
    proxy_base_url: str,
    downloads: list[tuple[str, str]],
) -> None:
    for achievement in achievements:
        if not isinstance(achievement, dict):
            continue
        _rewrite_url_field(achievement, "BadgeURL", proxy_base_url, downloads)
        _rewrite_url_field(achievement, "BadgeLockedURL", proxy_base_url, downloads)


def rewrite_image_urls(
    action: str | None,
    body: str,
    proxy_base_url: str,
) -> tuple[str, list[tuple[str, str]]]:
    """
    Rewrites all image URL fields in an API response body so they point to the
    local proxy instead of the upstream RA media server.

    Returns a tuple of (rewritten_body, [(original_url, path), ...]).
    The caller is responsible for downloading each (original_url, path) pair.
    Returns (body, []) unchanged on parse errors or unrecognised actions.
    """
    if action not in ("patch", "achievementsets", "login2"):
        return body, []
    try:
        data = json.loads(body)
    except Exception:
        return body, []

    if not isinstance(data, dict):
        return body, []

    downloads: list[tuple[str, str]] = []

    if action == "patch":
        patch_data = data.get("PatchData")
        if isinstance(patch_data, dict):
            _rewrite_icon_fields(patch_data, proxy_base_url, downloads)
            achievements = patch_data.get("Achievements")
            if isinstance(achievements, list):
                _rewrite_achievement_badge_fields(achievements, proxy_base_url, downloads)

    elif action == "achievementsets":
        _rewrite_icon_fields(data, proxy_base_url, downloads)
        sets = data.get("Sets")
        if isinstance(sets, list):
            for s in sets:
                if not isinstance(s, dict):
                    continue
                _rewrite_icon_fields(s, proxy_base_url, downloads)
                achievements = s.get("Achievements")
                if isinstance(achievements, list):
                    _rewrite_achievement_badge_fields(achievements, proxy_base_url, downloads)

    elif action == "login2":
        _rewrite_url_field(data, "AvatarUrl", proxy_base_url, downloads)

    return json.dumps(data, separators=(",", ":")), downloads


def download_static_image(
    url: str,
    image_path: str,
    user_agent: str,
    game_id: int | None = None,
) -> None:
    """
    Downloads an image from url and stores it in the static cache at image_path
    (e.g. "/Badge/496014.png"). No-ops if already cached.

    If game_id is provided and image_path starts with /Images/, also copies the
    downloaded file to the per-game directory for UI display. All failures are
    silently swallowed — images are best-effort.
    """
    try:
        clean_path = image_path.lstrip("/").split("?", 1)[0]
        target = STATIC_DIR / clean_path
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            request = urllib.request.Request(
                url,
                headers={"User-Agent": user_agent, "Accept-Encoding": "identity"},
                method="GET",
            )
            tmp = target.with_suffix(target.suffix + ".tmp")
            try:
                with urllib.request.urlopen(request, timeout=10) as response:
                    tmp.write_bytes(response.read())
                tmp.rename(target)
                tmp = None
            finally:
                if tmp is not None:
                    tmp.unlink(missing_ok=True)
        if (
            game_id is not None
            and image_path.lower().startswith("/images/")
            and target.exists()
        ):
            icon_file = game_image_dir(game_id) / "icon.png"
            if not icon_file.exists():
                icon_file.parent.mkdir(parents=True, exist_ok=True)
                icon_file.write_bytes(target.read_bytes())
    except Exception as exc:
        LOGGER.debug("Failed to cache image path=%s: %s", image_path, exc)


def schedule_image_download(
    url: str,
    image_path: str,
    user_agent: str,
    game_id: int | None = None,
) -> None:
    collected = getattr(_inline_downloads, "items", None)
    if collected is not None:
        collected.append((url, image_path, user_agent, game_id))
        return
    with _pending_downloads_lock:
        if image_path in _pending_downloads:
            return
        _pending_downloads.add(image_path)
    _image_download_executor.submit(_download_pending_image, url, image_path, user_agent, game_id)


def _download_pending_image(url: str, image_path: str, user_agent: str, game_id: int | None) -> None:
    try:
        download_static_image(url, image_path, user_agent, game_id)
    finally:
        with _pending_downloads_lock:
            _pending_downloads.discard(image_path)


@contextlib.contextmanager
def images_downloaded_inline():
    """Downloads the images a game schedules on this thread before the block returns, 4 at a
    time, instead of handing them to the shared background executor.

    Bulk caching goes through here: dozens of badges per game queued behind each other on the
    executor pile up into a backlog that keeps a handheld busy for hours after the batch ended.
    """
    previous = getattr(_inline_downloads, "items", None)
    collected: list[tuple[str, str, str, int | None]] = []
    _inline_downloads.items = collected
    try:
        yield
    finally:
        _inline_downloads.items = previous
    pending: dict[str, tuple[str, str, str, int | None]] = {}
    for item in collected:
        if item[1] not in pending and resolve_cached_static_asset(item[1]) is None:
            pending[item[1]] = item
    if not pending:
        return
    with ThreadPoolExecutor(
        max_workers=_IMAGE_DOWNLOAD_POOL_SIZE, initializer=_lower_thread_priority
    ) as pool:
        list(pool.map(lambda item: download_static_image(*item), pending.values()))


def shutdown_image_downloads() -> None:
    """Drop queued image downloads so they cannot hold up process exit.

    ThreadPoolExecutor workers are not daemon threads, and concurrent.futures
    joins them during interpreter shutdown — before atexit handlers run, so this
    has to be called explicitly. A first run that caches a game queues a badge
    per achievement, and without this the menu stays alive after its window
    closes until every one of them has been fetched.

    Images are best-effort and re-requested on the next launch, so cancelling
    what has not started yet costs nothing. Downloads already in flight still
    finish, but each carries its own timeout.
    """
    _image_download_executor.shutdown(wait=False, cancel_futures=True)


def resolve_cached_static_asset(path: str) -> Path | None:
    """Returns the cached static image file for path, or None if not yet downloaded."""
    clean_path = path.lstrip("/").split("?", 1)[0]
    asset = STATIC_DIR / clean_path
    return asset if asset.is_file() else None


def resolve_cached_game_icon_path(game_id: int) -> Path | None:
    """Returns the cached game icon file for game_id, used by the UI game-list."""
    directory = game_image_dir(game_id)
    if not directory.exists():
        return None
    for f in directory.iterdir():
        if f.is_file():
            return f
    return None


def delete_cached_images_for_game(game_id: int) -> None:
    directory = game_image_dir(game_id)
    if directory.exists():
        shutil.rmtree(directory, ignore_errors=True)


def clear_all_cached_images() -> None:
    if IMAGE_CACHE_DIR.exists():
        shutil.rmtree(IMAGE_CACHE_DIR, ignore_errors=True)
