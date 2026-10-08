"""RA username and Web API key (.agents/integration.md).

The username comes from Spruce's settings, or from RetroArch's config when Spruce's RA mode is
"Manual" (the user signed in inside RetroArch). The password is never read. The API key lives in
``Saves/cheevos/apikey.txt`` and is never logged: reading or saving it registers it with the log
redaction straight away.
"""

from __future__ import annotations

import codecs
import json
import logging
import re
from pathlib import Path
from typing import Any

from cheevos.core.files import write_text_atomic
from cheevos.core.ra_client.redact import install_redaction
from cheevos.platform.paths import Paths

logger = logging.getLogger(__name__)

RA_SETTINGS_SECTION = "RetroAchievements Settings"
API_KEY_LENGTH = 32
_API_KEY = re.compile(rf"[A-Za-z0-9]{{{API_KEY_LENGTH}}}")


def read_spruce_ra_setting(paths: Paths, key: str) -> str | None:
    """Return a ``selected`` value from Spruce's "RetroAchievements Settings" block.

    Args:
        paths: Resolved paths.
        key: Setting key, e.g. ``"username"`` or ``"enableOfflineProxy"``.

    Returns:
        The value as a string, or ``None`` when the file, block or key is missing or malformed.
    """
    try:
        data: Any = json.loads(paths.spruce_config.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        logger.warning("Cannot read Spruce settings %s: %s", paths.spruce_config, exc)
        return None
    try:
        value = data["menuOptions"][RA_SETTINGS_SECTION][key]["selected"]
    except (KeyError, TypeError):
        return None
    return value if isinstance(value, str) else None


def _parse_cfg_value(raw: str) -> str:
    """Extract the value part of a RetroArch ``key = value`` line.

    Args:
        raw: Everything after the first ``=``.

    Returns:
        The quoted content, or the unquoted token up to whitespace or ``#``.
    """
    raw = raw.strip()
    if raw.startswith('"'):
        end = raw.find('"', 1)
        return raw[1:end] if end != -1 else raw[1:]
    return re.split(r"[\s#]", raw, maxsplit=1)[0]


def read_retroarch_setting(cfg_path: Path, key: str) -> str | None:
    """Read one setting from a RetroArch config file.

    Handles ``key = "value"``, ``key="value"`` and unquoted values; skips comments. When a key
    appears more than once, the last occurrence wins.

    Args:
        cfg_path: ``retroarch.cfg``-style file.
        key: Setting name, e.g. ``"cheevos_username"``.

    Returns:
        The value (possibly empty), or ``None`` when the file or key is missing.
    """
    try:
        text = cfg_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    found: str | None = None
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        name, raw_value = stripped.split("=", 1)
        if name.strip() == key:
            found = _parse_cfg_value(raw_value)
    return found


def read_username(paths: Paths) -> str | None:
    """Return the RA username: Spruce's setting first, then RetroArch's ``cheevos_username``.

    Args:
        paths: Resolved paths.

    Returns:
        The username, or ``None`` when neither source has one.
    """
    for candidate in (
        read_spruce_ra_setting(paths, "username"),
        read_retroarch_setting(paths.retroarch_config, "cheevos_username"),
    ):
        if candidate and candidate.strip():
            return candidate.strip()
    return None


def read_api_key(paths: Paths) -> str | None:
    """Return the first non-empty line of ``apikey.txt``, stripped.

    The file is often written in Windows Notepad, so its encodings are understood too: UTF-8
    with a byte-order mark, and UTF-16 ("Unicode"). The key itself isn't checked here.

    Args:
        paths: Resolved paths.

    Returns:
        The key, or ``None`` when the file is missing or blank.
    """
    try:
        data = paths.api_key_file.read_bytes()
    except OSError:
        return None
    if data.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        text = data.decode("utf-16", errors="replace")
    else:
        text = data.decode("utf-8-sig", errors="replace")
    for line in text.splitlines():
        if line.strip():
            install_redaction(line.strip())
            return line.strip()
    return None


def save_api_key(paths: Paths, key: str) -> None:
    """Store the API key atomically (owner-only permissions where the filesystem has them).

    Args:
        paths: Resolved paths.
        key: The Web API key; surrounding whitespace is removed.
    """
    install_redaction(key.strip())
    write_text_atomic(paths.api_key_file, key.strip() + "\n", mode=0o600)
    logger.info("Saved the API key to %s", paths.api_key_file)


def looks_like_api_key(text: str) -> bool:
    """Check the shape of a Web API key: 32 ASCII letters or digits.

    Args:
        text: Candidate key (surrounding whitespace is ignored).

    Returns:
        ``True`` if it has the right shape (RA still has to accept it).
    """
    return _API_KEY.fullmatch(text.strip()) is not None
