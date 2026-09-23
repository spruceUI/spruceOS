from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

from . import config

INCIDENT_FILENAME = "storage_corruption.json"


def _incident_file(directory: Path | None = None) -> Path:
    return (directory or config.CONFIG_DIR) / INCIDENT_FILENAME


def record_incident(
    quarantined_path: Path,
    reason: str,
    size_bytes: int,
    lost_pending_awards: int | None,
) -> None:
    incident = {
        "detected_at": int(time.time() * 1000),
        "quarantined_path": str(quarantined_path),
        "reason": reason,
        "size_bytes": size_bytes,
        "lost_pending_awards": lost_pending_awards,
        "reported": False,
        "upload_id": None,
        "notified": False,
    }
    _write(_incident_file(quarantined_path.parent), incident)


def load_incident(directory: Path | None = None) -> dict[str, Any] | None:
    try:
        return json.loads(_incident_file(directory).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def mark_reported(upload_id: str, directory: Path | None = None) -> None:
    _update(directory, reported=True, upload_id=upload_id)


def mark_notified(directory: Path | None = None) -> None:
    _update(directory, notified=True)


def _update(directory: Path | None, **fields: Any) -> None:
    incident = load_incident(directory)
    if incident is None:
        return
    incident.update(fields)
    _write(_incident_file(directory), incident)


def _write(incident_file: Path, incident: dict[str, Any]) -> None:
    try:
        incident_file.parent.mkdir(parents=True, exist_ok=True)
        incident_file.write_text(json.dumps(incident), encoding="utf-8")
    except OSError:
        pass
