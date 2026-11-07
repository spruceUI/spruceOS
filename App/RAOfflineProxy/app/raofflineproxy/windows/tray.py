from __future__ import annotations

"""Tray icon and notifications on Windows, the counterpart of the Android
app's foreground-service notification: online/offline, caching progress and
pending awards in the tooltip, and a Windows notification when the proxy goes
offline or back online, starts caching, queues an award, syncs awards or
fails to sync one. Right-click for the menu, start/stop and exit.

Runs as its own process (python -m raofflineproxy.windows.tray), started at
sign-in by Start with Windows and by the Start script. It only reads the proxy's
state files and database, every few seconds, so it can come and go without
affecting the proxy. Win32 through ctypes, so nothing extra to install."""

import ctypes
import subprocess
import sys
import threading
from ctypes import wintypes
from pathlib import Path

from .. import cache_queue
from . import background as windows_background
from . import history as windows_history
from ..config import CONFIG_DIR, ONLINE_STATE_FILE
from ..service import process_is_running, process_matches_service
from ..state import load_json_file, load_pid
from ..storage import PENDING_AWARD_STATUS_PENDING, Storage

POLL_MS = 5000
ICON_FILE = CONFIG_DIR / "tray.ico"
# The menu's "Exit completely" asks the tray to close through this file, which
# the tray checks on every poll.
QUIT_REQUEST_FILE = CONFIG_DIR / "tray.quit"
MUTEX_NAME = "Local\\RAOfflineProxyTray"

WM_USER = 0x0400
WM_TRAY = WM_USER + 1
WM_TIMER = 0x0113
WM_COMMAND = 0x0111
WM_DESTROY = 0x0002
WM_LBUTTONDBLCLK = 0x0203
WM_RBUTTONUP = 0x0205
NIN_BALLOONUSERCLICK = WM_USER + 5
NIM_ADD, NIM_MODIFY, NIM_DELETE = 0, 1, 2
NIF_MESSAGE, NIF_ICON, NIF_TIP, NIF_INFO = 0x1, 0x2, 0x4, 0x10
NIIF_INFO, NIIF_WARNING = 0x1, 0x2
MF_STRING, MF_GRAYED, MF_SEPARATOR = 0x0, 0x1, 0x800
TPM_RETURNCMD, TPM_RIGHTBUTTON = 0x100, 0x2
IMAGE_ICON, LR_LOADFROMFILE, LR_DEFAULTSIZE = 1, 0x10, 0x40
ERROR_ALREADY_EXISTS = 183

CMD_OPEN, CMD_TOGGLE, CMD_EXIT, CMD_STOP_CACHE = 1, 2, 3, 4

LRESULT = ctypes.c_ssize_t
WNDPROC = ctypes.WINFUNCTYPE(LRESULT, wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM)

user32 = ctypes.WinDLL("user32", use_last_error=True)
shell32 = ctypes.WinDLL("shell32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
user32.DefWindowProcW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user32.RegisterWindowMessageW.restype = wintypes.UINT
# Sent to every top-level window when the taskbar is (re)created: at sign-in the
# tray can start before it exists, and Explorer can restart. Icons added before
# then are gone, so they're added again on this.
TASKBAR_CREATED = user32.RegisterWindowMessageW("TaskbarCreated")
user32.DefWindowProcW.restype = LRESULT
user32.CreateWindowExW.restype = wintypes.HWND
user32.LoadImageW.restype = wintypes.HANDLE
user32.LoadIconW.restype = wintypes.HANDLE
user32.CreatePopupMenu.restype = wintypes.HMENU
user32.TrackPopupMenu.argtypes = [
    wintypes.HMENU, wintypes.UINT, ctypes.c_int, ctypes.c_int, ctypes.c_int, wintypes.HWND, ctypes.c_void_p,
]
kernel32.CreateMutexW.restype = wintypes.HANDLE


class WNDCLASSW(ctypes.Structure):
    _fields_ = [
        ("style", wintypes.UINT),
        ("lpfnWndProc", WNDPROC),
        ("cbClsExtra", ctypes.c_int),
        ("cbWndExtra", ctypes.c_int),
        ("hInstance", wintypes.HINSTANCE),
        ("hIcon", wintypes.HICON),
        ("hCursor", wintypes.HANDLE),
        ("hbrBackground", wintypes.HBRUSH),
        ("lpszMenuName", wintypes.LPCWSTR),
        ("lpszClassName", wintypes.LPCWSTR),
    ]


class GUID(ctypes.Structure):
    _fields_ = [("a", wintypes.DWORD), ("b", wintypes.WORD), ("c", wintypes.WORD), ("d", ctypes.c_ubyte * 8)]


class NOTIFYICONDATAW(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("hWnd", wintypes.HWND),
        ("uID", wintypes.UINT),
        ("uFlags", wintypes.UINT),
        ("uCallbackMessage", wintypes.UINT),
        ("hIcon", wintypes.HICON),
        ("szTip", wintypes.WCHAR * 128),
        ("dwState", wintypes.DWORD),
        ("dwStateMask", wintypes.DWORD),
        ("szInfo", wintypes.WCHAR * 256),
        ("uVersion", wintypes.UINT),
        ("szInfoTitle", wintypes.WCHAR * 64),
        ("dwInfoFlags", wintypes.DWORD),
        ("guidItem", GUID),
        ("hBalloonIcon", wintypes.HICON),
    ]


class POINT(ctypes.Structure):
    _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]


class MSG(ctypes.Structure):
    _fields_ = [
        ("hwnd", wintypes.HWND),
        ("message", wintypes.UINT),
        ("wParam", wintypes.WPARAM),
        ("lParam", wintypes.LPARAM),
        ("time", wintypes.DWORD),
        ("pt", POINT),
    ]


# State -------------------------------------------------------------------------------


def write_icon() -> Path | None:
    """An .ico wrapping a 64px PNG of the app logo (ICO files may hold PNG data)."""
    logo = Path(__file__).resolve().parent.parent / "logo-320.png"
    if ICON_FILE.exists() or not logo.exists():
        return ICON_FILE if ICON_FILE.exists() else None
    try:
        import io

        import pygame

        image = pygame.transform.smoothscale(pygame.image.load(str(logo)), (64, 64))
        buffer = io.BytesIO()
        pygame.image.save(image, buffer, "png")
        png = buffer.getvalue()
        header = (0).to_bytes(2, "little") + (1).to_bytes(2, "little") + (1).to_bytes(2, "little")
        entry = bytes([64, 64, 0, 0]) + (1).to_bytes(2, "little") + (32).to_bytes(2, "little")
        entry += len(png).to_bytes(4, "little") + (22).to_bytes(4, "little")
        ICON_FILE.parent.mkdir(parents=True, exist_ok=True)
        ICON_FILE.write_bytes(header + entry + png)
        return ICON_FILE
    except Exception:
        return None


def proxy_running() -> bool:
    """Read-only, unlike service.service_status(), which rewrites the status and
    pid files the service and CLI own."""
    pid = load_pid()
    return pid is not None and process_is_running(pid) and process_matches_service(pid)


def read_snapshot(storage: Storage) -> dict:
    online = (load_json_file(ONLINE_STATE_FILE) or {}).get("online")
    awards = storage.get_pending_awards()
    pending = [a for a in awards if a.get("status", PENDING_AWARD_STATUS_PENDING) == PENDING_AWARD_STATUS_PENDING]
    return {
        "running": proxy_running(),
        "online": online,
        "pending": len(pending),
        "failed": {int(a.get("achievementId", 0)): a.get("lastError") for a in pending if a.get("lastError")},
        "queued": cache_queue.count(storage),
        # Written only when an award reaches RetroAchievements, unlike the pending
        # count, which also drops when awards are deleted.
        "synced": windows_history.synced_count(),
        "smart_cache": windows_background.is_running(),
        "smart_cache_text": windows_background.status_text(),
    }


def tooltip(snapshot: dict) -> str:
    if not snapshot["running"]:
        return "RAOfflineProxy: stopped"
    text = "RAOfflineProxy: " + ("online, forwarding to RA" if snapshot["online"] is not False else "offline, serving from cache")
    if snapshot["pending"]:
        text += f"\n{snapshot['pending']} award(s) waiting to sync"
    if snapshot.get("smart_cache") and snapshot.get("smart_cache_text"):
        text += f"\n{snapshot['smart_cache_text']}"
    if snapshot["queued"]:
        text += f"\nCaching: {snapshot['queued']} queued"
    return text[:127]


def notifications(previous: dict | None, current: dict) -> list[tuple[str, str, int]]:
    """(title, text, icon flag) for what changed since the last poll."""
    if previous is None or not current["running"]:
        return []
    found = []
    if previous["online"] is not False and current["online"] is False:
        found.append(("Offline", "Serving achievements from cache. Unlocks are saved and synced later.", NIIF_INFO))
    if previous["online"] is False and current["online"] is not False:
        found.append(("Online", "Forwarding to RetroAchievements again.", NIIF_INFO))
    if current["pending"] > previous["pending"]:
        added = current["pending"] - previous["pending"]
        found.append(("Award saved offline", f"{added} unlock(s) queued, {current['pending']} waiting to sync.", NIIF_INFO))
    if current["synced"] > previous["synced"]:
        synced = current["synced"] - previous["synced"]
        found.append(("Awards synced", f"Synced {synced} offline unlock(s) to RetroAchievements.", NIIF_INFO))
    if previous.get("smart_cache") and not current.get("smart_cache"):
        text = current.get("smart_cache_text") or "Smart Cache finished."
        if text.startswith("Smart Cache failed"):
            found.append(("Smart Cache failed", text.removeprefix("Smart Cache failed: "), NIIF_WARNING))
        else:
            found.append(("Smart Cache finished", text, NIIF_INFO))
    if previous["queued"] == 0 and current["queued"] > 0:
        found.append(("Caching games", f"{current['queued']} game(s) queued for offline play.", NIIF_INFO))
    for achievement_id, error in current["failed"].items():
        if previous["failed"].get(achievement_id) != error:
            found.append(("Award sync failed", f"Achievement #{achievement_id}: {error}"[:250], NIIF_WARNING))
    return found


# Tray ---------------------------------------------------------------------------------


class Tray:
    def __init__(self) -> None:
        self.storage = Storage()
        self.snapshot: dict | None = None
        self.update_notified: str | None = None
        self.update_thread: threading.Thread | None = None
        self.toggle_thread: threading.Thread | None = None
        self.update_notice: str | None = None
        self.proc = WNDPROC(self.window_proc)  # kept alive for Windows to call
        instance = kernel32.GetModuleHandleW(None)
        wc = WNDCLASSW(lpfnWndProc=self.proc, hInstance=instance, lpszClassName="RAOfflineProxyTray")
        user32.RegisterClassW(ctypes.byref(wc))
        self.hwnd = user32.CreateWindowExW(0, wc.lpszClassName, "RAOfflineProxy", 0, 0, 0, 0, 0, None, None, instance, None)
        icon_path = write_icon()
        self.icon = (
            user32.LoadImageW(None, str(icon_path), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE)
            if icon_path
            else None
        ) or user32.LoadIconW(None, ctypes.c_void_p(32512))  # IDI_APPLICATION
        self.data = NOTIFYICONDATAW(cbSize=ctypes.sizeof(NOTIFYICONDATAW), hWnd=self.hwnd, uID=1)
        self.data.uCallbackMessage = WM_TRAY
        self.data.hIcon = self.icon
        self.data.szTip = "RAOfflineProxy"
        self.icon_added = False
        self.add_icon()
        self.poll()
        user32.SetTimer(self.hwnd, 1, POLL_MS, None)

    def add_icon(self) -> None:
        """Fails while there's no taskbar yet; poll() keeps trying until it works."""
        self.data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP
        self.icon_added = bool(shell32.Shell_NotifyIconW(NIM_ADD, ctypes.byref(self.data)))

    def notify(self, title: str, text: str, flag: int) -> None:
        self.data.uFlags = NIF_INFO
        self.data.szInfoTitle = title[:63]
        self.data.szInfo = text[:255]
        self.data.dwInfoFlags = flag
        shell32.Shell_NotifyIconW(NIM_MODIFY, ctypes.byref(self.data))

    def poll(self) -> None:
        if QUIT_REQUEST_FILE.exists():
            QUIT_REQUEST_FILE.unlink(missing_ok=True)
            user32.DestroyWindow(self.hwnd)
            return
        if not self.icon_added:
            self.add_icon()
        try:
            current = read_snapshot(self.storage)
        except Exception:
            return
        for title, text, flag in notifications(self.snapshot, current):
            self.notify(title, text, flag)
        self.snapshot = current
        if self.update_notice is not None:
            self.notify("Update available", self.update_notice, NIIF_INFO)
            self.update_notice = None
        self.start_update_check()
        self.data.uFlags = NIF_TIP
        self.data.szTip = tooltip(current)
        shell32.Shell_NotifyIconW(NIM_MODIFY, ctypes.byref(self.data))

    def start_update_check(self) -> None:
        # Off the message loop: a network check can take seconds.
        if self.update_thread is None or not self.update_thread.is_alive():
            self.update_thread = threading.Thread(target=self.check_for_update, daemon=True)
            self.update_thread.start()

    def check_for_update(self) -> None:
        """At most one network check a day (update.py caches the result),
        and one notification per new version."""
        from ..config import load_config
        from .settings import UPDATE_CHECK_KEY, setting_enabled
        from .update import check

        try:
            if not setting_enabled(load_config(), UPDATE_CHECK_KEY):
                return
            info = check()
        except Exception:
            return
        if info.available and info.latest_version != self.update_notified:
            self.update_notified = info.latest_version
            # Shown by the next poll, on the thread that owns self.data.
            self.update_notice = f"RAOfflineProxy {info.latest_version} is out. Click here or open the menu to install it."

    def open_menu(self) -> None:
        # Its own process, so the tray stays responsive while it's open.
        from .process import pythonw_command

        subprocess.Popen(pythonw_command("raofflineproxy.main", "menu"))

    def toggle_proxy(self) -> None:
        """Runs in the background so the icon stays responsive; the next poll
        shows the result."""
        if self.toggle_thread is not None and self.toggle_thread.is_alive():
            return
        command = "stop-proxy" if self.snapshot and self.snapshot["running"] else "start-proxy"
        self.toggle_thread = threading.Thread(
            target=subprocess.run,
            args=([sys.executable, "-m", "raofflineproxy.main", command],),
            kwargs={"creationflags": 0x08000000},
            daemon=True,
        )
        self.toggle_thread.start()

    def show_context_menu(self) -> None:
        running = bool(self.snapshot and self.snapshot["running"])
        menu = user32.CreatePopupMenu()
        user32.AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, tooltip(self.snapshot or {"running": False}).split("\n")[0])
        user32.AppendMenuW(menu, MF_SEPARATOR, 0, None)
        user32.AppendMenuW(menu, MF_STRING, CMD_OPEN, "Open menu")
        user32.AppendMenuW(menu, MF_STRING, CMD_TOGGLE, "Stop proxy" if running else "Start proxy")
        if windows_background.is_running():
            user32.AppendMenuW(menu, MF_STRING, CMD_STOP_CACHE, "Stop Smart Cache")
        user32.AppendMenuW(menu, MF_SEPARATOR, 0, None)
        user32.AppendMenuW(menu, MF_STRING, CMD_EXIT, "Exit tray icon")
        point = POINT()
        user32.GetCursorPos(ctypes.byref(point))
        user32.SetForegroundWindow(self.hwnd)
        command = user32.TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0, self.hwnd, None)
        user32.DestroyMenu(menu)
        if command == CMD_OPEN:
            self.open_menu()
        elif command == CMD_TOGGLE:
            self.toggle_proxy()
        elif command == CMD_STOP_CACHE:
            windows_background.request_stop()
        elif command == CMD_EXIT:
            user32.DestroyWindow(self.hwnd)

    def window_proc(self, hwnd, message, wparam, lparam):
        if message == WM_TRAY:
            if lparam == WM_RBUTTONUP:
                self.show_context_menu()
            elif lparam in (WM_LBUTTONDBLCLK, NIN_BALLOONUSERCLICK):
                # Clicking a notification ("Update available") opens the menu too.
                self.open_menu()
            return 0
        if message == WM_TIMER:
            self.poll()
            return 0
        if message == TASKBAR_CREATED:
            self.add_icon()
            return 0
        if message == WM_DESTROY:
            shell32.Shell_NotifyIconW(NIM_DELETE, ctypes.byref(self.data))
            user32.PostQuitMessage(0)
            return 0
        return user32.DefWindowProcW(hwnd, message, wparam, lparam)

    def run(self) -> None:
        msg = MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))
        self.storage.close()


def main(argv: list[str]) -> int:
    QUIT_REQUEST_FILE.unlink(missing_ok=True)  # a stale request from before
    mutex = kernel32.CreateMutexW(None, False, MUTEX_NAME)
    if ctypes.get_last_error() == ERROR_ALREADY_EXISTS:
        return 0  # one tray icon per user
    if "--start-proxy" in argv and not proxy_running():
        # Sign-in autostart starts the tray, and the tray starts the proxy.
        subprocess.run([sys.executable, "-m", "raofflineproxy.main", "start-proxy"], creationflags=0x08000000)
    Tray().run()
    kernel32.CloseHandle(mutex)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
