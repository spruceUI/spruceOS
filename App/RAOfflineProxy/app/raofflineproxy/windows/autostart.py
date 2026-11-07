from __future__ import annotations

"""Start with Windows for the portable folder, surviving a changed drive letter.

The sign-in entry (the per-user Run key, no admin rights) doesn't hold the
folder's path. It runs a small launcher kept in %LOCALAPPDATA%, which looks for
the folder: first where it last was, then at the same path on every other
drive letter, matching the id written into the folder's portable.txt. So
E:\\Games\\RAOfflineProxy that comes back as F:\\Games\\RAOfflineProxy is still
found, and with the stick unplugged the launcher quietly does nothing. Only
the drive with the folder's volume serial is searched, so network drives
aren't probed and a backup copy on another drive is never started instead.

Every start records where the folder is (refresh_location), so after moving it
somewhere else the next manual start is enough. Turning Start with Windows off
removes both the entry and the launcher, leaving nothing behind."""

import json
import os
import subprocess
import uuid
from pathlib import Path

from ..config import load_config, save_config
from .paths import PORTABLE_MARKER, portable_root

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
RUN_VALUE = "RAOfflineProxy"
ID_PREFIX = "id="
# Windows 10 2004 and later have conhost --headless.
HEADLESS_CONHOST_BUILD = 19041

LAUNCHER_SCRIPT = r"""
# RAOfflineProxy sign-in launcher. Finds the portable folder (which may have
# changed drive letter) and starts it. Written by the app; safe to delete.
$state = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'location.json') | ConvertFrom-Json
function Test-Folder($root) {
    $marker = Join-Path $root 'portable.txt'
    (Test-Path -LiteralPath $marker) -and
        ((Get-Content -LiteralPath $marker) -contains ('id=' + $state.id))
}
$candidates = @($state.root)
# Only the drive with the folder's volume serial (a stick keeps it under any
# letter); network drives (DriveType 4) are never probed, as they can stall.
foreach ($disk in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 2 OR DriveType = 3') {
    if (-not $state.volume -or $disk.VolumeSerialNumber -eq $state.volume) {
        $candidates += Join-Path ($disk.DeviceID + '\') $state.relative
    }
}
foreach ($root in $candidates) {
    if (Test-Folder $root) {
        Start-Process -FilePath (Join-Path $root 'python\pythonw.exe') `
            -ArgumentList '-m', 'raofflineproxy.windows.launch', '--sign-in' `
            -WorkingDirectory $root
        break
    }
}
"""


def launcher_dir() -> Path:
    base = Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local")
    return base / "RAOfflineProxy-autostart"


def folder_id(root: Path) -> str:
    """The id in portable.txt, added the first time it's needed."""
    marker = root / PORTABLE_MARKER
    lines = marker.read_text(encoding="utf-8").splitlines() if marker.exists() else []
    for line in lines:
        if line.startswith(ID_PREFIX):
            return line[len(ID_PREFIX):].strip()
    new_id = uuid.uuid4().hex
    marker.write_text("\n".join([*lines, ID_PREFIX + new_id]) + "\n", encoding="utf-8")
    return new_id


def volume_serial(root: Path) -> str | None:
    """The drive's volume serial as Win32_LogicalDisk shows it (8 hex digits).
    It stays the same when a USB stick comes back under another letter."""
    import ctypes

    drive = os.path.splitdrive(str(root))[0] + os.sep
    serial = ctypes.c_uint32()
    if not ctypes.windll.kernel32.GetVolumeInformationW(drive, None, 0, ctypes.byref(serial), None, None, None, 0):
        return None
    return f"{serial.value:08X}"


def _write_location(root: Path) -> None:
    drive, relative = os.path.splitdrive(str(root))
    folder = launcher_dir()
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "location.json").write_text(
        json.dumps(
            {
                "id": folder_id(root),
                "root": str(root),
                "relative": relative.lstrip("\\/"),
                "volume": volume_serial(root),
            }
        ),
        encoding="utf-8",
    )


TASK_NAME = "RAOfflineProxy"
# Tests (and anyone who wants no admin prompt) can keep to the Run entry.
MODE_ENV = "RAOFFLINEPROXY_AUTOSTART_MODE"

# Registers the logon task. Creating a logon-triggered task needs admin rights,
# so this runs elevated, once, through the standard UAC prompt. The task itself
# runs as the signed-in user, unelevated, with no time limit and on battery.
REGISTER_SCRIPT = r"""
$ErrorActionPreference = 'Stop'
$action = New-ScheduledTaskAction -Execute $Execute -Argument $Arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $User
$principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'RAOfflineProxy' -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null
"""
REMOVE_SCRIPT = r"""
$ErrorActionPreference = 'Stop'
Unregister-ScheduledTask -TaskName 'RAOfflineProxy' -Confirm:$false
"""


def _ps_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _launcher_command() -> list[str]:
    import sys

    script = launcher_dir() / "start.ps1"
    command = [
        "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", str(script),
    ]
    # conhost --headless keeps PowerShell's console from flashing at sign-in.
    # Early Windows 10 builds lack it; there the console just flashes briefly.
    if sys.getwindowsversion().build >= HEADLESS_CONHOST_BUILD:
        command = ["conhost.exe", "--headless", *command]
    return command


def _run_value() -> str:
    return subprocess.list2cmdline(_launcher_command())


def _run_elevated(script: str, **values: str) -> bool:
    """Runs a PowerShell script elevated (one UAC prompt) and waits. The script
    goes inline as -EncodedCommand, never through a file: a file in a folder
    the user can write to could be swapped before the elevated PowerShell
    reads it. values become $name variables set ahead of the script. False
    when the prompt was declined or the script failed."""
    import base64

    prelude = "".join(f"${name} = {_ps_literal(value)}\n" for name, value in values.items())
    encoded = base64.b64encode((prelude + script.lstrip()).encode("utf-16-le")).decode("ascii")
    outer = (
        "try { $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden "
        f"-ArgumentList '-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand {encoded}'; "
        "exit $p.ExitCode } catch { exit 1223 }"
    )
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", outer],
        capture_output=True,
        creationflags=subprocess.CREATE_NO_WINDOW,
        timeout=300,
        check=False,
    )
    return result.returncode == 0


# The Settings screen asks every frame; schtasks.exe takes a moment to start.
_task_cache: tuple[float, bool] | None = None
TASK_CACHE_SECONDS = 5


def task_exists() -> bool:
    import time

    # RAOFFLINEPROXY_AUTOSTART_MODE=run: the Run entry only, no logon task, so no
    # admin prompt. The e2e tests set it, so they never touch (or see) a task
    # that's on the machine they run on.
    if os.environ.get(MODE_ENV) == "run":
        return False
    global _task_cache
    if _task_cache is not None and time.monotonic() - _task_cache[0] < TASK_CACHE_SECONDS:
        return _task_cache[1]
    result = subprocess.run(
        ["schtasks.exe", "/Query", "/TN", TASK_NAME],
        capture_output=True,
        creationflags=subprocess.CREATE_NO_WINDOW,
        check=False,
    )
    _task_cache = (time.monotonic(), result.returncode == 0)
    return _task_cache[1]


def _forget_task() -> None:
    global _task_cache
    _task_cache = None


def _run_entry_exists() -> bool:
    import winreg

    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
            winreg.QueryValueEx(key, RUN_VALUE)
            return True
    except OSError:
        return False


# The setting in config.json. The sign-in check is installed either way; this
# decides whether it starts the proxy or only puts the emulator configs back.
SETTING_KEY = "start_with_windows"
# Set by remove_sign_in_check(), so starts don't add the check back.
CHECK_REMOVED_KEY = "sign_in_check_removed"


def check_removed(config_data: dict) -> bool:
    return bool(config_data.get(CHECK_REMOVED_KEY))


def is_enabled(config_data: dict | None = None) -> bool:
    config_data = load_config() if config_data is None else config_data
    if SETTING_KEY in config_data:
        return bool(config_data[SETTING_KEY])
    # Installed before the setting existed: a sign-in entry meant it was on.
    return _run_entry_exists() or task_exists()


def _set_setting(enabled: bool) -> None:
    config_data = load_config()
    config_data[SETTING_KEY] = enabled
    save_config(config_data)


def _set_run_entry(enabled: bool) -> None:
    import winreg

    if enabled:
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
            winreg.SetValueEx(key, RUN_VALUE, 0, winreg.REG_SZ, _run_value())
        return
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as key:
            winreg.DeleteValue(key, RUN_VALUE)
    except FileNotFoundError:
        pass


def enable() -> str:
    """Turns Start with Windows on. Prefers a logon task, which Windows' Xbox
    full screen experience still runs (it skips the Run list's startup apps);
    falls back to the Run entry if the admin prompt is declined. Returns
    "task" or "run" for which one it used."""
    root = portable_root()
    if root is None:
        raise OSError("Start with Windows needs the portable RAOfflineProxy folder")
    config_data = load_config()
    config_data[SETTING_KEY] = True
    config_data.pop(CHECK_REMOVED_KEY, None)
    save_config(config_data)
    _write_location(root)
    (launcher_dir() / "start.ps1").write_text(LAUNCHER_SCRIPT.lstrip(), encoding="utf-8")

    _forget_task()
    if task_exists():
        return "task"  # kept from before (turning it off keeps it): no admin prompt needed
    if os.environ.get(MODE_ENV) != "run":
        command = _launcher_command()
        # Passed in, not read inside: an elevated prompt answered with another
        # admin's password would otherwise register the task for that account.
        domain, name = os.environ.get("USERDOMAIN", ""), os.environ.get("USERNAME", "")
        user = f"{domain}\\{name}" if domain else name
        if _run_elevated(
            REGISTER_SCRIPT, User=user, Execute=command[0], Arguments=subprocess.list2cmdline(command[1:])
        ):
            _set_run_entry(False)  # one way to start, not two
            return "task"
    _set_run_entry(True)
    return "run"


def disable() -> None:
    """Turns the setting off. The sign-in check stays (the logon task too, with
    no admin prompt to remove it): from now on it starts the proxy only if it
    was running when Windows went down, and otherwise puts the emulator configs
    back. remove_sign_in_check() takes it away."""
    _set_setting(False)


def remove_sign_in_check() -> bool:
    """Removes everything RAOfflineProxy adds to Windows: the Run entry, the
    logon task (one admin prompt, when there is one) and the launcher in
    %LOCALAPPDATA%. Start with Windows goes off, and starts don't put the check
    back until it's turned on again. False when the admin prompt was declined;
    the task is then left, and so is everything else."""
    import shutil

    _forget_task()
    if task_exists() and not _run_elevated(REMOVE_SCRIPT):
        return False
    _forget_task()
    _set_run_entry(False)
    shutil.rmtree(launcher_dir(), ignore_errors=True)
    config_data = load_config()
    config_data[SETTING_KEY] = False
    config_data[CHECK_REMOVED_KEY] = True
    save_config(config_data)
    return True


def ensure_sign_in_check(root: Path) -> None:
    """Installs the sign-in check when nothing runs at sign-in yet: the Run
    entry, which needs no admin rights (only the logon task, from turning Start
    with Windows on, also runs in Xbox full screen mode)."""
    _write_location(root)
    (launcher_dir() / "start.ps1").write_text(LAUNCHER_SCRIPT.lstrip(), encoding="utf-8")
    if not task_exists() and not _run_entry_exists():
        _set_run_entry(True)


def refresh_location() -> None:
    """Called on every start, so the launcher's first guess is where the folder
    is now, the launcher itself is the current version's, and the sign-in check
    is in place."""
    root = portable_root()
    if root is None:
        return
    config_data = load_config()
    if check_removed(config_data):
        return  # removed on purpose: back only when Start with Windows is turned on
    if SETTING_KEY not in config_data:
        _set_setting(is_enabled())  # before the check is added, which would read as "on"
    ensure_sign_in_check(root)
