"""Host and hardcore patching for emulators that read a custom
RetroAchievements host from one section of their own ini file."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .config import proxy_value
from .dolphin_cfg import extract_achievements_value, update_achievements_section
from .utils import write_emulator_config


@dataclass(frozen=True)
class HostSetting:
    section: str
    host_key: str
    hardcore_key: str
    hardcore_off: str
    previous_state_key: str
    path_state_key: str


def patch(setting: HostSetting, ini_path: str | None, config_data: dict) -> dict:
    if ini_path is None:
        return {"exists": False, "changed": False, "path": None, "previous": {}}

    target = Path(ini_path)
    if not target.exists():
        return {"exists": False, "changed": False, "path": str(target), "previous": {}}

    original = target.read_text(encoding="utf-8", errors="replace")
    previous = {
        key: extract_achievements_value(original, key, setting.section)
        for key in (setting.host_key, setting.hardcore_key)
    }
    transformed = update_achievements_section(
        original,
        {setting.host_key: proxy_value(config_data), setting.hardcore_key: setting.hardcore_off},
        setting.section,
    )
    if transformed != original:
        write_emulator_config(target, transformed)

    return {
        "exists": True,
        "changed": transformed != original,
        "already_patched": previous[setting.host_key] == proxy_value(config_data),
        "path": str(target),
        "previous": previous,
    }


def store_previous(setting: HostSetting, patch_state: dict, result: dict) -> None:
    """A re-patch would capture the proxy's own values, so the first capture is kept."""
    if not (result.get("already_patched") and setting.previous_state_key in patch_state):
        patch_state[setting.previous_state_key] = result.get("previous", {})
    patch_state[setting.path_state_key] = result.get("path")


def revert(
    setting: HostSetting, ini_path: str | None, config_data: dict, previous: dict | None
) -> dict:
    if ini_path is None:
        return {"exists": False, "changed": False, "path": None}

    target = Path(ini_path)
    if not target.exists():
        return {"exists": False, "changed": False, "path": str(target)}

    current = target.read_text(encoding="utf-8", errors="replace")
    restored = dict(previous or {})
    if restored.get(setting.host_key) == proxy_value(config_data):
        restored[setting.host_key] = None
    transformed = update_achievements_section(
        current,
        {key: restored.get(key) for key in (setting.host_key, setting.hardcore_key)},
        setting.section,
    )
    if transformed != current:
        write_emulator_config(target, transformed)
    return {"exists": True, "changed": transformed != current, "path": str(target)}
