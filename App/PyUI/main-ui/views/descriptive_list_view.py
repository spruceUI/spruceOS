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

class DescriptiveListView(ListView):

    def __init__(self, top_bar_text,
                 options: List[GridOrListEntry], selected_bg, selected : int = 0):
        super().__init__()
        self.top_bar_text = top_bar_text
        self.options : List[GridOrListEntry] = options

        self.selected : int = selected
        PyUiLogger.get_logger().info(f"selected_bg = {selected_bg}")

        self.selected_bg = selected_bg
        self.each_entry_width, self.each_entry_height = Display.get_image_dimensions(selected_bg)
        self.each_entry_height = max(self.each_entry_height, self.calculate_max_text_height(options))

        # TODO is there a bettter way? Apps are getting set to 3 instead of 4 
        self.max_rows = (Display.get_usable_screen_height(force_include_top_bar=True) // self.each_entry_height)
        self.current_top = 0
        self.current_bottom = min(self.max_rows,len(options))
        self.center_selection()

    def calculate_max_text_height(self, options : List[GridOrListEntry]):
        main_text_width, main_text_height = Display.get_text_dimensions(FontPurpose.DESCRIPTIVE_LIST_TITLE)
        for option in options:
            if(option.get_description() is not None and option.get_description() != ''):
                desc_text_width, desc_text_height = Display.get_text_dimensions(FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION)
                return Theme.get_descriptive_list_text_offset_y() *2 + main_text_height + desc_text_height

        return Theme.get_descriptive_list_text_offset_y() + main_text_height

    def set_options(self, options):
        self.options = options

    def _render(self):
        visible_options: List[GridOrListEntry] = self.options[self.current_top:self.current_bottom]

        row_offset_x = Theme.get_descriptive_list_icon_offset_x()
        #TODO get padding from theme
        row_offset_y = Display.get_top_bar_height(force_include_top_bar = True) + 5
        
        for visible_index, (gridOrListEntry) in enumerate(visible_options):
            actual_index = self.current_top + visible_index
            iconPath = gridOrListEntry.get_icon()

            if actual_index == self.selected:
                Display.render_image(
                    self.selected_bg, 
                    0, 
                    row_offset_y,
                    target_width=Device.screen_width(),
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
            title_w, title_h = Display.render_text(
                gridOrListEntry.get_primary_text(), 
                row_offset_x + icon_w + Theme.get_descriptive_list_text_from_icon_offset(), 
                row_offset_y + Theme.get_descriptive_list_text_offset_y(), 
                color, 
                FontPurpose.DESCRIPTIVE_LIST_TITLE)

            if(gridOrListEntry.get_value_text() is not None):
                Display.render_text(
                    gridOrListEntry.get_value_text(), 
                    Device.screen_width() - Theme.get_descriptive_list_text_from_icon_offset(), 
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
            