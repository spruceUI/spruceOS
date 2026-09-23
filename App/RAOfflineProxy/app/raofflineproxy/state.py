from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Optional

from .config import ONLINE_STATE_FILE, PID_FILE, STATE_FILE, STATUS_FILE, UPDATE_STATUS_FILE, ensure_config_dir


def load_patch_state() -> Optional[dict]:
    if not STATE_FILE.exists():
        return None

    with STATE_FILE.open(encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            logging.getLogger("raofflineproxy").warning(
                "Patch state file %s is empty or corrupt, resetting to defaults", STATE_FILE
            )
            return None

    if not isinstance(data, dict):
        raise ValueError(f"Invalid patch state file: {STATE_FILE}")

    return data


def save_patch_state(data: dict) -> Path:
    ensure_config_dir()
    with STATE_FILE.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return STATE_FILE


def clear_patch_state() -> None:
    if STATE_FILE.exists():
        STATE_FILE.unlink()


def load_json_file(path: Path) -> Optional[dict]:
    if not path.exists():
        return None

    with path.open(encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            logging.getLogger("raofflineproxy").warning(
                "State file %s is empty or corrupt, resetting to defaults", path
            )
            return None

    if not isinstance(data, dict):
        raise ValueError(f"Invalid state file: {path}")

    return data


def save_json_file(path: Path, data: dict) -> Path:
    ensure_config_dir()
    with path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return path


def clear_json_file(path: Path) -> None:
    if path.exists():
        path.unlink()


def load_service_status() -> Optional[dict]:
    return load_json_file(STATUS_FILE)


def save_service_status(data: dict) -> Path:
    return save_json_file(STATUS_FILE, data)


def clear_service_status() -> None:
    clear_json_file(STATUS_FILE)


def load_online_state() -> Optional[bool]:
    data = load_json_file(ONLINE_STATE_FILE)
    if data is None:
        return None
    return bool(data.get("online"))


def save_online_state(online: bool) -> Path:
    return save_json_file(ONLINE_STATE_FILE, {"online": online})


def load_update_status() -> Optional[dict]:
    return load_json_file(UPDATE_STATUS_FILE)


def save_update_status(data: dict) -> Path:
    return save_json_file(UPDATE_STATUS_FILE, data)


def clear_update_status() -> None:
    clear_json_file(UPDATE_STATUS_FILE)


def load_pid() -> Optional[int]:
    if not PID_FILE.exists():
        return None

    value = PID_FILE.read_text(encoding="utf-8").strip()
    if not value:
        return None
    return int(value)


def save_pid(pid: int) -> Path:
    ensure_config_dir()
    PID_FILE.write_text(f"{pid}\n", encoding="utf-8")
    return PID_FILE


def clear_pid() -> None:
    if PID_FILE.exists():
        PID_FILE.unlink()
