"""Theme-backed button glyphs and contextual footer layout."""
from __future__ import annotations

from .buttons import Button
from . import glyphs


def hints(text: str) -> list[tuple[Button, str]]:
    parsed = []
    for part in text.split('    '):
        key, _, label = part.strip().partition(' ')
        if key == "LEFT/RIGHT": key = "LEFT_RIGHT"
        if key in Button.__members__ and label:
            parsed.append((Button[key], label))
    return sorted(parsed, key=lambda item: 0 if item[0] == Button.B else 1)


def render(left: list[tuple[Button, str]], active: bool, text: str = '') -> None:
    from devices.device import Device
    from display.display import Display
    from display.font_purpose import FontPurpose
    from display.render_mode import RenderMode
    from themes.theme import Theme

    height = int(Display.bottom_bar.get_bottom_bar_height())
    if height <= 0:
        return
    width = int(Device.get_device().screen_width())
    y = int(Device.get_device().screen_height()) - height // 2
    purpose = FontPurpose.DESCRIPTIVE_LIST_TITLE
    color = Theme.text_color(purpose)
    mode = RenderMode.MIDDLE_LEFT_ALIGNED
    padding = max(8, width // 80)

    def measure(button, label):
        path = glyphs.glyph(button)
        glyph_width = int(Display.get_image_dimensions(str(path))[0]) if path else 0
        shown = label if path else f'({button.value}) {label}'
        text_width = int(Display.get_text_dimensions(purpose, shown)[0])
        return path, glyph_width, shown, glyph_width + (6 if path else 0) + text_width

    def draw(item, x):
        path, glyph_width, label, total = item
        if path:
            Display.render_image(str(path), x, y, mode)
            x += glyph_width + 6
        Display.render_text(label, x, y, color, purpose, mode)
        return total

    if active:
        # Keep all actions visible on 640px devices, including long CHANGE hints.
        required = sum(measure(button, label)[3] + padding * 2 for button, label in left)
        required += measure(Button.X, 'END SESSION')[3]
        required += int(Display.get_text_dimensions(purpose, '000/0000')[0]) + padding * 3
        if required > width:
            purpose = FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION
            color = Theme.text_color(purpose)
            padding = max(4, width // 160)

    x = padding
    for button, label in left:
        item = measure(button, label)
        x += draw(item, x) + padding * 2
    if text and not left:
        Display.render_text(text, x, y, color, purpose, mode)
    if active:
        # PyUI draws its item index at the far right after the footer.
        index_width = int(Display.get_text_dimensions(purpose, '000/0000')[0])
        item = measure(Button.X, 'END SESSION')
        end_x = width - padding * 2 - index_width - item[3]
        if end_x >= x:
            draw(item, end_x)
