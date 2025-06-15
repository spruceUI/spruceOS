import time
from typing import List
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.font_purpose import FontPurpose
from display.display import Display
from display.render_mode import RenderMode
import sdl2
from controller.controller import Controller
from themes.theme import Theme
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view import View

class CarouselView(View):
    def __init__(self,top_bar_text, options: List[GridOrListEntry], cols : int, 
                  selected_index=0, show_grid_text=False,  
                  set_top_bar_text_to_selection=False, 
                  resize_type=None,
                  selected_entry_width_percent=None, 
                  shrink_further_away = None,
                  sides_hang_off_edge = None,
                  missing_image_path = None):
        super().__init__()
        self.resize_type = resize_type
        self.top_bar_text = top_bar_text
        self.set_top_bar_text_to_selection = set_top_bar_text_to_selection
        self.options : List[GridOrListEntry] = list(options)
        self.font_purpose = FontPurpose.GRID_ONE_ROW
        self.show_grid_text = show_grid_text
        self.selected_entry_width_percent = selected_entry_width_percent
        self.shrink_further_away = shrink_further_away
        self.sides_hang_off_edge = sides_hang_off_edge

        self.options_length = len(options)
        if(self.selected_entry_width_percent is None):
            self.selected_entry_width_percent = 40

        self.selected = selected_index
        if(cols < 3):
            cols = 3

        while(len(self.options) <= cols*2):
            self.options += self.options
                       
        cols = min(cols, len(self.options))
        if(cols %2 == 0):
            cols +=1 
        
        cols = min(cols, len(self.options))
        
        self.cols = cols
        self.current_left = len(self.options)-(cols-1)//2
        self.current_right = (cols-1)//2
        self.correct_selected_for_off_list()
        self.prev_visible_options = None
        self.animated_count = 0
        self.include_index_text = True
        self.missing_image_path = missing_image_path

    def set_options(self, options):
        #Carousel breaks but the options shouldn't change the view
        pass

    def correct_selected_for_off_list(self):
        if(self.selected < 0):
            self.selected = len(self.options) + self.selected

        if(self.current_left < 0):
            self.current_left = len(self.options) + self.current_left

        if(self.current_right < 0):
            self.current_right = len(self.options) + self.current_right

        if(self.selected >= len(self.options)):
            self.selected = self.selected%len(self.options)

        if(self.current_left >= len(self.options)):
            self.current_left = self.current_left%len(self.options)

        if(self.current_right >= len(self.options)):
            self.current_right =  self.current_right%len(self.options)

    def get_visible_options(self):
        n = len(self.options)
        # Normalize into [0, n)
        left = (self.current_left-1) % n
        right = (self.current_right+1) % n

        visible = []
        visible_indexes = []

        i = left
        while True:
            visible.append(self.options[i])
            visible_indexes.append(i)
            # stop as soon as we've just appended the inclusive `right`
            if i == right:
                break
            i = (i + 1) % n  # wrap around

        return visible


    def get_width_percentages(self) -> List[float]:
        if(self.shrink_further_away):
            mid_size = self.selected_entry_width_percent
            scale_size = (100.0 - mid_size) //2

            # half‑width
            k = self.cols // 2

            # the total “raw weight” on one side is 2^0 + 2^1 + … + 2^(k−1) = 2^k − 1
            total_raw = 2**k - 1

            # 3) we want the left sum to be exactly 25, so scale factor:
            scale = scale_size / total_raw

            # 4) left side doubles: 2^0,2^1,…,2^(k−1)
            left = [(2**i) * scale for i in range(k)]

            # 2) middle is 50
            mid = [mid_size]

            # 5) right side halves from the middle: use the reverse‐doubling sequence
            #    2^(k−1),2^(k−2),…,2^0, scaled to sum to 25
            right = [(2**(k - 1 - i)) * scale for i in range(k)]

            return left + mid + right
        else:
            k = self.cols // 2
            if(self.sides_hang_off_edge):
                secondary_width_percent = (100-self.selected_entry_width_percent) // (self.cols-2)
            else:
                secondary_width_percent = (100-self.selected_entry_width_percent) // (self.cols-1)

            mid = [self.selected_entry_width_percent]

            left = [secondary_width_percent for i in range(k)]
            right = [secondary_width_percent for i in range(k)]

            return left + mid + right


    def _clear(self):
        if(self.set_top_bar_text_to_selection) and len(self.options) > 0:
            Display.clear(self.options[self.selected].get_primary_text(), hide_top_bar_icons=True)
        else:
            Display.clear(self.top_bar_text, bottom_bar_text=self.options[self.selected].get_primary_text())

    def _render_image(self,
                      image_path: str, 
                      x: int, 
                      y: int, 
                      render_mode, 
                      target_width, 
                      target_height,
                      resize_type):
        width, height = Display.render_image(image_path=image_path, 
                            x=x, 
                            y=y,
                            render_mode=render_mode,
                            target_width=target_width,
                            target_height=target_height,
                            resize_type=resize_type)
        if(0 == width and 0 == height):
            Display.render_image(image_path=self.missing_image_path, 
                                x=x, 
                                y=y,
                                render_mode=render_mode,
                                target_width=target_width,
                                target_height=target_height,
                                resize_type=resize_type)
    def _render(self):
        self._clear()
        self.correct_selected_for_off_list()

        
        #TODO Get hard coded values for padding from theme
        x_pad = 10
        usable_width = Device.screen_width()
        image_width_percentages = self.get_width_percentages()

        widths = [int(round(percent/100 * usable_width)) for percent in image_width_percentages]
        # x_offset[0] = 0; for i>0, sum of widths[0] through widths[i-1]
        x_offsets = [0] + [sum(widths[:i]) for i in range(1, len(widths))]

        #Add one extra that is offscreen
        x_offsets = [-x_offsets[1]] + x_offsets + [x_offsets[len(x_offsets)-1] + (x_offsets[len(x_offsets)-1] - x_offsets[len(x_offsets)-2])]
        widths = [widths[0]] + widths + [widths[len(widths)-1]]

        if(self.sides_hang_off_edge):
            x_offsets = [x - widths[0]//2 for x in x_offsets]

        #Center the x_offset in its spot
        x_offsets = [x + w // 2 for x, w in zip(x_offsets, widths)]

        # now handle padding
        widths = [w - 2*x_pad for w in widths]
        
        visible_options: List[GridOrListEntry] = self.get_visible_options()

        if(self.prev_visible_options is not None and self.selected != self.prev_selected):
            self.animate_transition()
        else:
            self.animated_count = 0
        
        render_mode = RenderMode.MIDDLE_CENTER_ALIGNED
        for visible_index, imageTextPair in enumerate(visible_options):
            x_offset = x_offsets[visible_index]

            y_image_offset = Display.get_center_of_usable_screen_height()
            
            self._render_image(imageTextPair.get_image_path(), 
                                    x_offset, 
                                    y_image_offset,
                                    render_mode,
                                    target_width=widths[visible_index],
                                    target_height=Display.get_usable_screen_height(),
                                    resize_type=self.resize_type)
        self.prev_selected = self.selected
        self.prev_visible_options = visible_options
        self.prev_x_offsets = x_offsets
        self.prev_widths = widths
        if(self.include_index_text):
            Display.add_index_text(self.selected%self.options_length + 1, self.options_length, 
                                   letter=self.options[self.selected].get_primary_text()[0])

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
                self.current_left-=1
                self.current_right-=1
                self.correct_selected_for_off_list()
            elif Controller.last_input() == ControllerInput.DPAD_RIGHT:
                self.selected+=1
                self.current_left+=1
                self.current_right+=1
                self.correct_selected_for_off_list()
            elif Controller.last_input() in select_controller_inputs:
                return Selection(self.get_selected_option(),Controller.last_input(), self.selected)
            elif Controller.last_input() == ControllerInput.B:
                return Selection(self.get_selected_option(),Controller.last_input(), self.selected)
                
        return Selection(self.get_selected_option(),None, self.selected)


    def animate_transition(self):
        animation_frames = 10 - self.animated_count*2


        if PyUiConfig.animations_enabled() and animation_frames > 1:
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
                    
                    self._render_image(imageTextPair.get_image_path(), 
                                            x_offset, 
                                            y_image_offset,
                                            render_mode,
                                            target_width=frame_widths[visible_index],
                                            target_height=Display.get_usable_screen_height(),
                                            resize_type=self.resize_type)

                if time.time() - last_frame_time < frame_duration:
                    time.sleep(frame_duration - (time.time() - last_frame_time))
                if(self.include_index_text):
                    Display.add_index_text(self.selected%self.options_length +1, self.options_length,
                                           letter=self.options[self.selected].get_primary_text()[0])
                Display.present()
                last_frame_time = time.time()
        
        self.animated_count += 1
