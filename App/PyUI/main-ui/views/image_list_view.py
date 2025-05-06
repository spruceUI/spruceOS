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

class ImageListView(ListView):
    SHOW_ICONS = True
    DONT_SHOW_ICONS = False

    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme, top_bar_text,
                 options: List[GridOrListEntry], img_offset_x : int, img_offset_y : int, img_width : int, img_height: int,
                 selected_index : int, show_icons : bool, image_render_mode: RenderMode, selected_bg = None):
        super().__init__(controller)
        self.display = display
        self.device = device
        self.theme = theme
        self.top_bar_text = top_bar_text
        self.options = options

        self.selected = selected_index
        while(self.selected > len(options) and self.selected > 0):
            self.selected -= 1
        self.current_top = 0
        self.img_offset_x = img_offset_x
        self.img_offset_y = img_offset_y
        self.img_width = img_width
        self.img_height = img_height
        self.base_y_offset = self.display.get_top_bar_height() + 5
        #TODO get line height padding from theme
        self.show_icons = show_icons
        self.image_render_mode = image_render_mode
        self.selected_bg = selected_bg
        self.line_height = self._calculate_line_height()            
        self.max_rows = self.display.get_usable_screen_height() // self.line_height
        self.current_bottom = min(self.max_rows,len(options))

    
    def _calculate_line_height(self):
        text_line_height = self.display.get_line_height(FontPurpose.LIST) + 10  # add 10px padding between lines
        icon_line_height = 0
        if(self.show_icons):
            for gridOrListEntry in self.options:
                if(gridOrListEntry.get_icon() is not None):
                    icon_w, icon_h = self.display.get_image_dimensions(gridOrListEntry.get_icon())
                    icon_line_height = max(icon_line_height, icon_h)

        bg_height = 0
        if(self.selected_bg is not None):
            bg_w, bg_height = self.display.get_image_dimensions(self.selected_bg)

        return max(text_line_height, icon_line_height, bg_height)



    def _render_text(self, visible_options):
        for visible_index, (imageTextPair) in enumerate(visible_options):
            actual_index = self.current_top + visible_index
           
            x_value = 20 #TODO get this from somewhere
            y_value = self.base_y_offset + visible_index * self.line_height

            if actual_index == self.selected:
                color = self.theme.text_color_selected(FontPurpose.LIST)
                if(self.selected_bg is not None):
                    self.display.render_image(self.selected_bg,0, y_value)
            else:
                color = self.theme.text_color(FontPurpose.LIST)

            if(self.show_icons and imageTextPair.get_icon() is not None):
                icon_width, icon_height = self.display.render_image(imageTextPair.get_icon(),x_value, y_value)
                x_value += icon_width
            else:
                pass

            self.display.render_text(imageTextPair.get_primary_text(), x_value, y_value + self.line_height//2, color, FontPurpose.LIST,
                                    RenderMode.MIDDLE_LEFT_ALIGNED)


    def _render_image(self, visible_options):
        for visible_index, (imageTextPair) in enumerate(visible_options):
            actual_index = self.current_top + visible_index
            imagePath = imageTextPair.get_image_path_selected() if actual_index == self.selected else imageTextPair.get_image_path()
            if(actual_index == self.selected and imagePath is not None):
                self.display.render_image(imagePath, 
                                     self.img_offset_x, 
                                     self.img_offset_y,
                                     self.image_render_mode,
                                     self.img_width,
                                     self.img_height)

    def _render(self):
        visible_options = self.options[self.current_top:self.current_bottom]

        #ensure image is rendered last so it is on top of the text
        self._render_text(visible_options)
        self._render_image(visible_options)