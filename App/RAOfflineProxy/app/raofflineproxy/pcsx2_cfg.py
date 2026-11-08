"""PCSX2 (Windows and desktop Linux): Host in PCSX2.ini's [Achievements]
section. ChallengeMode is its hardcore setting."""

from __future__ import annotations

from . import achievements_ini
from .config import detect_pcsx2_ini

PCSX2 = achievements_ini.HostSetting(
    section="[Achievements]",
    host_key="Host",
    hardcore_key="ChallengeMode",
    hardcore_off="false",
    previous_state_key="pcsx2_previous",
    path_state_key="pcsx2_ini_path",
)


def patch_pcsx2_ini(config_data: dict) -> dict:
    return achievements_ini.patch(PCSX2, detect_pcsx2_ini(config_data), config_data)


def store_pcsx2_previous(patch_state: dict, pcsx2: dict) -> None:
    achievements_ini.store_previous(PCSX2, patch_state, pcsx2)


def revert_pcsx2_ini(config_data: dict, previous: dict | None = None) -> dict:
    return achievements_ini.revert(PCSX2, detect_pcsx2_ini(config_data), config_data, previous)
