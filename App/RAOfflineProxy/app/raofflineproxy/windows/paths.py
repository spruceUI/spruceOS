from __future__ import annotations

"""Where things live on Windows. config.py consults these only when
running_on_windows() is true, so nothing here runs on the Linux devices."""

import os
from pathlib import Path


def _appdata() -> Path:
    return Path(os.environ.get("APPDATA") or Path.home() / "AppData" / "Roaming")


def _local_appdata() -> Path:
    return Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local")


PORTABLE_MARKER = "portable.txt"


def portable_root() -> Path | None:
    """The unzipped RAOfflineProxy folder when running from one: its bundled
    Python lives in <root>/python, next to a portable.txt marker (as Dolphin
    marks its portable installs). None when running from a source checkout."""
    import sys

    root = Path(sys.executable).resolve().parent.parent
    return root if (root / PORTABLE_MARKER).is_file() else None


TEST_CHANNEL_FILE = "testing.json"


def test_channel() -> dict:
    """Redirects for test builds only, from a testing.json that build_bundle.sh
    adds when RAOFFLINEPROXY_TEST_CHANNEL names one (CI checks release bundles
    never carry it). Keys: "update_releases_url" (a releases list in GitHub's
    format, e.g. a fork's test releases) and "logs_folder" (Send Logs saves the
    zip there instead of uploading it to the developer). Empty otherwise, so
    the real destinations are the default with nothing to reset."""
    import json

    root = portable_root()
    if root is None:
        return {}
    try:
        data = json.loads((root / TEST_CHANNEL_FILE).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def config_dir() -> Path:
    """Settings, cached games and awards. In the portable folder's data/ so
    they travel with it; otherwise (a source checkout) under %LOCALAPPDATA%."""
    root = portable_root()
    if root is not None:
        return root / "data"
    return _local_appdata() / "RAOfflineProxy"


def retroarch_cfg_candidates() -> tuple[Path, ...]:
    """The installer build keeps its config under %APPDATA%; the portable zip and
    the default installer location keep it next to retroarch.exe. Anything else
    (a portable copy in some other folder) is set via retroarch_cfg in config.json."""
    program_files = Path(os.environ.get("ProgramFiles") or "C:/Program Files")
    return (
        _appdata() / "RetroArch" / "retroarch.cfg",
        Path("C:/RetroArch-Win64/retroarch.cfg"),
        program_files / "RetroArch" / "retroarch.cfg",
    )


def retroarch_placeholder(config_dir: Path) -> Path:
    """An empty retroarch.cfg in the data folder. The shared RetroArch patcher
    refuses a missing cfg (only Batocera-style devices may lack one), so on
    Windows, where RetroArch may be absent, turned off or never launched yet,
    the proxy patches and reverts this harmless file instead."""
    placeholder = config_dir / "disabled-emulators" / "retroarch.cfg"
    # One stat in the common case: this runs on every config load on Windows.
    if not placeholder.exists():
        placeholder.parent.mkdir(parents=True, exist_ok=True)
        placeholder.write_text("", encoding="utf-8")
    return placeholder


def dolphin_config_dir() -> Path | None:
    """Dolphin's user directory is Documents/Dolphin Emulator when that folder
    already exists (older installs), otherwise %APPDATA%/Dolphin Emulator. Its
    .ini files live in the Config subfolder. Portable installs (portable.txt
    beside Dolphin.exe) are set via dolphin_config_dir in config.json."""
    for user_dir in (
        Path.home() / "Documents" / "Dolphin Emulator",
        _appdata() / "Dolphin Emulator",
    ):
        if (user_dir / "Config").is_dir():
            return user_dir / "Config"
    return None


def duckstation_local_ini() -> Path:
    local = os.environ.get("LOCALAPPDATA")
    base = Path(local) if local else Path.home() / "AppData" / "Local"
    return base / "DuckStation" / "settings.ini"


def duckstation_ini(folder: Path | None = None) -> Path | None:
    """A portable copy (portable.txt beside the exe in folder) keeps it beside the exe."""
    candidates = [duckstation_local_ini()]
    if folder is not None and (folder / "portable.txt").exists():
        candidates.insert(0, folder / "settings.ini")
    return next((candidate for candidate in candidates if candidate.exists()), None)


def flycast_appdata_cfg() -> Path:
    roaming = os.environ.get("APPDATA")
    base = Path(roaming) if roaming else Path.home() / "AppData" / "Roaming"
    return base / "flycast" / "emu.cfg"


def flycast_cfg(folder: Path | None = None) -> Path | None:
    candidates = [folder / "emu.cfg"] if folder is not None else []
    candidates.append(flycast_appdata_cfg())
    return next((candidate for candidate in candidates if candidate.exists()), None)


def pcsx2_documents_ini() -> Path:
    return Path.home() / "Documents" / "PCSX2" / "inis" / "PCSX2.ini"


def pcsx2_ini(folder: Path | None = None) -> Path | None:
    """The PCSX2.ini that exists: a portable copy's own inis folder beside
    pcsx2-qt.exe (when folder is that exe's folder), else Documents/PCSX2,
    where an installed PCSX2 keeps it."""
    candidates = [folder / "inis" / "PCSX2.ini"] if folder is not None else []
    candidates.append(pcsx2_documents_ini())
    return next((candidate for candidate in candidates if candidate.exists()), None)


def ppsspp_ini() -> Path | None:
    """Installed PPSSPP keeps its memstick under Documents/PPSSPP. The portable
    zip uses a memstick folder beside the exe and is set via ppsspp_ini."""
    candidate = Path.home() / "Documents" / "PPSSPP" / "PSP" / "SYSTEM" / "ppsspp.ini"
    return candidate if candidate.exists() else None


def write_preserving_newlines(target: Path, content: str) -> None:
    """Writes an emulator config back with the line endings it already had.
    Text mode on Windows turns every LF into CRLF, which would rewrite a
    whole LF file (RetroArch writes LF on Windows too) just to change one key."""
    newline = ""
    try:
        if b"\r\n" in target.read_bytes():
            newline = "\r\n"
    except OSError:
        pass
    with target.open("w", encoding="utf-8", newline=newline) as handle:
        handle.write(content)
