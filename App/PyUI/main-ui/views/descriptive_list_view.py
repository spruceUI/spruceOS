from typing import List
from devices.device import Device
from display.display import Display
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
import sdl2
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.list_view import ListView

class DescriptiveListView(ListView):

    def __init__(self, top_bar_text,
                 options: List[GridOrListEntry], selected_bg, selected : int = 0):
        super().__init__()
        self.top_bar_text = top_bar_text
        self.options : List[GridOrListEntry] = options

        self.selected : int = selected
        self.selected_bg = selected_bg
        each_entry_width, self.each_entry_height = Display.get_image_dimensions(selected_bg)
        # TODO is there a bettter way? Apps are getting set to 3 instead of 4 
        self.max_rows = (Display.get_usable_screen_height(force_include_top_bar=True) // self.each_entry_height)
        self.current_top = 0
        self.current_bottom = min(self.max_rows,len(options))

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
                    row_offset_y)
                
            icon_w = 0
            icon_h = 0
            if(iconPath is not None):
                icon_w, icon_h = Display.render_image(iconPath, 
                                    row_offset_x, 
                                    row_offset_y + Theme.get_descriptive_list_icon_offset_y())

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
                    row_offset_y + Theme.get_descriptive_list_text_offset_y(), 
                    color, 
                    FontPurpose.DESCRIPTIVE_LIST_TITLE,
                    RenderMode.TOP_RIGHT_ALIGNED)

            color = Theme.text_color_selected(FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION) if actual_index == self.selected else Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION)
            
            if(gridOrListEntry.get_description() is not None):
                text_w, text_h = Display.render_text(
                    gridOrListEntry.get_description(), 
                    row_offset_x + icon_w + Theme.get_descriptive_list_text_from_icon_offset(), 
                    row_offset_y + + Theme.get_descriptive_list_text_offset_y() + title_h, 
                    color, 
                    FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION)

            row_offset_y += self.each_entry_height
            