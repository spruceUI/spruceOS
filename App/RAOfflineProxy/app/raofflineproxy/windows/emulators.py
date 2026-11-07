from __future__ import annotations

"""Finds RetroArch, Dolphin and PPSSPP on Windows and turns each one on or off,
like the Android app's emulator selector.

Android can ask the system which apps are installed. Windows has no single
list, and portable copies (unzipped anywhere) are common, so detection looks in
the installed-programs registry, Start-menu and desktop shortcuts, and a
shallow scan of likely folders on local drives, then works out each emulator's
config from where its exe is.

Turning one off needs no change to the shared patching code: its config path
in config.json points at a placeholder, and the real path is kept to restore
when it's turned back on. Dolphin's and PPSSPP's placeholders don't exist, which
their patchers skip. RetroArch's patcher instead refuses a missing cfg (only
Batocera-style devices may lack one), so its placeholder is an empty cfg in the
data folder that the proxy patches and reverts harmlessly.

Run as a module (python -m raofflineproxy.windows.emulators) to detect and
save; the portable folder's first start does that."""

import ctypes
import json
import os
import string
import sys
from dataclasses import dataclass
from pathlib import Path

from . import paths as windows_paths
from ..config import CONFIG_DIR, load_config, save_config

STATE_KEY = "windows_emulators"
DISABLED_DIR = CONFIG_DIR / "disabled-emulators"


@dataclass(frozen=True)
class EmulatorKind:
    key: str
    name: str
    exe_names: tuple[str, ...]
    config_key: str  # the shared config.json key the patcher reads


RETROARCH = EmulatorKind("retroarch", "RetroArch", ("retroarch.exe",), "retroarch_cfg")
DOLPHIN = EmulatorKind("dolphin", "Dolphin", ("dolphin.exe",), "dolphin_config_dir")
PPSSPP = EmulatorKind("ppsspp", "PPSSPP", ("ppssppwindows64.exe", "ppssppwindows.exe"), "ppsspp_ini")
PCSX2 = EmulatorKind("pcsx2", "PCSX2", ("pcsx2-qt.exe",), "pcsx2_ini")
DUCKSTATION = EmulatorKind(
    "duckstation",
    "DuckStation",
    ("duckstation-qt-x64-releaseltcg.exe", "duckstation-qt-arm64-releaseltcg.exe"),
    "duckstation_ini",
)
FLYCAST = EmulatorKind("flycast", "Flycast", ("flycast.exe",), "flycast_cfg")
KINDS = (RETROARCH, DOLPHIN, PPSSPP, PCSX2, DUCKSTATION, FLYCAST)

SCAN_DEPTH = 3
SKIP_DIRS = {"windows", "$recycle.bin", "system volume information", "programdata", "node_modules", ".git"}


def _appdata() -> Path:
    return Path(os.environ.get("APPDATA") or Path.home() / "AppData" / "Roaming")


def _documents() -> Path:
    return Path.home() / "Documents"


# Where each emulator keeps the file the proxy patches, given its exe ----------------


def config_for_exe(kind: EmulatorKind, exe: Path) -> Path:
    folder = exe.parent
    if kind is RETROARCH:
        # The portable zip and the installer's own folder keep it beside the exe.
        beside = folder / "retroarch.cfg"
        return beside if beside.exists() else _appdata() / "RetroArch" / "retroarch.cfg"
    if kind is DOLPHIN:
        if (folder / "portable.txt").exists():
            return folder / "User" / "Config"
        documents = _documents() / "Dolphin Emulator"
        if documents.is_dir():
            return documents / "Config"
        return _appdata() / "Dolphin Emulator" / "Config"
    if kind is PCSX2:
        # Before PCSX2's first run there's no ini yet: Documents, where an
        # installed PCSX2 will create it, so it still shows on the Emulators screen.
        return windows_paths.pcsx2_ini(folder) or windows_paths.pcsx2_documents_ini()
    if kind is DUCKSTATION:
        return windows_paths.duckstation_ini(folder) or windows_paths.duckstation_local_ini()
    if kind is FLYCAST:
        return windows_paths.flycast_cfg(folder) or folder / "emu.cfg"
    # PPSSPP uses a memstick folder beside the exe unless installed.txt says it
    # was installed, in which case it uses Documents\PPSSPP.
    if (folder / "memstick").is_dir() and not (folder / "installed.txt").exists():
        return folder / "memstick" / "PSP" / "SYSTEM" / "ppsspp.ini"
    return _documents() / "PPSSPP" / "PSP" / "SYSTEM" / "ppsspp.ini"


# Finding exes ------------------------------------------------------------------------


def _registry_install_dirs() -> list[Path]:
    import winreg

    found: list[Path] = []
    roots = (
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"),
        (winreg.HKEY_CURRENT_USER, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
    )
    names = ("retroarch", "dolphin", "ppsspp", "pcsx2", "duckstation", "flycast")
    for hive, path in roots:
        try:
            root = winreg.OpenKey(hive, path)
        except OSError:
            continue
        with root:
            for index in range(winreg.QueryInfoKey(root)[0]):
                try:
                    with winreg.OpenKey(root, winreg.EnumKey(root, index)) as app:
                        display = str(winreg.QueryValueEx(app, "DisplayName")[0]).lower()
                        if not any(name in display for name in names):
                            continue
                        for value in ("InstallLocation", "DisplayIcon"):
                            try:
                                raw = str(winreg.QueryValueEx(app, value)[0]).strip('"').split(",")[0]
                            except OSError:
                                continue
                            if raw:
                                candidate = Path(raw)
                                found.append(candidate if candidate.is_dir() else candidate.parent)
                except OSError:
                    continue
    return found


def _shortcut_target(link: Path) -> Path | None:
    """The target of a .lnk, read from the file itself: the shell link header,
    then the LinkInfo block's local base path. Enough for exe shortcuts."""
    try:
        data = link.read_bytes()
        flags = int.from_bytes(data[20:24], "little")
        offset = 76
        if flags & 0x1:  # HasLinkTargetIDList
            offset += 2 + int.from_bytes(data[offset : offset + 2], "little")
        if not flags & 0x2:  # HasLinkInfo
            return None
        info = offset
        base_offset = int.from_bytes(data[info + 16 : info + 20], "little")
        start = info + base_offset
        end = data.index(b"\x00", start)
        return Path(data[start:end].decode("mbcs", errors="replace"))
    except (OSError, ValueError, IndexError):
        return None


def _shortcut_dirs() -> list[Path]:
    folders = [
        _appdata() / "Microsoft" / "Windows" / "Start Menu" / "Programs",
        Path(os.environ.get("ProgramData", "C:/ProgramData")) / "Microsoft" / "Windows" / "Start Menu" / "Programs",
        Path.home() / "Desktop",
    ]
    found: list[Path] = []
    for folder in folders:
        if not folder.is_dir():
            continue
        for link in folder.rglob("*.lnk"):
            target = _shortcut_target(link)
            if target is not None and target.name.lower() in {n for kind in KINDS for n in kind.exe_names}:
                found.append(target.parent)
    return found


def _local_drives() -> list[Path]:
    """Fixed drives only: scanning a network share or a card reader could take minutes."""
    drive_fixed = 3
    drives = []
    for letter in string.ascii_uppercase:
        root = f"{letter}:\\"
        if ctypes.windll.kernel32.GetDriveTypeW(root) == drive_fixed:
            drives.append(Path(root))
    return drives


def _scan_roots() -> list[Path]:
    roots = [
        Path(os.environ.get("ProgramFiles", "C:/Program Files")),
        Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")),
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs",
        Path.home() / "scoop" / "apps",
        Path.home() / "Desktop",
        Path.home() / "Downloads",
        _documents(),
        *_local_drives(),
    ]
    return [root for root in roots if str(root) and root.is_dir()]


def _scan(root: Path, depth: int, wanted: set[str], found: list[Path]) -> None:
    try:
        with os.scandir(root) as entries:
            for entry in entries:
                name = entry.name.lower()
                try:
                    if entry.is_file() and name in wanted:
                        found.append(Path(entry.path))
                    elif depth > 0 and entry.is_dir() and name not in SKIP_DIRS and not name.startswith((".", "$")):
                        _scan(Path(entry.path), depth - 1, wanted, found)
                except OSError:
                    continue
    except OSError:
        return


def find_exes() -> dict[str, Path]:
    """The first exe found for each emulator kind."""
    wanted = {name for kind in KINDS for name in kind.exe_names}
    candidates: list[Path] = []
    for folder in [*_registry_install_dirs(), *_shortcut_dirs()]:
        for kind in KINDS:
            for exe_name in kind.exe_names:
                exe = folder / exe_name
                if exe.is_file():
                    candidates.append(exe)
    for root in _scan_roots():
        _scan(root, SCAN_DEPTH, wanted, candidates)

    result: dict[str, Path] = {}
    for kind in KINDS:
        matches = [exe for exe in candidates if exe.name.lower() in kind.exe_names]
        if matches:
            # A copy that has been used (its config exists) wins over a stray or
            # never-launched one; then exe_names order, e.g. PPSSPP's 64-bit build.
            result[kind.key] = min(
                matches,
                key=lambda exe: (not config_for_exe(kind, exe).exists(), kind.exe_names.index(exe.name.lower())),
            )
    return result


# State -----------------------------------------------------------------------------


def emulator_state(config_data: dict) -> dict[str, dict]:
    value = config_data.get(STATE_KEY)
    return value if isinstance(value, dict) else {}


def placeholder_path(kind: EmulatorKind) -> str:
    if kind is RETROARCH:
        return str(windows_paths.retroarch_placeholder(CONFIG_DIR))
    return str(DISABLED_DIR / kind.key)


def is_enabled(config_data: dict, kind: EmulatorKind) -> bool:
    return emulator_state(config_data).get(kind.key, {}).get("enabled", True)


def apply_state(config_data: dict) -> None:
    """Points each emulator's shared config key at its real path, or at the
    placeholder when it's turned off."""
    # Runs on every config load on Windows (see config.load_config), so it stays
    # at most one stat per emulator, and nothing at all without saved state.
    state = emulator_state(config_data)
    if not state:
        return
    for kind in KINDS:
        entry = state.get(kind.key)
        if not entry or not entry.get("config"):
            continue
        usable = entry.get("enabled", True) and (kind is not RETROARCH or Path(entry["config"]).is_file())
        config_data[kind.config_key] = entry["config"] if usable else placeholder_path(kind)


def set_emulator(config_data: dict, kind: EmulatorKind, exe: Path | None = None, enabled: bool | None = None) -> None:
    state = emulator_state(config_data)
    entry = dict(state.get(kind.key, {}))
    if exe is not None:
        entry["exe"] = str(exe)
        entry["config"] = str(config_for_exe(kind, exe))
    if enabled is not None:
        entry["enabled"] = enabled
    entry.setdefault("enabled", True)
    state[kind.key] = entry
    config_data[STATE_KEY] = state
    apply_state(config_data)


def detect_and_save() -> dict[str, dict]:
    """Records every emulator found, keeping each one's on/off choice and any
    exe the user picked by hand that still exists."""
    config_data = load_config()
    found = find_exes()
    for kind in KINDS:
        existing = emulator_state(config_data).get(kind.key, {})
        if existing.get("exe") and Path(existing["exe"]).is_file():
            continue
        if kind.key in found:
            set_emulator(config_data, kind, exe=found[kind.key])
    save_config(config_data)
    return emulator_state(config_data)


def main() -> int:
    state = detect_and_save()
    for kind in KINDS:
        entry = state.get(kind.key)
        if entry:
            status = "on" if entry.get("enabled", True) else "off"
            print(f"{kind.name}: {entry.get('exe') or entry['config']} ({status})")
        else:
            print(f"{kind.name}: not found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
