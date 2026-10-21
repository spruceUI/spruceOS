"""Accent Color: recolour the active theme to any accent colour, on the device.

Works with any theme that ships accent templates (an ``accent/`` folder with
``manifest.json``), e.g. NextUI Style and NextUI Style Light. Draws RGB sliders, hex entry
(PyUI's on-screen keyboard) and presets with a live preview, recolours the theme with
accent_engine.py and exits; spruce restarts PyUI, which loads the new colours.

Start-up mirrors App/Cheevos (cheevos/ui/pyui/bootstrap.py): PyUI's main-ui directory goes
first on sys.path (PyUI finds its lang/ and fonts relative to sys.path[0]), PyUI's logging
is routed to this app's log file, and the app keeps its own PyUI state file so the main
menu's state is never touched.
"""
import argparse
import logging
import os
import sys
import time

APP_DIR = os.path.dirname(os.path.abspath(__file__))
MAIN_UI_DIR = os.environ.get("PYUI_MAIN_UI_DIR", "/mnt/SDCARD/App/PyUI/main-ui")
if MAIN_UI_DIR in sys.path:
    sys.path.remove(MAIN_UI_DIR)
sys.path.insert(0, MAIN_UI_DIR)
sys.path.append(APP_DIR)

from controller.controller import Controller  # noqa: E402  (PyUI, importable after the path setup)
from controller.controller_inputs import ControllerInput  # noqa: E402
from devices.device import Device  # noqa: E402
from devices.miyoo.user_config import UserConfig  # noqa: E402
from display.display import Display  # noqa: E402
from display.font_purpose import FontPurpose  # noqa: E402
from display.on_screen_keyboard import OnScreenKeyboard  # noqa: E402
from display.render_mode import RenderMode  # noqa: E402
from menus.language.language import Language  # noqa: E402
from themes.theme import Theme  # noqa: E402
from utils.cfw_system_config import CfwSystemConfig  # noqa: E402
from utils.logger import PyUiLogger  # noqa: E402
from utils.py_ui_config import PyUiConfig  # noqa: E402
from utils.py_ui_state import PyUiState  # noqa: E402

import accent_engine as eng  # noqa: E402

PRESETS = [("White", "#FFFFFF"), ("NextUI Red", "#9B2257"), ("Red", "#E5484D"), ("Orange", "#F28C28"),
           ("Yellow", "#F5C518"), ("Green", "#3DBE6B"), ("Teal", "#1FB5A8"), ("Blue", "#2F7DE1"),
           ("Purple", "#8E5BE8"), ("Pink", "#FF4FA3")]
ROWS = ["R", "G", "B", "HEX", "PRESET"]
# screen colours; replaced from the theme's palette (dark or light version) at start-up
WHITE, GRAY, DARK, TRACK, BG = (255, 255, 255), (138, 138, 138), (34, 36, 40), (60, 62, 70), (0, 0, 0)
CHANNEL = [(230, 70, 70), (70, 200, 110), (70, 140, 240)]


def set_palette(pal):
    """WHITE = main text/ink, GRAY = secondary, DARK = preview card, TRACK = slider track."""
    global WHITE, GRAY, DARK, TRACK, BG
    WHITE, GRAY = eng.parse_hex(pal["ink"]), eng.parse_hex(pal["sub"])
    DARK, TRACK, BG = eng.parse_hex(pal["card"]), eng.parse_hex(pal["track"]), eng.parse_hex(pal["bg"])


def log():
    return PyUiLogger.get_logger()


def parse_args():
    p = argparse.ArgumentParser(prog="accent_picker.py")
    p.add_argument("-device", default=os.environ.get("ACCENT_PYUI_DEVICE"),
                   help="PyUI device name (launch.sh sets ACCENT_PYUI_DEVICE)")
    p.add_argument("-pyUiConfig", default="/mnt/SDCARD/App/PyUI/py-ui-config.json")
    p.add_argument("-cfwConfig", default="/mnt/SDCARD/Saves/spruce/spruce-config.json")
    p.add_argument("-logDir", default="/mnt/SDCARD/Saves/spruce")
    p.add_argument("-stateFile", default="/mnt/SDCARD/Saves/accentcolor/pyui-state.json")
    args, _ = p.parse_known_args()
    return args


def setup_logging(log_dir):
    """Route PyUI's logger to this app's own file (like Cheevos; no stdout/stderr takeover)."""
    os.makedirs(log_dir, exist_ok=True)
    logger = logging.getLogger("AccentColor")
    logger.setLevel(logging.INFO)
    handler = logging.FileHandler(
        os.path.join(log_dir, f"accentcolor-{os.environ.get('PLATFORM', 'unknown')}.log"))
    handler.setFormatter(logging.Formatter("%(asctime)s - %(levelname)s - %(message)s"))
    logger.addHandler(handler)
    PyUiLogger._logger = logger  # PyUI's only logger handle; every module uses get_logger()


def init(args):
    """PyUI start-up in mainui.py's order: config, device, state, theme, display, controller."""
    PyUiConfig.init(args.pyUiConfig)
    UserConfig.reload_config()
    CfwSystemConfig.init(args.cfwConfig if args.cfwConfig and os.path.isfile(args.cfwConfig) else None)
    Language.init()
    try:
        from devices.device_factory import initialize_device
    except ModuleNotFoundError as error:
        if error.name != "devices.device_factory":
            raise
        from mainui import initialize_device  # older SpruceOS releases
    initialize_device(args.device, main_ui_mode=False)
    device = Device.get_device()
    device.restore_saved_timezone()
    os.makedirs(os.path.dirname(args.stateFile), exist_ok=True)
    if not os.path.exists(args.stateFile):
        with open(args.stateFile, "w") as fh:
            fh.write("{}")
    PyUiState.init(args.stateFile)
    theme_dir = os.path.join(PyUiConfig.get("themeDir"), device.get_system_config().get_theme())
    Theme.init(theme_dir, device.screen_width(), device.screen_height())
    Display.init()
    Display.present()
    Controller.init()
    return theme_dir


class Picker:
    def __init__(self, theme_dir):
        self.theme_dir = theme_dir
        set_palette(eng.theme_palette(theme_dir))
        self.saved = eng.current_accent(theme_dir)
        self.rgb = list(self.saved)
        self.row = 0
        self.preset = 0
        self.W = Device.get_device().screen_width()
        self.H = Device.get_device().screen_height()
        self.s = min(self.W / 640, self.H / 480)

    def px(self, v):
        return int(round(v * self.s))

    # ---------- drawing ----------
    def draw(self):
        Display.clear("", bottom_bar_text="<> ADJUST   L1/R1 x16   A APPLY   B CANCEL")
        W, px = self.W, self.px
        acc = tuple(self.rgb)
        sel = eng.selected_text_color(acc)
        bar_h = Display.get_top_bar_height()
        # cover the Games/Apps/Settings tabs spruce draws in the top bar; this screen has its own title
        Display.render_box(BG, 0, 0, W - px(150), bar_h)
        Display.render_text("ACCENT COLOR", px(20), bar_h // 2, WHITE, FontPurpose.DESCRIPTIVE_LIST_TITLE, RenderMode.MIDDLE_LEFT_ALIGNED)
        top = bar_h + px(4)
        row_h = px(54)
        y0 = top + px(10)
        label_x, track_x, track_w = px(24), px(100), px(250)

        for i, name in enumerate(ROWS):
            y = y0 + i * row_h
            cy = y + row_h // 2
            if i == self.row:  # tab-style marker: accent bar on the left of the row
                Display.render_box(acc, 0, y + px(6), px(8), row_h - px(12))
            color = WHITE if i == self.row else GRAY
            if i < 3:
                Display.render_text(name, label_x, cy, color, FontPurpose.DESCRIPTIVE_LIST_TITLE, RenderMode.MIDDLE_LEFT_ALIGNED)
                th = px(14)
                Display.render_box(TRACK, track_x, cy - th // 2, track_w, th)
                fill = int(track_w * self.rgb[i] / 255)
                if fill > 0:
                    Display.render_box(CHANNEL[i], track_x, cy - th // 2, fill, th)
                kw = px(8)
                Display.render_box(WHITE, track_x + fill - kw // 2, cy - px(13), kw, px(26))
                Display.render_text(str(self.rgb[i]), track_x + track_w + px(64), cy, color,
                                    FontPurpose.DESCRIPTIVE_LIST_TITLE, RenderMode.MIDDLE_RIGHT_ALIGNED)
            elif name == "HEX":
                Display.render_text("HEX", label_x, cy, color, FontPurpose.DESCRIPTIVE_LIST_TITLE, RenderMode.MIDDLE_LEFT_ALIGNED)
                Display.render_text(eng.to_hex(acc) + ("   (A to type)" if i == self.row else ""), track_x, cy, color,
                                    FontPurpose.DESCRIPTIVE_LIST_TITLE, RenderMode.MIDDLE_LEFT_ALIGNED)
            else:
                Display.render_text("PRESET", label_x, cy, color, FontPurpose.DESCRIPTIVE_LIST_TITLE, RenderMode.MIDDLE_LEFT_ALIGNED)
                Display.render_text("< " + PRESETS[self.preset][0] + " >", track_x + px(20), cy, color,
                                    FontPurpose.DESCRIPTIVE_LIST_TITLE, RenderMode.MIDDLE_LEFT_ALIGNED)

        # live preview on the right: a list row highlighted in the accent, plus a hint circle
        pv_x, pv_w = px(450), W - px(450) - px(16)
        pv_y = y0
        Display.render_box(DARK, pv_x, pv_y, pv_w, px(200))
        Display.render_text("Game Boy", pv_x + px(14), pv_y + px(30), WHITE, FontPurpose.DESCRIPTIVE_LIST_TITLE, RenderMode.MIDDLE_LEFT_ALIGNED)
        Display.render_box(acc, pv_x + px(4), pv_y + px(58), pv_w - px(4), px(44))
        Display.render_text("GBA", pv_x + px(14), pv_y + px(80), sel, FontPurpose.DESCRIPTIVE_LIST_TITLE, RenderMode.MIDDLE_LEFT_ALIGNED)
        Display.render_text("SNES", pv_x + px(14), pv_y + px(128), WHITE, FontPurpose.DESCRIPTIVE_LIST_TITLE, RenderMode.MIDDLE_LEFT_ALIGNED)
        d = px(28)
        Display.render_box(acc, pv_x + px(14), pv_y + px(160), d, d)
        Display.render_text("A", pv_x + px(14) + d // 2, pv_y + px(160) + d // 2, sel, FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION, RenderMode.MIDDLE_CENTER_ALIGNED)
        Display.render_text("OPEN", pv_x + px(52), pv_y + px(160) + d // 2, WHITE, FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION, RenderMode.MIDDLE_LEFT_ALIGNED)
        Display.present()

    def draw_progress(self, done, total, label):
        Display.clear("", bottom_bar_text=" ")
        cy = self.H // 2
        Display.render_text(label, self.W // 2, cy - self.px(40), WHITE, FontPurpose.DESCRIPTIVE_LIST_TITLE, RenderMode.MIDDLE_CENTER_ALIGNED)
        bw, bh = self.px(400), self.px(16)
        x = (self.W - bw) // 2
        Display.render_box(TRACK, x, cy, bw, bh)
        if total:
            Display.render_box(tuple(self.rgb), x, cy, int(bw * done / total), bh)
        Display.present()

    # ---------- input ----------
    def adjust(self, delta):
        if self.row < 3:
            self.rgb[self.row] = max(0, min(255, self.rgb[self.row] + delta))
        elif ROWS[self.row] == "PRESET":
            self.preset = (self.preset + (1 if delta > 0 else -1)) % len(PRESETS)
            self.rgb = list(eng.parse_hex(PRESETS[self.preset][1]))

    def type_hex(self):
        text = OnScreenKeyboard().get_input("Hex color (RRGGBB)", eng.to_hex(self.rgb).lstrip("#"))
        if text:
            try:
                self.rgb = list(eng.parse_hex(text))
            except ValueError:
                Display.display_message("Not a hex color - use 6 digits, e.g. F5C518", 2000)

    def apply(self):
        # current screen's folder first so the colour you see next is ready soonest
        current = getattr(Theme, "_skin_folder", "skin")
        self.draw_progress(0, 1, "Applying " + eng.to_hex(self.rgb) + "...")
        eng.apply_accent(self.theme_dir, self.rgb, folders=[current],
                         progress=lambda d, t: self.draw_progress(d, t, "Applying " + eng.to_hex(self.rgb) + "..."))
        # then every other screen size, so the SD card looks right in other devices too
        others = [f for f in eng.template_folders(self.theme_dir) if f != current]
        eng.apply_accent(self.theme_dir, self.rgb, folders=others,
                         progress=lambda d, t: self.draw_progress(d, t, "Updating other screen sizes..."))

    def run(self):
        held_since, last = None, None
        while True:
            self.draw()
            if not Controller.get_input():
                held_since, last = None, None
                continue
            inp = Controller.last_input()
            # holding left/right speeds up after half a second
            now = time.time()
            if inp != last:
                held_since, last = now, inp
            step = 1 if now - held_since < 0.5 else 5
            if inp == ControllerInput.DPAD_UP:
                self.row = (self.row - 1) % len(ROWS)
            elif inp == ControllerInput.DPAD_DOWN:
                self.row = (self.row + 1) % len(ROWS)
            elif inp == ControllerInput.DPAD_LEFT:
                self.adjust(-step)
            elif inp == ControllerInput.DPAD_RIGHT:
                self.adjust(step)
            elif inp == ControllerInput.L1:
                self.adjust(-16)
            elif inp == ControllerInput.R1:
                self.adjust(16)
            elif inp == ControllerInput.A:
                if ROWS[self.row] == "HEX":
                    self.type_hex()
                else:
                    self.apply()
                    return True
            elif inp == ControllerInput.B:
                return False


def main():
    args = parse_args()
    setup_logging(args.logDir)
    if not args.device:
        log().error("No PyUI device: start the app through launch.sh")
        return 2
    log().info("Starting on %s (%s)", os.environ.get("PLATFORM", "unknown"), args.device)
    theme_dir = init(args)
    if not os.path.isfile(os.path.join(theme_dir, "accent", "manifest.json")):
        Display.display_message("This theme doesn't support Accent Color. Try NextUI Style.", 3500)
        return 0
    try:
        applied = Picker(theme_dir).run()
        log().info("Exiting (%s)", "applied" if applied else "cancelled")
    except Exception:
        log().exception("Accent picker failed")
        Display.display_message("Accent Color hit an error - see Saves/spruce/accentcolor log.", 3500)
        return 1
    return 0


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    os._exit(code)  # like mainui: do not wait for PyUI's background threads
