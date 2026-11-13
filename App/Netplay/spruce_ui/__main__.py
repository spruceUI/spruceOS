"""Netplay's spruce front end. All session work stays in netplay.elf.

Two ways in: launch.sh runs it as its own process (python -m spruce_ui), which
brings PyUI up itself; and spruce's PyUI runs it inside its own process from
the Apps menu ("pyuiEntry" in config.json -> pyui.run -> run_in_pyui), where
PyUI is already up and everything put into it is taken out again on exit."""

from __future__ import annotations

import logging
import math
import os
import subprocess
import sys
import threading
from pathlib import Path

CARD = Path(os.environ.get("SDCARD_PATH", "/mnt/SDCARD"))
PAK = Path(os.environ.get("NETPLAY_PAK", CARD / "App/Netplay"))
PLATFORM = os.environ.get("PLATFORM", "")
ENGINE = PAK / "bin" / PLATFORM / "netplay.elf"
# In PyUI's process: netplay.elf's environment, as launch.sh --env prints it.
ENGINE_ENV: dict[str, str] | None = None
STATE = Path(os.environ.get("NETPLAY_STATE", CARD / "Saves/netplay"))
HINT = "B BACK    A SELECT"
FOOTER_CONTEXT = None
GLYPH_SCRATCH = None
CORE_RESULTS: dict[str, tuple[bool, str]] = {}
CORE_READY = threading.Event()
PROMPTING = False


def control(*args: str) -> str:
    env = os.environ.copy()
    if ENGINE_ENV is not None:
        env.update(ENGINE_ENV)
    # netplay.elf links only libc: give it spruce's library path, not PyUI's.
    if "NETPLAY_ENGINE_LD_LIBRARY_PATH" in env:
        env["LD_LIBRARY_PATH"] = env["NETPLAY_ENGINE_LD_LIBRARY_PATH"]
    result = subprocess.run(
        [str(ENGINE), "--ctl", *args], capture_output=True, text=True, check=False, env=env
    )
    if result.returncode:
        raise RuntimeError(result.stdout.strip() or result.stderr.strip() or "Netplay command failed")
    return result.stdout


def fields(text: str) -> dict[str, str]:
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)


def warm_cores() -> None:
    """Read spruce's core choices while the user is still on the main screen."""
    def read():
        try:
            CORE_RESULTS["all"] = (True, control("cores"))
        except Exception as error:
            CORE_RESULTS["all"] = (False, str(error))
        finally:
            CORE_READY.set()

    threading.Thread(target=read, daemon=True).start()


def bootstrap() -> None:
    main_ui = CARD / "App/PyUI/main-ui"
    sys.path.insert(0, str(main_ui))
    from utils.logger import PyUiLogger
    from utils.py_ui_config import PyUiConfig
    from utils.py_ui_state import PyUiState
    from utils.cfw_system_config import CfwSystemConfig
    from devices.miyoo.user_config import UserConfig
    from devices.device import Device
    from menus.language.language import Language
    from themes.theme import Theme
    from display.display import Display
    from controller.controller import Controller

    PyUiLogger._logger = logging.getLogger("netplay.pyui")
    PyUiConfig.init(str(CARD / "App/PyUI/py-ui-config.json"))
    if os.environ.get("NETPLAY_PYUI_USER_CONFIG"):
        UserConfig.FILEPATH = os.environ["NETPLAY_PYUI_USER_CONFIG"]
    UserConfig.reload_config()
    CfwSystemConfig.init(str(CARD / "Saves/spruce/spruce-config.json"))
    Language.init()
    try:
        from devices.device_factory import initialize_device
    except ModuleNotFoundError as error:
        if error.name != "devices.device_factory":
            raise
        from mainui import initialize_device
    initialize_device(os.environ["NETPLAY_PYUI_DEVICE"], main_ui_mode=False)
    device = Device.get_device()
    device.restore_saved_timezone()
    state_file = STATE / "pyui-state.json"
    if not state_file.exists():
        state_file.write_text("{}\n", encoding="utf-8")
    PyUiState.init(str(state_file))
    theme = device.get_system_config().get_theme()
    Theme.init(str(Path(PyUiConfig.get("themeDir")) / theme), device.screen_width(), device.screen_height())
    Display.init()
    Display.present()
    Controller.init()


_BAR_SAVED: tuple[bool, object] | None = None


def enter() -> None:
    """Put Netplay into an initialised PyUI: scratch space for generated
    glyphs, and our footer in place of PyUI's bottom bar. leave() undoes it."""
    global GLYPH_SCRATCH, _BAR_SAVED
    from display.display import Display
    from . import generated
    import tempfile
    GLYPH_SCRATCH = tempfile.TemporaryDirectory(prefix="netplay-ui-")
    generated.use_scratch(Path(GLYPH_SCRATCH.name))
    bar = Display.bottom_bar
    # Our override is an instance attribute over PyUI's method; remember
    # whether one was there before, so leave() restores exactly that.
    _BAR_SAVED = ("render_bottom_bar" in vars(bar), vars(bar).get("render_bottom_bar"))
    original = bar.render_bottom_bar

    def bottom_bar(bottom_bar_text=None, render_bottom_bar_icons_and_images=True, **more):
        from . import footer
        # Leave native keyboard prompts alone when no Netplay menu owns them.
        # Newer PyUI passes more keywords (bottom_bar_hints); hand them on.
        if FOOTER_CONTEXT is None and bottom_bar_text is not None:
            return original(bottom_bar_text, render_bottom_bar_icons_and_images, **more)
        original(bottom_bar_text=None, render_bottom_bar_icons_and_images=False, **more)
        left = FOOTER_CONTEXT() if FOOTER_CONTEXT else footer.hints(HINT)
        # An invitation's X is Browse, not End session.
        footer.render(left, session_active() and HINT != "PLEASE WAIT" and not PROMPTING,
                      HINT if not left else "")

    bar.render_bottom_bar = bottom_bar


def leave() -> None:
    """Take Netplay out of PyUI again: PyUI drops our modules after an
    in-process app returns, so nothing of ours may stay running or hooked."""
    global GLYPH_SCRATCH, _BAR_SAVED, FOOTER_CONTEXT
    from display.display import Display
    CORE_READY.wait(timeout=20)   # the core check is the one worker thread
    bar = Display.bottom_bar
    if _BAR_SAVED is not None:
        had, previous = _BAR_SAVED
        if had:
            bar.render_bottom_bar = previous
        elif "render_bottom_bar" in vars(bar):
            del bar.render_bottom_bar
        _BAR_SAVED = None
    FOOTER_CONTEXT = None
    if GLYPH_SCRATCH is not None:
        GLYPH_SCRATCH.cleanup()
        GLYPH_SCRATCH = None


class SessionEnded(Exception):
    """Unwind nested menus after the global X action."""


def session_active() -> bool:
    return (STATE / "session").is_file()


def menu(title: str, rows: list[tuple[str, str, str, str]], hint: str = "A SELECT    B BACK",
         selected: int = 0, extra: tuple[str, ...] = (),
         actions: dict[str, str | None] | None = None, back: str = "BACK",
         pin_last: bool = False, headings: frozenset[str] = frozenset(),
         compact_rows: frozenset[str] | None = None) -> tuple[str, str] | None:
    global HINT, FOOTER_CONTEXT
    from controller.controller_inputs import ControllerInput
    from views.grid_or_list_entry import GridOrListEntry
    from views.view_creator import ViewCreator
    from views.view_type import ViewType

    previous_hint = HINT
    HINT = hint
    entries = [GridOrListEntry(label, value_text=value or None, description=description or None,
                               value=key) for key, label, description, value in rows]
    if not entries:
        entries = [GridOrListEntry("Nothing found", description="B to go back", value="empty")]
    view = ViewCreator.create_view(ViewType.ICON_AND_DESC, entries, title, selected_index=selected)
    if compact_rows is not None:
        from .core_list import style_rows
        style_rows(view, rows, headings, compact_rows)
    if pin_last:
        pin_last_row(view, len(rows) - 1, rows[-1][1])
    if headings:
        adjust = view.adjust_selected

        def skip_headings(amount, skip_by_letter):
            adjust(amount, skip_by_letter)
            while rows[view.selected][0] in headings:
                adjust(1 if amount > 0 else -1, False)

        view.adjust_selected = skip_headings
    from .buttons import Button
    from .footer import hints

    def contextual_hints():
        key = rows[min(max(int(view.selected), 0), len(rows) - 1)][0] if rows else "empty"
        if actions is None:
            left = hints(hint)
        else:
            action = actions.get(key, "SELECT")
            left = [(Button.B, back)] + ([(Button.A, action)] if action else [])
        # Back/Exit is contextual even for ordinary selection lists.
        return [(button, back if button == Button.B else label) for button, label in left]

    previous = FOOTER_CONTEXT
    FOOTER_CONTEXT = contextual_hints
    accepted = [ControllerInput.A, ControllerInput.B, ControllerInput.X] + [ControllerInput[name] for name in extra]
    try:
        while True:
            selection = view.get_selection(accepted)
            pressed = selection.get_input()
            if pressed == ControllerInput.X:
                if session_active() and attempt("Netplay", "Ending session", "end"):
                    raise SessionEnded()
                continue
            if pressed == ControllerInput.B:
                return None
            if pressed in accepted and actions is not None:
                key = str(selection.get_selection().value)
                collapsing = compact_rows is not None and pressed.name == "DPAD_LEFT"
                if not collapsing and not actions.get(key, "SELECT"):
                    continue
            if pressed in accepted and pressed != ControllerInput.B:
                return str(selection.get_selection().value), pressed.name
    finally:
        HINT, FOOTER_CONTEXT = previous_hint, previous
        finished = getattr(view, "view_finished", None)
        if finished:
            finished()


def pin_last_row(view, index: int, label: str) -> None:
    from devices.device import Device
    from display.display import Display
    from display.font_purpose import FontPurpose
    from display.render_mode import RenderMode
    from display.resize_type import ResizeType
    from themes.theme import Theme

    render = view._render
    hit_test = getattr(view, "row_at_touch_point", None)
    height = view.each_entry_height
    width = Device.get_device().screen_width()
    bottom = Device.get_device().screen_height() - Display.bottom_bar.get_bottom_bar_height()
    y = bottom - height
    top = Display.get_top_bar_height(force_include_top_bar=True) + 5
    view.max_rows = max(1, (bottom - top) // height)
    view.current_top = 0
    view.current_bottom = min(view.max_rows, len(view.options))
    view.center_selection()

    def render_with_pinned_row():
        end = view.current_bottom
        view.current_bottom = min(end, index)
        try:
            render()
        finally:
            view.current_bottom = end
        purpose = FontPurpose.DESCRIPTIVE_LIST_TITLE
        if view.selected == index:
            Display.render_image(view.selected_bg, 0, y, target_width=width,
                                 target_height=height, resize_type=ResizeType.ZOOM)
            color = Theme.text_color_selected(purpose)
        else:
            color = Theme.text_color(purpose)
        x = Theme.get_descriptive_list_icon_offset_x() + Theme.get_descriptive_list_text_from_icon_offset()
        Display.render_text(label, x, y + height // 2, color, purpose, RenderMode.MIDDLE_LEFT_ALIGNED)

    def pinned_hit_test(point):
        if point is not None and y <= point[1] < bottom:
            return index
        hit = hit_test(point)
        return hit if hit != index else None

    view._render = render_with_pinned_row
    if hit_test:
        view.row_at_touch_point = pinned_hit_test


def message(title: str, detail: str) -> bool:
    return menu(title, [("ok", "OK", detail, "")], "A OK    B BACK") is not None


def confirm(title: str, detail: str) -> bool:
    choice = menu(title, [("yes", "Yes", detail, ""), ("no", "No", "", "")])
    return choice is not None and choice[0] == "yes"


def working(title: str, description: str, action):
    """Animate the theme's working page while native networking runs."""
    global HINT, FOOTER_CONTEXT
    from controller.controller import Controller
    from devices.device import Device
    from display.display import Display
    from display.font_purpose import FontPurpose
    from display.render_mode import RenderMode
    from themes.theme import Theme

    previous_hint, previous_context = HINT, FOOTER_CONTEXT
    HINT = "PLEASE WAIT"
    FOOTER_CONTEXT = None
    try:
        result = []

        def run():
            try:
                result.append((True, action()))
            except Exception as error:
                result.append((False, str(error)))

        thread = threading.Thread(target=run, daemon=True)
        thread.start()
        frame = 0
        while thread.is_alive():
            Display.clear(title)
            width = int(Device.get_device().screen_width())
            top = Display.get_top_bar_height()
            bottom = Display.get_bottom_bar_height()
            center_y = top + (int(Device.get_device().screen_height()) - top - bottom) // 2
            color = Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_TITLE)
            for dot in range(8):
                angle = math.tau * (dot / 8)
                x = width // 2 + int(math.cos(angle) * 19)
                y = center_y - 13 + int(math.sin(angle) * 19)
                if dot == frame % 8 or dot == (frame - 1) % 8:
                    Display.render_box(color, x, y, 5, 5)
            Display.render_text(description, width // 2, center_y + 38, color,
                                FontPurpose.DESCRIPTIVE_LIST_TITLE, RenderMode.TOP_CENTER_ALIGNED)
            Display.present()
            Controller.get_input(timeout=0.08)
            frame += 1
        thread.join()
        if not result[0][0]:
            raise RuntimeError(result[0][1])
        return result[0][1]

    finally:
        HINT, FOOTER_CONTEXT = previous_hint, previous_context


def attempt(title: str, detail: str, *args: str) -> bool:
    try:
        answer = working(title, detail, lambda: control(*args))
    except Exception as error:
        message(title, str(error))
        return False
    if answer.startswith("error "):
        message(title, answer[6:])
        return False
    return True


def onboarding() -> bool:
    marker = STATE / "onboarding-complete"
    if marker.exists():
        return True
    import json
    from controller.controller import Controller
    from controller.controller_inputs import ControllerInput
    from devices.device import Device
    from display.display import Display
    from display.font_purpose import FontPurpose
    from display.render_mode import RenderMode
    from themes.theme import Theme

    pages = json.loads((PAK / "pak_onboarding.json").read_text()).get("pages", [])
    if not pages:
        return True
    settings_now = fields(control("settings"))
    choices = {}
    for index, page in enumerate(pages):
        if page.get("setting"):
            current = settings_now.get(page["setting"], "")
            choices[index] = next((i for i, option in enumerate(page["options"])
                                   if str(option["value"]) == current), 0)
    width = int(Device.get_device().screen_width())
    height = int(Device.get_device().screen_height())
    page_index = 0
    while page_index < len(pages):
        page = pages[page_index]
        has_options = page_index in choices
        global HINT
        HINT = "A NEXT    B BACK    LEFT/RIGHT CHOOSE" if has_options else (
            "A FINISH    B BACK" if page_index == len(pages) - 1 else "A NEXT    B BACK"
        )
        Display.clear("")
        top = Display.get_top_bar_height()
        bottom = height - Display.get_bottom_bar_height()
        usable = bottom - top
        color = Theme.text_color(FontPurpose.LIST)
        Display.render_text(page["title"], width // 2, top + int(usable * 0.14),
                            color, FontPurpose.MESSAGE,
                            RenderMode.MIDDLE_CENTER_ALIGNED)
        lines = Display.split_message(page["description"], FontPurpose.LIST,
                                      clip_to_device_width=True)
        Display.write_message_multiline(lines, top + int(usable * (0.44 if has_options else 0.51)))
        if has_options:
            options = page["options"]
            for i, option in enumerate(options):
                x = width * (i + 1) // (len(options) + 1)
                picked = choices[page_index] == i
                label = f"< {option['label']} >" if picked else option["label"]
                Display.render_text(label, x, top + int(usable * 0.76),
                                    Theme.text_color_selected(FontPurpose.LIST) if picked else color,
                                    FontPurpose.LIST, RenderMode.MIDDLE_CENTER_ALIGNED)
        dots_y = bottom - max(20, int(usable * 0.08))
        step = max(18, min(28, width // 24))
        first_x = width // 2 - (len(pages) - 1) * step // 2
        for i in range(len(pages)):
            Display.render_text("●" if i == page_index else "○", first_x + i * step,
                                dots_y, color, FontPurpose.LIST, RenderMode.MIDDLE_CENTER_ALIGNED)
        Display.present()
        if not Controller.get_input():
            continue
        pressed = Controller.last_input()
        if pressed == ControllerInput.X and session_active():
            attempt("Netplay", "Ending session", "end")
        elif pressed == ControllerInput.B:
            if page_index == 0:
                return False
            page_index -= 1
        elif has_options and pressed in (ControllerInput.DPAD_LEFT, ControllerInput.DPAD_RIGHT):
            delta = -1 if pressed == ControllerInput.DPAD_LEFT else 1
            choices[page_index] = (choices[page_index] + delta) % len(page["options"])
        elif pressed == ControllerInput.A:
            page_index += 1
    for index, selected in choices.items():
        page = pages[index]
        if not attempt(page["title"], "Saving choice", "set", page["setting"],
                       str(page["options"][selected]["value"])):
            return False
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text("1\n")
    return True


def host() -> None:
    status = fields(control("status"))
    choices = []
    if status.get("can_host_adhoc") == "1":
        choices.append(("adhoc", "Create ad hoc network", "Fast local connection", ""))
    choices.append(("wifi", "Host over WiFi", "Use the current network", ""))
    choice = menu("Host", choices)
    if choice:
        attempt("Hosting", "Checking and starting session", "host", choice[0])


def join() -> None:
    while True:
        if not join_once():
            return


def join_once() -> bool:
    try:
        result = working("Join", "Looking for hosts", lambda: control("peers", "3"))
    except Exception as error:
        message("Join", str(error))
        return False
    peers = [parts for line in result.splitlines() if line.startswith("peer\t")
             if len(parts := line.split("\t")) >= 8]
    rows = []
    for i, peer in enumerate(peers):
        _, ip, nick, platform, protocol, hotspot, ssid, _psk = peer[:8]
        label = nick or ssid or ip
        rows.append((str(i), label, f"{platform} · {'Ad hoc' if hotspot == '1' else ip}",
                     "RetroArch" if protocol == "1" else "Linkplay"))
    if not rows:
        message("Join", "No hosts found. Check Wi-Fi and try again.")
        return False
    choice = menu("Join", rows, "A JOIN    B BACK    Y RESCAN", extra=("Y",))
    if choice is None:
        return False
    if choice[1] == "Y":
        return True
    peer = peers[int(choice[0])]
    _, ip, _nick, _platform, protocol, hotspot, ssid, psk = peer[:8]
    args = ("join-peer", ip, "retroarch" if protocol == "1" else "linkplay")
    if hotspot == "1":
        args += (ssid, psk)
    attempt("Joining", "Connecting and checking cores", *args)
    return False


def settings() -> None:
    while True:
        values = fields(control("settings"))
        rows = [
            ("host_protocol", "Host protocol", "Protocol used for the next session",
             "RetroArch" if values.get("host_protocol") == "retroarch" else "Linkplay"),
            ("hybrid_network", "Hybrid Network Traffic", "UDP inputs and hashes; applies to the next session",
             "On" if values.get("hybrid_network", "1") == "1" else "Off"),
            ("compatibility_cores", "Compatibility cores", "Use matched cores when builds differ",
             "On" if values.get("compatibility_cores") == "1" else "Off"),
            ("disable_powersave", "Disable Wi-Fi Power Saving", "May improve connection timing",
             "On" if values.get("disable_powersave") == "1" else "Off"),
        ]
        choice = menu("Settings", rows, actions={row[0]: "CHANGE" for row in rows})
        if choice is None:
            return
        key = choice[0]
        if key == "host_protocol":
            value = "linkplay" if values[key] == "retroarch" else "retroarch"
        else:
            value = "0" if values.get(key, "1" if key == "hybrid_network" else "0") == "1" else "1"
            if key == "disable_powersave" and value == "1" and not confirm(
                "Wi-Fi Power Saving", "This may reload the Wi-Fi driver for several seconds."
            ):
                continue
        if key == "disable_powersave":
            attempt("Settings", "Applying change", "powersave", "off" if value == "1" else "on")
        else:
            attempt("Settings", "Applying change", "set", key, value)


CORE_GROUPS = (
    ("GB", "GB/GBC"), ("GBA", "GBA"), ("GG", "Game Gear"), ("NDS", "NDS"),
    ("FC", "NES / FC"), ("SFC", "SNES / SFC"), ("MD", "Genesis / MegaDrive"),
    ("SEGACD", "SegaCD / 32X"), ("SMS", "Master System"), ("PS", "PS"),
)
CORE_HEADINGS = frozenset(("link", "shared"))


def core_engines(output: str) -> dict[str, list[tuple[str, str, str, bool]]]:
    engines = {tag: [] for tag, _ in CORE_GROUPS}
    for line in output.splitlines():
        parts = line.split("\t")
        if len(parts) != 6 or parts[0] != "core_engine":
            continue
        _, tag, core, label, state, more = parts
        if tag in engines and state not in ("absent", "unavailable"):
            engines[tag].append((core, label, state, more == "1"))
    return engines


def core_rows(output: str, expanded: set[str] | None = None):
    expanded = expanded or set()
    engines = core_engines(output)
    rows, actions = [], {}
    for tag, label in CORE_GROUPS:
        if tag in ("GB", "FC"):
            key = "link" if tag == "GB" else "shared"
            rows.append((key, "Link Play" if key == "link" else "Shared Screen", "", ""))
            actions[key] = None
        if len(engines[tag]) == 1:
            core, name, state, more = engines[tag][0]
            mark = "✓" if state in ("ready", "dual", "paired", "instanced") else "○"
            rows.append((tag, f"{label} ({name})", "", mark + ("  >" if more else "")))
            actions[tag] = "SELECT" if more else None
            continue
        if not engines[tag]:
            rows.append((tag, label, "", ""))
            actions[tag] = None
            continue
        rows.append((tag, label, "", "▾"))
        actions[tag] = "COLLAPSE" if tag in expanded else "EXPAND"
        if tag not in expanded:
            continue
        for core, name, state, more in engines[tag]:
            key = f"{tag}/{core}"
            mark = "✓" if state in ("ready", "dual", "paired", "instanced") else "○"
            rows.append((key, name, "", mark + ("  >" if more else "")))
            actions[key] = "SELECT" if more else None
    return rows, actions


DUAL_CHOICES = (("0", "No"), ("1", "Yes"))
GPSP_CABLE = (("mul_poke", "Pokémon Gen III"), ("mul_aw1", "Advance Wars 1"), ("mul_aw2", "Advance Wars 2"))
ARMGBA_COMMON = (
    ("armgba_link_players", "Number of Players", (("2", "2"), ("3", "3"), ("4", "4"))),
)
CORE_OPTIONS = {
    "GB": (
        ("armGBA", ARMGBA_COMMON + (
            ("armgba_gb_link_port", "Link Port", (("cable", "Link Cable"), ("adapter", "Four Player Adapter"))),
            ("armgba_gb_link_timing", "Link Timing", (("standard", "Standard"), ("exact", "Exact"))),
            ("armgba_gb_model", "Game Boy Model", tuple((model, model) for model in
                ("Auto", "Game Boy", "Game Boy Pocket", "Game Boy Color", "Game Boy Advance"))),
        )),
    ),
    "GBA": (
        ("gpSP", (("gpsp_mode", "Link Type", (
            ("auto", "Automatic"), ("rfu", "Wireless Adapter"), ("cable", "Link Cable"),
        )),)),
        ("armGBA", ARMGBA_COMMON + (
            ("armgba_link_port", "Link Port", (("cable", "Link Cable"), ("wireless", "Wireless Adapter"))),
        )),
    ),
}


def core_options(tag: str, title: str, output: str, engine: str | None = None) -> bool:
    values = fields(output)
    dual = {"inst_gambatte": "gambatte_dual", "inst_mgba": "mgba_dual"}
    sections = CORE_OPTIONS.get(tag, ())
    if engine is not None:
        sections = tuple((name, options) for name, options in sections if name.lower() == engine)
    # Which core, paired or not, and armGBA's Link Mode are Netplay's call
    # (app/engines.c): a core with only those has nothing here.
    if not sections:
        return False
    selected = 0
    changed = False
    cable_game = values.get("gpsp_serial", "")
    if cable_game not in dict(GPSP_CABLE):
        cable_game = GPSP_CABLE[0][0]
    while True:
        rows, actions, choices = [], {}, {}
        for core, options in sections:
            if core == "gpSP":
                serial = values.get("gpsp_serial", "auto")
                values["gpsp_mode"] = "cable" if serial in dict(GPSP_CABLE) else serial
                if values["gpsp_mode"] == "cable":
                    options += (("gpsp_serial", "Cable Game", GPSP_CABLE),)
            for key, label, options_for_key in options:
                available = key not in dual or values.get(dual[key]) == "1"
                labels = dict(options_for_key)
                current = values.get(key)
                value = f"< {labels.get(current, options_for_key[0][1])} >" if available else "Unavailable"
                rows.append((key, "  " + label, "", value))
                actions[key] = "CHANGE" if available else None
                choices[key] = [option for option, _ in options_for_key]
        picked = menu(title, rows, selected=selected, extra=("DPAD_LEFT", "DPAD_RIGHT"),
                      actions=actions)
        if picked is None:
            return changed
        key, pressed = picked
        selected = next(i for i, row in enumerate(rows) if row[0] == key)
        options = choices[key]
        direction = -1 if pressed == "DPAD_LEFT" else 1
        current = values.get(key, options[0])
        index = options.index(current) if current in options else 0
        value = options[(index + direction) % len(options)]
        if key == "gpsp_mode":
            key = "gpsp_serial"
            value = cable_game if value == "cable" else value
        command = "set" if key in dual else "core-option"
        try:
            control(command, key, value)
        except RuntimeError as error:
            message(title, str(error))
        else:
            values[key] = value
            if key == "gpsp_serial" and value in dict(GPSP_CABLE):
                cable_game = value
            changed = True


def cores() -> None:
    try:
        if not CORE_READY.is_set():
            working("Cores", "Checking cores", CORE_READY.wait)
        ok, output = CORE_RESULTS["all"]
        if not ok:
            output = working("Cores", "Checking cores", lambda: control("cores"))
    except Exception as error:
        message("Cores", str(error))
        return
    selected_key = "GB"
    expanded = set()
    while True:
        rows, actions = core_rows(output, expanded)
        selected = next((i for i, row in enumerate(rows) if row[0] == selected_key), 1)
        compact = frozenset(key for key, *_ in rows if "/" in key)
        picked = menu("Cores", rows, selected=selected, actions=actions,
                      extra=("DPAD_LEFT", "DPAD_RIGHT"), headings=CORE_HEADINGS, compact_rows=compact)
        if picked is None:
            if expanded:
                expanded.clear()
                selected_key = selected_key.partition("/")[0]
                continue
            return
        selected_key, pressed = picked
        tag, _, engine = selected_key.partition("/")
        if engine and pressed == "DPAD_LEFT":
            expanded.discard(tag)
            selected_key = tag
            continue
        available = core_engines(output)[tag]
        if not engine and len(available) == 1:
            if pressed == "DPAD_LEFT":
                continue
            engine, label, _, _ = available[0]
        elif not engine:
            if pressed == "DPAD_LEFT":
                expanded.discard(tag)
            elif pressed == "DPAD_RIGHT":
                expanded.add(tag)
            elif tag in expanded:
                expanded.remove(tag)
            else:
                expanded.add(tag)
            continue
        if "/" in selected_key:
            label = next(row[1] for row in rows if row[0] == selected_key)
        title = f"{dict(CORE_GROUPS)[tag]} - {label}"
        if core_options(tag, title, output, engine=engine):
            try:
                output = working("Cores", "Checking cores", lambda: control("cores"))
                CORE_RESULTS["all"] = (True, output)
            except RuntimeError as error:
                message("Cores", str(error))
                return


def debug() -> None:
    while True:
        values = fields(control("settings"))
        rows = [(key, label, detail, "On" if values.get(key) == "1" else "Off") for key, label, detail in (
            ("force_compatibility", "Force compatibility cores", "Testing option"),
            ("verbose_logs", "Verbose debugging logs", "Keep game launch logs"),
            ("session_save_backups", "Session save backups", "Keep three original save snapshots"),
        )]
        rows += [("checks", "Run checks", "Bindings, paths, cores and network", ""),
                 ("restore", "Restore Wi-Fi", "Reconnect to your usual network", "")]
        choice = menu("Debug", rows, actions={row[0]: "RUN" if row[0] == "checks" else "RESTORE" if row[0] == "restore" else "CHANGE" for row in rows})
        if choice is None:
            return
        key = choice[0]
        if key == "checks":
            try:
                result = working("Checks", "Checking device", lambda: control("checks"))
                checks = [line.split("\t", 3) for line in result.splitlines() if line.startswith("check\t")]
                menu("Checks", [(str(i), check[2], check[3], ("OK", "Warn", "Fail")[int(check[1])])
                                for i, check in enumerate(checks)], actions={str(i): None for i in range(len(checks))})
            except Exception as error:
                message("Checks", str(error))
        elif key == "restore":
            if confirm("Restore Wi-Fi", "Reconnect to your usual network?"):
                attempt("Wi-Fi", "Restoring connection", "restore-wifi")
        else:
            attempt("Debug", "Saving setting", "set", key, "0" if values.get(key) == "1" else "1")


def configuration() -> None:
    while True:
        values = fields(control("settings"))
        rows = [("nickname", "Nickname", "Shown to other players", values.get("nickname", "")),
                ("cores", "Cores", "Supported systems and paired play", ""),
                ("settings", "Settings", "Protocol and connection options", ""),
                ("debug", "Debug", "Checks, logs and backups", ""),
                ("off", "Turn Off Netplay", "End the session and restore ordinary emulator launches", "")]
        choice = menu("Configuration", rows, actions={"nickname": "CHANGE", "off": "TURN OFF"})
        if choice is None:
            return
        key = choice[0]
        if key == "nickname":
            from display.on_screen_keyboard import OnScreenKeyboard
            nickname = OnScreenKeyboard().get_input("Nickname", values.get("nickname_custom", ""))
            if nickname is not None:
                attempt("Nickname", "Saving nickname", "set", "nickname", str(nickname)[:31])
        elif key == "cores":
            cores()
        elif key == "settings":
            settings()
        elif key == "debug":
            debug()
        elif confirm("Turn Off Netplay", "Games will launch normally until you host or join again."):
            attempt("Netplay", "Turning off", "off")
            return



def main_menu() -> bool:
    status = fields(control("status"))
    if status.get("armed") == "1":
        detail = "Hosting" if status.get("role") == "host" else "Joined " + status.get("host", "")
        rows = [("session", "Session status", detail, ""),
                ("end", "End session", "Return to normal play", ""),
                ("config", "Configuration", "", "")]
    else:
        rows = [("host", "Host", "Start a session", ""),
                ("join", "Join", "Find someone hosting", ""),
                ("config", "Configuration", "", "")]
    choice = menu("Netplay", rows, back="EXIT", pin_last=True,
                  actions={"session": "VIEW", "end": "END SESSION"})
    if choice is None:
        return False
    key = choice[0]
    if key == "host": host()
    elif key == "join": join()
    elif key == "config": configuration()
    elif key == "end" and confirm("End session", "Disconnect and restore normal play?"):
        attempt("Netplay", "Ending session", "end")
    elif key == "session":
        guests = status.get("guests", "0")
        message("Session", detail + (f" · {guests} guest(s)" if status.get("role") == "host" else ""))
    return True


def start_prompt_input(args: dict[str, str]) -> subprocess.Popen:
    """The answer comes from netplay.elf, which holds the pad exclusively while
    we ask: spruce's menu is only paused, and through SDL we could not keep our
    presses out of its queue. Started before PyUI so nothing pressed meanwhile
    reaches the menu."""
    env = os.environ.copy()
    # netplay.elf links only libc: give it spruce's library path, not PyUI's.
    if "NETPLAY_ENGINE_LD_LIBRARY_PATH" in env:
        env["LD_LIBRARY_PATH"] = env["NETPLAY_ENGINE_LD_LIBRARY_PATH"]
    command = [str(ENGINE), "--prompt", "--input-only", "1",
               "--accept", args.get("accept", ""), "--decline", args.get("decline", "NOT NOW"),
               "--browse", args.get("browse", ""), "--timeout", args.get("timeout", "60")]
    return subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)


def invite(args: dict[str, str], answer: subprocess.Popen) -> int:
    """A game invitation over spruce's paused menu, in spruce's own look."""
    global FOOTER_CONTEXT, PROMPTING
    import time
    from devices.device import Device
    from display.display import Display
    from display.font_purpose import FontPurpose
    from display.render_mode import RenderMode
    from display.resize_type import ResizeType
    from themes.theme import Theme
    from .buttons import Button

    left = [(Button.B, args.get("decline", "NOT NOW"))]
    if args.get("accept"):
        left.append((Button.A, args["accept"]))
    if args.get("browse"):
        left.append((Button.X, args["browse"]))
    FOOTER_CONTEXT, PROMPTING = (lambda: left), True
    width = int(Device.get_device().screen_width())
    height = int(Device.get_device().screen_height())
    deadline = time.monotonic() + int(args.get("timeout", "60"))
    art = args.get("art", "")
    shown = None
    while answer.poll() is None:
        remaining = max(0, int(deadline - time.monotonic() + 0.999))
        if remaining != shown:
            shown = remaining
            Display.clear(args.get("title", "Invitation"))
            top = Display.get_top_bar_height()
            bottom = height - Display.get_bottom_bar_height()
            usable = bottom - top
            y = top + usable // 20
            if art and os.path.isfile(art):
                box = int(usable * 0.55)
                Display.render_image(art, width // 2, y, RenderMode.TOP_CENTER_ALIGNED,
                                     int(width * 0.8), box, ResizeType.FIT)
                y += box + usable // 25
            else:
                y = top + usable // 3
            lines = Display.split_message(args.get("text", ""), FontPurpose.LIST,
                                          clip_to_device_width=True)
            if art and os.path.isfile(art):
                Display.write_message_multiline_starting_height_specified(lines, y)
            else:
                Display.write_message_multiline(lines, y)
            Display.render_text(f"Closes in {remaining} s", width // 2, bottom - usable // 20,
                                Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION),
                                FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION,
                                RenderMode.BOTTOM_CENTER_ALIGNED)
            Display.present()
        time.sleep(0.05)
    return answer.returncode


def run() -> None:
    if not onboarding(): return
    while True:
        try:
            if not main_menu(): return
        except SessionEnded:
            continue


def main() -> int:
    STATE.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(filename=str(STATE / "pyui.log"), level=logging.INFO)
    if len(sys.argv) > 1 and sys.argv[1] == "--invite":
        # --invite --title T --text X [--art P] [--accept L] [--decline L]
        #          [--browse L] [--timeout S]: exits as netplay.elf --prompt does
        # (0 accept, 1 decline, 2 timeout, 3 browse).
        opts = sys.argv[2:]
        args = {opts[i][2:]: opts[i + 1] for i in range(0, len(opts) - 1, 2)}
        answer = start_prompt_input(args)
        try:
            bootstrap()
            return invite(args, answer)
        except Exception:
            logging.exception("PyUI invitation failed; waiting for the answer anyway")
            return answer.wait()
    try:
        bootstrap()
        enter()
        warm_cores()
        run()
        return 0
    except Exception:
        logging.exception("PyUI front end failed")
        return 1


def engine_environment() -> dict[str, str]:
    """netplay.elf's environment for this device, from launch.sh --env: the
    same code that sets it up when launch.sh opens the app itself."""
    out = subprocess.run(["sh", str(PAK / "launch.sh"), "--env"], capture_output=True,
                         text=True, check=False, cwd=str(PAK))
    if out.returncode:
        raise RuntimeError("Netplay has no build for this device")
    return dict(line.split("=", 1) for line in out.stdout.splitlines() if "=" in line)


def run_in_pyui() -> None:
    """The Apps menu entry inside PyUI's own process (see pyui.py)."""
    global ENGINE_ENV, PLATFORM, ENGINE, STATE
    log = logging.getLogger("netplay")
    handler = None
    try:
        ENGINE_ENV = engine_environment()
        PLATFORM = ENGINE_ENV.get("PLATFORM", PLATFORM)
        ENGINE = PAK / "bin" / PLATFORM / "netplay.elf"
        STATE = Path(ENGINE_ENV.get("NETPLAY_STATE", str(STATE)))
        STATE.mkdir(parents=True, exist_ok=True)
        handler = logging.FileHandler(str(STATE / "pyui.log"))
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s"))
        log.addHandler(handler)
        log.setLevel(logging.INFO)
        log.info("opening inside PyUI on %s", PLATFORM)
        enter()
        try:
            warm_cores()
            run()
        finally:
            leave()
    except Exception:
        log.exception("Netplay inside PyUI failed")
        raise   # PyUI logs it too and says the app stopped after an error
    finally:
        if handler is not None:
            log.removeHandler(handler)
            handler.close()


if __name__ == "__main__":
    sys.exit(main())
