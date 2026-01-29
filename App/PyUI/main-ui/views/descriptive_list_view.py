from email.mime import text
import time
from typing import List
from devices.device import Device
from display.display import Display
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from display.resize_type import ResizeType
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.list_view import ListView
from views.text_utils import TextUtils

class DescriptiveListView(ListView):

    def __init__(self, top_bar_text,
                 options: List[GridOrListEntry], selected_bg, selected : int = 0):
        super().__init__()
        self.top_bar_text = top_bar_text
        self.set_options(options)
        self.selected : int = selected

        self.selected_bg = selected_bg
        self.each_entry_width, self.each_entry_height = Display.get_image_dimensions(selected_bg)

        usable = Display.get_usable_screen_height(force_include_top_bar=True) / self.each_entry_height

        self.max_rows = int(usable + (1 if usable % 1 >= 0.80 else 0))

        self.current_top = 0
        self.current_bottom = min(self.max_rows,len(options))
        self.center_selection()
        self.scroll_value_text_amount = 0
        self.last_selected = -1
        self.selected_same_entry_time = time.time()

    def set_options(self, options):
        self.options = options
        self.options_are_sorted = self.is_alphabetized(options)

    def options_are_alphabetized(self):
        return self.options_are_sorted
    
    def _render(self):
        visible_options: List[GridOrListEntry] = self.options[self.current_top:self.current_bottom]

        row_offset_x = Theme.get_descriptive_list_icon_offset_x()
        #TODO get padding from theme
        row_offset_y = Display.get_top_bar_height(force_include_top_bar = True) + 5
        
        if self.last_selected != self.selected:
            self.selected_same_entry_time = time.time()
            self.scroll_value_text_amount = 0
            self.last_selected = self.selected
        else:
            if(time.time() - self.selected_same_entry_time > 1):
                self.scroll_value_text_amount += 1

        for visible_index, (gridOrListEntry) in enumerate(visible_options):
            actual_index = self.current_top + visible_index
            iconPath = gridOrListEntry.get_icon()

            if actual_index == self.selected:
                Display.render_image(
                    self.selected_bg, 
                    0, 
                    row_offset_y,
                    target_width=Device.get_device().screen_width(),
                    target_height=self.each_entry_height,
                    resize_type= ResizeType.ZOOM
                    )
                
            icon_w = 0
            icon_h = 0
            if(iconPath is not None):
                icon_w, icon_h = Display.render_image(iconPath, 
                                    row_offset_x, 
                                    row_offset_y + Theme.get_descriptive_list_icon_offset_y(),
                                    render_mode = RenderMode.TOP_LEFT_ALIGNED, 
                                    target_width=int(self.each_entry_width*0.8), 
                                    target_height=int(self.each_entry_height*0.8))

            color = Theme.text_color_selected(FontPurpose.DESCRIPTIVE_LIST_TITLE) if actual_index == self.selected else Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_TITLE)
            title_y_offset = row_offset_y + Theme.get_descriptive_list_text_offset_y()
            title_render_mode = RenderMode.TOP_LEFT_ALIGNED
            if(gridOrListEntry.get_description() is None):
                title_y_offset = row_offset_y + self.each_entry_height // 2
                title_render_mode = RenderMode.MIDDLE_LEFT_ALIGNED

            title_w, title_h = Display.render_text(
                gridOrListEntry.get_primary_text(), 
                row_offset_x + icon_w + Theme.get_descriptive_list_text_from_icon_offset(), 
                title_y_offset, 
                color, 
                FontPurpose.DESCRIPTIVE_LIST_TITLE,
                render_mode=title_render_mode)

            if(gridOrListEntry.get_value_text() is not None):
                value_text = gridOrListEntry.get_value_text()
                max_value_text_length = 25
                
                if(len(value_text) > max_value_text_length):
                    value_text = value_text[1:-1].strip()
                    if actual_index == self.selected:
                        value_text = TextUtils.scroll_string_chars(text=value_text,
                                                amt=self.scroll_value_text_amount,
                                                max_chars=max_value_text_length)
                    else:
                        value_text = value_text[:max_value_text_length-3] + "..."

                    value_text = "< " + value_text + " >"
                Display.render_text(
                    value_text, 
                    Device.get_device().screen_width() - Theme.get_descriptive_list_text_from_icon_offset(), 
                    row_offset_y + self.each_entry_height // 2, 
                    color, 
                    FontPurpose.DESCRIPTIVE_LIST_TITLE,
                    RenderMode.MIDDLE_RIGHT_ALIGNED)

            color = Theme.text_color_selected(FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION) if actual_index == self.selected else Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION)
            
            if(gridOrListEntry.get_description() is not None):
                text_w, text_h = Display.render_text(
                    gridOrListEntry.get_description(), 
                    row_offset_x + icon_w + Theme.get_descriptive_list_text_from_icon_offset(), 
                    row_offset_y + Theme.get_descriptive_list_text_offset_y() + title_h, 
                    color, 
                    FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION)

            row_offset_y += self.each_entry_height
            