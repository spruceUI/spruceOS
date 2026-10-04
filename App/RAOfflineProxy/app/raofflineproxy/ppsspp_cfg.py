from __future__ import annotations

from pathlib import Path

from .config import detect_ppsspp_ini, proxy_value

ACHIEVEMENTS_SECTION = "[Achievements]"
HOST_KEY = "AchievementsHost"
CHALLENGE_MODE_KEY = "AchievementsChallengeMode"


def is_ppsspp_patched(config_data: dict) -> bool:
    """Read-only check, unlike patch_ppsspp_ini() which writes. PPSSPP has no persisted
    patch-state file (unlike RetroArch's state.load_patch_state()), so this reads the ini
    directly — same idempotency check patch_ppsspp_ini() does internally to decide whether a
    rewrite is needed."""
    ini_path = detect_ppsspp_ini(config_data)
    if ini_path is None:
        return False

    target = Path(ini_path)
    if not target.exists():
        return False

    content = target.read_text(encoding="utf-8", errors="replace")
    return _extract_achievements_value(content, HOST_KEY) == proxy_value(config_data)


def patch_ppsspp_ini(config_data: dict) -> dict:
    ini_path = detect_ppsspp_ini(config_data)
    if ini_path is None:
        return {"exists": False, "changed": False, "path": None, "previous": {}}

    target = Path(ini_path)
    if not target.exists():
        return {"exists": False, "changed": False, "path": str(target), "previous": {}}

    original = target.read_text(encoding="utf-8", errors="replace")
    previous = {
        HOST_KEY: _extract_achievements_value(original, HOST_KEY),
        CHALLENGE_MODE_KEY: _extract_achievements_value(original, CHALLENGE_MODE_KEY),
    }
    transformed = build_patched_ppsspp_ini(original, config_data)
    if transformed != original:
        target.write_text(transformed, encoding="utf-8")

    already_patched = transformed == original and previous[HOST_KEY] == proxy_value(
        config_data
    )

    return {
        "exists": True,
        "changed": transformed != original,
        "already_patched": already_patched,
        "path": str(target),
        "previous": previous,
    }


def store_ppsspp_previous(patch_state: dict, ppsspp: dict) -> None:
    """Record the pre-patch ini values without poisoning them on re-patch.

    Re-running the patch while the ini is already patched would otherwise
    capture the proxy's own values as "previous"; keep the first-captured set.
    """
    if not (ppsspp.get("already_patched") and "ppsspp_previous" in patch_state):
        patch_state["ppsspp_previous"] = ppsspp.get("previous", {})
    patch_state["ppsspp_ini_path"] = ppsspp.get("path")


def revert_ppsspp_ini(config_data: dict, previous: dict | None = None) -> dict:
    ini_path = detect_ppsspp_ini(config_data)
    if ini_path is None:
        return {"exists": False, "changed": False, "path": None}

    target = Path(ini_path)
    if not target.exists():
        return {"exists": False, "changed": False, "path": str(target)}

    current = target.read_text(encoding="utf-8", errors="replace")
    transformed = build_reverted_ppsspp_ini(
        current, _sanitize_previous(config_data, previous or {})
    )
    if transformed != current:
        target.write_text(transformed, encoding="utf-8")

    return {"exists": True, "changed": transformed != current, "path": str(target)}


def build_patched_ppsspp_ini(content: str, config_data: dict) -> str:
    return _update_achievements_section(
        content,
        {
            HOST_KEY: proxy_value(config_data),
            CHALLENGE_MODE_KEY: "False",
        },
    )


def _sanitize_previous(config_data: dict, previous: dict) -> dict:
    """Drop a captured host value that is actually the proxy address.

    Re-patching an already-patched ini (e.g. autostart re-running on every
    boot) records the proxy host itself as the "previous" value. Restoring
    that would re-point PPSSPP at the dead local proxy, so treat it as unset.
    """
    sanitized = dict(previous)
    if sanitized.get(HOST_KEY) == proxy_value(config_data):
        sanitized[HOST_KEY] = None
    return sanitized


def build_reverted_ppsspp_ini(content: str, previous: dict) -> str:
    return _update_achievements_section(
        content,
        {
            HOST_KEY: previous.get(HOST_KEY) or "",
            CHALLENGE_MODE_KEY: previous.get(CHALLENGE_MODE_KEY) or "False",
        },
    )


def _update_achievements_section(content: str, updates: dict[str, str]) -> str:
    lines = content.split("\n")
    section_index = next(
        (i for i, line in enumerate(lines) if line.strip() == ACHIEVEMENTS_SECTION),
        None,
    )

    if section_index is None:
        suffix = "\n".join(f"{key} = {value}" for key, value in updates.items())
        return content.rstrip("\n") + f"\n{ACHIEVEMENTS_SECTION}\n{suffix}\n"

    section_end = next(
        (
            i
            for i in range(section_index + 1, len(lines))
            if lines[i].strip().startswith("[") and lines[i].strip().endswith("]")
        ),
        len(lines),
    )

    remaining = dict(updates)
    for index in range(section_index + 1, section_end):
        stripped = lines[index].strip()
        separator = stripped.find("=")
        if separator == -1:
            continue
        key = stripped[:separator].strip()
        if key not in remaining:
            continue
        value = remaining.pop(key)
        lines[index] = f"{key} = {value}"

    if remaining:
        additions = [f"{key} = {value}" for key, value in remaining.items()]
        lines[section_end:section_end] = additions

    return "\n".join(lines)


def _extract_achievements_value(content: str, key: str) -> str | None:
    in_section = False
    for line in content.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_section = stripped == ACHIEVEMENTS_SECTION
            continue
        if not in_section:
            continue

        separator = stripped.find("=")
        if separator == -1:
            continue
        current_key = stripped[:separator].strip()
        if current_key != key:
            continue
        return stripped[separator + 1 :].strip()

    return None
