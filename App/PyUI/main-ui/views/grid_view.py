from typing import List
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.font_purpose import FontPurpose
from display.display import Display
from display.render_mode import RenderMode
from display.resize_type import ResizeType
import sdl2
from controller.controller import Controller
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view import View

class GridView(View):
    def __init__(self,top_bar_text, options: List[GridOrListEntry], cols : int, rows: int,selected_bg : str = None,
                  selected_index=0, show_grid_text=True, resized_width=None, resized_height=None, 
                  set_top_bar_text_to_selection=False, resize_type=None):
        super().__init__()
        self.resized_width = resized_width
        self.resized_height = resized_height
        self.resize_type = resize_type
        self.top_bar_text = top_bar_text
        self.set_top_bar_text_to_selection = set_top_bar_text_to_selection
        self.options : List[GridOrListEntry] = options 

        self.max_img_height = resized_height
        if(self.max_img_height is None):
            self.max_img_height = 0
            for option in options:           
                self.max_img_height = max(self.max_img_height, Display.get_image_dimensions(option.get_image_path())[1])

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
        self.show_grid_text = show_grid_text
     
    def set_options(self, options):
        self.options = options

    def correct_selected_for_off_list(self):
        while(self.selected < 0):
            self.selected = len(self.options) + self.selected
        self.selected = max(0, self.selected)

        if(len(self.options) > 0):
            self.selected = self.selected % (len(self.options))

        while(self.selected < self.current_left):
            if(self.rows > 1):
                self.current_left -= (self.cols*self.rows)
                self.current_right -= (self.cols*self.rows)
            else:
                self.current_left -=1
                self.current_right -=1

        while(self.selected >= self.current_right):
            if(self.rows > 1):
                self.current_left += (self.cols*self.rows)
                self.current_right += (self.cols*self.rows)
            else:
                self.current_left +=1
                self.current_right +=1

    def _render(self):
        if(self.set_top_bar_text_to_selection) and len(self.options) > 0:
            Display.clear(self.options[self.selected].get_primary_text(), hide_top_bar_icons=True)
        else:
            Display.clear(self.top_bar_text)
        self.correct_selected_for_off_list()

        visible_options: List[GridOrListEntry] = self.options[self.current_left:self.current_right]

        #TODO Get hard coded values for padding from theme
        x_pad = 10
        usable_width = Device.screen_width() - (2 * x_pad)
        icon_width = usable_width / self.cols  # Initial icon width
        
        for visible_index, imageTextPair in enumerate(visible_options):

            actual_index = self.current_left + visible_index
            image_path = imageTextPair.get_image_path_selected() if actual_index == self.selected else imageTextPair.get_image_path()
            
            x_index = visible_index % self.cols
            x_offset = int(x_pad + x_index * (icon_width)) + int(icon_width/2)


            if(self.rows == 1) : 
                y_image_offset = Display.get_center_of_usable_screen_height()
                render_mode = RenderMode.MIDDLE_CENTER_ALIGNED
            else :
                y_index = int(visible_index / self.cols) 
                row_spacing = Display.get_usable_screen_height() / self.rows
                row_start_y = y_index * row_spacing
                row_mid_y = row_start_y
                y_image_offset = int(row_mid_y + Display.get_top_bar_height()) + Theme.get_grid_multi_row_extra_y_pad()
                render_mode = RenderMode.TOP_CENTER_ALIGNED

            if(self.selected_bg is not None):
                if(actual_index == self.selected):
                    target_bg_width = self.resized_width
                    target_bg_height = self.resized_height
                    
                    selected_bg_offset = 0
                    if(self.resized_width is not None):
                        #TODO not fixed values
                        target_bg_width += Theme.get_grid_multi_row_sel_bg_resize_pad_width()
                        target_bg_height += Theme.get_grid_multi_row_sel_bg_resize_pad_height()
                        selected_bg_offset = -1 * Theme.get_grid_multi_row_sel_bg_resize_pad_height()//2
                        
                    Display.render_image(self.selected_bg, 
                                            x_offset, 
                                            y_image_offset + selected_bg_offset,
                                            render_mode,
                                            target_width=target_bg_width,
                                            target_height=target_bg_height,
                                            resize_type=self.resize_type)
            
            Display.render_image(image_path, 
                                    x_offset, 
                                    y_image_offset,
                                    render_mode,
                                    target_width=self.resized_width,
                                    target_height=self.resized_height,
                                    resize_type=self.resize_type)
            color = Theme.text_color_selected(self.font_purpose) if actual_index == self.selected else Theme.text_color(self.font_purpose)

            if(self.rows == 1) : 
                real_y_text_offset = int(Device.screen_height() * 325/480)
            else:
                real_y_text_offset = y_image_offset + self.max_img_height + Theme.get_grid_multirow_text_offset_y()

            if(self.show_grid_text) :
                Display.render_text_centered(imageTextPair.get_primary_text(), 
                                        x_offset,
                                        real_y_text_offset, color,
                                        self.font_purpose)
        
        # Don't display indexing for single row grids
        if(self.rows > 1) :
            Display.add_index_text(self.selected+1, len(self.options))            
        Display.present()

    def get_selected_option(self):
        if 0 <= self.selected < len(self.options):
            return self.options[self.selected]
        else:
            return None

    def get_selection(self, select_controller_inputs = [ControllerInput.A]):
        self._render()
        
        if(Controller.get_input()):
            if Controller.last_input() == ControllerInput.DPAD_LEFT:
                self.selected-=1
                self.correct_selected_for_off_list()
            elif Controller.last_input() == ControllerInput.DPAD_RIGHT:
                self.selected+=1
                self.correct_selected_for_off_list()
            elif Controller.last_input() == ControllerInput.L1:
                self.selected-=self.cols*self.rows
                self.correct_selected_for_off_list()
            elif Controller.last_input() == ControllerInput.R1:
                self.selected+=self.cols*self.rows
                self.correct_selected_for_off_list()
            if Controller.last_input() == ControllerInput.DPAD_UP:
                
                if(self.selected == 0):
                    self.selected-= 1
                elif(self.selected - self.cols < 0):
                    self.selected = 0
                else:
                    self.selected-=self.cols

                self.correct_selected_for_off_list()
            elif Controller.last_input() == ControllerInput.DPAD_DOWN:
                
                if(self.selected == len(self.options)-1):
                    self.selected=len(self.options)
                elif(self.selected + self.cols >= len(self.options)):
                    self.selected = len(self.options) - 1
                else:
                    self.selected+=self.cols

                self.correct_selected_for_off_list()
            elif Controller.last_input() in select_controller_inputs:
                return Selection(self.get_selected_option(),Controller.last_input(), self.selected)
            elif Controller.last_input() == ControllerInput.B:
                return Selection(self.get_selected_option(),Controller.last_input(), self.selected)
                
        return Selection(self.get_selected_option(),None, self.selected)
