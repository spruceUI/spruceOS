from typing import List
from controller.controller_inputs import ControllerInput
from display.display import Display
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
import sdl2
from devices.device import Device
from controller.controller import Controller
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.list_view import ListView

class DescriptiveListView(ListView):

    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme, top_bar_text,
                 options: List[GridOrListEntry], selected_bg, selected : int = 0):
        super().__init__(controller)
        self.display = display
        self.device = device
        self.theme = theme
        self.top_bar_text = top_bar_text
        self.options : List[GridOrListEntry] = options

        self.selected : int = selected
        self.selected_bg = selected_bg
        each_entry_width, self.each_entry_height = display.get_image_dimensions(selected_bg)
        # TODO is there a bettter way? Apps are getting set to 3 instead of 4 
        self.max_rows = (self.display.get_usable_screen_height() // self.each_entry_height)
        self.current_top = 0
        self.current_bottom = min(self.max_rows,len(options))

    def set_options(self, options):
        self.options = options

    def _render(self):
        visible_options: List[GridOrListEntry] = self.options[self.current_top:self.current_bottom]

        row_offset_x = self.theme.get_descriptive_list_icon_offset_x()
        #TODO get padding from theme
        row_offset_y = self.display.get_top_bar_height() + 5
        
        for visible_index, (gridOrListEntry) in enumerate(visible_options):
            actual_index = self.current_top + visible_index
            iconPath = gridOrListEntry.get_icon()

            if actual_index == self.selected:
                self.display.render_image(
                    self.selected_bg, 
                    0, 
                    row_offset_y)
                
            icon_w = 0
            icon_h = 0
            if(iconPath is not None):
                icon_w, icon_h = self.display.render_image(iconPath, 
                                    row_offset_x, 
                                    row_offset_y + self.theme.get_descriptive_list_icon_offset_y())

            color = self.theme.text_color_selected(FontPurpose.DESCRIPTIVE_LIST_TITLE) if actual_index == self.selected else self.theme.text_color(FontPurpose.DESCRIPTIVE_LIST_TITLE)
            title_w, title_h = self.display.render_text(
                gridOrListEntry.get_primary_text(), 
                row_offset_x + icon_w + self.theme.get_descriptive_list_text_from_icon_offset(), 
                row_offset_y + self.theme.get_descriptive_list_text_offset_y(), 
                color, 
                FontPurpose.DESCRIPTIVE_LIST_TITLE)

            if(gridOrListEntry.get_value_text() is not None):
                self.display.render_text(
                    gridOrListEntry.get_value_text(), 
                    self.device.screen_width - self.theme.get_descriptive_list_text_from_icon_offset(), 
                    row_offset_y + self.theme.get_descriptive_list_text_offset_y(), 
                    color, 
                    FontPurpose.DESCRIPTIVE_LIST_TITLE,
                    RenderMode.TOP_RIGHT_ALIGNED)

            color = self.theme.text_color_selected(FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION) if actual_index == self.selected else self.theme.text_color(FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION)
            
            if(gridOrListEntry.get_description() is not None):
                text_w, text_h = self.display.render_text(
                    gridOrListEntry.get_description(), 
                    row_offset_x + icon_w + self.theme.get_descriptive_list_text_from_icon_offset(), 
                    row_offset_y + + self.theme.get_descriptive_list_text_offset_y() + title_h, 
                    color, 
                    FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION)

            row_offset_y += self.each_entry_height