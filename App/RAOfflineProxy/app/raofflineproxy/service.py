from __future__ import annotations

import logging
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from .boot import LISTEN_FD_ENV
from .config import (
    CONFIG_DIR,
    DATABASE_FILE,
    LOG_FILE,
    configure_logging,
    proxy_host,
    proxy_port,
    running_on_darkos,
)
from .darkos_service import (
    darkos_service_start,
    darkos_service_status,
    darkos_service_stop,
)
from .proxy_service import run_proxy_service
from .state import (
    clear_pid,
    clear_service_status,
    load_pid,
    load_service_status,
    save_pid,
    save_service_status,
)

SERVICE_COMMAND_MARKERS = [
    "-m raofflineproxy.main run-service",
    "-m linux.raofflineproxy.main run-service",
]


def process_is_running(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def process_has_exited(pid: int) -> bool:
    proc_state = _proc_state(pid)
    if proc_state is not None:
        return proc_state == "Z"
    return not process_is_running(pid)


def process_matches_service(pid: int) -> bool:
    command = _proc_command_line(pid)
    if command:
        return any(marker in command for marker in SERVICE_COMMAND_MARKERS)
    return False


def process_is_orphaned(pid: int) -> bool:
    """True if the process still has our log/database files open by fd, but
    the paths were deleted (e.g. by a reinstall that removed the app folder
    while this process — from the previous install — was still running)."""
    fd_dir = Path("/proc") / str(pid) / "fd"
    watched = (str(LOG_FILE), str(DATABASE_FILE))
    try:
        fd_entries = list(fd_dir.iterdir())
    except OSError:
        return False

    for fd_entry in fd_entries:
        try:
            target = os.readlink(fd_entry)
        except OSError:
            continue
        if target.endswith(" (deleted)") and target[: -len(" (deleted)")] in watched:
            return True
    return False


def discover_service_pids() -> list[int]:
    pids: set[int] = set()

    proc_pid = _discover_service_pid_from_proc()
    if proc_pid is not None:
        pids.add(proc_pid)

    try:
        output = subprocess.check_output(["ps", "-eo", "pid=,args="], text=True)
    except (subprocess.CalledProcessError, OSError):
        output = ""

    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        pid_text, _, command = line.partition(" ")
        if not pid_text or not command:
            continue
        if not any(marker in command for marker in SERVICE_COMMAND_MARKERS):
            continue
        try:
            pids.add(int(pid_text))
        except ValueError:
            continue

    return sorted(
        pid
        for pid in pids
        if process_is_running(pid) and process_matches_service(pid)
    )


def discover_service_pid() -> int | None:
    pids = discover_service_pids()
    if not pids:
        return None
    return pids[0]


def tracked_or_discovered_service_pid() -> int | None:
    pid = load_pid()
    if pid is not None and process_is_running(pid) and process_matches_service(pid):
        return pid
    return discover_service_pid()


def _proc_state(pid: int) -> str | None:
    stat_path = Path("/proc") / str(pid) / "stat"
    try:
        content = stat_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    _, _, remainder = content.partition(") ")
    if not remainder:
        return None

    fields = remainder.split()
    if not fields:
        return None
    return fields[0]


def _proc_command_line(pid: int) -> str:
    cmdline_path = Path("/proc") / str(pid) / "cmdline"
    try:
        raw = cmdline_path.read_bytes()
    except OSError:
        return ""

    parts = [
        part.decode("utf-8", errors="replace") for part in raw.split(b"\x00") if part
    ]
    return " ".join(parts)


def _discover_service_pid_from_proc() -> int | None:
    proc_root = Path("/proc")
    if not proc_root.exists():
        return None

    try:
        entries = list(proc_root.iterdir())
    except OSError:
        return None

    for entry in entries:
        if not entry.name.isdigit():
            continue

        command = _proc_command_line(int(entry.name))
        if not command:
            continue
        if any(marker in command for marker in SERVICE_COMMAND_MARKERS):
            return int(entry.name)

    return None


def save_running_service_state(
    pid: int, config_data: dict, started_at: int | None = None
) -> None:
    save_pid(pid)
    save_service_status(
        {
            "running": True,
            "pid": pid,
            "startedAt": started_at or int(time.time()),
            "proxyHost": proxy_host(config_data),
            "proxyPort": proxy_port(config_data),
        }
    )


def _kill_orphaned_pid(pid: int, timeout_seconds: int = 5) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return

    deadline = time.time() + timeout_seconds
    while time.time() < deadline and not process_has_exited(pid):
        time.sleep(0.25)

    if not process_has_exited(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def port_is_available(config_data: dict) -> bool:
    import socket

    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        # Same option the real server binds with (ThreadingTCPServer.allow_reuse_address),
        # so a port left in TIME_WAIT by our own previous run is not reported as taken.
        # It still fails against a live listener, which is the case worth catching.
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind((proxy_host(config_data), proxy_port(config_data)))
    except OSError:
        return False
    finally:
        probe.close()
    return True


def start_service_process(config_data: dict) -> dict:
    if running_on_darkos():
        return darkos_service_start()

    discovered_pids = discover_service_pids()
    healthy_pids = [pid for pid in discovered_pids if not process_is_orphaned(pid)]
    if healthy_pids:
        pid = healthy_pids[0]
        save_running_service_state(pid, config_data)
        return {"started": False, "already_running": True, "pid": pid, "pids": healthy_pids}

    for orphaned_pid in discovered_pids:
        _kill_orphaned_pid(orphaned_pid)
    if discovered_pids:
        clear_pid()
        clear_service_status()

    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    listen_fd = os.environ.get(LISTEN_FD_ENV)
    # The service is spawned detached, so a failed bind would only ever surface as a bare
    # errno in service.log while the menu reports a successful start. Check here, where
    # the error can still be shown, unless the boot entrypoint already holds the socket.
    if not listen_fd and not port_is_available(config_data):
        port = proxy_port(config_data)
        raise RuntimeError(
            f"Port {port} already in use - change proxy_port in config.json"
        )
    pass_fds: tuple[int, ...] = ()
    env = None
    if listen_fd:
        # Hand the already-listening socket from the boot entrypoint to the
        # service so the port never closes between the two processes.
        pass_fds = (int(listen_fd),)
        env = {**os.environ, LISTEN_FD_ENV: listen_fd}

    with LOG_FILE.open("a", encoding="utf-8") as log_handle:
        process = subprocess.Popen(
            [sys.executable, "-m", "raofflineproxy.main", "run-service"],
            stdout=log_handle,
            stderr=log_handle,
            stdin=subprocess.DEVNULL,
            close_fds=True,
            start_new_session=True,
            pass_fds=pass_fds,
            env=env,
        )

    save_running_service_state(process.pid, config_data)
    return {"started": True, "already_running": False, "pid": process.pid}


def stop_service_process(timeout_seconds: int = 10) -> dict:
    if running_on_darkos():
        return darkos_service_stop()

    pids = discover_service_pids()
    tracked_pid = load_pid()
    if tracked_pid is not None and tracked_pid not in pids:
        pids = [tracked_pid, *pids]

    pids = [
        pid
        for pid in dict.fromkeys(pids)
        if process_is_running(pid) and process_matches_service(pid)
    ]

    if not pids:
        clear_pid()
        clear_service_status()
        return {"stopped": False, "already_stopped": True}

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass

    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        remaining = [pid for pid in pids if not process_has_exited(pid)]
        if not remaining:
            clear_pid()
            clear_service_status()
            return {"stopped": True, "already_stopped": False, "pid": pids[0], "pids": pids}
        time.sleep(0.25)

    remaining = [pid for pid in pids if not process_has_exited(pid)]
    for pid in remaining:
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass

    clear_pid()
    clear_service_status()
    return {
        "stopped": True,
        "already_stopped": False,
        "pid": pids[0],
        "pids": pids,
        "forced": True,
    }


def service_status() -> dict:
    if running_on_darkos():
        return darkos_service_status()

    pid = tracked_or_discovered_service_pid()
    status = load_service_status() or {}
    running = pid is not None and process_is_running(pid)

    if not running:
        clear_pid()
        status["running"] = False
        if pid is not None or "pid" in status:
            status["pid"] = pid
        save_service_status(status)
    else:
        if "startedAt" not in status:
            status["startedAt"] = int(time.time())
        status["running"] = True
        status["pid"] = pid
        status["proxyHost"] = status.get("proxyHost", "127.0.0.1")
        status["proxyPort"] = int(status.get("proxyPort", 8080))
        save_pid(pid)
        save_service_status(status)

    return status


def run_service_foreground(config_data: dict) -> None:
    stop_requested = False

    def handle_signal(_signum: int, _frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    configure_logging()
    logging.getLogger("raofflineproxy").info(
        "Service logging initialized configDir=%s logFile=%s",
        CONFIG_DIR,
        LOG_FILE,
    )

    stop_event = __import__("threading").Event()

    def watch_stop() -> None:
        while not stop_requested:
            time.sleep(0.2)
        stop_event.set()

    watcher = __import__("threading").Thread(target=watch_stop, daemon=True)
    watcher.start()

    save_service_status(
        {
            "running": True,
            "pid": os.getpid(),
            "startedAt": int(time.time()),
            "proxyHost": proxy_host(config_data),
            "proxyPort": proxy_port(config_data),
        }
    )
    save_pid(os.getpid())

    try:
        run_proxy_service(config_data, stop_event)
    finally:
        clear_pid()
        save_service_status(
            {
                "running": False,
                "pid": os.getpid(),
                "stoppedAt": int(time.time()),
            }
        )
