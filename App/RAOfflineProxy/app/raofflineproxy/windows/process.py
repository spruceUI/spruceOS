from __future__ import annotations

"""Process, socket and file-lock helpers for Windows, where there is no /proc or ps, and where
os.kill() with any signal other than CTRL_C_EVENT/CTRL_BREAK_EVENT calls
TerminateProcess (so the POSIX os.kill(pid, 0) liveness probe would kill the
process it is probing). Only imported on win32."""

import ctypes
from ctypes import wintypes
from pathlib import Path

_PROCESS_TERMINATE = 0x0001
_SYNCHRONIZE = 0x00100000
_PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
_WAIT_TIMEOUT = 0x00000102

_kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
_kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
_kernel32.OpenProcess.restype = wintypes.HANDLE
_kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
_kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
_kernel32.WaitForSingleObject.restype = wintypes.DWORD
_kernel32.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
_kernel32.QueryFullProcessImageNameW.argtypes = [
    wintypes.HANDLE,
    wintypes.DWORD,
    wintypes.LPWSTR,
    ctypes.POINTER(wintypes.DWORD),
]


def _open(pid: int, access: int) -> int | None:
    if pid <= 0:
        return None
    handle = _kernel32.OpenProcess(access, False, pid)
    return handle or None


def process_is_running(pid: int) -> bool:
    handle = _open(pid, _SYNCHRONIZE | _PROCESS_QUERY_LIMITED_INFORMATION)
    if handle is None:
        return False
    try:
        return _kernel32.WaitForSingleObject(handle, 0) == _WAIT_TIMEOUT
    finally:
        _kernel32.CloseHandle(handle)


def process_image_name(pid: int) -> str:
    handle = _open(pid, _PROCESS_QUERY_LIMITED_INFORMATION)
    if handle is None:
        return ""
    try:
        size = wintypes.DWORD(32768)
        buffer = ctypes.create_unicode_buffer(size.value)
        if not _kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            return ""
        return Path(buffer.value).name.lower()
    finally:
        _kernel32.CloseHandle(handle)


def terminate_process(pid: int) -> None:
    handle = _open(pid, _PROCESS_TERMINATE)
    if handle is None:
        return
    try:
        _kernel32.TerminateProcess(handle, 1)
    finally:
        _kernel32.CloseHandle(handle)


class _Overlapped(ctypes.Structure):
    _fields_ = [
        ("Internal", ctypes.c_void_p),
        ("InternalHigh", ctypes.c_void_p),
        ("Offset", wintypes.DWORD),
        ("OffsetHigh", wintypes.DWORD),
        ("hEvent", wintypes.HANDLE),
    ]


_LOCKFILE_FAIL_IMMEDIATELY = 0x00000001
_LOCKFILE_EXCLUSIVE_LOCK = 0x00000002

_kernel32.LockFileEx.argtypes = [
    wintypes.HANDLE,
    wintypes.DWORD,
    wintypes.DWORD,
    wintypes.DWORD,
    wintypes.DWORD,
    ctypes.POINTER(_Overlapped),
]
_kernel32.UnlockFileEx.argtypes = [
    wintypes.HANDLE,
    wintypes.DWORD,
    wintypes.DWORD,
    wintypes.DWORD,
    ctypes.POINTER(_Overlapped),
]


def lock_file(fileno: int, shared: bool) -> bool:
    """Non-blocking flock() stand-in: locks the first byte of the file, shared or
    exclusive. False when another handle holds a conflicting lock."""
    import msvcrt

    flags = _LOCKFILE_FAIL_IMMEDIATELY | (0 if shared else _LOCKFILE_EXCLUSIVE_LOCK)
    overlapped = _Overlapped()
    return bool(
        _kernel32.LockFileEx(msvcrt.get_osfhandle(fileno), flags, 0, 1, 0, ctypes.byref(overlapped))
    )


def unlock_file(fileno: int) -> None:
    import msvcrt

    overlapped = _Overlapped()
    _kernel32.UnlockFileEx(msvcrt.get_osfhandle(fileno), 0, 1, 0, ctypes.byref(overlapped))


# The service runs as `python -m raofflineproxy.main run-service`, or as the
# packaged exe.
SERVICE_IMAGES = ("python.exe", "pythonw.exe", "python3.exe", "raofflineproxy.exe")


class _FileTime(ctypes.Structure):
    _fields_ = [("low", wintypes.DWORD), ("high", wintypes.DWORD)]


_kernel32.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(_FileTime)] * 4


def process_creation_time(pid: int) -> int | None:
    handle = _open(pid, _PROCESS_QUERY_LIMITED_INFORMATION)
    if handle is None:
        return None
    try:
        times = [_FileTime() for _ in range(4)]
        if not _kernel32.GetProcessTimes(handle, *(ctypes.byref(t) for t in times)):
            return None
        return (times[0].high << 32) | times[0].low
    finally:
        _kernel32.CloseHandle(handle)


def _identity_file() -> Path:
    from ..config import CONFIG_DIR

    return CONFIG_DIR / "service.identity.json"


def _wanted_file() -> Path:
    from ..config import CONFIG_DIR

    return CONFIG_DIR / "proxy_wanted"


def proxy_wanted() -> bool:
    """The proxy was started and not stopped since: it was running when Windows
    shut down or crashed, so the sign-in check starts it again."""
    return _wanted_file().exists()


def remember_service(pid: int) -> None:
    """Records the spawned service's creation time next to its pid, so a pid
    Windows later hands to another process can't pass for the service."""
    import json

    _wanted_file().parent.mkdir(parents=True, exist_ok=True)
    _wanted_file().touch()

    created = process_creation_time(pid)
    target = _identity_file()
    if created is None:
        # Without it, an older service's identity would make this one look
        # foreign; with no file, matching falls back to the image name.
        target.unlink(missing_ok=True)
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({"pid": pid, "created": created}), encoding="utf-8")


def process_matches_service(pid: int) -> bool:
    """Reading another process's command line needs PEB access, so the check is
    the image name plus the creation time recorded when the service started."""
    import json

    if process_image_name(pid) not in SERVICE_IMAGES:
        return False
    try:
        identity = json.loads(_identity_file().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        # A service started before identities were recorded: the image is all there is.
        return True
    return identity.get("pid") == pid and identity.get("created") == process_creation_time(pid)


def discover_service_pids(tracked_pid: int | None) -> list[int]:
    """No /proc or ps to scan, so the pid file is the only source."""
    if tracked_pid is not None and process_is_running(tracked_pid) and process_matches_service(tracked_pid):
        return [tracked_pid]
    return []


def detached_popen_kwargs() -> dict:
    """start_new_session/pass_fds are POSIX-only; this is the Windows way to
    start the service without a console that dies with the caller."""
    import subprocess

    return {
        "creationflags": subprocess.DETACHED_PROCESS
        | subprocess.CREATE_NEW_PROCESS_GROUP
        | subprocess.CREATE_NO_WINDOW,
    }


def make_probe_exclusive(sock) -> None:
    """Windows SO_REUSEADDR lets a socket bind over a live listener, so a probe
    using it would report a taken port as free. TIME_WAIT never blocks a bind
    on Windows anyway, so probe exclusively instead."""
    import socket

    sock.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)


# There is no SIGTERM on Windows: os.kill() is TerminateProcess, which would
# skip the service's cleanup (including reverting the emulator configs). So
# stopping is a request file the service polls for, with TerminateProcess
# only as the timeout fallback.
def forget_wanted() -> None:
    """A deliberate stop (menu, tray, Stop script, update): not started again
    at sign-in. Also when nothing was running (it had crashed): stopping says
    the user wants it off."""
    _wanted_file().unlink(missing_ok=True)


def request_stop(stop_file: Path) -> None:
    forget_wanted()
    stop_file.parent.mkdir(parents=True, exist_ok=True)
    stop_file.touch()


def stop_requested(stop_file: Path) -> bool:
    return stop_file.exists()


def clear_stop_request(stop_file: Path) -> None:
    stop_file.unlink(missing_ok=True)


def acquire_file_lock(handle, shared: bool, blocking: bool, should_abort, poll_seconds: float) -> bool:
    """cache_queue's fcntl.flock loop, on LockFileEx."""
    import time

    while True:
        if lock_file(handle.fileno(), shared):
            return True
        if not blocking or (should_abort is not None and should_abort()):
            return False
        time.sleep(poll_seconds)


def pythonw_command(module: str, *args: str) -> list[str]:
    """Runs one of the app's modules without a console window: pythonw.exe
    beside the running interpreter, or the interpreter itself if there's none."""
    import sys

    pythonw = Path(sys.executable).with_name("pythonw.exe")
    return [str(pythonw if pythonw.exists() else sys.executable), "-m", module, *args]


# Start with Windows lives in autostart.py, which survives the portable
# folder changing drive letter; these keep the names platform.py calls.
def autostart_enabled(config_data: dict | None = None) -> bool:
    from . import autostart as windows_autostart

    return windows_autostart.is_enabled(config_data)


def enable_autostart() -> None:
    from . import autostart as windows_autostart

    windows_autostart.enable()


def disable_autostart() -> None:
    from . import autostart as windows_autostart

    windows_autostart.disable()


def processes_from_folder(root: Path, exclude_self: bool = False) -> list[int]:
    """Pids whose executable lives under root (the portable folder's Python)."""
    import os

    psapi = ctypes.WinDLL("psapi")
    pids = (wintypes.DWORD * 4096)()
    needed = wintypes.DWORD()
    if not psapi.EnumProcesses(pids, ctypes.sizeof(pids), ctypes.byref(needed)):
        return []
    prefix = str(root.resolve()).lower().rstrip("\\") + "\\"
    found = []
    for pid in pids[: needed.value // ctypes.sizeof(wintypes.DWORD)]:
        if not pid or (exclude_self and pid == os.getpid()):
            continue
        handle = _open(pid, _PROCESS_QUERY_LIMITED_INFORMATION)
        if handle is None:
            continue
        try:
            size = wintypes.DWORD(32768)
            buffer = ctypes.create_unicode_buffer(size.value)
            if _kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
                if buffer.value.lower().startswith(prefix):
                    found.append(pid)
        finally:
            _kernel32.CloseHandle(handle)
    return found


_kernel32.CreateFileW.argtypes = [
    wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE,
]
_kernel32.CreateFileW.restype = wintypes.HANDLE
_FILE_APPEND_DATA = 0x0004
_FILE_SHARE_ALL = 0x1 | 0x2 | 0x4  # read, write, delete (which allows renaming)
_OPEN_ALWAYS = 4
_INVALID_HANDLE = wintypes.HANDLE(-1).value


def open_log_for_append(path: str, encoding: str | None, errors: str | None):
    """A log file other processes can rename while this one has it open, as on
    Linux. Without FILE_SHARE_DELETE, the service's log can't roll over while
    the menu or a command (each logging to the same file) has it open, and
    grows without limit."""
    import msvcrt
    import os

    handle = _kernel32.CreateFileW(path, _FILE_APPEND_DATA, _FILE_SHARE_ALL, None, _OPEN_ALWAYS, 0, None)
    if handle in (None, _INVALID_HANDLE):
        raise ctypes.WinError(ctypes.get_last_error())
    fd = msvcrt.open_osfhandle(handle, os.O_APPEND | os.O_WRONLY)
    return open(fd, "a", encoding=encoding, errors=errors)


def rotating_log_handler(path: str, max_bytes: int, backup_count: int, encoding: str):
    import logging.handlers

    class SharedRotatingFileHandler(logging.handlers.RotatingFileHandler):
        def _open(self):
            return open_log_for_append(self.baseFilename, self.encoding, self.errors)

    return SharedRotatingFileHandler(path, maxBytes=max_bytes, backupCount=backup_count, encoding=encoding)
