"""Compact emulator rows inside the system accordion, using PyUI's input handling."""

from . import generated


def down_caret(color, width):
    thickness = max(1, width // 8)
    height = (width - 1) // 2 + thickness
    pixels = bytearray(width * height * 4)
    for x in range(width):
        y = min(x, width - 1 - x)
        for offset in range(thickness):
            start = ((y + offset) * width + x) * 4
            pixels[start:start + 4] = bytes((*color, 166))
    name = f"down-caret-{'-'.join(map(str, color))}-{width}.png"
    return str(generated.write(name, width, height, bytes(pixels)))


def style_rows(view, rows, headings, compact_rows):
    from devices.device import Device
    from display.display import Display
    from display.font_purpose import FontPurpose
    from display.render_mode import RenderMode
    from display.resize_type import ResizeType
    from themes.theme import Theme

    title_font = FontPurpose.DESCRIPTIVE_LIST_TITLE
    small_font = FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION
    top = Display.get_top_bar_height(force_include_top_bar=True) + 5
    bottom = Device.get_device().screen_height() - Display.bottom_bar.get_bottom_bar_height()
    width = Device.get_device().screen_width()
    padding = Theme.get_descriptive_list_icon_offset_x() + Theme.get_descriptive_list_text_from_icon_offset()
    small_height = max(Display.get_text_dimensions(small_font, "Ag")[1] + 12,
                       int(view.each_entry_height * 0.65))
    heights = [small_height if key in headings or key in compact_rows else view.each_entry_height
               for key, *_ in rows]

    def layout():
        view.current_top = min(max(0, view.current_top), len(rows) - 1)
        if view.selected < view.current_top:
            view.current_top = view.selected
        if (view.current_top == view.selected and view.selected > 0
                and rows[view.selected - 1][0] in headings):
            view.current_top -= 1
        used = sum(heights[view.current_top:view.selected + 1])
        while used > bottom - top and view.current_top < view.selected:
            used -= heights[view.current_top]
            view.current_top += 1
        end = view.current_top
        used = 0
        while end < len(rows) and (end == view.current_top or used + heights[end] <= bottom - top):
            used += heights[end]
            end += 1
        view.current_bottom = end
        view.max_rows = max(1, end - view.current_top)

    def render():
        y = top
        for index in range(view.current_top, view.current_bottom):
            key, label, _, value = rows[index]
            height = heights[index]
            small = key in compact_rows or key in headings
            purpose = small_font if small else title_font
            selected = index == view.selected and key not in headings
            if selected:
                Display.render_image(view.selected_bg, 0, y, target_width=width,
                                     target_height=height, resize_type=ResizeType.ZOOM)
            color = Theme.text_color_selected(purpose) if selected else Theme.text_color(purpose)
            x = padding + (16 if key in compact_rows else 0)
            if key in headings:
                x = (width - Display.get_text_dimensions(purpose, label)[0]) // 2
            caret = value.endswith("▾")
            mark = value[:-1].rstrip() if caret else value
            caret_width = max(8, Display.get_text_dimensions(purpose, "Ag")[1] * 3 // 5)
            value_width = Display.get_text_dimensions(purpose, mark)[0] if mark else 0
            if caret:
                value_width += (12 if mark else 0) + caret_width
            primary, separator, suffix = label.partition(" (") if not small and label.endswith(")") else (label, "", "")
            label_room = max(1, width - x - padding - value_width - 12)
            Display.render_text(primary, x, y + height // 2, color, purpose,
                                RenderMode.MIDDLE_LEFT_ALIGNED,
                                crop_w=label_room)
            if separator:
                primary_width = Display.get_text_dimensions(purpose, primary)[0]
                if primary_width < label_room:
                    Display.render_text(separator + suffix, x + primary_width, y + height // 2,
                                        color, purpose, RenderMode.MIDDLE_LEFT_ALIGNED,
                                        crop_w=label_room - primary_width, alpha=166)
            if value:
                value_x = width - padding - value_width
                if mark:
                    Display.render_text(mark, value_x, y + height // 2,
                                        color, purpose, RenderMode.MIDDLE_LEFT_ALIGNED)
                if caret:
                    path = down_caret(tuple(color[:3]), caret_width)
                    Display.render_image(path, width - padding - caret_width, y + height // 2,
                                         render_mode=RenderMode.MIDDLE_LEFT_ALIGNED)
            y += height

    def hit_test(point):
        if point is None or not 0 <= point[0] < width or not top <= point[1] < bottom:
            return None
        y = top
        for index in range(view.current_top, view.current_bottom):
            if y <= point[1] < y + heights[index]:
                return index if rows[index][0] not in headings else None
            y += heights[index]
        return None

    view.adjust_selected_top_bottom_for_overflow = layout
    view._render = render
    view.row_at_touch_point = hit_test
    view.touch_scroll_step_size = lambda: small_height
    layout()
