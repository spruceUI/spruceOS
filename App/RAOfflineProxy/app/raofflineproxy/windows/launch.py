from __future__ import annotations

"""Start and stop for the portable Windows folder, run by its
"Start RAOfflineProxy.cmd" and "Stop RAOfflineProxy.cmd".

  python -m raofflineproxy.windows.launch            start: proxy, tray, menu
  python -m raofflineproxy.windows.launch --autostart  start without the menu (after an update)
  python -m raofflineproxy.windows.launch --sign-in   the sign-in check (see sign_in)
  python -m raofflineproxy.windows.launch --uninstall  remove what it added to Windows (see uninstall)
  python -m raofflineproxy.windows.launch --stop     stop everything from this folder

Settings and cache live in the folder's data/; the only thing added to
Windows is the sign-in check, which --uninstall removes. The first
start finds the emulators; every start refreshes where the folder is, so Start
with Windows keeps working after the folder (or its USB stick) moves."""

import platform
import subprocess
import sys
import time

from ..config import load_config, save_config

# The PC the emulator paths in data/ were found on.
MACHINE_KEY = "emulators_found_on"


def _run_cli(*args: str) -> None:
    subprocess.run(
        [sys.executable, "-m", "raofflineproxy.main", *args],
        creationflags=subprocess.CREATE_NO_WINDOW,
        check=False,
    )


def start(open_menu: bool) -> None:
    from . import autostart as windows_autostart
    from . import emulators as windows_emulators
    from .process import pythonw_command
    from .tray import proxy_running

    config_data = load_config()
    machine = platform.node()
    if not windows_emulators.emulator_state(config_data) or config_data.get(MACHINE_KEY) != machine:
        # First start from this folder, or the folder was copied from another
        # PC: find RetroArch, Dolphin and PPSSPP here. Emulators whose exe still
        # exists keep their on/off choice; the cache and settings carry over.
        windows_emulators.detect_and_save()
        config_data = load_config()
        config_data[MACHINE_KEY] = machine
        save_config(config_data)
    windows_autostart.refresh_location()

    if not proxy_running():
        _run_cli("start-proxy")
    # The tray exits at once if one is already running (it holds a mutex).
    subprocess.Popen(pythonw_command("raofflineproxy.windows.tray"))
    if open_menu:
        subprocess.Popen(pythonw_command("raofflineproxy.main", "menu"))


def stop() -> None:
    """Stops the proxy (which puts the emulator configs back), then closes the
    tray and menu still running from this folder."""
    from .tray import QUIT_REQUEST_FILE

    _run_cli("stop-proxy")
    QUIT_REQUEST_FILE.parent.mkdir(parents=True, exist_ok=True)
    QUIT_REQUEST_FILE.touch()
    from .process import processes_from_folder, terminate_process
    from .paths import portable_root

    root = portable_root()
    if root is None:
        return
    # The tray notices its quit file within a poll; anything left (a menu) is closed.
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline and processes_from_folder(root, exclude_self=True):
        time.sleep(0.5)
    for pid in processes_from_folder(root, exclude_self=True):
        terminate_process(pid)


def sign_in() -> None:
    """Runs at every sign-in, so a crash or power loss never leaves the
    emulators pointed at a proxy that isn't running: starts it when Start with
    Windows is on or it was running when Windows went down, and otherwise
    quietly puts the emulator configs back."""
    from . import autostart as windows_autostart
    from .process import proxy_wanted

    if windows_autostart.is_enabled() or proxy_wanted():
        start(open_menu=False)
    else:
        _run_cli("stop-proxy")


def uninstall() -> int:
    """Removes the sign-in check (Run entry, logon task, launcher), for deleting
    the folder afterwards. Nothing else is installed outside it."""
    from . import autostart as windows_autostart

    if not windows_autostart.remove_sign_in_check():
        print("Not removed: the admin prompt to remove the sign-in task was declined.")
        return 1
    print("Removed RAOfflineProxy from Windows sign-in.")
    return 0


def main(argv: list[str]) -> int:
    if "--uninstall" in argv:
        return uninstall()
    if "--stop" in argv:
        stop()
    elif "--sign-in" in argv:
        sign_in()
    else:
        start(open_menu="--autostart" not in argv)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
