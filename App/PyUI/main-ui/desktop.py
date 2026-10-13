"""Run PyUI in a window on a Mac or PC: python3 App/PyUI/main-ui/desktop.py --help

The whole launcher (mainui.py) on the DESKTOP device, reading the SpruceOS checkout as its SD
card. See App/PyUI/docs/desktop_readme.txt.
"""
import argparse
import json
import os
import sys
import warnings
from pathlib import Path

from devices.desktop.desktop_options import DEFAULT_DATA_DIR, SPRUCE_ROOT, parse_resolution
from devices.desktop.desktop_script import ScriptError, parse_script

SD_ROOT = "/mnt/SDCARD/"
# Keys of py-ui-config.json that are left out on the desktop: the CFW's scripts and lists of
# them. Every key ending in "Cmd" is dropped too.
CFW_SCRIPT_KEYS = ("aboutEntries", "cfwTasks")


def parse_arguments(argv):
    parser = argparse.ArgumentParser(
        prog="desktop.py",
        description="Run PyUI in a window. Keys: arrows = D-pad, X = A, Z = B, S = X, A = Y, "
                    "Q/W = L1/R1, 1/2 = L2/R2, Enter = Start, Right Shift = Select, M = Menu, "
                    "F8 = screenshot, Esc = quit. Arguments it doesn't know go to mainui.py "
                    "(e.g. -msgDisplay \"Hello\").")
    parser.add_argument("--res", default="640x480", help="screen size, e.g. 752x560 (default 640x480)")
    parser.add_argument("--scale", type=int, default=1, help="window zoom (default 1)")
    parser.add_argument("--theme", help="theme folder name; kept for later runs")
    parser.add_argument("--themes", type=Path,
                        help="folder of themes (default <sdcard>/Themes); kept for later runs")
    parser.add_argument("--sdcard", type=Path, default=SPRUCE_ROOT,
                        help="read-only SD card: App/, Emu/, Themes/ (default: this SpruceOS checkout)")
    parser.add_argument("--roms", type=Path, help="ROMs folder (default <sdcard>/Roms)")
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA_DIR,
                        help=f"where PyUI writes: Saves/, Collections/, logs/ (default {DEFAULT_DATA_DIR})")
    parser.add_argument("--script", default="",
                        help='button presses to play, e.g. "down,a,shot:games,wait:12,b"')
    parser.add_argument("--headless", action="store_true",
                        help="no window: play --script, save its shots and exit")
    parser.add_argument("--quit-after-script", action="store_true", help="exit when --script ends")
    parser.add_argument("--out", type=Path, help="folder for screenshots (default <data>/screenshots/<WxH>)")
    args, mainui_args = parser.parse_known_args(argv)
    try:
        parse_resolution(args.res)
        script = parse_script(args.script)
    except (ValueError, ScriptError) as e:
        parser.error(str(e))
    if args.headless and not script:
        parser.error("--headless needs --script (otherwise it would wait for input forever)")
    if args.scale < 1:
        parser.error("--scale must be 1 or more")
    return args, mainui_args


def desktop_environment(args):
    """The PYUI_DESKTOP_* variables DesktopOptions reads."""
    env = {
        "PYUI_DESKTOP_RES": args.res,
        "PYUI_DESKTOP_SCALE": str(args.scale),
        "PYUI_DESKTOP_SDCARD": str(args.sdcard.expanduser().resolve()),
        "PYUI_DESKTOP_DATA": str(args.data.expanduser().resolve()),
        "PYUI_DESKTOP_SCRIPT": args.script,
        "PYUI_DESKTOP_HEADLESS": "1" if args.headless else "",
        "PYUI_DESKTOP_EXIT_AFTER_SCRIPT": "1" if args.quit_after_script else "",
    }
    if args.theme:
        env["PYUI_DESKTOP_THEME"] = args.theme
    if args.roms:
        env["PYUI_DESKTOP_ROMS"] = str(args.roms.expanduser().resolve())
    if args.out:
        env["PYUI_DESKTOP_SHOTS"] = str(args.out.expanduser().resolve())
    return env


def without_cfw_scripts(value):
    """value with every "...Cmd" key removed, at any depth."""
    if isinstance(value, dict):
        return {key: without_cfw_scripts(item) for key, item in value.items() if not key.endswith("Cmd")}
    if isinstance(value, list):
        return [without_cfw_scripts(item) for item in value]
    return value


def on_desktop(value, sdcard, data):
    """A /mnt/SDCARD path moved to the desktop's: Saves/ to the data folder, the rest to the
    read-only SD card."""
    if not isinstance(value, str) or not value.startswith(SD_ROOT):
        return value
    rest = value[len(SD_ROOT):]
    return str((data if rest.startswith("Saves/") else sdcard) / rest)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=4), encoding="utf-8")


def read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def prepare_pyui_config(sdcard, data, themes=None):
    """<data>/Saves/pyui-config.json: spruce's py-ui-config.json the first time (settings
    changed in PyUI are kept after that), always without the CFW's scripts and with its paths
    on the desktop. themes, if given, replaces the themes folder."""
    path = data / "Saves" / "pyui-config.json"
    source = path if path.is_file() else sdcard / "App" / "PyUI" / "py-ui-config.json"
    if not source.is_file():
        source = Path(__file__).resolve().parent / "config.json"
    config = without_cfw_scripts(read_json(source))
    config = {key: on_desktop(value, sdcard, data) for key, value in config.items()
              if key not in CFW_SCRIPT_KEYS}
    if themes is not None:
        config["themeDir"] = os.path.join(themes, "")
    write_json(path, config)
    return path


def prepare_cfw_config(sdcard, data):
    """<data>/Saves/spruce/spruce-config.json (spruce's settings menus), copied from the SD card
    the first time, without the scripts its settings run when changed."""
    path = data / "Saves" / "spruce" / "spruce-config.json"
    source = path if path.is_file() else sdcard / "Saves" / "spruce" / "spruce-config.json"
    if not source.is_file():
        return None
    write_json(path, without_cfw_scripts(read_json(source)))
    return path


def main(argv=None):
    args, mainui_args = parse_arguments(sys.argv[1:] if argv is None else argv)
    env = desktop_environment(args)
    os.environ.update(env)
    sdcard = Path(env["PYUI_DESKTOP_SDCARD"])
    data = Path(env["PYUI_DESKTOP_DATA"])
    themes = args.themes.expanduser().resolve() if args.themes else None
    if args.headless:
        os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
    # pysdl2-dll is what a desktop should use; its notice on import is noise.
    warnings.filterwarnings("ignore", message="Using SDL2 binaries from pysdl2-dll")

    (data / "logs").mkdir(parents=True, exist_ok=True)
    # principal.sh logs PyUI's start here before launching it, so PyUI expects the file.
    activity_log = data / "Saves" / "spruce" / "activity.jsonl"
    activity_log.parent.mkdir(parents=True, exist_ok=True)
    activity_log.touch()
    pyui_config = prepare_pyui_config(sdcard, data, themes)
    cfw_config = prepare_cfw_config(sdcard, data)

    from devices.miyoo.user_config import UserConfig
    import mainui

    # Hard-coded to the SD card; mainui reads it before the device exists.
    UserConfig.FILEPATH = str(data / "Saves" / "pyui-common.json")
    sys.argv = [mainui.__file__, "-device", "DESKTOP", "-pyUiConfig", str(pyui_config),
                "-logDir", str(data / "logs")]
    if cfw_config is not None:
        sys.argv += ["-cfwConfig", str(cfw_config)]
    sys.argv += mainui_args
    code = 0
    try:
        mainui.main()
    except SystemExit as e:  # Esc, closing the window, power off, the end of a --script
        code = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
    except KeyboardInterrupt:  # Ctrl+C in the terminal
        code = 130
    unplayed = _unplayed_script_steps()
    if unplayed:
        print(f"PyUI left the menu with {len(unplayed)} script steps not played: {unplayed}",
              file=sys.__stderr__)
        code = code or 1
    # Like mainui: don't wait for background threads.
    sys.__stdout__.flush()
    os._exit(code)


def _unplayed_script_steps():
    from devices.device import Device
    device = Device.get_device()
    controller = getattr(device, "controller_interface", None)
    return getattr(controller, "unplayed", [])


if __name__ == "__main__":
    main()
