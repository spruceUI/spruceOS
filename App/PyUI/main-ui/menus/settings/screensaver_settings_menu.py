import os
import copy

from controller.controller_inputs import ControllerInput
from menus.language.language import Language
from menus.settings import settings_menu
from themes.theme import Theme
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType


COLOR_PALETTE = [
    "#FFFFFF", "#66F7FF", "#FF4FD8", "#FFE66D", "#80FF72",
    "#FF9F1C", "#FF4040", "#AAAAAA", "#000000",
]


class ScreenSaverSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def launch_screen_saver(self, input):
        pass

    def toggle_show_clock(self, input):
        if ControllerInput.A == input:
            current = Theme._data.get("screensaver", {}).get("showClock", True)
            self._set_screensaver_prop("showClock", not current)

    def toggle_show_date(self, input):
        if ControllerInput.A == input:
            current = Theme._data.get("screensaver", {}).get("showDate", True)
            self._set_screensaver_prop("showDate", not current)

    def toggle_show_battery(self, input):
        if ControllerInput.A == input:
            current = Theme._data.get("screensaver", {}).get("showBattery", True)
            self._set_screensaver_prop("showBattery", not current)

    def change_timeout(self, input):
        current = PyUiConfig.get_screensaver_timeout_sec()
        if ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input:
            new_val = min(300, current + 30)
        elif ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input:
            new_val = max(0, current - 30)
        elif ControllerInput.A == input:
            new_val = 0 if current > 0 else 120
        else:
            return
        PyUiConfig.set("screensaverTimeoutSec", new_val)
        PyUiConfig.save()

    def change_overlay_opacity(self, input):
        current = Theme._data.get("screensaver", {}).get("overlayOpacity", 0.3)
        if ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input:
            new_val = min(1.0, round(current + 0.1, 1))
        elif ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input:
            new_val = max(0.0, round(current - 0.1, 1))
        elif ControllerInput.A == input:
            new_val = 0.0 if current > 0 else 0.5
        else:
            return
        self._set_screensaver_prop("overlayOpacity", new_val)

    def change_blur(self, input):
        current = Theme._data.get("screensaver", {}).get("blur", 0)
        if ControllerInput.DPAD_RIGHT == input or ControllerInput.R1 == input:
            new_val = min(30, current + 2)
        elif ControllerInput.DPAD_LEFT == input or ControllerInput.L1 == input:
            new_val = max(0, current - 2)
        elif ControllerInput.A == input:
            new_val = 0 if current > 0 else 10
        else:
            return
        self._set_screensaver_prop("blur", new_val)

    def edit_layout(self, input):
        if ControllerInput.A != input:
            return

        original = copy.deepcopy(Theme._data.get("screensaver", {}))
        ss = Theme._data.get("screensaver", {})
        widgets = ss.get("widgets") or Theme.get_screensaver_widgets()
        ss["widgets"] = widgets
        Theme._data["screensaver"] = ss

        selected = 0
        from controller.controller import Controller
        from display.screensaver import ScreenSaver
        from display.display import Display

        dirty = True
        while True:
            selected = max(0, min(selected, len(widgets) - 1))
            if dirty:
                self._render_layout_preview(ScreenSaver, widgets, selected)
                dirty = False

            if not Controller.get_input(timeout=0.2):
                continue

            pressed = Controller.last_input()
            widget = widgets[selected]

            if pressed == ControllerInput.A:
                Theme.save_changes()
                return
            if pressed == ControllerInput.B:
                Theme._data["screensaver"] = original
                Display.clear_cache()
                return
            if pressed == ControllerInput.SELECT:
                selected = (selected + 1) % len(widgets)
                dirty = True
                continue
            if pressed == ControllerInput.X:
                widget["enabled"] = not widget.get("enabled", True)
                dirty = True
                continue
            if pressed == ControllerInput.DPAD_LEFT:
                widget["x"] = max(0.0, round(widget.get("x", 0.5) - 0.02, 2))
                dirty = True
            elif pressed == ControllerInput.DPAD_RIGHT:
                widget["x"] = min(1.0, round(widget.get("x", 0.5) + 0.02, 2))
                dirty = True
            elif pressed == ControllerInput.DPAD_UP:
                widget["y"] = max(0.0, round(widget.get("y", 0.5) - 0.02, 2))
                dirty = True
            elif pressed == ControllerInput.DPAD_DOWN:
                widget["y"] = min(1.0, round(widget.get("y", 0.5) + 0.02, 2))
                dirty = True
            elif pressed == ControllerInput.L1:
                widget["fontSize"] = max(10, int(widget.get("fontSize", 24)) - 2)
                dirty = True
            elif pressed == ControllerInput.R1:
                widget["fontSize"] = min(120, int(widget.get("fontSize", 24)) + 2)
                dirty = True
            elif pressed == ControllerInput.L2:
                widget["color"] = self._next_palette_color(widget.get("color", "#FFFFFF"), -1)
                dirty = True
            elif pressed == ControllerInput.R2:
                widget["color"] = self._next_palette_color(widget.get("color", "#FFFFFF"), 1)
                dirty = True
            elif pressed == ControllerInput.Y:
                if widget.get("type") == "battery":
                    widget["style"] = self._next_battery_style(widget.get("style", "percent"))
                else:
                    widget["font"] = self._next_font(widget.get("font"))
                dirty = True
            elif pressed == ControllerInput.START:
                new_color = self._show_rgb_picker(widget.get("color", "#FFFFFF"))
                if new_color is not None:
                    widget["color"] = new_color
                    dirty = True

    def _render_layout_preview(self, ScreenSaver, widgets, selected):
        original_color = widgets[selected].get("color", "#FFFFFF")
        original_value = widgets[selected].get("value")
        widgets[selected]["color"] = "#FFE66D"
        if widgets[selected].get("type") == "text":
            widgets[selected]["value"] = original_value or "TEXT"
        ScreenSaver.render()
        widgets[selected]["color"] = original_color
        if original_value is not None:
            widgets[selected]["value"] = original_value
        elif "value" in widgets[selected]:
            del widgets[selected]["value"]

    def _next_palette_color(self, color, direction):
        color = color.upper()
        try:
            index = COLOR_PALETTE.index(color)
        except ValueError:
            index = 0
        return COLOR_PALETTE[(index + direction) % len(COLOR_PALETTE)]

    def _next_battery_style(self, current):
        styles = ["percent", "blocks", "bar", "pill", "segments"]
        try:
            index = styles.index(current)
        except ValueError:
            index = 0
        return styles[(index + 1) % len(styles)]

    def _next_font(self, current):
        fonts = self._find_fonts()
        if not fonts:
            return current
        try:
            index = fonts.index(current)
        except ValueError:
            index = -1
        return fonts[(index + 1) % len(fonts)]

    def _find_fonts(self):
        font_dirs = ["/mnt/SDCARD/App/PyUI/fonts", Theme.get_theme_path()]
        fonts = []
        for font_dir in font_dirs:
            if not os.path.isdir(font_dir):
                continue
            for name in os.listdir(font_dir):
                if name.lower().endswith((".ttf", ".otf")) and name not in fonts:
                    fonts.append(name)
        fonts.sort()
        return fonts

    def change_bg_color(self, input):
        if ControllerInput.A != input:
            return

        current = Theme._data.get("screensaver", {}).get("bgColor", "#000000")
        new_color = self._show_rgb_picker(current)
        if new_color is not None:
            self._set_screensaver_prop("bgColor", new_color)

    def _show_rgb_picker(self, current):
        color = self._normalize_hex_color(current) or "#000000"
        values = [int(color[1:3], 16), int(color[3:5], 16), int(color[5:7], 16)]
        channel = 0
        labels = ["R", "G", "B"]
        from controller.controller import Controller
        from display.display import Display
        from display.font_purpose import FontPurpose
        from display.render_mode import RenderMode
        from devices.device import Device

        while True:
            hex_color = "#" + "".join(f"{v:02X}" for v in values)
            Display.clear(Language.get("screensaverBgColor", "Background color"))
            w = Device.get_device().screen_width()
            h = Device.get_device().screen_height()
            swatch_w = int(w * 0.55)
            swatch_h = int(h * 0.28)
            x = (w - swatch_w) // 2
            y = int(h * 0.18)
            import sdl2
            rgb = tuple(values)
            sdl2.SDL_SetRenderDrawColor(Display.renderer.sdlrenderer, rgb[0], rgb[1], rgb[2], 255)
            sdl2.SDL_RenderFillRect(Display.renderer.sdlrenderer, sdl2.SDL_Rect(x, y, swatch_w, swatch_h))

            start_y = y + swatch_h + 35
            for index, label in enumerate(labels):
                prefix = "> " if index == channel else "  "
                bar_len = 18
                filled = int(values[index] / 255 * bar_len)
                bar = "[" + ("#" * filled).ljust(bar_len, "-") + "]"
                text = f"{prefix}{label} {values[index]:03d} {bar}"
                color_tuple = (255, 230, 109) if index == channel else (255, 255, 255)
                Display.render_text(text, int(w * 0.22), start_y + index * 42, color_tuple, FontPurpose.LIST, RenderMode.TOP_LEFT_ALIGNED)

            Display.render_text(hex_color, int(w * 0.5), start_y + 145, (102, 247, 255), FontPurpose.LIST, RenderMode.TOP_CENTER_ALIGNED)
            Display.render_text("Up/Down channel  Left/Right +/-1  L1/R1 +/-10  X reset  A save  B cancel",
                int(w * 0.5), h - 55, (170, 170, 170), FontPurpose.LIST, RenderMode.TOP_CENTER_ALIGNED)
            Display.present()

            if not Controller.get_input(timeout=0.1):
                continue

            pressed = Controller.last_input()
            if pressed == ControllerInput.A:
                return hex_color
            if pressed == ControllerInput.B:
                return None
            if pressed == ControllerInput.X:
                values = [0, 0, 0]
            elif pressed == ControllerInput.DPAD_UP:
                channel = (channel - 1) % 3
            elif pressed == ControllerInput.DPAD_DOWN:
                channel = (channel + 1) % 3
            elif pressed == ControllerInput.DPAD_LEFT:
                values[channel] = max(0, values[channel] - 1)
            elif pressed == ControllerInput.DPAD_RIGHT:
                values[channel] = min(255, values[channel] + 1)
            elif pressed == ControllerInput.L1:
                values[channel] = max(0, values[channel] - 10)
            elif pressed == ControllerInput.R1:
                values[channel] = min(255, values[channel] + 10)

    def cycle_bg_image(self, input):
        if ControllerInput.A != input:
            return

        ss = Theme._data.get("screensaver", {})
        current = ss.get("bgImage", "")
        images = [""] + self._find_bg_images()
        selected = self._show_image_selection(images, current)
        if selected is not None:
            self._set_screensaver_prop("bgImage", selected)

    def _show_image_selection(self, images, current):
        selected_index = 0
        option_list = []
        for index, path in enumerate(images):
            if path == current:
                selected_index = index
            image_path = path or "/mnt/SDCARD/App/PyUI/main-ui/themes/screensaver.png"
            option_list.append(
                GridOrListEntry(
                    primary_text=self._format_image_label(path),
                    value=path,
                    image_path=image_path if os.path.exists(image_path) else None,
                    image_path_selected=image_path if os.path.exists(image_path) else None,
                    description=path or Language.get("screensaverBgDefault", "Default"),
                )
            )

        view = ViewCreator.create_view(
            view_type=ViewType.TEXT_AND_IMAGE,
            top_bar_text=Language.get("screensaverBgImage", "Background image"),
            options=option_list,
            selected_index=selected_index)

        while True:
            selected = view.get_selection([ControllerInput.A, ControllerInput.B])
            if ControllerInput.A == selected.get_input():
                return selected.get_selection().get_value()
            if ControllerInput.B == selected.get_input():
                return None

    def _normalize_hex_color(self, color):
        color = color.strip()
        if not color.startswith("#"):
            color = "#" + color
        if len(color) != 7:
            return None
        hex_part = color[1:]
        if any(c not in "0123456789abcdefABCDEF" for c in hex_part):
            return None
        return "#" + hex_part.upper()

    def _find_bg_images(self):
        user_dir = "/mnt/SDCARD/App/PyUI/screensavers"
        os.makedirs(user_dir, exist_ok=True)
        paths = [user_dir, Theme.get_theme_path(), "/mnt/SDCARD/App/PyUI/main-ui/themes"]
        images = []
        exts = (".png", ".jpg", ".jpeg", ".bmp", ".gif")
        for base in paths:
            if not os.path.exists(base):
                continue
            for f in os.listdir(base):
                path = os.path.join(base, f)
                lower = f.lower()
                is_user_screensaver = base == user_dir
                is_screensaver = is_user_screensaver or (lower.startswith("screensaver") and not lower.startswith("screensaver_color_"))
                if os.path.isfile(path) and lower.endswith(exts) and is_screensaver and path not in images:
                    images.append(path)
        images.sort()
        return images

    def _set_screensaver_prop(self, key, value):
        ss = Theme._data.get("screensaver", {})
        ss[key] = value
        Theme._data["screensaver"] = ss
        Theme.save_changes()

    def _get_screensaver_prop(self, key, default=True):
        return Theme._data.get("screensaver", {}).get(key, default)

    def _format_image_label(self, path):
        if not path:
            return Language.get("screensaverBgDefault", "Default")
        return os.path.basename(path)

    def _format_color_label(self, color):
        labels = {
            "#000000": "Black",
            "#1A1A1A": "Dark gray",
            "#102030": "Deep blue",
            "#201020": "Deep purple",
            "#102010": "Deep green",
            "#301010": "Deep red",
            "#302010": "Deep orange",
            "#303010": "Deep yellow",
            "#103030": "Deep teal",
            "#303030": "Gray",
            "#FFFFFF": "White",
        }
        return labels.get(color, color)

    def build_options_list(self):
        option_list = []

        timeout = PyUiConfig.get_screensaver_timeout_sec()
        timeout_text = f"{timeout // 60}m {timeout % 60}s" if timeout > 0 else Language.get("off", "Off")
        option_list.append(
            GridOrListEntry(
                primary_text=Language.get("screensaverTimeout", "Timeout"),
                value_text="<    " + timeout_text + "    >",
                image_path=None,
                image_path_selected=None,
                description=Language.get("screensaverTimeoutDesc", "Minutes before screensaver activates (0=off)"),
                icon=None,
                value=self.change_timeout
            )
        )

        current_image = self._get_screensaver_prop("bgImage", "")
        option_list.append(
            GridOrListEntry(
                primary_text=Language.get("screensaverBgImage", "Background image"),
                value_text="<    " + self._format_image_label(current_image) + "    >",
                image_path=None,
                image_path_selected=None,
                description=Language.get("screensaverBgImageDesc", "Choose a screensaver background image"),
                icon=None,
                value=self.cycle_bg_image
            )
        )

        current_color = self._get_screensaver_prop("bgColor", "#000000")
        option_list.append(
            GridOrListEntry(
                primary_text=Language.get("screensaverBgColor", "Background color"),
                value_text="<    " + self._format_color_label(current_color) + "    >",
                image_path=None,
                image_path_selected=None,
                description=Language.get("screensaverBgColorDesc", "Solid background color when no image is selected"),
                icon=None,
                value=self.change_bg_color
            )
        )

        overlay_opacity = self._get_screensaver_prop("overlayOpacity", 0.3)
        option_list.append(
            GridOrListEntry(
                primary_text=Language.get("screensaverOverlayOpacity", "Overlay opacity"),
                value_text="<    " + f"{int(overlay_opacity * 100)}%" + "    >",
                image_path=None,
                image_path_selected=None,
                description=Language.get("screensaverOverlayOpacityDesc", "Dark overlay over background (0=off, 100=full black)"),
                icon=None,
                value=self.change_overlay_opacity
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text=Language.get("screensaverEditLayout", "Edit layout"),
                value_text=None,
                image_path=None,
                image_path_selected=None,
                description=Language.get("screensaverEditLayoutDesc", "D-pad move, L1/R1 size, L2/R2 color, START RGB color, Y font/battery style, X show/hide, A save, B cancel"),
                icon=None,
                value=self.edit_layout
            )
        )

        return option_list
