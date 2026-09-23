from __future__ import annotations

import io
import json
import logging
import re
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

from . import config, ppsspp_cfg, retroarch_cfg
from .network import configured_ssl_context
from .utils import redact_query_tokens

LOGGER = logging.getLogger(__name__)

REQUEST_UPLOAD_URL = "https://ud63psmdb5.execute-api.eu-central-1.amazonaws.com/logs/request-upload"
REQUEST_TIMEOUT_SECONDS = 15
# Not config.running_on_muos() (doesn't exist) or menu_sdl.running_on_muos() (would create a
# circular import, since menu_sdl imports upload_logs from this module) — duplicated here.
MUOS_MARKER_PATH = Path("/opt/muos/script/archive")
# Both confirmed from OnionUI/Onion's own diagnostics script
# (static/build/.tmp_update/script/diagnostics/util_snapshot.sh), which reads the exact same
# two files for its "System log snapshot" support tool.
ONION_VERSION_FILE = config.ONION_VERSION_FILE
ONION_DEVICE_MODEL_FILE = Path("/tmp/deviceModel")
# Allium's own version marker, the same file its updater migrations check against.
ALLIUM_VERSION_FILE = Path("/mnt/SDCARD/.allium/version.txt")
# /etc/os-release's OS_VERSION is deliberately truncated to just the leading number by Knulli's
# own build script (board/scripts/post-build-script.sh in knulli-cfw/knulli-linux); this
# untruncated file (version + build date + time) is what Knulli's own knulli-report-stats tool
# reads instead.
KNULLI_VERSION_FILE = Path("/usr/share/knulli/knulli.version")
# muOS's own board/name config value (confirmed on real hardware — see MustardOS/internal's
# script/var/func.sh GET_VAR "device" "board/name"). Its devicetree model property only holds
# the bare SoC codename (e.g. "sun50iw9"), not a useful device label.
MUOS_BOARD_NAME_FILE = Path("/opt/muos/device/config/board/name")
# The standard Linux hardware-identity files (ARM devicetree, x86 DMI) — the same pair
# ROCKNIX's own rocknix-info script uses to label the device, not Onion-specific.
DEVICETREE_MODEL_FILE = Path("/sys/firmware/devicetree/base/model")
DMI_SYS_VENDOR_FILE = Path("/sys/class/dmi/id/sys_vendor")
DMI_PRODUCT_NAME_FILE = Path("/sys/class/dmi/id/product_name")

QUARANTINED_STORAGE_GLOB = "*.json.corrupt-*"
# Matches a pending_awards/api_cache JSON object whose cacheKey identifies it as
# holding RA credentials (login2:: responses carry a session Token; the
# auth::invalid_token entry's responseBody *is* a raw token), and blanks only
# that object's responseBody value. DOTALL + non-greedy so it stops at the
# first responseBody after the matched cacheKey, i.e. the same object's.
_SENSITIVE_CACHE_ENTRY = re.compile(
    r'("cacheKey":\s*"(?:login2::|auth::invalid_token)[^"]*".*?"responseBody":\s*")'
    r'((?:\\.|[^"\\])*)(")',
    re.DOTALL,
)


def _log_file_paths() -> list[Path]:
    # RotatingFileHandler renames the active file to "<name>.1" on rollover, so the
    # backup can hold the most relevant history if a rollover just happened. Oldest first.
    backup = config.LOG_FILE.with_name(config.LOG_FILE.name + ".1")
    # menu-sdl.log is a separate log written by the pygame menu process itself
    # (key logger output, controller calibration, crashes) — not covered by service.log.
    menu_sdl_log = config.CONFIG_DIR / "menu-sdl.log"
    # launch.log (muOS only) timestamps every launcher invocation, including the
    # boot hook — the only way to see how late the service starts at boot.
    launch_log = config.CONFIG_DIR / "launch.log"
    # menu-stdout.log (ROCKNIX only) holds the raw stdout/stderr of each launcher
    # attempt. A native SDL crash kills the process before any Python handler runs,
    # so this is the only record of which driver/preload combination died and how.
    menu_stdout_log = config.CONFIG_DIR / "menu-stdout.log"
    return [
        backup,
        config.LOG_FILE,
        menu_sdl_log,
        launch_log,
        menu_stdout_log,
        config.UPDATE_STATUS_FILE,
        config.STATUS_FILE,
    ]


def _redact_storage_json(text: str) -> str:
    text = _SENSITIVE_CACHE_ENTRY.sub(r"\1<redacted>\3", text)
    return "\n".join(redact_query_tokens(line) for line in text.splitlines())


def _quarantined_storage_files() -> dict[str, str]:
    files: dict[str, str] = {}
    for path in sorted(config.CONFIG_DIR.glob(QUARANTINED_STORAGE_GLOB)):
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        files[path.name] = _redact_storage_json(content)
    return files


def _read_redacted_log_files() -> dict[str, str]:
    # redact_query_tokens does an in-place substring replacement, safe on arbitrary
    # free-text log lines. redact_form_tokens fully reparses/re-encodes its input as
    # a query string, which would mangle a formatted log line (timestamp, message
    # text, etc.) around the secret rather than just blanking it out.
    files: dict[str, str] = {}
    for path in _log_file_paths():
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        redacted_lines = (redact_query_tokens(line) for line in content.splitlines())
        files[path.name] = "\n".join(redacted_lines)
    files.update(_quarantined_storage_files())
    return files


def _zip_logs(files: dict[str, str]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in files.items():
            archive.writestr(name, content.encode("utf-8"))
    return buffer.getvalue()


def _request_upload_target() -> tuple[str, str]:
    request = urllib.request.Request(
        REQUEST_UPLOAD_URL,
        data=json.dumps(_upload_metadata()).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(
            request, timeout=REQUEST_TIMEOUT_SECONDS, context=configured_ssl_context()
        ) as response:
            body = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        LOGGER.error(
            "Log upload request-upload failed status=%s body=%s",
            error.code,
            body[:512],
        )
        raise RuntimeError(f"Could not request an upload URL (HTTP {error.code})") from error
    except urllib.error.URLError as error:
        LOGGER.error("Log upload request-upload failed reason=%s", error.reason)
        raise RuntimeError(f"Could not reach upload service: {error.reason}") from error

    try:
        parsed = json.loads(body)
        upload_id = parsed["id"]
        upload_url = parsed["uploadUrl"]
    except (json.JSONDecodeError, KeyError, TypeError) as error:
        LOGGER.error("Log upload request-upload returned malformed response body=%s", body[:512])
        raise RuntimeError("Malformed request-upload response") from error

    return upload_id, upload_url


def _platform_label() -> str:
    if config.running_on_spruce():
        return "spruce"
    if config.running_on_onion():
        return "Onion"
    if config.running_on_allium():
        return "Allium"
    if MUOS_MARKER_PATH.exists():
        return "muOS"
    if config.running_on_rocknix():
        return "ROCKNIX"
    if config.running_on_darkos():
        return "dArkOS"
    return "Knulli"


def _os_release_field(*keys: str) -> str | None:
    try:
        content = config.OS_RELEASE_PATH.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    values: dict[str, str] = {}
    for line in content.splitlines():
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip().strip('"')

    for key in keys:
        if values.get(key):
            return values[key]
    return None


def _read_stripped(path: Path) -> str | None:
    try:
        # Devicetree properties (e.g. DEVICETREE_MODEL_FILE) are null-terminated C strings,
        # hence the explicit strip("\0") — plain .strip() only trims whitespace.
        text = path.read_text(encoding="utf-8", errors="replace").strip().strip("\0")
    except OSError:
        return None
    return text or None


def _onion_device_label() -> str:
    # /tmp/deviceModel holds just the raw numeric chip/model code Onion itself uses (283 =
    # Miyoo Mini, 354 = Miyoo Mini Plus/Flip — see OnionUI/Onion's device_model.h). Onion's own
    # System Settings -> About Device screen prefixes it with "MY" for display; match that.
    raw = _read_stripped(ONION_DEVICE_MODEL_FILE)
    if raw and raw.isdigit():
        return f"MY{raw}"
    return raw or "Onion"


def _onion_os_version() -> str | None:
    return _read_stripped(ONION_VERSION_FILE)


def _spruce_os_version() -> str | None:
    return _read_stripped(config.SPRUCE_VERSION_FILE)


def spruce_os_version() -> str | None:
    return _spruce_os_version()


def _allium_os_version() -> str | None:
    return _read_stripped(ALLIUM_VERSION_FILE)


# OnionOS v4.3.1-1 ships a bundled RetroArch build whose achievements client is not
# reliably compatible with a custom host, so we only support the build after it.
SUPPORTED_ONION_VERSION_PREFIX = "v4.4.0"


def onion_os_version() -> str | None:
    return _onion_os_version()


def onion_version_supported() -> bool:
    version = _onion_os_version()
    if not version:
        return False
    return version.lower().startswith(SUPPORTED_ONION_VERSION_PREFIX)


def _knulli_os_version() -> str | None:
    return _read_stripped(KNULLI_VERSION_FILE)


def _muos_device_label() -> str | None:
    # e.g. "rg40xx-h" -> "RG40XX-H" — muOS's own device/build-target slug, not a marketing name,
    # but the closest thing available and far more useful than the bare SoC codename.
    raw = _read_stripped(MUOS_BOARD_NAME_FILE)
    return raw.upper() if raw else None


def _hardware_device_label(fallback: str) -> str:
    # Same pair ROCKNIX's own rocknix-info script uses to label the device: devicetree model
    # on ARM boards, DMI vendor+product on x86. Both are the OS's own self-reported hardware
    # identity, not an inferred/indirect signal.
    model = _read_stripped(DEVICETREE_MODEL_FILE)
    if model:
        return model
    vendor = _read_stripped(DMI_SYS_VENDOR_FILE)
    product = _read_stripped(DMI_PRODUCT_NAME_FILE)
    combined = " ".join(part for part in (vendor, product) if part)
    return combined or fallback


def _device_label(platform: str) -> str:
    if platform == "spruce":
        return config.spruce_platform()
    if platform == "Onion":
        return _onion_device_label()
    if platform == "Allium":
        # Deliberately NOT _onion_device_label(): /tmp/deviceModel is written by Onion's own
        # runtime and does not exist on Allium (verified on a Miyoo Mini Plus), so that
        # helper's fallback would label every Allium device the literal string "Onion".
        return _hardware_device_label(platform)
    if platform == "muOS":
        return _muos_device_label() or _hardware_device_label(platform)
    return _hardware_device_label(platform)


def _os_version_value(platform: str) -> str | None:
    if platform == "spruce":
        # spruce has no /etc/os-release either; this is the file its own updater reads.
        return _spruce_os_version()
    if platform == "Onion":
        # Onion has no /etc/os-release; its own diagnostics tool reads this file instead.
        return _onion_os_version()
    if platform == "Allium":
        return _allium_os_version()
    if platform == "Knulli":
        # The dedicated file has the full version + build date/time; os-release's OS_VERSION
        # is a truncated copy of just the leading number.
        return _knulli_os_version() or _os_release_field("OS_VERSION", "VERSION", "PRETTY_NAME", "VERSION_ID")
    # ROCKNIX writes a real firmware version into a custom OS_VERSION key (not the standard
    # os-release VERSION/VERSION_ID/PRETTY_NAME keys), so it has to be checked first. muOS does
    # use the standard keys.
    return _os_release_field("OS_VERSION", "VERSION", "PRETTY_NAME", "VERSION_ID")


def _upload_metadata() -> dict[str, str | list[str]]:
    # Submitted alongside the log so the support form can skip asking for this again once the
    # user provides a Log ID. Best-effort: precise emulator/core isn't reliably detectable
    # across these distros, so that field is coarser than the Android equivalent (only whether
    # RetroArch was patched, not which core).
    platform = _platform_label()
    version_value = _os_version_value(platform)

    metadata: dict[str, str | list[str]] = {
        "system": "Linux",
        "os": platform,
        "device": _device_label(platform),
        "app_version": config.APP_VERSION,
    }
    if version_value:
        metadata["os_version"] = version_value

    config_data = config.load_config()
    emulators: list[str] = []
    if retroarch_cfg.is_retroarch_patched(config.detect_retroarch_cfg(), config_data):
        emulators.append("RetroArch")
    if ppsspp_cfg.is_ppsspp_patched(config_data):
        emulators.append("PPSSPP")
    if emulators:
        metadata["emulator"] = emulators

    return metadata


def _put_log_archive(upload_url: str, zip_bytes: bytes) -> None:
    request = urllib.request.Request(
        upload_url,
        data=zip_bytes,
        headers={"Content-Type": "application/zip"},
        method="PUT",
    )
    try:
        with urllib.request.urlopen(
            request, timeout=REQUEST_TIMEOUT_SECONDS, context=configured_ssl_context()
        ):
            return
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        LOGGER.error("Log upload PUT failed status=%s body=%s", error.code, body[:512])
        raise RuntimeError(f"Upload failed (HTTP {error.code})") from error
    except urllib.error.URLError as error:
        LOGGER.error("Log upload PUT failed reason=%s", error.reason)
        raise RuntimeError(f"Upload failed: {error.reason}") from error


def upload_logs(extra_files: dict[str, str] | None = None) -> str:
    files = _read_redacted_log_files()
    if extra_files:
        files.update(extra_files)
    zip_bytes = _zip_logs(files)
    try:
        upload_id, upload_url = _request_upload_target()
        _put_log_archive(upload_url, zip_bytes)
    except RuntimeError:
        raise
    except Exception as error:
        LOGGER.exception("Log upload failed unexpectedly")
        raise RuntimeError(f"Log upload failed: {error}") from error
    return upload_id


def report_storage_corruption(incident: dict) -> str:
    lost_pending_awards = incident.get("lost_pending_awards")
    note = (
        "A corrupted local data file was detected and automatically reset.\n"
        f"Detected at (ms since epoch): {incident.get('detected_at')}\n"
        f"Quarantined file: {incident.get('quarantined_path')}\n"
        f"Corrupted file size (bytes): {incident.get('size_bytes')}\n"
        f"Parse error: {incident.get('reason')}\n"
        f"Salvaged pending_awards count: {lost_pending_awards if lost_pending_awards is not None else 'unknown (unrecoverable)'}\n"
    )
    return upload_logs({"storage_corruption.txt": note})
