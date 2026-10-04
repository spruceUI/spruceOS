from __future__ import annotations

import os
import socket
import subprocess
import time
from datetime import datetime
from pathlib import Path

from .config import DEFAULT_DARKOS_HOME, load_config, proxy_host, proxy_port

DEFAULT_DARKOS_SERVICE_UNIT = Path("/etc/systemd/system/raofflineproxy.service")
DARKOS_SERVICE_NAME = "raofflineproxy.service"
# The launcher already exports HOME, XDG_CONFIG_HOME, PYTHONPATH and
# LD_LIBRARY_PATH, so the unit runs it rather than restating that environment.
DARKOS_LAUNCHER = DEFAULT_DARKOS_HOME / "raofflineproxy" / "bin" / "raofflineproxy"
# dArkOS's own user. The menu runs as this account, so the service must too:
# anything it creates in the config dir as root would be unwritable from the menu.
DARKOS_USER = "ark"


def _run_privileged(args: list[str]) -> tuple[bool, str]:
    # dArkOS's own ES Tools scripts (e.g. "Enable Remote Services.sh") call
    # `sudo systemctl ...` non-interactively from the same unprivileged Tools
    # context RAOfflineProxy runs in, which only works with passwordless sudo
    # configured for the device user. -n makes sudo fail fast instead of
    # hanging on a password prompt if that assumption turns out to be wrong.
    candidates = [["sudo", "-n", *args]]
    if os.geteuid() == 0:
        candidates.append(list(args))

    for candidate in candidates:
        try:
            result = subprocess.run(candidate, capture_output=True, timeout=10)
        except OSError:
            continue
        if result.returncode == 0:
            return True, result.stdout.decode().strip()

    return False, ""


def _write_privileged(path: Path, content: str) -> bool:
    try:
        path.write_text(content, encoding="utf-8")
        return True
    except OSError:
        pass

    try:
        result = subprocess.run(
            ["sudo", "-n", "tee", str(path)],
            input=content,
            text=True,
            capture_output=True,
            timeout=10,
        )
        return result.returncode == 0
    except OSError:
        return False


def _systemd_timestamp_to_unix(ts: str) -> int | None:
    # `systemctl show --value --property=ActiveEnterTimestamp` prints a local-time
    # stamp like "Mon 2026-08-31 20:02:52 EEST". It is empty for a unit that has
    # never started, and the property is dropped entirely on some systemd builds,
    # so anything unparseable returns None rather than raising into the caller.
    parts = ts.split()
    if len(parts) < 3:
        return None

    try:
        dt = datetime.strptime(f"{parts[1]} {parts[2]}", "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None
    return int(time.mktime(dt.timetuple()))


def darkos_systemd_unit() -> str:
    return "\n".join(
        [
            "[Unit]",
            "Description=RAOfflineProxy server",
            "After=emulationstation.service network.target",
            "",
            "[Service]",
            "Type=simple",
            f"User={DARKOS_USER}",
            f"Group={DARKOS_USER}",
            # Autostart has to repoint the emulators at the proxy the same way the
            # menu's start does; without this the proxy comes up after a reboot but
            # nothing routes through it. Prefixed with '-' so a failed patch (e.g. a
            # missing retroarch.cfg) never blocks the proxy itself from starting.
            f"ExecStartPre=-{DARKOS_LAUNCHER} apply-emulator-config",
            f"ExecStart={DARKOS_LAUNCHER} run-service",
            "Restart=always",
            "RestartSec=1",
            "",
            "[Install]",
            "WantedBy=multi-user.target",
            "",
        ]
    )


def systemd_install_service() -> None:
    if not _write_privileged(DEFAULT_DARKOS_SERVICE_UNIT, darkos_systemd_unit()):
        return
    _run_privileged(["systemctl", "daemon-reload"])


def systemd_remove_service() -> None:
    _run_privileged(["systemctl", "disable", "--now", DARKOS_SERVICE_NAME])
    if not _run_privileged(["rm", "-f", str(DEFAULT_DARKOS_SERVICE_UNIT)])[0]:
        try:
            DEFAULT_DARKOS_SERVICE_UNIT.unlink(missing_ok=True)
        except OSError:
            pass
    _run_privileged(["systemctl", "daemon-reload"])


def systemd_service_status() -> bool:
    # Active: active => True
    # Active: inactive => False
    return _run_privileged(["systemctl", "is-active", "--quiet", DARKOS_SERVICE_NAME])[0]


def systemd_service_enabled() -> bool:
    # enabled => True
    # disabled => False
    return _run_privileged(["systemctl", "is-enabled", "--quiet", DARKOS_SERVICE_NAME])[0]


def systemd_service_pid() -> int | None:
    # "0" is what systemd reports for an inactive or unknown unit.
    pid = _run_privileged(
        ["systemctl", "show", "--property", "MainPID", "--value", DARKOS_SERVICE_NAME]
    )[1]
    try:
        return int(pid) or None
    except ValueError:
        return None


def systemd_service_start_time() -> int:
    if not systemd_service_status():
        return int(time.time())

    ts = _run_privileged(
        [
            "systemctl",
            "show",
            "--property",
            "ActiveEnterTimestamp",
            "--value",
            DARKOS_SERVICE_NAME,
        ]
    )[1]
    return _systemd_timestamp_to_unix(ts) or int(time.time())


def _ensure_unit_installed() -> None:
    if not DEFAULT_DARKOS_SERVICE_UNIT.exists():
        systemd_install_service()


def systemd_enable_service() -> bool:
    _ensure_unit_installed()
    return _run_privileged(["systemctl", "enable", DARKOS_SERVICE_NAME])[0]


def systemd_disable_service() -> bool:
    return _run_privileged(["systemctl", "disable", DARKOS_SERVICE_NAME])[0]


def systemd_start_service() -> bool:
    return _run_privileged(["systemctl", "start", DARKOS_SERVICE_NAME])[0]


def systemd_stop_service() -> bool:
    return _run_privileged(["systemctl", "stop", DARKOS_SERVICE_NAME])[0]


def wait_until_listening(timeout: float = 60.0) -> bool:
    """Block until the proxy accepts connections.

    The unit is Type=simple, so `systemctl start` returns once ExecStart has
    forked — not once the proxy has bound its port. Without this, start-proxy
    reports success while the very next emulator request is still refused,
    which is easy to hit on hardware slow to start an interpreter.
    """
    config_data = load_config()
    address = (proxy_host(config_data), proxy_port(config_data))
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        with socket.socket() as probe:
            probe.settimeout(1.0)
            if probe.connect_ex(address) == 0:
                return True
        time.sleep(0.2)
    return False


def darkos_service_start() -> dict:
    # `systemctl start` fails outright on a missing unit, so repair it first:
    # covers an install whose unit write was denied, or one removed by hand.
    _ensure_unit_installed()
    already_running = systemd_service_status()
    started = systemd_start_service()
    if started:
        wait_until_listening()
    return {
        "started": started,
        "already_running": already_running,
        "pid": systemd_service_pid(),
    }


def darkos_service_stop() -> dict:
    was_running = systemd_service_status()
    pid = systemd_service_pid() if was_running else None
    stopped = systemd_stop_service()
    return {
        "stopped": stopped,
        "already_stopped": not was_running,
        "pid": pid,
        # systemd escalates to SIGKILL on its own, so there is no separate forced
        # path to report the way the bare-process stop has.
        "forced": False,
    }


def _systemd_show(properties: list[str]) -> dict[str, str]:
    """Read several unit properties in one call.

    Every `_run_privileged` is a sudo + systemctl spawn, and the menu polls
    status on each refresh, so asking once for everything keeps that cheap on
    hardware that is slow to fork.
    """
    values: dict[str, str] = {}
    output = _run_privileged(
        ["systemctl", "show", "--property", ",".join(properties), DARKOS_SERVICE_NAME]
    )[1]
    for line in output.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def darkos_service_status() -> dict:
    config_data = load_config()
    props = _systemd_show(["ActiveState", "MainPID", "ActiveEnterTimestamp"])

    running = props.get("ActiveState") == "active"
    try:
        pid = int(props.get("MainPID") or 0) or None
    except ValueError:
        pid = None
    started_at = (
        _systemd_timestamp_to_unix(props.get("ActiveEnterTimestamp", ""))
        if running
        else None
    )

    return {
        "running": running,
        "pid": pid,
        "startedAt": started_at or int(time.time()),
        "proxyHost": proxy_host(config_data),
        "proxyPort": proxy_port(config_data),
    }
