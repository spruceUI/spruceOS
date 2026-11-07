from __future__ import annotations

"""Add to Steam: puts RAOfflineProxy in a Steam account's library as a
non-Steam game, so it can be opened from Steam or Windows' Xbox full screen
mode, where there's no tray icon. The same as Steam's own "Add a Non-Steam
Game", plus library artwork made from the logo.

Steam keeps non-Steam games in userdata/<account>/config/shortcuts.vdf (binary
VDF) and rewrites it when it exits, so Steam is closed first and started again
after. An existing RAOfflineProxy entry is updated in place, which also fixes
its path after the folder moves; every other entry is kept as it was. The file
is backed up before each write."""

import binascii
import re
import shutil
import struct
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath

APP_NAME = "RAOfflineProxy"
LAUNCH_OPTIONS = "-m raofflineproxy.windows.launch"
STEAM_KEY = r"Software\Valve\Steam"
# Account ids in userdata are SteamID64s minus this.
STEAM_ID64_BASE = 76561197960265728
SHUTDOWN_SECONDS = 30

# Binary VDF type bytes.
_MAP, _STRING, _INT32, _END = 0, 1, 2, 8


# Binary VDF -------------------------------------------------------------------------


def parse_vdf(data: bytes) -> dict:
    """Binary VDF into nested dicts (insertion ordered, so writing it back keeps
    the order). Raises ValueError on a file it can't read."""

    def read_cstring(pos: int) -> tuple[str, int]:
        end = data.index(b"\x00", pos)
        return data[pos:end].decode("utf-8", errors="surrogateescape"), end + 1

    def read_map(pos: int) -> tuple[dict, int]:
        result: dict = {}
        while True:
            if pos >= len(data):
                raise ValueError("shortcuts.vdf ends early")
            kind = data[pos]
            pos += 1
            if kind == _END:
                return result, pos
            key, pos = read_cstring(pos)
            if kind == _MAP:
                result[key], pos = read_map(pos)
            elif kind == _STRING:
                result[key], pos = read_cstring(pos)
            elif kind == _INT32:
                result[key] = struct.unpack_from("<i", data, pos)[0]
                pos += 4
            else:
                raise ValueError(f"shortcuts.vdf has an unknown field type {kind}")

    try:
        result, _ = read_map(0)
    except (IndexError, struct.error) as exc:
        raise ValueError("shortcuts.vdf is damaged") from exc
    return result


def write_vdf(value: dict) -> bytes:
    out = bytearray()

    def cstring(text: str) -> bytes:
        return text.encode("utf-8", errors="surrogateescape") + b"\x00"

    def write_map(items: dict) -> None:
        for key, item in items.items():
            if isinstance(item, dict):
                out.append(_MAP)
                out.extend(cstring(key))
                write_map(item)
            elif isinstance(item, int):
                out.append(_INT32)
                out.extend(cstring(key))
                out.extend(struct.pack("<i", item))
            else:
                out.append(_STRING)
                out.extend(cstring(key))
                out.extend(cstring(str(item)))
        out.append(_END)

    write_map(value)
    return bytes(out)


# Steam on this PC ---------------------------------------------------------------------


@dataclass
class SteamAccount:
    account_id: str
    name: str
    userdata: Path


def steam_root() -> Path | None:
    import winreg

    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, STEAM_KEY) as key:
            path = Path(winreg.QueryValueEx(key, "SteamPath")[0])
    except OSError:
        return None
    return path if (path / "steam.exe").exists() else None


def _persona_names(root: Path) -> dict[str, str]:
    """Account id -> Steam display name, from config/loginusers.vdf (text VDF)."""
    try:
        text = (root / "config" / "loginusers.vdf").read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    names = {}
    for steam_id, body in re.findall(r'"(\d{17})"\s*\{([^}]*)\}', text):
        match = re.search(r'"PersonaName"\s+"([^"]*)"', body)
        if match:
            names[str(int(steam_id) - STEAM_ID64_BASE)] = match.group(1)
    return names


def accounts(root: Path | None = None) -> list[SteamAccount]:
    root = root or steam_root()
    if root is None:
        return []
    names = _persona_names(root)
    found = []
    for folder in sorted((root / "userdata").glob("*")):
        # "0" is Steam's anonymous placeholder, not an account.
        if folder.is_dir() and folder.name.isdigit() and folder.name != "0":
            found.append(SteamAccount(folder.name, names.get(folder.name, f"Account {folder.name}"), folder))
    return found


def steam_running() -> bool:
    result = subprocess.run(
        ["tasklist.exe", "/FI", "IMAGENAME eq steam.exe", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        creationflags=subprocess.CREATE_NO_WINDOW,
        check=False,
    )
    return "steam.exe" in result.stdout.lower()


def close_steam(root: Path) -> bool:
    """Asks Steam to exit, as its own menu does, and waits. False if it didn't."""
    subprocess.Popen([str(root / "steam.exe"), "-shutdown"], creationflags=subprocess.CREATE_NO_WINDOW)
    deadline = time.monotonic() + SHUTDOWN_SECONDS
    while time.monotonic() < deadline:
        if not steam_running():
            time.sleep(1)  # let it finish writing its files
            return True
        time.sleep(0.5)
    return False


def start_steam(root: Path) -> None:
    subprocess.Popen([str(root / "steam.exe")], creationflags=subprocess.DETACHED_PROCESS)


# The shortcut ---------------------------------------------------------------------------


def shortcut_app_id(exe: str, name: str) -> int:
    """The id Steam gives a non-Steam game (unsigned), also used to name its artwork."""
    return (binascii.crc32((exe + name).encode("utf-8")) & 0xFFFFFFFF) | 0x80000000


def _signed(value: int) -> int:
    return value - (1 << 32) if value >= 1 << 31 else value


def _field(entry: dict, name: str):
    """Steam has written some keys in different cases over the years (appname/AppName)."""
    for key, value in entry.items():
        if key.lower() == name.lower():
            return value
    return None


def _set_field(entry: dict, name: str, value) -> None:
    for key in entry:
        if key.lower() == name.lower():
            entry[key] = value
            return
    entry[name] = value


def _is_ours(entry: dict) -> bool:
    exe = str(_field(entry, "Exe") or "").lower()
    return _field(entry, "appname") == APP_NAME or (
        "pythonw.exe" in exe and LAUNCH_OPTIONS in str(_field(entry, "LaunchOptions") or "")
    )


def upsert_shortcut(shortcuts: dict, root: Path, icon: Path | None) -> int:
    """Adds or updates our entry in parsed shortcuts.vdf data; returns its app id."""
    table = shortcuts.setdefault("shortcuts", {})
    # Windows paths whatever the host, so the tests read the same everywhere.
    root = PureWindowsPath(root)
    exe = f'"{root / "python" / "pythonw.exe"}"'
    app_id = shortcut_app_id(exe, APP_NAME)
    entry = next((item for item in table.values() if isinstance(item, dict) and _is_ours(item)), None)
    if entry is None:
        entry = {
            "appid": 0,
            "appname": APP_NAME,
            "Exe": "",
            "StartDir": "",
            "icon": "",
            "ShortcutPath": "",
            "LaunchOptions": "",
            "IsHidden": 0,
            "AllowDesktopConfig": 1,
            "AllowOverlay": 1,
            "OpenVR": 0,
            "Devkit": 0,
            "DevkitGameID": "",
            "DevkitOverrideAppID": 0,
            "LastPlayTime": 0,
            "FlatpakAppID": "",
            "tags": {},
        }
        next_key = max((int(key) for key in table if key.isdigit()), default=-1) + 1
        table[str(next_key)] = entry
    _set_field(entry, "appid", _signed(app_id))
    _set_field(entry, "appname", APP_NAME)
    _set_field(entry, "Exe", exe)
    _set_field(entry, "StartDir", f'"{root}"')
    _set_field(entry, "LaunchOptions", LAUNCH_OPTIONS)
    _set_field(entry, "icon", str(icon) if icon else "")
    return app_id


def write_artwork(grid: Path, app_id: int, logo: Path) -> None:
    """Library artwork from the logo: the portrait tile, the wide tile, the
    banner behind the game page and the logo over it."""
    import pygame

    background = (16, 20, 28)
    image = pygame.image.load(str(logo))
    grid.mkdir(parents=True, exist_ok=True)

    def tile(size: tuple[int, int], logo_width: int, name: str) -> None:
        if (grid / name).exists():
            return  # artwork the user picked in Steam stays
        surface = pygame.Surface(size)
        surface.fill(background)
        scale = logo_width / image.get_width()
        art = pygame.transform.smoothscale(image, (logo_width, int(image.get_height() * scale)))
        surface.blit(art, art.get_rect(center=(size[0] // 2, size[1] // 2)))
        pygame.image.save(surface, str(grid / name))

    tile((600, 900), 420, f"{app_id}p.png")
    tile((920, 430), 300, f"{app_id}.png")
    if not (grid / f"{app_id}_hero.png").exists():
        hero = pygame.Surface((1920, 620))
        hero.fill(background)
        pygame.image.save(hero, str(grid / f"{app_id}_hero.png"))
    if not (grid / f"{app_id}_logo.png").exists():
        shutil.copyfile(logo, grid / f"{app_id}_logo.png")


def add_to_steam(account: SteamAccount, root: Path, icon: Path | None, logo: Path | None) -> None:
    """Steam must be closed (see close_steam). Raises OSError/ValueError on failure,
    leaving shortcuts.vdf as it was."""
    config = account.userdata / "config"
    path = config / "shortcuts.vdf"
    shortcuts = parse_vdf(path.read_bytes()) if path.exists() else {"shortcuts": {}}
    app_id = upsert_shortcut(shortcuts, root, icon)
    config.mkdir(parents=True, exist_ok=True)
    if path.exists():
        shutil.copyfile(path, config / "shortcuts.vdf.raofflineproxy-backup")
    temporary = config / "shortcuts.vdf.raofflineproxy-new"
    temporary.write_bytes(write_vdf(shortcuts))
    temporary.replace(path)
    if logo is not None and logo.exists():
        try:
            write_artwork(config / "grid", app_id, logo)
        except Exception:
            pass  # the shortcut works without artwork
