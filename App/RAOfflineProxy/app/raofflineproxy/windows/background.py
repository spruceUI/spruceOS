from __future__ import annotations

"""Smart Cache in the background on Windows, as the Android app runs it in its
service: the menu starts the existing run-smart-cache command as its own
process and returns at once, so the menu stays responsive and can be closed.
Progress goes to a file the menu and the tray read; stopping uses the
command's own abort file (RAOFFLINEPROXY_ABORT_FILE)."""

import json
import os
import subprocess

from ..config import CONFIG_DIR

PROGRESS_FILE = CONFIG_DIR / "smart_cache.progress.jsonl"
# The command's errors: it exits with one when offline or not logged in.
ERROR_FILE = CONFIG_DIR / "smart_cache.errors.txt"
# How long a finished run's result stays on screen.
RESULT_SHOWN_SECONDS = 60 * 60
PID_FILE = CONFIG_DIR / "smart_cache.pid"
ABORT_FILE = CONFIG_DIR / "smart_cache.abort"


def running_pid() -> int | None:
    from .process import process_image_name, process_is_running

    try:
        pid = int(PID_FILE.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return None
    if process_is_running(pid) and process_image_name(pid) in ("python.exe", "pythonw.exe"):
        return pid
    return None


def is_running() -> bool:
    return running_pid() is not None


def start() -> bool:
    """False when a run is already going."""
    from .process import detached_popen_kwargs, pythonw_command

    if is_running():
        return False
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    ABORT_FILE.unlink(missing_ok=True)
    env = {**os.environ, "RAOFFLINEPROXY_ABORT_FILE": str(ABORT_FILE)}
    with PROGRESS_FILE.open("w", encoding="utf-8") as progress, ERROR_FILE.open("w", encoding="utf-8") as errors:
        process = subprocess.Popen(
            pythonw_command("raofflineproxy.main", "run-smart-cache"),
            stdout=progress,
            stderr=errors,
            stdin=subprocess.DEVNULL,
            env=env,
            **detached_popen_kwargs(),
        )
    PID_FILE.write_text(str(process.pid), encoding="utf-8")
    return True


def request_stop() -> None:
    if is_running():
        ABORT_FILE.touch()


def last_event() -> dict | None:
    """The newest progress or result line."""
    try:
        lines = PROGRESS_FILE.read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    for line in reversed(lines):
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if isinstance(event, dict) and event.get("type") in ("progress", "result"):
            return event
    return None


def failure_text() -> str | None:
    """Why the last run stopped early, e.g. "Smart Cache requires an online
    connection"."""
    try:
        lines = [line.strip() for line in ERROR_FILE.read_text(encoding="utf-8", errors="replace").splitlines()]
    except OSError:
        return None
    # main prints the error first, then a usage footer ("Optional config
    # file: ..."); a crash prints a traceback ending in "SomeError: message".
    if lines and lines[0].startswith("Traceback"):
        last = next((line for line in reversed(lines) if line), "")
        return last.split(": ", 1)[-1] or None
    return next((line for line in lines if line and not line.startswith("Optional config file")), None)


def status_text() -> str | None:
    """A one-line status while a run is going, or for an hour after it ends."""
    import time

    running = is_running()
    if not running:
        try:
            if time.time() - PROGRESS_FILE.stat().st_mtime > RESULT_SHOWN_SECONDS:
                return None
        except OSError:
            return None
    event = last_event()
    if event is None or (event["type"] != "result" and not running):
        if running:
            return "Smart Cache: starting"
        failure = failure_text()
        return f"Smart Cache failed: {failure}" if failure else None
    if event["type"] == "result":
        if running:
            return None
        text = f"Smart Cache done: {event.get('cached', 0)} cached"
        if event.get("queued"):
            text += f", {event['queued']} queued"
        return text
    if not running:
        return None
    phase = "Hashing" if event.get("phase") == "hashing" else "Caching"
    return f"Smart Cache: {phase} {event.get('scanned', 0)}/{event.get('total', 0)}"
