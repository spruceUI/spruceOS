import time
from typing import List
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.font_purpose import FontPurpose
from display.display import Display
from display.render_mode import RenderMode
from display.resize_type import ResizeType
from controller.controller import Controller
from themes.theme import Theme
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view import View


class FullScreenGridView(View):
    def __init__(self, top_bar_text, options: List[GridOrListEntry], selected_bg: str = None,
                 selected_index=0, show_grid_text=True,
                 set_top_bar_text_to_selection=False,
                 unselected_bg = None, missing_image_path=None,
                 resize_type = ResizeType.ZOOM,
                 render_text_overlay = True,
                 image_resize_height_multiplier = None):
        super().__init__()
        if(render_text_overlay is None):
            render_text_overlay = True
        self.render_text_overlay = render_text_overlay
        self.resized_width = int(Device.get_device().screen_width() * 1.0)
        if(image_resize_height_multiplier is None):
            image_resize_height_multiplier = 0.75
        self.resized_height = int(Device.get_device().screen_height() * image_resize_height_multiplier)
        self.resize_type = resize_type
        if(self.resize_type is None):
            self.resize_type = ResizeType.ZOOM

        self.top_bar_text = top_bar_text
        self.set_top_bar_text_to_selection = set_top_bar_text_to_selection and not Theme.skip_main_menu()
        self.options: List[GridOrListEntry] = options

        self.max_img_height = self.resized_height
        if (self.max_img_height is None):
            self.max_img_height = 0
            for option in options:
                self.max_img_height = max(
                    self.max_img_height, Display.get_image_dimensions(option.get_image_path())[1])

        self.selected = selected_index
        self.toggles = [False] * len(options)

        self.current_left = 0
        self.current_right = min(len(options), 10)

        self.font_purpose = FontPurpose.GRID_ONE_ROW

        self.selected_bg = selected_bg
        self.unselected_bg = unselected_bg
        self.show_grid_text = show_grid_text
        self.missing_image_path = missing_image_path
        # TODO Get hard coded values for padding from theme
        self.x_pad = 10
        self.usable_width = Device.get_device().screen_width() - (2 * self.x_pad)
        self.icon_width = self.usable_width  # Initial icon width
        self.x_text_pad = 20 #TODO
        self.option_text_widths = []
        for option in self.options:
            self.option_text_widths.append(Display.get_text_dimensions(self.font_purpose, option.get_primary_text()[:10])[0])

        self.last_selected = self.selected
        self.last_start = 0
        self.animated_count = 0

        self.render_bottom_bar_text_enabled = image_resize_height_multiplier != 1.0
        self.image_resize_height_multiplier = image_resize_height_multiplier
        self.y_rotate_instead = False

    def set_options(self, options):
        self.options = options

    def correct_selected_for_off_list(self):
        while (self.selected < 0):
            self.selected = len(self.options) + self.selected
        if(self.selected >= len(self.options)):
            self.selected = 0

        self.selected = max(0, self.selected)

        while(self.selected < self.current_left):
            self.current_left -= 1
            self.current_right -=1

        while(self.selected >= self.current_right):
            self.current_left += 1
            self.current_right +=1

    def _render_shadowed_text(self, primary_text, y_offset_base, backdrop_font, front_font, x_offset, alpha=None):
        if(self.render_text_overlay):
            #TODO hardcoded values of 25
            shadow_color =  Theme.text_color(backdrop_font)
            # Render black text surfaces at offsets for the "outline"
            shift_amt = 5
            if(alpha is None):
                for dx in range (1,shift_amt):
                    for dy in range(1,shift_amt):
                        Display.render_text(primary_text,
                                                x_offset + dx,
                                                y_offset_base + dy,
                                                shadow_color,
                                                backdrop_font,
                                                render_mode=RenderMode.TOP_LEFT_ALIGNED,
                                                alpha=alpha)
                        Display.render_text(primary_text,
                                                x_offset - dx,
                                                y_offset_base + dy,
                                                shadow_color,
                                                backdrop_font,
                                                render_mode=RenderMode.TOP_LEFT_ALIGNED,
                                                alpha=alpha)
                        Display.render_text(primary_text,
                                                x_offset + dx,
                                                y_offset_base - dy,
                                                shadow_color,
                                                backdrop_font,
                                                render_mode=RenderMode.TOP_LEFT_ALIGNED,
                                                alpha=alpha)
                        Display.render_text(primary_text,
                                                x_offset - dx,
                                                y_offset_base - dy,
                                                shadow_color,
                                                backdrop_font,
                                                render_mode=RenderMode.TOP_LEFT_ALIGNED,
                                                alpha=alpha)
            primary_color =  Theme.text_color(front_font)

            # Render text in primary color
            offsets = [(0,0)]  # diagonal directions
            for dx, dy in offsets:
                Display.render_text(primary_text,
                                        x_offset + dx,
                                        y_offset_base + dy,
                                        primary_color,
                                        front_font,
                                        render_mode=RenderMode.TOP_LEFT_ALIGNED,
                                        alpha=alpha)

    def _fit_text(self, text, font_purpose, max_width):
        text = str(text or "").strip()
        if text == "":
            return ""

        if Display.get_text_dimensions(font_purpose, text)[0] <= max_width:
            return text

        suffix = "..."
        while text:
            candidate = text.rstrip() + suffix
            if Display.get_text_dimensions(font_purpose, candidate)[0] <= max_width:
                return candidate
            text = text[:-1]

        return suffix

    def _clamp_alpha(self, alpha):
        if alpha is None:
            return None
        return max(0, min(255, int(alpha)))

    def _use_compact_text_overlay(self, imageTextPair):
        extra_data = imageTextPair.get_extra_data() or {}
        return extra_data.get("compact_text_overlay") is True

    def _selected_uses_compact_text_overlay(self):
        selected = self.get_selected_option()
        return selected is not None and self._use_compact_text_overlay(selected)

    def _get_hltb_card_size(self, hltb_time, pad_x, pad_y, line_gap):
        label_w, label_h = Display.get_text_dimensions(FontPurpose.LIST_TOTAL, "HLTB")
        value_w, value_h = Display.get_text_dimensions(FontPurpose.LIST_INDEX, f"~{hltb_time}")
        min_w = int(74 * Theme._default_multiplier)
        box_w = max(min_w, max(label_w, value_w) + (pad_x * 2))
        box_h = label_h + line_gap + value_h + (pad_y * 2)
        return box_w, box_h

    def _render_hltb_card(self, hltb_time, margin, pad_x, pad_y, line_gap, x_offset=0, y_add_offset=0, alpha=None):
        label = "HLTB"
        value = f"~{hltb_time}"
        box_w, box_h = self._get_hltb_card_size(hltb_time, pad_x, pad_y, line_gap)
        box_x = Device.get_device().screen_width() - margin - box_w + x_offset
        box_y = Device.get_device().screen_height() - box_h - margin + y_add_offset
        text_center_x = box_x + (box_w // 2)
        label_y = box_y + pad_y
        value_y = label_y + Display.get_text_dimensions(FontPurpose.LIST_TOTAL, label)[1] + line_gap

        Display.render_box((255, 255, 255), box_x - 1, box_y - 1, box_w + 2, box_h + 2)
        Display.render_box((0, 0, 0), box_x, box_y, box_w, box_h)
        Display.render_text(
            label,
            text_center_x,
            label_y,
            Theme.text_color(FontPurpose.LIST_TOTAL),
            FontPurpose.LIST_TOTAL,
            render_mode=RenderMode.TOP_CENTER_ALIGNED,
            alpha=self._clamp_alpha(alpha)
        )
        Display.render_text(
            value,
            text_center_x,
            value_y,
            Theme.text_color(FontPurpose.LIST_INDEX),
            FontPurpose.LIST_INDEX,
            render_mode=RenderMode.TOP_CENTER_ALIGNED,
            alpha=self._clamp_alpha(alpha)
        )

    def _get_playtime_progress_height(self):
        pad_y = int(5 * Theme._default_multiplier)
        line_gap = int(4 * Theme._default_multiplier)
        bar_h = max(14, int(14 * Theme._default_multiplier))
        label_h = Display.get_text_dimensions(FontPurpose.LIST_TOTAL, "progress")[1]
        return label_h + line_gap + bar_h + pad_y

    def _get_playtime_progress_color(self, progress_percent):
        progress_percent = max(0, min(100, int(progress_percent or 0)))
        if progress_percent >= 100:
            return (226, 74, 74)
        if progress_percent >= 75:
            return (238, 132, 64)
        if progress_percent >= 45:
            return (238, 196, 74)
        return (86, 205, 106)

    def _render_soft_box(self, color, x, y, width, height, corner_inset=None):
        width = int(width)
        height = int(height)
        if width <= 0 or height <= 0:
            return
        if width < 4 or height < 4:
            Display.render_box(color, x, y, width, height)
            return

        if corner_inset is None:
            corner_inset = height // 2
        radius = max(1, min(int(corner_inset), height // 2, width // 2))

        for row in range(height):
            inset = 0
            if row < radius:
                distance = radius - row - 0.5
                inset = int(radius - ((radius * radius) - (distance * distance)) ** 0.5)
            elif row >= height - radius:
                distance = row - (height - radius) + 0.5
                inset = int(radius - ((radius * radius) - (distance * distance)) ** 0.5)

            line_w = width - (inset * 2)
            if line_w > 0:
                Display.render_box(color, x + inset, y + row, line_w, 1)

    def _render_playtime_progress_bar(self, extra_data, x, y, width):
        progress_percent = extra_data.get("playtime_progress_percent")
        if progress_percent is None:
            return 0

        progress_percent = max(0, min(100, int(progress_percent)))
        total_h = self._get_playtime_progress_height()
        pad_x = int(9 * Theme._default_multiplier)
        pad_y = int(5 * Theme._default_multiplier)
        line_gap = int(4 * Theme._default_multiplier)
        bar_h = max(14, int(14 * Theme._default_multiplier))
        track_x = x + pad_x
        track_w = max(1, width - (pad_x * 2))
        label = "progress"
        label_w, label_h = Display.get_text_dimensions(FontPurpose.LIST_TOTAL, label)
        label_x = x + (width // 2)
        label_y = y
        panel_y = y + max(3, label_h // 2)
        panel_h = total_h - (panel_y - y)
        track_y = y + label_h + line_gap
        fill_w = max(0, int(track_w * (progress_percent / 100.0)))
        panel_corner = max(3, int(5 * Theme._default_multiplier))
        bar_corner = max(2, bar_h // 2)
        notch_pad_x = int(7 * Theme._default_multiplier)
        notch_x = label_x - ((label_w + (notch_pad_x * 2)) // 2)

        self._render_soft_box((255, 255, 255), x - 1, panel_y - 1, width + 2, panel_h + 2, panel_corner)
        self._render_soft_box((0, 0, 0), x, panel_y, width, panel_h, panel_corner)
        Display.render_box(
            (0, 0, 0),
            notch_x,
            label_y,
            label_w + (notch_pad_x * 2),
            label_h + 1
        )
        Display.render_text(
            label,
            label_x,
            label_y,
            Theme.text_color(FontPurpose.LIST_TOTAL),
            FontPurpose.LIST_TOTAL,
            render_mode=RenderMode.TOP_CENTER_ALIGNED
        )

        self._render_soft_box((255, 255, 255), track_x - 1, track_y - 1, track_w + 2, bar_h + 2, bar_corner)
        self._render_soft_box((24, 24, 24), track_x, track_y, track_w, bar_h, bar_corner)
        if fill_w > 0:
            self._render_soft_box(
                self._get_playtime_progress_color(progress_percent),
                track_x,
                track_y,
                fill_w,
                bar_h,
                bar_corner
            )

        return total_h

    def _render_compact_text_overlay(self, imageTextPair, x_offset=0, y_add_offset=0, alpha=None):
        title_font = FontPurpose.LIST_INDEX
        subtitle_font = FontPurpose.LIST_TOTAL
        margin = int(18 * Theme._default_multiplier)
        pad_x = int(12 * Theme._default_multiplier)
        pad_y = int(8 * Theme._default_multiplier)
        line_gap = int(3 * Theme._default_multiplier)
        extra_data = imageTextPair.get_extra_data() or {}
        hltb_time = extra_data.get("hltb_time")

        max_box_width = Device.get_device().screen_width() - (margin * 2)
        if hltb_time is not None:
            hltb_box_w, _ = self._get_hltb_card_size(hltb_time, pad_x, pad_y, line_gap)
            max_box_width -= hltb_box_w + int(12 * Theme._default_multiplier)

        max_text_width = max_box_width - (pad_x * 2)
        title = self._fit_text(imageTextPair.get_primary_text_long(), title_font, max_text_width)
        subtitle = self._fit_text(imageTextPair.get_description(), subtitle_font, max_text_width)
        if title == "" and subtitle == "" and hltb_time is None:
            return

        if hltb_time is not None:
            self._render_hltb_card(hltb_time, margin, pad_x, pad_y, line_gap, x_offset, y_add_offset, alpha)

        if title == "" and subtitle == "":
            return

        title_w, title_h = Display.get_text_dimensions(title_font, title)
        subtitle_w, subtitle_h = Display.get_text_dimensions(subtitle_font, subtitle) if subtitle != "" else (0, 0)
        text_w = max(title_w, subtitle_w)
        text_h = title_h + (line_gap + subtitle_h if subtitle != "" else 0)

        box_w = min(max_box_width, text_w + (pad_x * 2))
        box_h = text_h + (pad_y * 2)
        box_x = margin + x_offset
        box_y = Device.get_device().screen_height() - box_h - margin + y_add_offset
        text_x = box_x + pad_x
        title_y = box_y + pad_y
        subtitle_y = title_y + title_h + line_gap

        Display.render_box((255, 255, 255), box_x - 1, box_y - 1, box_w + 2, box_h + 2)
        Display.render_box((0, 0, 0), box_x, box_y, box_w, box_h)
        Display.render_text(
            title,
            text_x,
            title_y,
            Theme.text_color(FontPurpose.LIST_INDEX),
            title_font,
            render_mode=RenderMode.TOP_LEFT_ALIGNED,
            alpha=self._clamp_alpha(alpha)
        )
        if subtitle != "":
            Display.render_text(
                subtitle,
                text_x,
                subtitle_y,
                Theme.text_color(FontPurpose.LIST_TOTAL),
                subtitle_font,
                render_mode=RenderMode.TOP_LEFT_ALIGNED,
                alpha=self._clamp_alpha(alpha)
            )

    def _render_primary_image(self,
                              image_path: str,
                              x: int,
                              y: int,
                              render_mode=RenderMode.TOP_LEFT_ALIGNED,
                              target_width=None,
                              target_height=None,
                              resize_type=None):

        w,h = Display.render_image(image_path=image_path,
                                   x=x,
                                   y=y,
                                   render_mode=render_mode,
                                   target_width=target_width,
                                   target_height=target_height,
                                   resize_type=resize_type,)

        if(w == 0):
            w,h = Display.render_image(image_path=self.missing_image_path,
                                   x=x,
                                   y=y,
                                   render_mode=render_mode,
                                   target_width=target_width,
                                   target_height=target_height,
                                   resize_type=resize_type)

        return w,h

    def _render_framed_image(self, image_path, x, y, target_width, target_height, resize_type):
        border = max(3, int(4 * Theme._default_multiplier))
        Display.render_box(
            (255, 255, 255),
            x - border - 1,
            y - border - 1,
            target_width + (border * 2) + 2,
            target_height + (border * 2) + 2
        )
        Display.render_box(
            (0, 0, 0),
            x - border,
            y - border,
            target_width + (border * 2),
            target_height + (border * 2)
        )

        w, h = Display.render_image(
            image_path=image_path,
            x=x,
            y=y,
            render_mode=RenderMode.TOP_LEFT_ALIGNED,
            target_width=target_width,
            target_height=target_height,
            resize_type=resize_type,
        )
        if w == 0:
            Display.render_image(
                image_path=self.missing_image_path,
                x=x,
                y=y,
                render_mode=RenderMode.TOP_LEFT_ALIGNED,
                target_width=target_width,
                target_height=target_height,
                resize_type=resize_type,
            )

    def _render_compact_switcher_media(self, imageTextPair, image_path, x_offset=0, y_add_offset=0):
        extra_data = imageTextPair.get_extra_data() or {}
        box_art_image_path = extra_data.get("box_art_image_path") or extra_data.get("overlay_image_path")
        preview_image_path = extra_data.get("preview_image_path")
        if preview_image_path is None and extra_data.get("overlay_image_path") is not None:
            preview_image_path = image_path
        if box_art_image_path is None:
            return False

        margin = int(18 * Theme._default_multiplier)
        gap = int(18 * Theme._default_multiplier)
        top_y = self.get_top_bar_height() + int(18 * Theme._default_multiplier) + y_add_offset
        text_margin = int(18 * Theme._default_multiplier)
        text_reserve_h = int(76 * Theme._default_multiplier)

        box_art_width = int(210 * Theme._default_multiplier)
        box_art_height = max(
            int(330 * Theme._default_multiplier),
            Device.get_device().screen_height() - top_y - text_reserve_h - text_margin)
        preview_width = int((Device.get_device().screen_width() - (margin * 2) - gap - box_art_width) * 0.92)
        preview_height = int(preview_width * 0.70)
        right_stack_y = top_y + int(42 * Theme._default_multiplier)
        preview_y = right_stack_y

        box_art_x = margin + x_offset
        preview_x = margin + box_art_width + gap + x_offset

        self._render_framed_image(
            box_art_image_path,
            box_art_x,
            top_y,
            box_art_width,
            box_art_height,
            ResizeType.ZOOM
        )
        if preview_image_path is not None:
            progress_y = right_stack_y
            progress_h = self._render_playtime_progress_bar(extra_data, preview_x, progress_y, preview_width)
            if progress_h > 0:
                preview_y = progress_y + progress_h + int(8 * Theme._default_multiplier)

            self._render_framed_image(
                preview_image_path,
                preview_x,
                preview_y,
                preview_width,
                preview_height,
                ResizeType.ZOOM
            )

        return True

    def _render_image_overlay(self, imageTextPair, x_offset=0, y_add_offset=0):
        extra_data = imageTextPair.get_extra_data() or {}
        overlay_image_path = extra_data.get("overlay_image_path")
        if overlay_image_path is None:
            return

        target_width = int(90 * Theme._default_multiplier)
        target_height = int(120 * Theme._default_multiplier)
        border = max(3, int(4 * Theme._default_multiplier))
        margin = int(12 * Theme._default_multiplier)

        right_x = Device.get_device().screen_width() - margin + x_offset
        top_y = self.get_top_bar_height() + margin + y_add_offset
        box_x = right_x - target_width - (border * 2)
        box_y = top_y - border
        box_w = target_width + (border * 2)
        box_h = target_height + (border * 2)

        Display.render_box((255, 255, 255), box_x - 1, box_y - 1, box_w + 2, box_h + 2)
        Display.render_box((0, 0, 0), box_x, box_y, box_w, box_h)
        Display.render_image(
            image_path=overlay_image_path,
            x=right_x - border,
            y=top_y,
            render_mode=RenderMode.TOP_RIGHT_ALIGNED,
            target_width=target_width,
            target_height=target_height,
            resize_type=ResizeType.FIT,
        )

    def get_top_bar_height(self):
        if(self.render_bottom_bar_text_enabled):
            return Display.get_top_bar_height(False)
        else:
            return 0

    def _render_image(self, index=None, x_offset=0, y_add_offset=0, render_text_overlay=True, text_alpha=None):
        imageTextPair = self.options[index]
        image_path = imageTextPair.get_image_path_selected_ideal(self.resized_width, self.resized_height)
        primary_text = imageTextPair.get_primary_text_long()
        secondary_text = imageTextPair.get_description()
        frame_x_offset = x_offset
        if self._use_compact_text_overlay(imageTextPair):
            rendered_compact_media = self._render_compact_switcher_media(imageTextPair, image_path, frame_x_offset, y_add_offset)
            if rendered_compact_media:
                if render_text_overlay:
                    self._render_compact_text_overlay(imageTextPair, frame_x_offset, y_add_offset, text_alpha)
                return

        y_offset = self.get_top_bar_height()
        if(self.resize_type is ResizeType.FIT):
            render_mode = RenderMode.TOP_CENTER_ALIGNED
            x_offset += Device.get_device().screen_width() // 2
        else:
            top_aligned = False
            bottom_aligned = False
            if(top_aligned):
                render_mode = RenderMode.TOP_CENTER_ALIGNED
                x_offset += Device.get_device().screen_width() // 2
            elif(bottom_aligned):
                render_mode = RenderMode.BOTTOM_CENTER_ALIGNED
                x_offset += Device.get_device().screen_width() // 2
                y_offset = Device.get_device().screen_height() - self.get_top_bar_height()
            else:
                render_mode = RenderMode.MIDDLE_CENTER_ALIGNED
                x_offset += Device.get_device().screen_width() // 2
                y_offset = Display.get_top_bar_height(False) + (Display.get_usable_screen_height(False))//2

        y_offset += y_add_offset
        self._render_primary_image( image_path,
                                    x_offset,
                                    y_offset,
                                    render_mode,
                                    target_width=self.resized_width,
                                    target_height=self.resized_height,
                                    resize_type=self.resize_type)

        self._render_image_overlay(imageTextPair, frame_x_offset, y_add_offset)

        if render_text_overlay:
            if self._use_compact_text_overlay(imageTextPair):
                self._render_compact_text_overlay(imageTextPair, frame_x_offset, y_add_offset, text_alpha)
            elif(not self.set_top_bar_text_to_selection or self.image_resize_height_multiplier == 1.0):
                self._render_shadowed_text(primary_text, Device.get_device().screen_height() * 0.68, FontPurpose.SHADOWED_BACKDROP, FontPurpose.SHADOWED, 25,text_alpha)
                self._render_shadowed_text(secondary_text, Device.get_device().screen_height() * 0.78, FontPurpose.SHADOWED_BACKDROP_SMALL, FontPurpose.SHADOWED_SMALL, 27,text_alpha)

    def calculate_start_index(self):
        start_index = self.selected + 1 if self.selected != len(self.options) -1 else self.selected
        current_width = self.option_text_widths[start_index] + self.x_text_pad

        for i in range(start_index - 1, -1, -1):
            added_width = self.option_text_widths[i] + self.x_text_pad
            if current_width + added_width > Device.get_device().screen_width():
                break
            current_width += added_width
            start_index = i

        return start_index

    def _render_bottom_bar_text(self):
        if(self.render_bottom_bar_text_enabled and not self._selected_uses_compact_text_overlay()):
            start_index = self.calculate_start_index()
            if(self.last_start > start_index):
                if(self.selected >= self.last_start):
                    start_index = self.last_start
                else:
                    while(self.last_start < start_index):
                        start_index = self.last_start - 1

            visible_text_options = self.options[start_index:len(self.options)]

            y_offset = int(Device.get_device().screen_height() - 10 * Theme._default_multiplier)
            x_offset = self.x_text_pad

            for visible_index, imageTextPair in enumerate(visible_text_options):
                actual_index = start_index + visible_index
                color = Theme.text_color_selected(
                    self.font_purpose) if actual_index == self.selected else Theme.text_color(self.font_purpose)
                w, h = Display.render_text(imageTextPair.get_primary_text()[:10],
                                    x_offset,
                                    y_offset,
                                    color,
                                    self.font_purpose,
                                    render_mode=RenderMode.BOTTOM_LEFT_ALIGNED)
                x_offset += self.x_text_pad + w

            self.last_start = start_index

    def _clear(self):
        if (self.set_top_bar_text_to_selection) and len(self.options) > 0:
            Display.clear(
                self.options[self.selected].get_primary_text(), hide_top_bar_icons=True, render_bottom_bar_icons_and_images=False)
        else:
            Display.clear(self.top_bar_text, render_bottom_bar_icons_and_images=False)

    def _render_entire_screen(self, index, x_offset):
        self._clear()
        self._render_image(index=index,x_offset=x_offset,render_text_overlay=True)
        self._render_bottom_bar_text()

    def _render(self):
        self.correct_selected_for_off_list()

        if(self.selected != self.last_selected):
            self.animate_transition()
            self._render_entire_screen(index=self.selected,x_offset=0)
        else:
            self._render_entire_screen(index=self.selected,x_offset=0)
            self.animated_count = 0

        self.last_selected = self.selected
        Display.present()

    def get_selected_option(self):
        if 0 <= self.selected < len(self.options):
            return self.options[self.selected]
        else:
            return None

    def get_selection(self, select_controller_inputs=[ControllerInput.A]):
        self._render()

        if (Controller.get_input()):
            compact_text_overlay = self._selected_uses_compact_text_overlay()
            if Controller.last_input() in select_controller_inputs:
                return Selection(self.get_selected_option(), Controller.last_input(), self.selected)
            elif Controller.last_input() == ControllerInput.B:
                return Selection(self.get_selected_option(), Controller.last_input(), self.selected)
            elif Controller.last_input() == ControllerInput.DPAD_DOWN:
                if not compact_text_overlay:
                    self.adjust_selected(-1, skip_by_letter=False)
                    self.y_rotate_instead = True
            elif Controller.last_input() == ControllerInput.DPAD_LEFT:
                self.adjust_selected(-1, skip_by_letter=False)
                self.y_rotate_instead = False
            elif Controller.last_input() == ControllerInput.DPAD_UP:
                if not compact_text_overlay:
                    self.adjust_selected(+1, skip_by_letter=False)
                    self.y_rotate_instead = True
            elif Controller.last_input() == ControllerInput.DPAD_RIGHT:
                self.adjust_selected(+1, skip_by_letter=False)
                self.y_rotate_instead = False
            elif Controller.last_input() == ControllerInput.L1:
                self.adjust_selected(-1, skip_by_letter=False)
            elif Controller.last_input() == ControllerInput.R1:
                self.adjust_selected(+1, skip_by_letter=False)
            elif Controller.last_input() == ControllerInput.L2:
                self.adjust_selected(+1, skip_by_letter=False)
            elif Controller.last_input() == ControllerInput.R2:
                self.adjust_selected(-1, skip_by_letter=False)

        return Selection(self.get_selected_option(), None, self.selected)

    def adjust_selected(self, amount, skip_by_letter):
        amount = self.calculate_amount_to_move_by(amount, skip_by_letter)
        self.selected += amount
        self.correct_selected_for_off_list()

    def animate_transition(self):
        if not Device.get_device().get_system_config().animations_enabled():
            return

        animation_duration = 0.30 / Device.get_device().animation_divisor() - self.animated_count *0.04  # seconds
        start_time = time.time()

        if(self.y_rotate_instead):
            total_shift = Device.get_device().screen_height()
        else:
            total_shift = Device.get_device().screen_width()

        last_frame_time = 0
        refresh_rate = 1/60

        option_count = len(self.options)
        if option_count <= 1:
            return

        diff = (self.selected - self.last_selected) % option_count
        rotate_left = diff > option_count // 2
        while animation_duration > 0:
            elapsed = time.time() - start_time
            t = min(elapsed / animation_duration, 1.0)  # clamp to [0, 1]

            self._clear()
            self._render_bottom_bar_text()

            if rotate_left:
                old_frame_offset = int(total_shift * t)
                new_frame_offset = -total_shift + old_frame_offset
            else:
                old_frame_offset = int(-total_shift * t)
                new_frame_offset = total_shift + old_frame_offset

            old_x_offset = 0
            new_x_offset = 0
            old_y_offset = 0
            new_y_offset = 0

            if(self.y_rotate_instead):
                old_y_offset = old_frame_offset
                new_y_offset = new_frame_offset
            else:
                old_x_offset = old_frame_offset
                new_x_offset = new_frame_offset

            if(t < 1.0):
                self._render_image(self.last_selected, old_x_offset, old_y_offset,render_text_overlay=False, text_alpha=int(256 * (1.0-t)//1.0))
            else:
                self._render_image(self.last_selected, old_x_offset, old_y_offset,render_text_overlay=False)


            self._render_image(self.selected, new_x_offset, new_y_offset,render_text_overlay=True, text_alpha=256)

            the_time = time.time()
            if the_time - last_frame_time < refresh_rate:
                time.sleep(refresh_rate - (the_time - last_frame_time))
            Display.present()

            if t >= 1.0:
                break

            last_frame_time = time.time()
        self.animated_count += 1
