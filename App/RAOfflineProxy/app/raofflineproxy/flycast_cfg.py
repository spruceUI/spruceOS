"""Flycast (Windows): HostUrl in emu.cfg's [achievements] section.
HardcoreMode is its hardcore setting."""

from __future__ import annotations

from . import achievements_ini
from .config import detect_flycast_cfg

FLYCAST = achievements_ini.HostSetting(
    section="[achievements]",
    host_key="HostUrl",
    hardcore_key="HardcoreMode",
    hardcore_off="no",
    previous_state_key="flycast_previous",
    path_state_key="flycast_cfg_path",
)


def patch_flycast_cfg(config_data: dict) -> dict:
    return achievements_ini.patch(FLYCAST, detect_flycast_cfg(config_data), config_data)


def store_flycast_previous(patch_state: dict, flycast: dict) -> None:
    achievements_ini.store_previous(FLYCAST, patch_state, flycast)


def revert_flycast_cfg(config_data: dict, previous: dict | None = None) -> dict:
    return achievements_ini.revert(FLYCAST, detect_flycast_cfg(config_data), config_data, previous)
