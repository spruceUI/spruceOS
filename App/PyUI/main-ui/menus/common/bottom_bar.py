from dataclasses import dataclass

from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from menus.language.language import Language
from themes.theme import Theme


@dataclass(frozen=True)
class BottomBarHint:
    button: ControllerInput
    label: str


class BottomBar:
    def __init__(self):
        self.bottom_bar_h = 0
        self.back_icon_w = 0
        self.back_icon_h = 0

    def render_bottom_bar(self, bottom_bar_text=None, render_bottom_bar_icons_and_images=True, bottom_bar_hints=None):
        bottom_bar_bg = Theme.bottom_bar_bg()
        from display.display import Display

        if(Theme.show_bottom_bar()):

            self.bottom_bar_w, self.bottom_bar_h = Display.render_image(bottom_bar_bg, 0, Device.get_device().screen_height(), render_mode=RenderMode.BOTTOM_LEFT_ALIGNED)
            if(self.back_icon_h > self.bottom_bar_h):
                self.bottom_bar_h = self.back_icon_h

            if(bottom_bar_text is not None):
                self.render_bottom_bar_text(bottom_bar_text)
            elif(render_bottom_bar_icons_and_images):
                if(Theme.context_buttons_enabled()):
                    self.render_context_bottom_bar(self._resolve_hints(bottom_bar_hints))
                else:
                    self.render_standard_bottom_bar()
        else:
            self.bottom_bar_h = 0

    def _resolve_hints(self, bottom_bar_hints):
        if(bottom_bar_hints is not None):
            return list(bottom_bar_hints)
        return [
            BottomBarHint(ControllerInput.A, Language.label("confirmText", Theme.confirm_text())),
            BottomBarHint(ControllerInput.B, Language.label("backText", Theme.back_text())),
        ]

    @staticmethod
    def fit_hint_count(hint_widths, available_width, keep=2):
        count = len(hint_widths)
        while(count > keep and sum(hint_widths[:count]) > available_width):
            count -= 1
        return count

    def render_context_bottom_bar(self, hints):
        from display.display import Display
        if(not hints):
            return
        # Height above the bottom matches the page index on the right
        # (Display.add_index_text); the left inset matches the lists (20px).
        x_padding = 20
        y_padding = max(5, Display.get_bottom_bar_height() // 4)
        bottom_y = Device.get_device().screen_height() - y_padding
        show_text = Theme.show_bottom_bar_buttons()
        # A text texture extends below its baseline, so a label bottom-aligned
        # at bottom_y shows its glyph bottoms that much higher. Lifting the
        # icons the full amount puts their bottoms exactly on the baseline,
        # which reads as too high against the text, so split the difference.
        icon_lift = Display.get_font_baseline_offset(FontPurpose.BOTTOM_BAR_HINT) // 2 if show_text else 0

        # A hint reads as one unit (icon, a space, label), with a wider gap
        # between hints: one space within, three between.
        space_w, _ = Display.get_text_dimensions(FontPurpose.BOTTOM_BAR_HINT, " ")
        if(space_w <= 0):
            space_w = 5
        between_w = space_w * 3

        entries = []
        for hint in hints:
            icon = Theme.context_icon(hint.button)
            icon_w, icon_h = Display.get_image_dimensions(icon)
            text_w = 0
            if(show_text and hint.label):
                text_w, _ = Display.get_text_dimensions(FontPurpose.BOTTOM_BAR_HINT, hint.label)
            width = icon_w + (space_w + text_w if text_w else 0) + between_w
            entries.append((hint, icon, icon_w, icon_h, text_w, width))

        available_width = Device.get_device().screen_width() - x_padding - 10
        keep_count = self.fit_hint_count([entry[5] for entry in entries], available_width)
        entries = entries[:keep_count]

        x_offset = x_padding
        for hint, icon, icon_w, icon_h, text_w, width in entries:
            if(icon is not None):
                Display.render_image(icon, x_offset, bottom_y - icon_lift, RenderMode.BOTTOM_LEFT_ALIGNED)
                if(icon_h > self.back_icon_h):
                    self.back_icon_w, self.back_icon_h = icon_w, icon_h
            x_offset += icon_w
            if(show_text and hint.label):
                x_offset += space_w
                Display.render_text(hint.label,
                                    x_offset,
                                    bottom_y,
                                    Theme.text_color(FontPurpose.BOTTOM_BAR_HINT),
                                    FontPurpose.BOTTOM_BAR_HINT,
                                    RenderMode.BOTTOM_LEFT_ALIGNED)
                x_offset += text_w
            x_offset += between_w

    def get_bottom_bar_height(self):
        return self.bottom_bar_h

    def render_standard_bottom_bar(self):
        from display.display import Display
        # TODO don't hard code these
        padding = 5
        bottom_icons_y = Device.get_device().screen_height() - padding

        confirm_icon = Theme.confirm_icon()
        x_offset = padding
        confirm_icon_w, confirm_icon_h = Display.render_image(
            confirm_icon, x_offset, bottom_icons_y, RenderMode.BOTTOM_LEFT_ALIGNED)

        x_offset += padding + confirm_icon_w

        if(Theme.show_bottom_bar_buttons()):
            confirm_text_y = bottom_icons_y - confirm_icon_h // 2
            confirm_text_w, confirm_text_h = Display.render_text(Language.label("confirmText", Theme.confirm_text()),
                                                                x_offset,
                                                                confirm_text_y,
                                                                Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_TITLE),
                                                                FontPurpose.DESCRIPTIVE_LIST_TITLE,
                                                                RenderMode.MIDDLE_LEFT_ALIGNED)
            x_offset += padding + confirm_text_w

            back_icon = Theme.back_icon()
            self.back_icon_w, self.back_icon_h = Display.render_image(
                back_icon, x_offset, bottom_icons_y, RenderMode.BOTTOM_LEFT_ALIGNED)
            x_offset += padding + self.back_icon_w
            back_text_y = bottom_icons_y - self.back_icon_h // 2
            back_text_w, back_text_h = Display.render_text(Language.label("backText", Theme.back_text()),
                                                        x_offset,
                                                        back_text_y,
                                                        Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_TITLE),
                                                            FontPurpose.DESCRIPTIVE_LIST_TITLE,
                                                            RenderMode.MIDDLE_LEFT_ALIGNED)
            x_offset += padding + back_text_w

    def render_bottom_bar_text(self, text):
        from display.display import Display
        y_padding = max(5, Display.get_bottom_bar_height() // 4)
        y_value = Device.get_device().screen_height() - y_padding
        Display.render_text(text,
                            Device.get_device().screen_width() // 2,
                            y_value,
                            Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_TITLE),
                            FontPurpose.DESCRIPTIVE_LIST_TITLE,
                            RenderMode.BOTTOM_CENTER_ALIGNED)
