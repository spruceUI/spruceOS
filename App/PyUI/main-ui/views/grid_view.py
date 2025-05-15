from typing import List
from controller.controller_inputs import ControllerInput
from display.font_purpose import FontPurpose
from display.font_size import FontSize
from display.display import Display
from display.render_mode import RenderMode
import sdl2
from devices.device import Device
from controller.controller import Controller
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view import View

class GridView(View):

    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme,
                  top_bar_text, options: List[GridOrListEntry], cols : int, rows: int,selected_bg : str = None,
                  selected_index=0):
        super().__init__()
        self.display : Display = display
        self.controller : Controller = controller
        self.device : Device = device
        self.theme : Theme = theme
        self.top_bar_text = top_bar_text
        self.options : List[GridOrListEntry] = options 

        self.selected = selected_index
        self.toggles = [False] * len(options)

        self.current_left = 0
        self.current_right = min(rows * cols,len(options))

        self.rows = rows
        self.cols = cols

        if(rows > 1):
            self.font_purpose = FontPurpose.GRID_MULTI_ROW
        else:
            self.font_purpose = FontPurpose.GRID_ONE_ROW

        self.selected_bg = selected_bg
     
    def set_options(self, options):
        self.options = options

    def correct_selected_for_off_list(self):
        self.selected = max(0, self.selected)
        self.selected = min(len(self.options)-1, self.selected)
        
        while(self.selected < self.current_left):
            self.current_left -= (self.cols*self.rows)
            self.current_right -= (self.cols*self.rows)

        while(self.selected >= self.current_right):
            self.current_left += (self.cols*self.rows)
            self.current_right += (self.cols*self.rows)

    def _render(self):
        self.display.clear(self.top_bar_text)
        self.correct_selected_for_off_list()

        visible_options: List[GridOrListEntry] = self.options[self.current_left:self.current_right]

        #TODO Get hard coded values for padding from theme
        x_pad = 9 * self.cols
        usable_width = self.device.screen_width - (2 * x_pad)
        icon_width = usable_width / self.cols  # Initial icon width
        
        for visible_index, imageTextPair in enumerate(visible_options):

            actual_index = self.current_left + visible_index
            image_path = imageTextPair.get_image_path_selected() if actual_index == self.selected else imageTextPair.get_image_path()
            
            x_index = visible_index % self.cols
            x_offset = int(x_pad + x_index * (icon_width)) + int(icon_width/2)


            if(self.rows == 1) : 
                y_icon_offset = self.display.get_center_of_usable_screen_height()
                render_mode = RenderMode.MIDDLE_CENTER_ALIGNED
            else :
                y_index = int(visible_index / self.cols) 
                row_spacing = self.display.get_usable_screen_height() / self.rows
                row_start_y = y_index * row_spacing
                row_mid_y = row_start_y + row_spacing /2
                y_icon_offset = int(row_mid_y + self.display.get_top_bar_height())
                render_mode = RenderMode.MIDDLE_CENTER_ALIGNED

            if(self.selected_bg is not None):
                if(actual_index == self.selected):
                    self.display.render_image(self.selected_bg, 
                                            x_offset, 
                                            y_icon_offset,
                                            render_mode)

            actual_height, actual_width = self.display.render_image(image_path, 
                                     x_offset, 
                                     y_icon_offset,
                                     render_mode)
            color = self.theme.text_color_selected(self.font_purpose) if actual_index == self.selected else self.theme.text_color(self.font_purpose)

            if(self.rows == 1) : 
                real_y_text_offset = int(self.device.screen_height * 325/480)
            else:
                real_y_text_offset = y_icon_offset + actual_width//2 + self.theme.get_grid_multirow_text_offset_y()

            self.display.render_text_centered(imageTextPair.get_primary_text(), 
                                    x_offset,
                                    real_y_text_offset, color,
                                    self.font_purpose)
        
        # Don't display indexing for single row grids
        if(self.rows > 1) :
            self.display.add_index_text(self.selected+1, len(self.options))            
        self.display.present()

    def get_selected_option(self):
        if 0 <= self.selected < len(self.options):
            return self.options[self.selected]
        else:
            return None

    def get_selection(self, select_controller_inputs = [ControllerInput.A]):
        self._render()
        
        if(self.controller.get_input()):
            if self.controller.last_input() == ControllerInput.DPAD_LEFT:
                self.selected-=1
                self.correct_selected_for_off_list()
            elif self.controller.last_input() == ControllerInput.DPAD_RIGHT:
                self.selected+=1
                self.correct_selected_for_off_list()
            elif self.controller.last_input() == ControllerInput.L1:
                self.selected-=self.cols*self.rows
                self.correct_selected_for_off_list()
            elif self.controller.last_input() == ControllerInput.R1:
                self.selected+=self.cols*self.rows
                self.correct_selected_for_off_list()
            if self.controller.last_input() == ControllerInput.DPAD_UP:
                self.selected-=self.cols
                self.correct_selected_for_off_list()
            elif self.controller.last_input() == ControllerInput.DPAD_DOWN:
                self.selected+=self.cols
                self.correct_selected_for_off_list()
            elif self.controller.last_input() in select_controller_inputs:
                return Selection(self.get_selected_option(),self.controller.last_input(), self.selected)
            elif self.controller.last_input() == ControllerInput.B:
                return Selection(self.get_selected_option(),self.controller.last_input(), self.selected)
                
        return Selection(self.get_selected_option(),None, self.selected)
