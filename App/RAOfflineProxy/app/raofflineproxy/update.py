from __future__ import annotations

import json
import logging
import os
import tempfile
import time
import http.client
import socket
import urllib.error
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path
import shutil

from .config import APP_VERSION, CONFIG_DIR
from .network import configured_ssl_context
from .state import load_update_status, save_update_status

LOGGER = logging.getLogger("raofflineproxy")
GITHUB_RELEASES_URL = "https://api.github.com/repos/misantronic/RAOfflineProxy/releases"
UPDATE_CHECK_INTERVAL_SECONDS = 24 * 60 * 60
PLATFORM_KNULLI = "knulli"
PLATFORM_ONION = "onion"
PLATFORM_SPRUCE = "spruce"
PLATFORM_MUOS = "muos"
PLATFORM_ROCKNIX = "rocknix"
PLATFORM_ALLIUM = "allium"
PLATFORM_DARKOS = "darkos"
KNULLI_UPDATE_INSTALLER_PATH = CONFIG_DIR / "update-installer.sh"
ONION_UPDATE_ARCHIVE_PATH = CONFIG_DIR / "update-onion.zip"
MUOS_UPDATE_ARCHIVE_PATH = CONFIG_DIR / "update-muos.muxapp"
INSTALLER_DOWNLOAD_RETRIES = 3
INSTALLER_DOWNLOAD_RETRY_DELAY_SECONDS = 1.5
RELEASES_FETCH_RETRIES = 3
RELEASES_FETCH_TIMEOUT_SECONDS = 10
RELEASES_FETCH_RETRY_DELAY_SECONDS = 2.0


@dataclass(frozen=True)
class UpdateInfo:
    current_version: str
    update_available: bool
    latest_version: str | None
    release_url: str | None
    asset_url: str | None
    checked_at: int

    def to_dict(self) -> dict:
        return {
            "current_version": self.current_version,
            "update_available": self.update_available,
            "latest_version": self.latest_version,
            "release_url": self.release_url,
            "asset_url": self.asset_url,
            "checked_at": self.checked_at,
        }


@dataclass(frozen=True, order=True)
class ParsedVersion:
    major: int
    minor: int
    patch: int
    stage_rank: int
    stage_number: int


@dataclass(frozen=True)
class ReleaseCandidate:
    version_name: str
    parsed_version: ParsedVersion
    release_url: str
    asset_url: str


def current_version() -> str:
    return APP_VERSION


def update_status(platform: str, force: bool = False) -> UpdateInfo:
    validated_platform = validate_platform(platform)
    now = int(time.time())
    cached = load_cached_update_status(validated_platform)
    if cached is not None and not force:
        checked_at = int(cached.get("checked_at") or 0)
        if checked_at > 0 and (now - checked_at) < UPDATE_CHECK_INTERVAL_SECONDS:
            LOGGER.info(
                "Update check cache hit platform=%s checked_at=%s",
                validated_platform,
                checked_at,
            )
            return dict_to_update_info(cached)

    LOGGER.info(
        "Checking GitHub releases for platform=%s current_version=%s",
        validated_platform,
        current_version(),
    )
    fetch_succeeded, latest = fetch_latest_release(validated_platform, current_version())
    if not fetch_succeeded:
        LOGGER.warning("Update check failed platform=%s; preserving prior cache", validated_platform)
        if cached is not None:
            return dict_to_update_info(cached)
        return UpdateInfo(
            current_version=current_version(),
            update_available=False,
            latest_version=None,
            release_url=None,
            asset_url=None,
            checked_at=0,
        )

    result = UpdateInfo(
        current_version=current_version(),
        update_available=latest is not None,
        latest_version=latest.version_name if latest is not None else None,
        release_url=latest.release_url if latest is not None else None,
        asset_url=latest.asset_url if latest is not None else None,
        checked_at=now,
    )
    save_cached_update_status(validated_platform, result)
    if latest is None:
        LOGGER.info("No Linux update available platform=%s", validated_platform)
    else:
        LOGGER.info(
            "Linux update available platform=%s latest_version=%s asset_url=%s",
            validated_platform,
            latest.version_name,
            latest.asset_url,
        )
    return result


def fetch_latest_release(
    platform: str, current_version_name: str
) -> tuple[bool, ReleaseCandidate | None]:
    current_parsed = parse_version(current_version_name)
    if current_parsed is None:
        LOGGER.warning("Skipping update check; unsupported current version=%s", current_version_name)
        return True, None

    releases = fetch_releases(platform)
    if releases is None:
        return False, None
    newer = [release for release in releases if release.parsed_version > current_parsed]
    if not newer:
        return True, None
    return True, max(newer, key=lambda release: release.parsed_version)


def fetch_releases(platform: str) -> list[ReleaseCandidate] | None:
    request = urllib.request.Request(
        GITHUB_RELEASES_URL,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": f"RAOfflineProxy/Linux/{APP_VERSION}",
        },
        method="GET",
    )
    body: str | None = None
    for attempt in range(1, RELEASES_FETCH_RETRIES + 1):
        try:
            with urllib.request.urlopen(
                request,
                timeout=RELEASES_FETCH_TIMEOUT_SECONDS,
                context=configured_ssl_context(),
            ) as response:
                body = response.read().decode("utf-8")
            break
        except urllib.error.HTTPError as error:
            LOGGER.warning(
                "GitHub releases request failed attempt=%s/%s status=%s reason=%s",
                attempt,
                RELEASES_FETCH_RETRIES,
                error.code,
                error.reason,
            )
            if not should_retry_release_fetch(error) or attempt >= RELEASES_FETCH_RETRIES:
                return None
        except (urllib.error.URLError, TimeoutError, socket.timeout, http.client.RemoteDisconnected) as error:
            LOGGER.warning(
                "GitHub releases request failed attempt=%s/%s reason=%s",
                attempt,
                RELEASES_FETCH_RETRIES,
                error,
            )
            if attempt >= RELEASES_FETCH_RETRIES:
                return None
        except Exception:
            LOGGER.exception("GitHub releases request failed attempt=%s/%s", attempt, RELEASES_FETCH_RETRIES)
            if attempt >= RELEASES_FETCH_RETRIES:
                return None

        time.sleep(RELEASES_FETCH_RETRY_DELAY_SECONDS)

    if body is None:
        return None

    data = json.loads(body)
    accepted: list[ReleaseCandidate] = []
    for release in data:
        if release.get("draft"):
            LOGGER.debug("Skipping draft release")
            continue

        tag_name = str(release.get("tag_name") or "").strip()
        version_name = tag_name.removeprefix("v")
        parsed_version = parse_version(version_name)
        if parsed_version is None:
            LOGGER.debug("Skipping release tag=%s unsupported version format", tag_name)
            continue

        release_url = str(release.get("html_url") or "").strip()
        if not release_url:
            LOGGER.debug("Skipping release tag=%s missing html_url", tag_name)
            continue

        asset_url = find_platform_asset_url(platform, release.get("assets") or [])
        if asset_url is None:
            LOGGER.debug("Skipping release tag=%s no %s asset", tag_name, platform)
            continue

        LOGGER.debug("Accepted %s release tag=%s asset_url=%s", platform, tag_name, asset_url)
        accepted.append(
            ReleaseCandidate(
                version_name=version_name,
                parsed_version=parsed_version,
                release_url=release_url,
                asset_url=asset_url,
            )
        )

    LOGGER.info("Fetched %s %s release candidates", len(accepted), platform)
    return accepted


def should_retry_release_fetch(error: urllib.error.HTTPError) -> bool:
    return error.code == 429 or error.code >= 500


def find_platform_asset_url(platform: str, assets: list[dict]) -> str | None:
    for asset in assets:
        name = str(asset.get("name") or "")
        lower_name = name.lower()
        if platform == PLATFORM_KNULLI:
            if "knulli" not in lower_name or not lower_name.endswith(".sh"):
                continue
        elif platform == PLATFORM_ONION:
            if "onion" not in lower_name or not lower_name.endswith(".zip"):
                continue
        elif platform == PLATFORM_SPRUCE:
            if "spruce" not in lower_name or not lower_name.endswith(".zip"):
                continue
        elif platform == PLATFORM_MUOS:
            if "muos" not in lower_name or not lower_name.endswith(".muxapp"):
                continue
        elif platform == PLATFORM_ROCKNIX:
            if "rocknix" not in lower_name or not lower_name.endswith(".sh"):
                continue
        elif platform == PLATFORM_ALLIUM:
            if "allium" not in lower_name or not lower_name.endswith(".zip"):
                continue
        elif platform == PLATFORM_DARKOS:
            if "darkos" not in lower_name or not lower_name.endswith(".sh"):
                continue
        else:
            continue

        asset_url = str(asset.get("browser_download_url") or "").strip()
        if asset_url:
            LOGGER.debug("Matched %s asset name=%s", platform, name)
            return asset_url
    return None


def download_knulli_update_installer(
    asset_url: str, destination: Path | None = None
) -> Path:
    destination_path = destination or KNULLI_UPDATE_INSTALLER_PATH
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    LOGGER.info(
        "Downloading KNULLI update installer asset_url=%s destination=%s",
        asset_url,
        destination_path,
    )

    last_error: Exception | None = None
    for attempt in range(1, INSTALLER_DOWNLOAD_RETRIES + 1):
        try:
            body = read_update_asset(asset_url)
            atomic_write_executable(destination_path, body)
            return destination_path
        except (urllib.error.URLError, http.client.IncompleteRead, ConnectionResetError, TimeoutError, OSError) as error:
            last_error = error
            LOGGER.warning(
                "Installer download failed attempt=%s/%s reason=%s",
                attempt,
                INSTALLER_DOWNLOAD_RETRIES,
                error,
            )
            if attempt < INSTALLER_DOWNLOAD_RETRIES:
                time.sleep(INSTALLER_DOWNLOAD_RETRY_DELAY_SECONDS)

    if last_error is not None:
        raise RuntimeError(f"download failed: {last_error}") from last_error
    return destination_path


def read_update_asset(asset_url: str) -> bytes:
    request = urllib.request.Request(
        asset_url,
        headers={
            "Accept": "application/octet-stream",
            "User-Agent": f"RAOfflineProxy/Linux/{APP_VERSION}",
        },
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=30, context=configured_ssl_context()) as response:
        return response.read()


def download_onion_update_archive(asset_url: str, destination: Path | None = None) -> Path:
    destination_path = destination or ONION_UPDATE_ARCHIVE_PATH
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    LOGGER.info(
        "Downloading Onion update archive asset_url=%s destination=%s",
        asset_url,
        destination_path,
    )

    last_error: Exception | None = None
    for attempt in range(1, INSTALLER_DOWNLOAD_RETRIES + 1):
        try:
            body = read_update_asset(asset_url)
            atomic_write_executable(destination_path, body, executable=False)
            return destination_path
        except (urllib.error.URLError, http.client.IncompleteRead, ConnectionResetError, TimeoutError, OSError) as error:
            last_error = error
            LOGGER.warning(
                "Onion archive download failed attempt=%s/%s reason=%s",
                attempt,
                INSTALLER_DOWNLOAD_RETRIES,
                error,
            )
            if attempt < INSTALLER_DOWNLOAD_RETRIES:
                time.sleep(INSTALLER_DOWNLOAD_RETRY_DELAY_SECONDS)

    if last_error is not None:
        raise RuntimeError(f"download failed: {last_error}") from last_error
    return destination_path


CLEANUP_RETRIES = 3
CLEANUP_RETRY_DELAY_SECONDS = 1.0


def remove_tree_best_effort(path: Path) -> None:
    """Delete a temp tree, retrying before giving up quietly.

    A plain rmtree(ignore_errors=True) measurably loses on a Miyoo Mini: right after an
    install has written ~129MB, the first pass over the old tree bails partway on the
    card's FAT32 write-back and silently leaves hundreds of files behind, while an
    immediate second pass removes all of them with no errors at all. Left as-is the
    debris accumulates with every update — which on Allium can push the card under the
    300MB its own OTA updater demands (see linux/allium/README.md).
    """
    for attempt in range(1, CLEANUP_RETRIES + 1):
        if not path.exists():
            return
        shutil.rmtree(path, ignore_errors=attempt < CLEANUP_RETRIES)
        if not path.exists():
            return
        if attempt < CLEANUP_RETRIES:
            time.sleep(CLEANUP_RETRY_DELAY_SECONDS)

    # Never fatal: the update itself already succeeded, so this is only tidy-up. But it is
    # logged rather than swallowed, so the debris is diagnosable instead of invisible.
    LOGGER.warning("Could not fully remove temporary update directory path=%s", path)


def install_onion_update_archive(
    archive_path: Path, app_dir: Path, archive_root: str = "App"
) -> None:
    """Swap `app_dir` for the copy inside the archive, atomically and with rollback.

    Everything here is layout-agnostic except where the app directory sits inside the
    archive, which is what `archive_root` names: Onion and spruce ship `App/RAOfflineProxy`,
    Allium ships `Apps/RAOfflineProxy.pak`.
    """
    app_dir = Path(app_dir)
    parent_dir = app_dir.parent
    temp_extract_dir = parent_dir / f".{app_dir.name}.update"
    backup_dir = parent_dir / f".{app_dir.name}.backup"
    preserved_data_dir = parent_dir / f".{app_dir.name}.data"
    data_dir_name = "data"

    if temp_extract_dir.exists():
        shutil.rmtree(temp_extract_dir)
    if backup_dir.exists():
        shutil.rmtree(backup_dir)
    if preserved_data_dir.exists():
        shutil.rmtree(preserved_data_dir)

    temp_extract_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive_path, "r") as archive:
        archive.extractall(temp_extract_dir)
        restore_archive_permissions(archive, temp_extract_dir)

    extracted_app_dir = temp_extract_dir / archive_root / app_dir.name
    if not extracted_app_dir.exists():
        raise RuntimeError(f"update archive missing {archive_root}/{app_dir.name}")

    preserve_data = should_preserve_onion_data(current_version(), extracted_app_dir)

    if app_dir.exists():
        os.replace(app_dir, backup_dir)
    try:
        os.replace(extracted_app_dir, app_dir)
        backup_data_dir = backup_dir / data_dir_name
        new_data_dir = app_dir / data_dir_name
        if preserve_data and backup_data_dir.exists():
            os.replace(backup_data_dir, preserved_data_dir)
            if new_data_dir.exists():
                shutil.rmtree(new_data_dir)
            os.replace(preserved_data_dir, new_data_dir)
    except Exception:
        if backup_dir.exists():
            backup_data_dir = backup_dir / data_dir_name
            if preserved_data_dir.exists() and not backup_data_dir.exists():
                os.replace(preserved_data_dir, backup_data_dir)
            if app_dir.exists():
                shutil.rmtree(app_dir, ignore_errors=True)
            os.replace(backup_dir, app_dir)
        raise
    finally:
        remove_tree_best_effort(temp_extract_dir)
        remove_tree_best_effort(backup_dir)
        remove_tree_best_effort(preserved_data_dir)

    clear_stale_update_status(app_dir)


def download_muos_update_archive(asset_url: str, destination: Path | None = None) -> Path:
    destination_path = destination or MUOS_UPDATE_ARCHIVE_PATH
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    LOGGER.info(
        "Downloading muOS update archive asset_url=%s destination=%s",
        asset_url,
        destination_path,
    )

    last_error: Exception | None = None
    for attempt in range(1, INSTALLER_DOWNLOAD_RETRIES + 1):
        try:
            body = read_update_asset(asset_url)
            atomic_write_executable(destination_path, body, executable=False)
            return destination_path
        except (urllib.error.URLError, http.client.IncompleteRead, ConnectionResetError, TimeoutError, OSError) as error:
            last_error = error
            LOGGER.warning(
                "muOS archive download failed attempt=%s/%s reason=%s",
                attempt,
                INSTALLER_DOWNLOAD_RETRIES,
                error,
            )
            if attempt < INSTALLER_DOWNLOAD_RETRIES:
                time.sleep(INSTALLER_DOWNLOAD_RETRY_DELAY_SECONDS)

    if last_error is not None:
        raise RuntimeError(f"download failed: {last_error}") from last_error
    return destination_path


def install_muos_update_archive(archive_path: Path, app_dir: Path) -> None:
    """Install a muOS .muxapp (a zip whose top-level dir is the app dir) over app_dir.

    The app's data/ directory (config, database, queued awards, secrets) is always
    preserved across the upgrade. The downloaded archive is removed on completion.
    """
    archive_path = Path(archive_path)
    app_dir = Path(app_dir)
    parent_dir = app_dir.parent
    temp_extract_dir = parent_dir / f".{app_dir.name}.update"
    backup_dir = parent_dir / f".{app_dir.name}.backup"
    preserved_data_dir = parent_dir / f".{app_dir.name}.data"
    data_dir_name = "data"

    if temp_extract_dir.exists():
        shutil.rmtree(temp_extract_dir)
    if backup_dir.exists():
        shutil.rmtree(backup_dir)
    if preserved_data_dir.exists():
        shutil.rmtree(preserved_data_dir)

    temp_extract_dir.mkdir(parents=True, exist_ok=True)
    try:
        with zipfile.ZipFile(archive_path, "r") as archive:
            archive.extractall(temp_extract_dir)
            restore_archive_permissions(archive, temp_extract_dir)

        extracted_app_dir = temp_extract_dir / app_dir.name
        if not extracted_app_dir.exists():
            raise RuntimeError(f"update archive missing {app_dir.name}")

        if app_dir.exists():
            os.replace(app_dir, backup_dir)
        try:
            os.replace(extracted_app_dir, app_dir)
            backup_data_dir = backup_dir / data_dir_name
            new_data_dir = app_dir / data_dir_name
            if backup_data_dir.exists():
                os.replace(backup_data_dir, preserved_data_dir)
                if new_data_dir.exists():
                    shutil.rmtree(new_data_dir)
                os.replace(preserved_data_dir, new_data_dir)
        except Exception:
            if backup_dir.exists():
                backup_data_dir = backup_dir / data_dir_name
                if preserved_data_dir.exists() and not backup_data_dir.exists():
                    os.replace(preserved_data_dir, backup_data_dir)
                if app_dir.exists():
                    shutil.rmtree(app_dir, ignore_errors=True)
                os.replace(backup_dir, app_dir)
            raise
    finally:
        remove_tree_best_effort(temp_extract_dir)
        remove_tree_best_effort(backup_dir)
        remove_tree_best_effort(preserved_data_dir)
        if archive_path.exists():
            archive_path.unlink()

    clear_stale_update_status(app_dir)


def should_preserve_onion_data(current_version_name: str, extracted_app_dir: Path) -> bool:
    current_parsed = parse_version(current_version_name)
    next_version = read_onion_app_version(extracted_app_dir)
    next_parsed = parse_version(next_version) if next_version is not None else None

    if current_parsed is None or next_parsed is None:
        LOGGER.info(
            "Skipping Onion data preservation; unable to compare versions current=%s next=%s",
            current_version_name,
            next_version,
        )
        return False

    preserve = current_parsed.major == next_parsed.major
    LOGGER.info(
        "Onion data preservation decision current=%s next=%s preserve=%s",
        current_version_name,
        next_version,
        preserve,
    )
    return preserve


def read_onion_app_version(extracted_app_dir: Path) -> str | None:
    common_sh = extracted_app_dir / "common.sh"
    if not common_sh.exists():
        return None

    for line in common_sh.read_text(encoding="utf-8").splitlines():
        if not line.startswith("APP_VERSION="):
            continue
        return line.partition("=")[2].strip().removeprefix("v")

    return None


def restore_archive_permissions(archive: zipfile.ZipFile, extract_root: Path) -> None:
    for info in archive.infolist():
        mode = info.external_attr >> 16
        if mode == 0:
            continue

        target_path = extract_root / info.filename
        if not target_path.exists():
            continue

        os.chmod(target_path, mode)


def clear_stale_update_status(app_dir: Path) -> None:
    update_status_path = app_dir / "data" / "update_status.json"
    if update_status_path.exists():
        update_status_path.unlink()


def atomic_write_executable(path: Path, body: bytes, executable: bool = True) -> None:
    fd, temp_path = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(body)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_path, 0o755 if executable else 0o644)
        os.replace(temp_path, path)
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def parse_version(raw: str) -> ParsedVersion | None:
    normalized = raw.strip().removeprefix("v")
    parts = normalized.split("-", maxsplit=1)
    version_numbers = parts[0].split(".")
    if len(version_numbers) != 3:
        return None

    try:
        major = int(version_numbers[0])
        minor = int(version_numbers[1])
        patch = int(version_numbers[2])
    except ValueError:
        return None

    if len(parts) == 1:
        return ParsedVersion(
            major=major,
            minor=minor,
            patch=patch,
            stage_rank=2,
            stage_number=2**31 - 1,
        )

    prerelease = parts[1].lower()
    if prerelease.startswith("alpha"):
        stage_rank = 0
        stage_number = prerelease.removeprefix("alpha")
    elif prerelease.startswith("beta"):
        stage_rank = 1
        stage_number = prerelease.removeprefix("beta")
    else:
        return None

    if not stage_number:
        return None

    try:
        parsed_stage_number = int(stage_number)
    except ValueError:
        return None

    return ParsedVersion(
        major=major,
        minor=minor,
        patch=patch,
        stage_rank=stage_rank,
        stage_number=parsed_stage_number,
    )


def validate_platform(platform: str) -> str:
    lowered = platform.strip().lower()
    if lowered not in {
        PLATFORM_KNULLI,
        PLATFORM_ONION,
        PLATFORM_SPRUCE,
        PLATFORM_MUOS,
        PLATFORM_ROCKNIX,
        PLATFORM_ALLIUM,
        PLATFORM_DARKOS,
    }:
        raise ValueError(f"Unsupported update platform: {platform}")
    return lowered


def load_cached_update_status(platform: str) -> dict | None:
    payload = load_update_status() or {}
    cached = payload.get(platform)
    return cached if isinstance(cached, dict) else None


def save_cached_update_status(platform: str, result: UpdateInfo) -> None:
    payload = load_update_status() or {}
    payload[platform] = result.to_dict()
    save_update_status(payload)


def dict_to_update_info(payload: dict) -> UpdateInfo:
    current_version_name = current_version()
    latest_version = str(payload.get("latest_version") or "") or None
    release_url = str(payload.get("release_url") or "") or None
    asset_url = str(payload.get("asset_url") or "") or None
    cached_update_available = bool(payload.get("update_available"))
    update_available = resolve_cached_update_available(
        current_version_name,
        latest_version,
        cached_update_available,
    )

    return UpdateInfo(
        current_version=current_version_name,
        update_available=update_available,
        latest_version=latest_version if update_available else None,
        release_url=release_url if update_available else None,
        asset_url=asset_url if update_available else None,
        checked_at=int(payload.get("checked_at") or 0),
    )


def resolve_cached_update_available(
    current_version_name: str,
    latest_version: str | None,
    cached_update_available: bool,
) -> bool:
    if not latest_version:
        return False

    current_parsed = parse_version(current_version_name)
    latest_parsed = parse_version(latest_version)
    if current_parsed is None or latest_parsed is None:
        return cached_update_available

    return latest_parsed > current_parsed
