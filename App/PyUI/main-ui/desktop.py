"""Run PyUI in a window on a Mac or PC: python3 App/PyUI/main-ui/desktop.py --help

The whole launcher (mainui.py) on the DESKTOP device, reading the SpruceOS checkout as its SD
card. See App/PyUI/docs/desktop_readme.txt.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import warnings
from pathlib import Path

from devices.desktop.desktop_options import DEFAULT_DATA_DIR, SPRUCE_ROOT, parse_resolution
from devices.desktop.desktop_script import ScriptError, parse_script

SD_ROOT = "/mnt/SDCARD/"
# Keys of py-ui-config.json that are left out on the desktop: the CFW's scripts and lists of
# them. Every key ending in "Cmd" is dropped too.
CFW_SCRIPT_KEYS = ("aboutEntries", "cfwTasks")

# PyUI runs in a child process, which tells desktop.py how it ended by its exit status. PyUI
# exits by itself whenever it wants to be started again - after a theme change, a theme
# conversion, a mode change, a deleted ROM, a crash - since spruce's principal.sh always starts
# it again: os._exit(0) or sys.exit(), status RESTART. The run ends with STOPPED (Esc, closing
# the window, Power Off, the end of a --script) or any other status.
RUN_PYUI = "--run-pyui"
RESTART = 0
STOPPED = 3
# A restart that comes this soon after starting, with no script step played, made no progress;
# this many in a row and desktop.py gives up rather than open the window forever.
QUICK_EXIT_SECONDS = 2
QUICK_EXITS_TO_STOP = 3


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
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == [RUN_PYUI]:
        run_pyui(argv[1:])
    args, mainui_args = parse_arguments(argv)
    env = desktop_environment(args)
    sdcard = Path(env["PYUI_DESKTOP_SDCARD"])
    data = Path(env["PYUI_DESKTOP_DATA"])
    themes = args.themes.expanduser().resolve() if args.themes else None
    if args.headless:
        env["SDL_AUDIODRIVER"] = os.environ.get("SDL_AUDIODRIVER", "dummy")

    (data / "logs").mkdir(parents=True, exist_ok=True)
    # principal.sh logs PyUI's start here before launching it, so PyUI expects the file.
    activity_log = data / "Saves" / "spruce" / "activity.jsonl"
    activity_log.parent.mkdir(parents=True, exist_ok=True)
    activity_log.touch()
    pyui_args = ["-device", "DESKTOP", "-pyUiConfig", str(prepare_pyui_config(sdcard, data, themes)),
                 "-logDir", str(data / "logs")]
    cfw_config = prepare_cfw_config(sdcard, data)
    if cfw_config is not None:
        pyui_args += ["-cfwConfig", str(cfw_config)]
    # Arguments for mainui.py select its one-shot modes (a message, an option list), which
    # are not started again.
    sys.exit(supervise(pyui_args + mainui_args, env, restart=not mainui_args))


def supervise(pyui_args, env, restart):
    """Run PyUI until the run is over, starting it again whenever it exits by itself."""
    script = env["PYUI_DESKTOP_SCRIPT"]
    quick_exits = 0
    with tempfile.TemporaryDirectory(prefix="pyui-desktop-") as scratch:
        script_state = Path(scratch) / "script"
        env = {**os.environ, **env, "PYUI_DESKTOP_SCRIPT_STATE": str(script_state)}
        while True:
            started = time.monotonic()
            code = run_child(pyui_args, env)
            if code != RESTART or not restart:
                return 0 if code in (STOPPED, RESTART) else code
            left = script_state.read_text(encoding="utf-8") if script_state.exists() else script
            if script and not left and (env["PYUI_DESKTOP_HEADLESS"] or env["PYUI_DESKTOP_EXIT_AFTER_SCRIPT"]):
                return 0
            progressed = left != script or time.monotonic() - started > QUICK_EXIT_SECONDS
            quick_exits = 0 if progressed else quick_exits + 1
            if quick_exits == QUICK_EXITS_TO_STOP:
                print(f"PyUI exited {quick_exits} times in a row as it started; giving up. "
                      f"See {Path(env['PYUI_DESKTOP_DATA']) / 'logs' / 'pyui.log'}", file=sys.stderr)
                return 1
            print("PyUI exited to be started again, as spruce does; starting it", file=sys.stderr)
            script = left
            env["PYUI_DESKTOP_SCRIPT"] = script
            # From now on the theme is the one picked in PyUI.
            env.pop("PYUI_DESKTOP_THEME", None)


def run_child(pyui_args, env):
    child = subprocess.Popen([sys.executable, os.path.abspath(__file__), RUN_PYUI, *pyui_args], env=env)
    try:
        return child.wait()
    except KeyboardInterrupt:  # Ctrl+C reaches PyUI too; let it finish
        child.wait()
        return 130


def run_pyui(pyui_args):
    """The child process: mainui.py on the DESKTOP device, configured by desktop.py's
    PYUI_DESKTOP_* variables. Exits with RESTART, STOPPED or a failure status."""
    # pysdl2-dll is what a desktop should use; its notice on import is noise.
    warnings.filterwarnings("ignore", message="Using SDL2 binaries from pysdl2-dll")
    from devices.desktop.desktop_controller_interface import DesktopQuit, ScriptFinished
    from devices.miyoo.user_config import UserConfig
    import mainui

    # Hard-coded to the SD card; mainui reads it before the device exists.
    UserConfig.FILEPATH = str(Path(os.environ["PYUI_DESKTOP_DATA"]) / "Saves" / "pyui-common.json")
    sys.argv = [mainui.__file__, *pyui_args]
    code = RESTART
    try:
        mainui.main()
    except (DesktopQuit, ScriptFinished):
        code = STOPPED
    except SystemExit:
        code = RESTART
    except KeyboardInterrupt:  # Ctrl+C in the terminal
        code = 130
    unplayed = _unplayed_script_steps()
    if code == STOPPED and unplayed:
        print(f"PyUI left the menu with {len(unplayed)} script steps not played: {unplayed}",
              file=sys.__stderr__)
        code = 1
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
