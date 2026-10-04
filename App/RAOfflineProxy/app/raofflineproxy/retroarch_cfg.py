from __future__ import annotations

import re
from pathlib import Path
from typing import Optional

from .config import (
    detect_batocera_conf,
    detect_darkos_retroarch32_cfg,
    detect_rocknix_system_cfg,
    proxy_value,
    running_on_spruce,
    spruce_setting,
)
from .state import clear_patch_state, load_patch_state, save_patch_state

HOST_KEY = "cheevos_custom_host"
ENABLE_KEY = "cheevos_enable"
HARDCORE_KEY = "cheevos_hardcore_mode_enable"
USERNAME_KEY = "cheevos_username"
TOKEN_KEY = "cheevos_token"
PASSWORD_KEY = "cheevos_password"
ROCKNIX_SYSTEM_USERNAME_KEY = "global.retroachievements.username"
ROCKNIX_SYSTEM_TOKEN_KEY = "global.retroachievements.token"
ROCKNIX_SYSTEM_PASSWORD_KEY = "global.retroachievements.password"


def cheevos_append_cfg_path(cfg_path: str | None) -> Path | None:
    if not cfg_path:
        return None

    target = Path(cfg_path)
    return target.with_name("retroarch.cheevos.cfg")


def patch_cheevos_append_cfg(cfg_path: str | None, config_data: dict) -> dict | None:
    target = cheevos_append_cfg_path(cfg_path)
    if target is None or not target.exists():
        return None

    original = target.read_text(encoding="utf-8", errors="replace")
    proxy_address = proxy_value(config_data)
    previous_host = _extract_config_value(original, HOST_KEY)
    previous_enable = _extract_config_value(original, ENABLE_KEY)
    hardcore_was_enabled = detect_hardcore_enabled(original)
    transformed = build_patched_content(original, proxy_address)

    if transformed != original:
        target.write_text(transformed, encoding="utf-8")

    if _is_proxy_host(previous_host, config_data):
        previous_host = ""

    return {
        "cfg_path": str(target),
        "hardcore_was_enabled": hardcore_was_enabled,
        "previous_enable": previous_enable,
        "previous_host": previous_host,
        "changed": transformed != original,
    }


def clear_cheevos_append_host(cfg_path: str | None, config_data: dict | None) -> dict | None:
    """Blind cleanup of the appendconfig, for when the saved patch state cannot
    describe it: the state was lost (crash, manual edit), or muOS created the file
    after the patch ran. Only a host pointing at our own proxy is cleared, so a
    genuinely custom host survives."""
    target = cheevos_append_cfg_path(cfg_path)
    if target is None or not target.exists():
        return None

    current = target.read_text(encoding="utf-8", errors="replace")
    if not _is_proxy_host(_extract_config_value(current, HOST_KEY), config_data or {}):
        return None

    transformed = _upsert_config_value(current, HOST_KEY, "")
    if transformed != current:
        target.write_text(transformed, encoding="utf-8")

    return {
        "cfg_path": str(target),
        "changed": transformed != current,
    }


def revert_cheevos_append_cfg(state: dict | None) -> dict | None:
    if not state:
        return None

    target_path = state.get("cfg_path")
    if not target_path:
        return None

    target = Path(target_path)
    if not target.exists():
        return None

    current = target.read_text(encoding="utf-8", errors="replace")
    transformed = build_reverted_content(
        current,
        state.get("previous_host"),
        state.get("previous_enable"),
        bool(state.get("hardcore_was_enabled", False)),
    )

    if transformed != current:
        target.write_text(transformed, encoding="utf-8")

    return {
        "cfg_path": str(target),
        "changed": transformed != current,
    }


def detect_hardcore_enabled(content: str) -> bool:
    return _extract_config_value(content, HARDCORE_KEY) == "true"


def load_spruce_credentials() -> dict | None:
    """spruce's own settings, which hold the credentials before any game launch has
    copied them into the RetroArch config. Password-only — spruce stores no token."""
    if not running_on_spruce():
        return None

    user = spruce_setting("username")
    password = spruce_setting("password")
    if not user or not password:
        return None

    return {"user": user, "password": password}


def load_rocknix_system_token_credentials(cfg_path: str | None = None) -> dict | None:
    """ROCKNIX's EmulationStation settings, the only source before a game has launched."""
    content = _read_rocknix_system_cfg(cfg_path)
    if content is None:
        return None

    user = _extract_config_value(content, ROCKNIX_SYSTEM_USERNAME_KEY)
    token = _extract_config_value(content, ROCKNIX_SYSTEM_TOKEN_KEY)
    if not user or not token:
        return None

    return {"user": user, "token": token}


def load_rocknix_system_password_credentials(
    cfg_path: str | None = None,
) -> dict | None:
    content = _read_rocknix_system_cfg(cfg_path)
    if content is None:
        return None

    user = _extract_config_value(content, ROCKNIX_SYSTEM_USERNAME_KEY)
    password = _extract_config_value(content, ROCKNIX_SYSTEM_PASSWORD_KEY)
    if not user or not password:
        return None

    return {"user": user, "password": password}


def _read_rocknix_system_cfg(cfg_path: str | None) -> str | None:
    path = cfg_path or detect_rocknix_system_cfg()
    if not path:
        return None

    target = Path(path)
    if not target.exists():
        return None

    return target.read_text(encoding="utf-8", errors="replace")


def load_retroarch_credentials(cfg_path: str | None) -> dict | None:
    # Try main cfg first, then the cheevos appendconfig (muOS stores credentials
    # there), then ROCKNIX's EmulationStation settings (it strips the cheevos keys
    # out of retroarch.cfg on every game launch, leaving that file the only source),
    # then dArkOS's second (32-bit) RetroArch build, which keeps a separate config
    # tree — a user who set achievements up under a 32-bit core has credentials
    # only there, and reading just the main cfg reports them as logged out.
    cheevos_cfg = str(cheevos_append_cfg_path(cfg_path)) if cfg_path else None
    darkos32_cfg = detect_darkos_retroarch32_cfg()

    token_credentials = load_retroarch_token_credentials(cfg_path)
    if token_credentials is not None:
        return token_credentials

    token_credentials = load_retroarch_token_credentials(cheevos_cfg)
    if token_credentials is not None:
        return token_credentials

    token_credentials = load_rocknix_system_token_credentials()
    if token_credentials is not None:
        return token_credentials

    token_credentials = load_retroarch_token_credentials(darkos32_cfg)
    if token_credentials is not None:
        return token_credentials

    password_credentials = load_retroarch_password_credentials(cfg_path)
    if password_credentials is not None:
        return password_credentials

    password_credentials = load_retroarch_password_credentials(cheevos_cfg)
    if password_credentials is not None:
        return password_credentials

    password_credentials = load_rocknix_system_password_credentials()
    if password_credentials is not None:
        return password_credentials

    password_credentials = load_retroarch_password_credentials(darkos32_cfg)
    if password_credentials is not None:
        return password_credentials

    return load_spruce_credentials()


def load_retroarch_token_credentials(cfg_path: str | None) -> dict | None:
    if not cfg_path:
        return None

    target = Path(cfg_path)
    if not target.exists():
        return None

    content = target.read_text(encoding="utf-8", errors="replace")
    user = _extract_config_value(content, USERNAME_KEY)
    token = _extract_config_value(content, TOKEN_KEY)
    if not user or not token:
        return None
    return {"user": user, "token": token}


def load_retroarch_password_credentials(cfg_path: str | None) -> dict | None:
    if not cfg_path:
        return None

    target = Path(cfg_path)
    if not target.exists():
        return None

    content = target.read_text(encoding="utf-8", errors="replace")
    user = _extract_config_value(content, USERNAME_KEY)
    password = _extract_config_value(content, PASSWORD_KEY)
    if not user or not password:
        return None
    return {"user": user, "password": password}


def retroarch_has_token(cfg_path: str | None) -> bool:
    return load_retroarch_credentials(cfg_path) is not None


def is_patched_content(content: str, proxy_address: str) -> bool:
    return _extract_config_value(content, HOST_KEY) == proxy_address


def is_retroarch_patched(cfg_path: str, config_data: dict) -> bool:
    """Read-only, ground-truth check: reads the cfg directly rather than trusting
    state.load_patch_state(), which only tells you a patch was applied at some point in the
    past — it goes stale if revert_retroarch_cfg() never ran (crash, manual edit, etc.)."""
    target = Path(cfg_path)
    if not target.exists():
        return False

    content = target.read_text(encoding="utf-8", errors="replace")
    return is_patched_content(content, proxy_value(config_data))


def build_patched_content(content: str, proxy_address: str) -> str:
    sanitized = _remove_orphan_boolean_lines(content)
    with_host = _upsert_config_value(sanitized, HOST_KEY, proxy_address)
    with_enable = _upsert_config_value(with_host, ENABLE_KEY, "true")
    return _upsert_config_value(with_enable, HARDCORE_KEY, "false")


def _ensure_cheevos_token(content: str, config_data: dict) -> str:
    """Some RetroArch cheevos client versions handle password-based login
    through a custom host unreliably (it's only exercised on a cold login;
    once a token exists they always use that path instead, which works
    fine). Resolve a real token ourselves and write it in ahead of time so
    RetroArch never has to take the password path through our proxy."""
    if _extract_config_value(content, TOKEN_KEY):
        return content

    username = _extract_config_value(content, USERNAME_KEY)
    password = _extract_config_value(content, PASSWORD_KEY)
    if not username or not password:
        return content

    from .auth import login_and_cache_token
    from .config import FALLBACK_USER_AGENT
    from .storage import Storage

    storage = Storage()
    try:
        credentials = login_and_cache_token(
            storage, config_data, {"user": username, "password": password}, FALLBACK_USER_AGENT
        )
    finally:
        storage.close()

    if not credentials or not credentials.get("token"):
        return content

    with_token = _upsert_config_value(content, TOKEN_KEY, credentials["token"])
    return _upsert_config_value(with_token, PASSWORD_KEY, "")


def build_reverted_content(
    content: str,
    previous_host: Optional[str],
    previous_enable: Optional[str],
    restore_hardcore: bool,
) -> str:
    sanitized = _remove_orphan_boolean_lines(content)
    restored_host = previous_host if previous_host is not None else ""
    with_host = _upsert_config_value(sanitized, HOST_KEY, restored_host)
    restored_enable = previous_enable if previous_enable is not None else ""
    with_enable = _upsert_config_value(with_host, ENABLE_KEY, restored_enable)

    if not restore_hardcore:
        return with_enable

    return _upsert_config_value(with_enable, HARDCORE_KEY, "true")


def secondary_retroarch_cfgs(config_data: dict | None = None) -> list[str]:
    """Extra retroarch.cfg files that need the same patch as the primary one.

    dArkOS ships a second, 32-bit RetroArch build with its own config tree, and
    EmulationStation dispatches part of the library to it. Patching only the
    primary cfg leaves every 32-bit core talking to retroachievements.org
    directly, bypassing the proxy entirely. Empty on every other platform.
    """
    darkos32 = detect_darkos_retroarch32_cfg(config_data)
    return [darkos32] if darkos32 else []


def patch_secondary_retroarch_cfgs(
    config_data: dict, saved_entries: list[dict] | None = None
) -> dict:
    """Patch the secondary cfgs, capturing each one's pre-patch values.

    Kept out of patch_retroarch_cfg() on purpose: that function owns the single
    top-level cfg_path/previous_host/previous_enable slots in the patch state, so
    calling it per file would have each cfg overwrite the previous one's saved
    values and break revert for all but the last.

    `saved_entries` are the previously recorded ones. They have to be passed in
    rather than read here: save_patch_state() rewrites the whole file, so by the
    time this runs the primary patch has already dropped them from disk.
    """
    proxy_address = proxy_value(config_data)
    previously_saved = {
        entry.get("cfg_path"): entry
        for entry in (saved_entries or [])
        if entry.get("cfg_path")
    }
    entries: list[dict] = []

    for cfg_path in secondary_retroarch_cfgs(config_data):
        target = Path(cfg_path)
        if not target.exists():
            continue

        original = target.read_text(encoding="utf-8", errors="replace")
        previous_host = _extract_config_value(original, HOST_KEY)
        previous_enable = _extract_config_value(original, ENABLE_KEY)
        hardcore_was_enabled = detect_hardcore_enabled(original)
        transformed = build_patched_content(original, proxy_address)
        already_patched = transformed == original and is_patched_content(
            original, proxy_address
        )

        if transformed != original:
            target.write_text(transformed, encoding="utf-8")

        # Re-patching an already-patched cfg would otherwise capture the proxy's
        # own host as "previous" and revert to it. Keep the first-captured set.
        saved = previously_saved.get(str(target))
        if already_patched and saved is not None:
            previous_host = saved.get("previous_host")
            previous_enable = saved.get("previous_enable")
            hardcore_was_enabled = bool(saved.get("hardcore_was_enabled", False))

        entries.append(
            {
                "cfg_path": str(target),
                "previous_host": previous_host,
                "previous_enable": previous_enable,
                "hardcore_was_enabled": hardcore_was_enabled,
                "already_patched": already_patched,
                "changed": transformed != original,
            }
        )

    return {"entries": entries}


def store_secondary_retroarch_previous(patch_state: dict, secondary: dict) -> None:
    patch_state["secondary_cfgs"] = [
        {
            "cfg_path": entry.get("cfg_path"),
            "previous_host": entry.get("previous_host"),
            "previous_enable": entry.get("previous_enable"),
            "hardcore_was_enabled": entry.get("hardcore_was_enabled", False),
        }
        for entry in secondary.get("entries", [])
    ]


def revert_secondary_retroarch_cfgs(
    config_data: dict, previous: list[dict] | None = None
) -> dict:
    """Restore each secondary cfg from its own saved values.

    A cfg with no saved entry is still reverted, from an empty baseline: that is
    the upgrade case, where the file was patched by a build that did not record
    secondary state, and leaving the proxy host behind would break achievements
    once the proxy is stopped.
    """
    saved = {
        entry.get("cfg_path"): entry for entry in (previous or []) if entry.get("cfg_path")
    }
    reverted: list[str] = []

    for cfg_path in secondary_retroarch_cfgs(config_data):
        target = Path(cfg_path)
        if not target.exists():
            continue

        entry = saved.get(str(target), {})
        current = target.read_text(encoding="utf-8", errors="replace")
        transformed = build_reverted_content(
            current,
            entry.get("previous_host"),
            entry.get("previous_enable"),
            bool(entry.get("hardcore_was_enabled", False)),
        )
        if transformed != current:
            target.write_text(transformed, encoding="utf-8")
            reverted.append(str(target))

    return {"reverted": reverted}


def enforce_secondary_retroarch_cfgs(config_data: dict) -> bool:
    changed = False
    for cfg_path in secondary_retroarch_cfgs(config_data):
        if enforce_patched_cfg(cfg_path, config_data):
            changed = True
    return changed


def conf_fallback_available(config_data: dict) -> bool:
    """Whether batocera.conf/knulli.conf can carry the host override on its own.

    Knulli generates retroarchcustom.cfg at the first libretro launch, so it is
    legitimately absent on a freshly flashed device. Its configgen rebuilds that
    file from the conf on every launch anyway, making the conf the authoritative
    patch target there and the missing cfg a no-op rather than a failure.
    """
    conf_path = detect_batocera_conf(config_data)
    return bool(conf_path) and Path(conf_path).exists()


def patch_retroarch_cfg(cfg_path: str, config_data: dict) -> dict:
    target = Path(cfg_path)
    if not target.exists():
        if not conf_fallback_available(config_data):
            raise FileNotFoundError(f"RetroArch config not found: {target}")
        return {
            "cfg_path": str(target),
            "exists": False,
            "hardcore_was_enabled": False,
            "previous_enable": None,
            "previous_host": None,
            "proxy_host": proxy_value(config_data),
            "changed": False,
            "already_patched": False,
        }

    existing_patch_state = load_patch_state() or {}
    original = target.read_text(encoding="utf-8", errors="replace")
    proxy_address = proxy_value(config_data)
    previous_host = _extract_config_value(original, HOST_KEY)
    previous_enable = _extract_config_value(original, ENABLE_KEY)
    hardcore_was_enabled = detect_hardcore_enabled(original)
    transformed = build_patched_content(original, proxy_address)
    transformed = _ensure_cheevos_token(transformed, config_data)
    was_already_patched = transformed == original and is_patched_content(
        original, proxy_address
    )

    if transformed != original:
        target.write_text(transformed, encoding="utf-8")

    cheevos_append_state = patch_cheevos_append_cfg(str(target), config_data)

    if was_already_patched and existing_patch_state.get("cfg_path") == str(target):
        saved_previous_host = existing_patch_state.get("previous_host")
        saved_proxy_host = existing_patch_state.get("proxy_host")
        previous_host = (
            ""
            if saved_previous_host == saved_proxy_host == proxy_address
            else saved_previous_host
        )
        previous_enable = existing_patch_state.get("previous_enable")
        hardcore_was_enabled = bool(
            existing_patch_state.get("hardcore_was_enabled", hardcore_was_enabled)
        )
        # Only the saved state knows what the appendconfig looked like before the
        # first patch. Keep the fresh one when nothing was saved for that file,
        # which is the case when muOS created it after the patch ran.
        saved_append_state = existing_patch_state.get("cheevos_append_cfg")
        append_path = str(cheevos_append_cfg_path(str(target)))
        if saved_append_state and saved_append_state.get("cfg_path") == append_path:
            cheevos_append_state = saved_append_state

    save_patch_state(
        {
            "cfg_path": str(target),
            "hardcore_was_enabled": hardcore_was_enabled,
            "previous_host": previous_host,
            "previous_enable": previous_enable,
            "proxy_host": proxy_address,
            "retroarch_cfg": str(target),
            "cheevos_append_cfg": cheevos_append_state,
        }
    )

    return {
        "cfg_path": str(target),
        "exists": True,
        "hardcore_was_enabled": hardcore_was_enabled,
        "previous_enable": previous_enable,
        "previous_host": previous_host,
        "proxy_host": proxy_address,
        "changed": transformed != original,
        "already_patched": was_already_patched,
    }


def revert_retroarch_cfg(
    cfg_path: Optional[str] = None,
    patch_state_override: Optional[dict] = None,
    config_data: Optional[dict] = None,
) -> dict:
    patch_state = patch_state_override if patch_state_override is not None else load_patch_state()
    target_path = cfg_path or (patch_state or {}).get("cfg_path")
    if target_path is None:
        raise RuntimeError("Proxy patch state not found")

    target = Path(target_path)
    if not target.exists():
        # Only a cfg the conf can regenerate is legitimately absent. Anything else is
        # a cfg that went missing after being patched, and dropping the saved state
        # there would strand the proxy host in it with nothing left to restore from.
        if not conf_fallback_available(config_data or {}):
            raise FileNotFoundError(f"RetroArch config not found: {target}")

        revert_cheevos_append_cfg((patch_state or {}).get("cheevos_append_cfg"))
        clear_cheevos_append_host(str(target), config_data)
        if patch_state_override is None and patch_state is not None:
            clear_patch_state()
        return {
            "cfg_path": str(target),
            "exists": False,
            "changed": False,
            "restored_hardcore": False,
            "previous_host": "",
            "used_saved_state": patch_state is not None,
        }

    current = target.read_text(encoding="utf-8", errors="replace")
    previous_host = patch_state.get("previous_host") if patch_state else ""
    previous_enable = patch_state.get("previous_enable") if patch_state else ""
    restore_hardcore = (
        bool(patch_state.get("hardcore_was_enabled", False)) if patch_state else False
    )

    if patch_state and previous_host == patch_state.get("proxy_host"):
        previous_host = ""

    if patch_state is None:
        previous_host = ""
        previous_enable = _extract_config_value(current, ENABLE_KEY)

    transformed = build_reverted_content(
        current,
        previous_host,
        previous_enable,
        restore_hardcore,
    )

    if transformed != current:
        target.write_text(transformed, encoding="utf-8")

    revert_cheevos_append_cfg((patch_state or {}).get("cheevos_append_cfg"))
    clear_cheevos_append_host(str(target), config_data)

    if patch_state_override is None and patch_state is not None:
        clear_patch_state()
    return {
        "cfg_path": str(target),
        "exists": True,
        "changed": transformed != current,
        "restored_hardcore": restore_hardcore,
        "previous_host": previous_host,
        "used_saved_state": patch_state is not None,
    }


def status_retroarch_cfg(cfg_path: str, config_data: dict) -> dict:
    target = Path(cfg_path)
    state = load_patch_state()
    proxy_address = proxy_value(config_data)

    if not target.exists():
        return {
            "cfg_path": str(target),
            "exists": False,
            "is_patched": False,
            "state_present": state is not None,
            "proxy_host": proxy_address,
        }

    content = target.read_text(encoding="utf-8", errors="replace")
    return {
        "cfg_path": str(target),
        "exists": True,
        "is_patched": is_patched_content(content, proxy_address),
        "cheevos_enabled": _extract_config_value(content, ENABLE_KEY) == "true",
        "hardcore_enabled": detect_hardcore_enabled(content),
        "state_present": state is not None,
        "proxy_host": proxy_address,
    }


def enforce_patched_cfg(cfg_path: str, config_data: dict) -> bool:
    target = Path(cfg_path)
    if not target.exists():
        return False

    current = target.read_text(encoding="utf-8", errors="replace")
    transformed = build_patched_content(current, proxy_value(config_data))
    if transformed == current:
        return False

    target.write_text(transformed, encoding="utf-8")
    return True


LOOPBACK_HOSTS = ("127.0.0.1", "localhost", "::1")


def _is_proxy_host(value: str | None, config_data: dict) -> bool:
    """Whether a cheevos_custom_host value is one of ours. The port is ignored on
    loopback so a host left behind by an earlier run (or a since-changed proxy port)
    is still recognised."""
    if not value:
        return False

    address = value.strip()
    if address == proxy_value(config_data):
        return True

    for scheme in ("http://", "https://"):
        if address.startswith(scheme):
            address = address[len(scheme) :]
            break

    address = address.rstrip("/")
    host = address.rsplit(":", 1)[0] if ":" in address else address
    return host.strip("[]") in LOOPBACK_HOSTS


def _extract_config_value(content: str, key: str) -> str | None:
    key_pattern = re.compile(rf"^\s*{re.escape(key)}\s*=\s*(.*?)\s*$")
    for raw_line in content.splitlines():
        match = key_pattern.match(raw_line)
        if match is None:
            continue

        value = match.group(1).strip()
        if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
            value = value[1:-1]
        elif value.startswith('"'):
            value = value[1:].strip()

        return value
    return None


def _upsert_config_value(content: str, key: str, value: str) -> str:
    # [ \t] instead of \s: \s matches newlines, so an empty existing value
    # (e.g. "key = " written by configgen) would swallow the next line
    pattern = re.compile(
        rf"^([ \t]*{re.escape(key)}[ \t]*=[ \t]*).*$", re.MULTILINE
    )
    if pattern.search(content):
        return pattern.sub(lambda match: f'{match.group(1)}"{value}"', content)

    stripped = content.rstrip("\n")
    if stripped:
        return f'{stripped}\n{key} = "{value}"\n'
    return f'{key} = "{value}"\n'


def _remove_orphan_boolean_lines(content: str) -> str:
    lines = content.splitlines()
    orphan_pattern = re.compile(
        r'^[\x00-\x1f\x7f\s]*"(?:true|false)?"[\x00-\x1f\x7f\s]*$'
    )
    kept = [line for line in lines if not orphan_pattern.fullmatch(line)]
    result = "\n".join(kept)
    if content.endswith("\n") and result:
        result += "\n"
    return result
