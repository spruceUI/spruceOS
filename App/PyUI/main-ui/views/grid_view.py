import math
import time
from typing import List
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.font_purpose import FontPurpose
from display.display import Display
from display.render_mode import RenderMode
from display.y_render_option import YRenderOption
from controller.controller import Controller
from themes.theme import Theme
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view import View


class GridView(View):
    def __init__(self, top_bar_text, options: List[GridOrListEntry], cols: int, rows: int, selected_bg: str = None,
                 selected_index=0, show_grid_text=True, resized_width=None, resized_height=None,
                 set_top_bar_text_to_selection=False, set_bottom_bar_text_to_selection=False, resize_type=None, 
                 unselected_bg = None, grid_img_y_offset=None, missing_image_path=None,
                 wrap_around_single_row=None):
        super().__init__()
        self.resized_width = resized_width
        self.resized_height = resized_height
        self.resize_type = resize_type
        self.top_bar_text = top_bar_text
        self.set_top_bar_text_to_selection = set_top_bar_text_to_selection
        self.set_bottom_bar_text_to_selection = set_bottom_bar_text_to_selection
        self.set_options(options)

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

        if(wrap_around_single_row is None):
            wrap_around_single_row = True
        self.wrap_around_single_row = wrap_around_single_row

        self.selected_bg = selected_bg
        self.unselected_bg = unselected_bg
        self.show_grid_text = show_grid_text
        self.img_offset = grid_img_y_offset
        self.missing_image_path = missing_image_path
        # TODO Get hard coded values for padding from theme
        self.x_pad = 10
        self.usable_width = Device.get_device().screen_width() - (2 * self.x_pad)
        self.icon_width = self.usable_width / self.cols  # Initial icon width
        self.set_bg_offset_to_image_offset = Theme.grid_bg_offset_to_image_offset()

    def set_options(self, options):
        self.options = options
        self.options_are_sorted = self.is_alphabetized(options)

    def single_row_in_window(self):
        """Return True if index i is inside the circular window."""
        if self.current_left <= self.current_right:
            return self.current_left <= self.selected < self.current_right
        else:
            # wrapped window case, e.g. left=28 right=2
            return self.selected >= self.current_left or self.selected < self.current_right
        
    def correct_selected_for_off_list(self):
        while (self.selected < 0):
            self.selected = len(self.options) + self.selected
        self.selected = max(0, self.selected)

        if (len(self.options) > 0):
            self.selected = self.selected % (len(self.options))

        if(self.rows > 1):
            while (self.selected < self.current_left):
                self.current_left -= (self.cols)
                self.current_right -= (self.cols)

            while (self.selected >= self.current_right):
                self.current_left += (self.cols)
                self.current_right += (self.cols)
        elif(self.wrap_around_single_row):
            if(len(self.options) > self.cols):
                N = len(self.options)  # total number of items
                self.selected = self.selected % N

                # normalize current_left/right to wrap properly
                self.current_left  %= N
                self.current_right = (self.current_left + self.cols) % N
                while not self.single_row_in_window():
                    # shift window toward sel
                    if (self.current_left - self.selected) % N < (self.selected - self.current_left) % N:
                        # sel is "to the left" in circular sense
                        self.current_left  = (self.current_left - 1) % N
                        self.current_right = (self.current_right - 1) % N
                    else:
                        # sel is "to the right"
                        self.current_left  = (self.current_left + 1) % N
                        self.current_right = (self.current_right + 1) % N
        else:
            while (self.selected < self.current_left):
                self.current_left -= 1
                self.current_right -= 1

            while (self.selected >= self.current_right):
                self.current_left += 1
                self.current_right += 1

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
                                   resize_type=resize_type)
        
        if(w == 0):
            w,h = Display.render_image(image_path=self.missing_image_path,
                                   x=x,
                                   y=y,
                                   render_mode=render_mode,
                                   target_width=target_width,
                                   target_height=target_height,
                                   resize_type=resize_type)
        return w,h

    def _render_cell(self, visible_index, imageTextPair):
        actual_index = (self.current_left + visible_index)%len(self.options)
        image_path = imageTextPair.get_image_path_selected_ideal(self.resized_width, self.resized_height) if actual_index == self.selected else imageTextPair.get_image_path_ideal(self.resized_width, self.resized_height)

        x_index = visible_index % self.cols
        x_offset = int(self.x_pad + (x_index) * (self.icon_width)) + self.icon_width//2

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
            img_offset = self.img_offset if self.img_offset is not None else 0
        else:
            img_offset = Theme.get_grid_multi_row_img_y_offset(text_height)
            
        bg_offset = 0
        if (self.resized_width is not None):
            # TODO not fixed values
            bg_width += Theme.get_grid_multi_row_sel_bg_resize_pad_width()
            bg_height += Theme.get_grid_multi_row_sel_bg_resize_pad_height()
            if(YRenderOption.CENTER == render_mode.y_mode):
                if(self.set_bg_offset_to_image_offset):
                    bg_offset = img_offset
                else:
                    bg_offset = 0
            elif(YRenderOption.BOTTOM == render_mode.y_mode):
                bg_offset = Theme.get_grid_multi_row_sel_bg_resize_pad_height() //2    

        if (actual_index == self.selected):
            if (self.selected_bg is not None):
                Display.render_image(self.selected_bg,
                         x_offset,
                         cell_y + bg_offset // offset_divisor,
                         render_mode,
                         target_width=int(bg_width*1.05),
                         target_height=int(bg_height*1.05))
        elif(self.unselected_bg is not None):
            Display.render_image(self.unselected_bg,
                         x_offset,
                         cell_y + bg_offset // offset_divisor,
                         render_mode,
                         target_width=int(bg_width*1.05),
                         target_height=int(bg_height*1.05))

        self._render_primary_image(image_path,
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
                y_text = int(Device.get_device().screen_height() * 310/480) + Theme.single_row_grid_text_y_offset()
            else:
                y_text = bottom_row_y - text_height + Theme.multi_row_grid_text_y_offset()
                
            Display.render_text(imageTextPair.get_primary_text(),
                                 x_offset,
                                 y_text,
                                 color,
                                 self.font_purpose,
                                 render_mode=RenderMode.BOTTOM_CENTER_ALIGNED)

    def _render(self):
        if (self.set_top_bar_text_to_selection) and len(self.options) > 0:
            Display.clear(
                self.options[self.selected].get_primary_text(), hide_top_bar_icons=True)
        elif(self.set_bottom_bar_text_to_selection and len(self.options) > 0):
            Display.clear(self.top_bar_text, bottom_bar_text=self.options[self.selected].get_primary_text())
        else:
            Display.clear(self.top_bar_text)
        self.correct_selected_for_off_list()

        if(self.rows > 1):
            visible_options: List[GridOrListEntry] = self.options[self.current_left:self.current_right]
        else:
            if self.current_left <= self.current_right:
                # Normal contiguous window
                visible_options = self.options[self.current_left:self.current_right]
            else:
                # Wrapped window: take end → wrap → beginning
                visible_options = (
                    self.options[self.current_left:] + 
                    self.options[:self.current_right]
                )

        for visible_index, imageTextPair in enumerate(visible_options):
            self._render_cell(visible_index=visible_index,imageTextPair=imageTextPair)


        # Don't display indexing for single row grids
        if (self.rows > 1):
            letter = ''
            if(self.options_are_sorted):
                letter = self.options[self.selected].get_primary_text()[0]
            Display.add_index_text(self.selected+1, len(self.options),letter=letter)
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
                self.adjust_selected(-1, skip_by_letter=False)
            elif Controller.last_input() == ControllerInput.DPAD_RIGHT:
                self.adjust_selected(1, skip_by_letter=False)
            elif Controller.last_input() == ControllerInput.L1:
                self.adjust_selected(-1 * self.cols * self.rows, skip_by_letter=False)
            elif Controller.last_input() == ControllerInput.R1:
                self.adjust_selected(self.cols * self.rows, skip_by_letter=False)
            elif Controller.last_input() == ControllerInput.L2:
                self.adjust_selected(-1 * self.cols * self.rows, skip_by_letter=True if not Theme.skip_main_menu() else Device.get_device().get_system_config().get_skip_by_letter())
            elif Controller.last_input() == ControllerInput.R2:
                self.adjust_selected(self.cols * self.rows, skip_by_letter=True if not Theme.skip_main_menu() else Device.get_device().get_system_config().get_skip_by_letter())
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

    def adjust_selected(self, amount, skip_by_letter):
        amount = self.calculate_amount_to_move_by(amount, skip_by_letter)
        self.selected += amount
        self.correct_selected_for_off_list()


    def animate_transition(self):
        animation_frames = math.floor(10 // Device.get_device().animation_divisor()) - self.animated_count*2

        if Device.get_device().get_system_config().animations_enabled() and animation_frames > 1:
            render_mode = RenderMode.MIDDLE_CENTER_ALIGNED
            animation_frames = 10
            frame_duration = 1 / 60.0  # 60 FPS
            last_frame_time = 0

            diff = (self.selected - self.prev_selected) % (len(self.options) + 1)
            rotate_left = diff > (len(self.options) + 1) // 2

            for frame in range(animation_frames):
                self._clear()

                frame_x_offset = []
                frame_widths = []
                t = frame / (animation_frames - 1)

                for i in range(len(self.prev_x_offsets)):
                    start_x_offset = self.prev_x_offsets[i]
                    start_width = self.prev_widths[i]

                    if rotate_left:
                        if i < len(self.prev_x_offsets) - 1:
                            end_x_offset = self.prev_x_offsets[i + 1]
                            end_width = self.prev_widths[i+1]
                        else:
                            # Last item exits to the right
                            end_x_offset = start_x_offset
                            end_width = start_width
                    else:
                        if i > 0:
                            end_x_offset = self.prev_x_offsets[i - 1]
                            end_width = self.prev_widths[i - 1]
                        else:
                            # First item exits to the left0+12
                            end_x_offset = start_x_offset
                            end_width = start_width

                    new_x_offset = start_x_offset + (end_x_offset - start_x_offset) * t
                    new_width = start_width + (end_width - start_width) * t
                    frame_x_offset.append(new_x_offset)         
                    frame_widths.append(new_width)

                for visible_index, imageTextPair in enumerate(self.prev_visible_options):
                    x_offset = frame_x_offset[visible_index]

                    y_image_offset = Display.get_center_of_usable_screen_height()
                    
                    self._render_image(imageTextPair.get_image_path_ideal(frame_widths[visible_index], Display.get_usable_screen_height()), 
                                            x_offset, 
                                            y_image_offset,
                                            render_mode,
                                            target_width=frame_widths[visible_index],
                                            target_height=None,
                                            resize_type=self.resize_type)

                delta_time = time.time() - last_frame_time
                if delta_time < frame_duration:
                    time.sleep(frame_duration - (delta_time))
                if(self.include_index_text):
                    letter = ''
                    if(self.options_are_sorted):
                        letter = self.options[self.selected].get_primary_text()[0]

                    Display.add_index_text(self.selected%self.options_length +1, self.options_length,
                                           letter)
                Display.present()
                last_frame_time = time.time()
        
        self.animated_count += 1
