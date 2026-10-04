from __future__ import annotations

from pathlib import Path

from .config import detect_batocera_conf, proxy_value

RETROACHIEVEMENTS_KEY = "global.retroachievements"
RETROACHIEVEMENTS_HARDCORE_KEY = "global.retroachievements.hardcore"
RETROARCH_CHEEVOS_ENABLE_KEY = "global.retroarch.cheevos_enable"
CHEEVOS_CUSTOM_HOST_KEY = "global.retroarch.cheevos_custom_host"
CHEEVOS_HARDCORE_KEY = "global.retroarch.cheevos_hardcore_mode_enable"
OBSOLETE_KEYS = [
    "global.cheevos_enable",
    RETROARCH_CHEEVOS_ENABLE_KEY,
    CHEEVOS_HARDCORE_KEY,
]


def patch_batocera_conf(config_data: dict) -> dict:
    conf_path = detect_batocera_conf(config_data)
    if conf_path is None:
        return {"exists": False, "changed": False, "path": None, "previous": {}}

    target = Path(conf_path)
    if not target.exists():
        return {"exists": False, "changed": False, "path": str(target), "previous": {}}

    original = target.read_text(encoding="utf-8", errors="replace")
    previous = {
        RETROACHIEVEMENTS_KEY: _extract_value(original, RETROACHIEVEMENTS_KEY),
        RETROACHIEVEMENTS_HARDCORE_KEY: _extract_value(
            original, RETROACHIEVEMENTS_HARDCORE_KEY
        ),
        RETROARCH_CHEEVOS_ENABLE_KEY: _extract_value(
            original, RETROARCH_CHEEVOS_ENABLE_KEY
        ),
        CHEEVOS_CUSTOM_HOST_KEY: _extract_value(original, CHEEVOS_CUSTOM_HOST_KEY),
        CHEEVOS_HARDCORE_KEY: _extract_value(original, CHEEVOS_HARDCORE_KEY),
    }
    transformed = build_patched_batocera_conf(original, config_data)
    if transformed != original:
        target.write_text(transformed, encoding="utf-8")

    already_patched = transformed == original and previous[
        CHEEVOS_CUSTOM_HOST_KEY
    ] == f'"{proxy_value(config_data)}"'

    return {
        "exists": True,
        "changed": transformed != original,
        "already_patched": already_patched,
        "path": str(target),
        "previous": previous,
    }


def store_batocera_previous(patch_state: dict, batocera: dict) -> None:
    """Record the pre-patch conf values without poisoning them on re-patch.

    Re-running the patch while the conf is already patched would otherwise
    capture the proxy's own values as "previous"; keep the first-captured set.
    """
    if not (batocera.get("already_patched") and "batocera_previous" in patch_state):
        patch_state["batocera_previous"] = batocera.get("previous", {})
    patch_state["batocera_conf_path"] = batocera.get("path")


def revert_batocera_conf(config_data: dict, previous: dict | None = None) -> dict:
    conf_path = detect_batocera_conf(config_data)
    if conf_path is None:
        return {"exists": False, "changed": False, "path": None}

    target = Path(conf_path)
    if not target.exists():
        return {"exists": False, "changed": False, "path": str(target)}

    current = target.read_text(encoding="utf-8", errors="replace")
    transformed = build_reverted_batocera_conf(
        current, _sanitize_previous(config_data, previous or {})
    )
    if transformed != current:
        target.write_text(transformed, encoding="utf-8")

    return {"exists": True, "changed": transformed != current, "path": str(target)}


def enforce_batocera_conf(config_data: dict) -> bool:
    conf_path = detect_batocera_conf(config_data)
    if conf_path is None:
        return False

    target = Path(conf_path)
    if not target.exists():
        return False

    current = target.read_text(encoding="utf-8", errors="replace")
    transformed = build_patched_batocera_conf(current, config_data)
    if transformed == current:
        return False

    target.write_text(transformed, encoding="utf-8")
    return True


def build_patched_batocera_conf(content: str, config_data: dict) -> str:
    updated = content
    for key in OBSOLETE_KEYS:
        updated = _restore_value(updated, key, None)

    updated = _upsert_value(updated, RETROACHIEVEMENTS_KEY, "1")
    updated = _upsert_value(updated, RETROACHIEVEMENTS_HARDCORE_KEY, "0")
    updated = _upsert_value(updated, RETROARCH_CHEEVOS_ENABLE_KEY, '"true"')
    updated = _upsert_value(
        updated, CHEEVOS_CUSTOM_HOST_KEY, f'"{proxy_value(config_data)}"'
    )
    return _upsert_value(updated, CHEEVOS_HARDCORE_KEY, '"false"')


def _sanitize_previous(config_data: dict, previous: dict) -> dict:
    """Drop a captured custom-host value that is actually the proxy address.

    Re-patching an already-patched conf (e.g. autostart re-running on every boot)
    records the proxy host itself as the "previous" value. Restoring that would
    re-point RetroArch at the dead local proxy, so treat it as unset instead.
    """
    proxy_quoted = f'"{proxy_value(config_data)}"'
    sanitized = dict(previous)
    if sanitized.get(CHEEVOS_CUSTOM_HOST_KEY) == proxy_quoted:
        sanitized[CHEEVOS_CUSTOM_HOST_KEY] = None
    return sanitized


def build_reverted_batocera_conf(content: str, previous: dict) -> str:
    # global.retroachievements is the user's master toggle: the proxy may
    # enable it on start but must never disable it on revert
    reverted = content
    reverted = _restore_value(
        reverted,
        RETROACHIEVEMENTS_HARDCORE_KEY,
        previous.get(RETROACHIEVEMENTS_HARDCORE_KEY),
    )
    reverted = _restore_value(
        reverted,
        RETROARCH_CHEEVOS_ENABLE_KEY,
        previous.get(RETROARCH_CHEEVOS_ENABLE_KEY),
    )
    reverted = _restore_value(
        reverted, CHEEVOS_CUSTOM_HOST_KEY, previous.get(CHEEVOS_CUSTOM_HOST_KEY)
    )
    reverted = _restore_value(
        reverted, CHEEVOS_HARDCORE_KEY, previous.get(CHEEVOS_HARDCORE_KEY)
    )
    return reverted


def _extract_value(content: str, key: str) -> str | None:
    prefix = f"{key}="
    for line in content.splitlines():
        if line.startswith(prefix):
            return line[len(prefix) :]
    return None


def _upsert_value(content: str, key: str, value: str) -> str:
    prefix = f"{key}="
    lines = content.splitlines()
    for index, line in enumerate(lines):
        if line.startswith(prefix):
            lines[index] = f"{key}={value}"
            return "\n".join(lines) + ("\n" if content.endswith("\n") else "")

    suffix = "\n" if content.endswith("\n") or not content else ""
    base = content if content.endswith("\n") or not content else f"{content}\n"
    return f"{base}{key}={value}{suffix}"


def _restore_value(content: str, key: str, previous_value: str | None) -> str:
    prefix = f"{key}="
    lines = content.splitlines()
    kept: list[str] = []
    replaced = False

    for line in lines:
        if line.startswith(prefix):
            if previous_value is not None and not replaced:
                kept.append(f"{key}={previous_value}")
                replaced = True
            continue
        kept.append(line)

    result = "\n".join(kept)
    if content.endswith("\n") and result:
        result += "\n"
    return result
