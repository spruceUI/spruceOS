"""DuckStation (Windows): Host in settings.ini's [Cheevos] section.
ChallengeMode is its hardcore setting."""

from __future__ import annotations

from . import achievements_ini
from .config import detect_duckstation_ini

DUCKSTATION = achievements_ini.HostSetting(
    section="[Cheevos]",
    host_key="Host",
    hardcore_key="ChallengeMode",
    hardcore_off="false",
    previous_state_key="duckstation_previous",
    path_state_key="duckstation_ini_path",
)


def patch_duckstation_ini(config_data: dict) -> dict:
    return achievements_ini.patch(DUCKSTATION, detect_duckstation_ini(config_data), config_data)


def store_duckstation_previous(patch_state: dict, duckstation: dict) -> None:
    achievements_ini.store_previous(DUCKSTATION, patch_state, duckstation)


def revert_duckstation_ini(config_data: dict, previous: dict | None = None) -> dict:
    return achievements_ini.revert(
        DUCKSTATION, detect_duckstation_ini(config_data), config_data, previous
    )
