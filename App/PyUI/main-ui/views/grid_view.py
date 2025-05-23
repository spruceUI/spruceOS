from typing import List
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.font_purpose import FontPurpose
from display.display import Display
from display.render_mode import RenderMode
from display.resize_type import ResizeType
from display.y_render_option import YRenderOption
import sdl2
from controller.controller import Controller
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view import View


class GridView(View):
    def __init__(self, top_bar_text, options: List[GridOrListEntry], cols: int, rows: int, selected_bg: str = None,
                 selected_index=0, show_grid_text=True, resized_width=None, resized_height=None,
                 set_top_bar_text_to_selection=False, resize_type=None, 
                 unselected_bg = None):
        super().__init__()
        self.resized_width = resized_width
        self.resized_height = resized_height
        self.resize_type = resize_type
        print(f"{top_bar_text} : resized_width = {self.resized_width}, resized_height={self.resized_height}, resize_type={self.resize_type}")
        self.top_bar_text = top_bar_text
        self.set_top_bar_text_to_selection = set_top_bar_text_to_selection
        self.options: List[GridOrListEntry] = options

        self.max_img_height = resized_height
        if (self.max_img_height is None):
            self.max_img_height = 0
            for option in options:
                self.max_img_height = max(
                    self.max_img_height, Display.get_image_dimensions(option.get_image_path())[1])

        self.selected = selected_index
        self.toggles = [False] * len(options)

        self.current_left = 0
        self.current_right = min(rows * cols, len(options))

        self.rows = rows
        self.cols = cols

        if (rows > 1):
            self.font_purpose = FontPurpose.GRID_MULTI_ROW
        else:
            self.font_purpose = FontPurpose.GRID_ONE_ROW

        self.selected_bg = selected_bg
        self.unselected_bg = unselected_bg
        self.show_grid_text = show_grid_text

    def set_options(self, options):
        self.options = options

    def correct_selected_for_off_list(self):
        while (self.selected < 0):
            self.selected = len(self.options) + self.selected
        self.selected = max(0, self.selected)

        if (len(self.options) > 0):
            self.selected = self.selected % (len(self.options))

        while (self.selected < self.current_left):
            if (self.rows > 1):
                self.current_left -= (self.cols*self.rows)
                self.current_right -= (self.cols*self.rows)
            else:
                self.current_left -= 1
                self.current_right -= 1

        while (self.selected >= self.current_right):
            if (self.rows > 1):
                self.current_left += (self.cols*self.rows)
                self.current_right += (self.cols*self.rows)
            else:
                self.current_left += 1
                self.current_right += 1

    def _render(self):
        if (self.set_top_bar_text_to_selection) and len(self.options) > 0:
            Display.clear(
                self.options[self.selected].get_primary_text(), hide_top_bar_icons=True)
        else:
            Display.clear(self.top_bar_text)
        self.correct_selected_for_off_list()

        visible_options: List[GridOrListEntry] = self.options[self.current_left:self.current_right]

        # TODO Get hard coded values for padding from theme
        x_pad = 10
        usable_width = Device.screen_width() - (2 * x_pad)
        icon_width = usable_width / self.cols  # Initial icon width

        for visible_index, imageTextPair in enumerate(visible_options):

            actual_index = self.current_left + visible_index
            image_path = imageTextPair.get_image_path_selected(
            ) if actual_index == self.selected else imageTextPair.get_image_path()

            x_index = visible_index % self.cols
            x_offset = int(x_pad + (x_index) * (icon_width)) + icon_width//2

            y_index = int(visible_index / self.cols)
            row_spacing = Display.get_usable_screen_height() / self.rows
            row_start_y = y_index * row_spacing
            bottom_row_y = row_start_y + row_spacing + Display.get_top_bar_height(False)
            render_mode = RenderMode.MIDDLE_CENTER_ALIGNED
            if(YRenderOption.CENTER == render_mode.y_mode):
                cell_y = bottom_row_y - row_spacing //2
                offset_divisor = 2
            elif(YRenderOption.BOTTOM == render_mode.y_mode):
                cell_y = bottom_row_y
                offset_divisor = 1
            

            bg_width = self.resized_width
            bg_height = self.resized_height
            if(self.show_grid_text):
                text_height = Display.get_line_height(self.font_purpose)
            else:
                text_height = 0
            
            if(self.rows == 1):
                img_offset = 0
            else:
                img_offset = Theme.get_system_select_grid_img_y_offset(text_height)
            print(f"Theme.ignore_top_and_bottom_bar_for_layout()={Theme.ignore_top_and_bottom_bar_for_layout()}, Display.get_top_bar_height()={Display.get_top_bar_height()}")
            print(f"img_offset = {img_offset}")

                
            bg_offset = 0
            if (self.resized_width is not None):
                # TODO not fixed values
                bg_width += Theme.get_grid_multi_row_sel_bg_resize_pad_width()
                bg_height += Theme.get_grid_multi_row_sel_bg_resize_pad_height()
                if(YRenderOption.CENTER == render_mode.y_mode):
                    bg_offset = 0
                elif(YRenderOption.BOTTOM == render_mode.y_mode):
                    bg_offset = Theme.get_grid_multi_row_sel_bg_resize_pad_height() //2    

            if (actual_index == self.selected):
                if (self.selected_bg is not None):
                    Display.render_image(self.selected_bg,
                                     x_offset,
                                     cell_y + bg_offset // offset_divisor,
                                     render_mode,
                                     target_width=bg_width,
                                     target_height=bg_height)
            elif(self.unselected_bg is not None):
                Display.render_image(self.unselected_bg,
                                     x_offset,
                                     cell_y,
                                     render_mode,
                                     target_width=bg_width,
                                     target_height=bg_height)

            Display.render_image(image_path,
                                 x_offset,
                                 cell_y + img_offset // offset_divisor,
                                 render_mode,
                                 target_width=self.resized_width,
                                 target_height=self.resized_height,
                                 resize_type=self.resize_type)
            color = Theme.text_color_selected(
                self.font_purpose) if actual_index == self.selected else Theme.text_color(self.font_purpose)

            if (self.show_grid_text):
                if(self.rows == 1) : 
                    y_text = int(Device.screen_height() * 360/480)
                else:
                    y_text = bottom_row_y - text_height
                Display.render_text(imageTextPair.get_primary_text(),
                                             x_offset,
                                             y_text,
                                             color,
                                             self.font_purpose,
                                             render_mode=RenderMode.BOTTOM_CENTER_ALIGNED)

        # Don't display indexing for single row grids
        if (self.rows > 1):
            Display.add_index_text(self.selected+1, len(self.options))
        Display.present()

    def get_selected_option(self):
        if 0 <= self.selected < len(self.options):
            return self.options[self.selected]
        else:
            return None

    def get_selection(self, select_controller_inputs=[ControllerInput.A]):
        self._render()

        if (Controller.get_input()):
            if Controller.last_input() == ControllerInput.DPAD_LEFT:
                self.selected -= 1
                self.correct_selected_for_off_list()
            elif Controller.last_input() == ControllerInput.DPAD_RIGHT:
                self.selected += 1
                self.correct_selected_for_off_list()
            elif Controller.last_input() == ControllerInput.L1:
                self.selected -= self.cols*self.rows
                self.correct_selected_for_off_list()
            elif Controller.last_input() == ControllerInput.R1:
                self.selected += self.cols*self.rows
                self.correct_selected_for_off_list()
            if Controller.last_input() == ControllerInput.DPAD_UP:

                if (self.selected == 0):
                    self.selected -= 1
                elif (self.selected - self.cols < 0):
                    self.selected = 0
                else:
                    self.selected -= self.cols

                self.correct_selected_for_off_list()
            elif Controller.last_input() == ControllerInput.DPAD_DOWN:

                if (self.selected == len(self.options)-1):
                    self.selected = len(self.options)
                elif (self.selected + self.cols >= len(self.options)):
                    self.selected = len(self.options) - 1
                else:
                    self.selected += self.cols

                self.correct_selected_for_off_list()
            elif Controller.last_input() in select_controller_inputs:
                return Selection(self.get_selected_option(), Controller.last_input(), self.selected)
            elif Controller.last_input() == ControllerInput.B:
                return Selection(self.get_selected_option(), Controller.last_input(), self.selected)

        return Selection(self.get_selected_option(), None, self.selected)
