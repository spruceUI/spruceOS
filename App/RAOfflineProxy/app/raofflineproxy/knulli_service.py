from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

SERVICE_NAME = "raofflineproxy"
USER_SERVICE_FILE = Path("/userdata/system/services/raofflineproxy")
SYSTEM_SERVICE_FILES = (
    Path("/usr/share/knulli/services/raofflineproxy"),
    Path("/usr/share/batocera/services/raofflineproxy"),
)


def services_binary() -> str | None:
    for name in ("knulli-services", "batocera-services"):
        found = shutil.which(name)
        if found:
            return found
    return None


def service_mode_active() -> bool:
    if services_binary() is None:
        return False
    if USER_SERVICE_FILE.exists():
        return True
    return any(path.exists() for path in SYSTEM_SERVICE_FILES)


def _run(action: str) -> None:
    binary = services_binary()
    if binary is None:
        raise RuntimeError("knulli-services not available")
    subprocess.run(
        [binary, action, SERVICE_NAME],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )


def service_autostart_enabled() -> bool:
    binary = services_binary()
    if binary is None:
        return False
    try:
        output = subprocess.check_output([binary, "list"], text=True, timeout=30)
    except (subprocess.SubprocessError, OSError):
        return False
    for line in output.splitlines():
        parts = line.split(";")
        if len(parts) == 2 and parts[0].strip() == SERVICE_NAME:
            return parts[1].strip() == "*"
    return False


def enable_service_autostart() -> None:
    _run("enable")


def disable_service_autostart() -> None:
    _run("disable")


def start_service() -> None:
    _run("start")


def stop_service() -> None:
    _run("stop")
