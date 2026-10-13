import os
from dataclasses import dataclass
from pathlib import Path

from devices.desktop.desktop_script import parse_script

# The SpruceOS checkout this file lives in: <root>/App/PyUI/main-ui/devices/desktop/
SPRUCE_ROOT = Path(__file__).resolve().parents[5]
DEFAULT_DATA_DIR = Path.home() / ".pyui-desktop"


def parse_resolution(text):
    """"640x480" -> (640, 480)."""
    try:
        width, height = (int(part) for part in text.lower().split("x"))
    except ValueError:
        raise ValueError(f"expected WIDTHxHEIGHT, got {text!r}") from None
    if width <= 0 or height <= 0:
        raise ValueError(f"expected WIDTHxHEIGHT, got {text!r}")
    return width, height


def _flag(environ, name):
    return environ.get(name, "").strip().lower() in ("1", "true", "yes")


def _path(environ, name, default):
    value = environ.get(name)
    return Path(value).expanduser().resolve() if value else default


@dataclass(frozen=True)
class DesktopOptions:
    """How the DESKTOP device runs.

    Read from PYUI_DESKTOP_* environment variables, so `mainui.py -device DESKTOP`, desktop.py
    and apps that bring PyUI up themselves (initialize_device) all configure it the same way.

    The SD card is split in two: `sdcard` is read only (App/, Emu/, Themes/ - by default the
    SpruceOS checkout this PyUI is in), `data` takes everything PyUI writes (Saves/,
    Collections/), so running the desktop never changes the checkout.
    """
    width: int = 640
    height: int = 480
    scale: int = 1
    theme: str = None
    headless: bool = False
    script: tuple = ()
    exit_after_script: bool = False
    sdcard: Path = SPRUCE_ROOT
    roms: Path = SPRUCE_ROOT / "Roms"
    data: Path = DEFAULT_DATA_DIR
    shots: Path = DEFAULT_DATA_DIR / "screenshots"

    @classmethod
    def from_environ(cls, environ=None):
        environ = os.environ if environ is None else environ
        width, height = parse_resolution(environ.get("PYUI_DESKTOP_RES", "640x480"))
        scale = int(environ.get("PYUI_DESKTOP_SCALE", "1"))
        if scale < 1:
            raise ValueError(f"PYUI_DESKTOP_SCALE must be 1 or more, got {scale}")
        headless = _flag(environ, "PYUI_DESKTOP_HEADLESS")
        script = tuple(parse_script(environ.get("PYUI_DESKTOP_SCRIPT", "")))
        if headless and not script:
            # Nothing would ever press a button: it would wait for input forever.
            raise ValueError("PYUI_DESKTOP_HEADLESS needs a PYUI_DESKTOP_SCRIPT")
        sdcard = _path(environ, "PYUI_DESKTOP_SDCARD", SPRUCE_ROOT)
        data = _path(environ, "PYUI_DESKTOP_DATA", DEFAULT_DATA_DIR)
        return cls(
            width=width,
            height=height,
            scale=1 if headless else scale,
            theme=environ.get("PYUI_DESKTOP_THEME") or None,
            headless=headless,
            script=script,
            exit_after_script=headless or _flag(environ, "PYUI_DESKTOP_EXIT_AFTER_SCRIPT"),
            sdcard=sdcard,
            roms=_path(environ, "PYUI_DESKTOP_ROMS", sdcard / "Roms"),
            data=data,
            shots=_path(environ, "PYUI_DESKTOP_SHOTS", data / "screenshots" / f"{width}x{height}"),
        )
