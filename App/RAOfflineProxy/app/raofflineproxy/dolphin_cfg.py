from __future__ import annotations

from pathlib import Path

from .config import detect_dolphin_ini, proxy_value

ACHIEVEMENTS_SECTION = "[Achievements]"
HOST_KEY = "HostUrl"
HARDCORE_KEY = "HardcoreEnabled"


def patch_dolphin_ini(config_data: dict) -> dict:
    ini_path = detect_dolphin_ini(config_data)
    if ini_path is None:
        return {"exists": False, "changed": False, "path": None, "previous": {}}

    target = Path(ini_path)
    if not target.exists():
        return {"exists": False, "changed": False, "path": str(target), "previous": {}}

    original = target.read_text(encoding="utf-8", errors="replace")
    previous = {
        HOST_KEY: _extract_achievements_value(original, HOST_KEY),
        HARDCORE_KEY: _extract_achievements_value(original, HARDCORE_KEY),
    }
    transformed = build_patched_dolphin_ini(original, config_data)
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


def store_dolphin_previous(patch_state: dict, dolphin: dict) -> None:
    """Record the pre-patch ini values without poisoning them on re-patch.

    Re-running the patch while the ini is already patched would otherwise
    capture the proxy's own values as "previous"; keep the first-captured set.
    """
    if not (dolphin.get("already_patched") and "dolphin_previous" in patch_state):
        patch_state["dolphin_previous"] = dolphin.get("previous", {})
    patch_state["dolphin_ini_path"] = dolphin.get("path")


def revert_dolphin_ini(config_data: dict, previous: dict | None = None) -> dict:
    ini_path = detect_dolphin_ini(config_data)
    if ini_path is None:
        return {"exists": False, "changed": False, "path": None}

    target = Path(ini_path)
    if not target.exists():
        return {"exists": False, "changed": False, "path": str(target)}

    current = target.read_text(encoding="utf-8", errors="replace")
    transformed = build_reverted_dolphin_ini(
        current, _sanitize_previous(config_data, previous or {})
    )
    if transformed != current:
        target.write_text(transformed, encoding="utf-8")

    return {"exists": True, "changed": transformed != current, "path": str(target)}


def build_patched_dolphin_ini(content: str, config_data: dict) -> str:
    return _update_achievements_section(
        content,
        {
            HOST_KEY: proxy_value(config_data),
            HARDCORE_KEY: "False",
        },
    )


def _sanitize_previous(config_data: dict, previous: dict) -> dict:
    """Drop a captured host value that is actually the proxy address.

    Re-patching an already-patched ini (e.g. autostart re-running on every
    boot) records the proxy host itself as the "previous" value. Restoring
    that would re-point Dolphin at the dead local proxy, so treat it as unset.
    """
    sanitized = dict(previous)
    if sanitized.get(HOST_KEY) == proxy_value(config_data):
        sanitized[HOST_KEY] = None
    return sanitized


def build_reverted_dolphin_ini(content: str, previous: dict) -> str:
    # Unlike PPSSPP, Dolphin's default ini has no HostUrl key at all until
    # patched, so a captured `None` (never set / sanitized away) means the
    # key should be removed entirely rather than restored as an empty value.
    return _update_achievements_section(
        content,
        {
            HOST_KEY: previous.get(HOST_KEY),
            HARDCORE_KEY: previous.get(HARDCORE_KEY) or "False",
        },
    )


def _update_achievements_section(content: str, updates: dict[str, str | None]) -> str:
    """Apply key updates within [Achievements]; a `None` value removes the key."""
    lines = content.split("\n")
    section_index = next(
        (i for i, line in enumerate(lines) if line.strip() == ACHIEVEMENTS_SECTION),
        None,
    )

    if section_index is None:
        additions = {key: value for key, value in updates.items() if value is not None}
        if not additions:
            return content
        suffix = "\n".join(f"{key} = {value}" for key, value in additions.items())
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
    result = lines[: section_index + 1]
    for index in range(section_index + 1, section_end):
        stripped = lines[index].strip()
        separator = stripped.find("=")
        if separator == -1:
            result.append(lines[index])
            continue
        key = stripped[:separator].strip()
        if key not in remaining:
            result.append(lines[index])
            continue
        value = remaining.pop(key)
        if value is not None:
            result.append(f"{key} = {value}")
        # value is None: drop this line, removing the key entirely.

    result.extend(f"{key} = {value}" for key, value in remaining.items() if value is not None)
    result.extend(lines[section_end:])

    return "\n".join(result)


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
