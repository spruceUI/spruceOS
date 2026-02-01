import math
import time
from typing import List
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.font_purpose import FontPurpose
from display.display import Display
from display.render_mode import RenderMode
from controller.controller import Controller
from display.resize_type import ResizeType
from themes.theme import Theme
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view import View
from utils.logger import PyUiLogger

class CarouselView(View):
    def __init__(self,top_bar_text, options: List[GridOrListEntry], cols : int, 
                  selected_index=0, show_grid_text=False,  
                  set_top_bar_text_to_selection=False, 
                  set_bottom_bar_text_to_selection=None, 
                  resize_type=None,
                  selected_entry_width_percent=None, 
                  shrink_further_away = None,
                  sides_hang_off_edge = None,
                  missing_image_path = None,
                  x_pad = None,
                  x_offset = None,
                  additional_y_offset = None,
                  fixed_width=None,
                  fixed_selected_width=None,
                  selected_offset=None,
                  use_selected_image_in_animation=None):
        super().__init__()
        self.resize_type = resize_type
        self.top_bar_text = top_bar_text
        self.set_top_bar_text_to_selection = set_top_bar_text_to_selection
        self.options : List[GridOrListEntry] = list(options)
        self.options_are_sorted = self.is_alphabetized(options)
        self.font_purpose = FontPurpose.GRID_ONE_ROW
        self.show_grid_text = show_grid_text
        self.selected_entry_width_percent = selected_entry_width_percent
        self.shrink_further_away = shrink_further_away
        self.sides_hang_off_edge = sides_hang_off_edge
        if(set_bottom_bar_text_to_selection is None):
            set_bottom_bar_text_to_selection = not self.set_top_bar_text_to_selection

        self.set_bottom_bar_text_to_selection = set_bottom_bar_text_to_selection

        self.options_length = len(options)
        if(self.selected_entry_width_percent is None):
            self.selected_entry_width_percent = 40
        self.fixed_width = fixed_width        

        if(x_pad is None):
            x_pad = 10
        if(x_offset is None):
            x_offset = 0
        if(additional_y_offset is None):
            additional_y_offset = 0
        if(selected_offset is None):
            selected_offset = 0
        if(fixed_selected_width is None):
            fixed_selected_width = fixed_width

        self.x_pad = x_pad
        self.x_offset = x_offset
        self.additional_y_offset = additional_y_offset
        self.selected_offset = selected_offset
        self.selected = selected_index
        self.fixed_selected_width = fixed_selected_width
        self.use_selected_image_in_animation = use_selected_image_in_animation if use_selected_image_in_animation is not None else True
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
        self.skip_next_animation = False


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

        half = self.cols // 2
        if(self.sides_hang_off_edge and not self.shrink_further_away):
            start = (self.selected - half - 1) % n
        else:
            start = (self.selected - half) % n

        visible = []
        range_amt = self.cols
        if(self.sides_hang_off_edge and not self.shrink_further_away):
            range_amt += 2

        #PyUiLogger.get_logger().info(f"Selected: {self.options[self.selected].get_primary_text()}, cols = {self.cols}")

        for i in range(range_amt):
            options_offset = (start + i + self.selected_offset) % n
            visible.append(self.options[options_offset])
            if options_offset == self.selected:
                selected_visible_index = i

            #PyUiLogger.get_logger().info(f"Visible option {i}: {self.options[options_offset].get_primary_text()}")


        return visible, selected_visible_index

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

            image_widths = left + mid + right
        else:
            k = self.cols // 2
            if(self.sides_hang_off_edge):
                secondary_width_percent = (100-self.selected_entry_width_percent) // (self.cols-2)
            else:
                secondary_width_percent = (100-self.selected_entry_width_percent) // (self.cols-1)

            mid = [self.selected_entry_width_percent]

            left = [secondary_width_percent for i in range(k)]
            right = [secondary_width_percent for i in range(k)]

            image_widths = left + mid + right
        
        if(self.sides_hang_off_edge):
            n = len(image_widths)

            first = image_widths[0]
            last = image_widths[-1]
            middle = image_widths[1:-1]

            weighted_sum = 0.5*first + sum(middle) + 0.5*last

            x = (100 - weighted_sum) / (n - 1)

            new_widths = [w + x for w in image_widths]
        else:
            total = sum(image_widths)
            target = 100 
            extra_per_item = (target - total) / len(image_widths)

            new_widths = [w + extra_per_item for w in image_widths]

        return new_widths


    def _clear(self):
        
        if self.selected < len(self.options):
            selected = self.options[self.selected]
            bg = Theme.get_bg_for_img(selected.get_image_path())
            if(bg is None):
                Display.restore_bg()
            else:
                Display.set_new_bg(bg, is_custom_theme_background=True)

        if(self.set_top_bar_text_to_selection) and len(self.options) > 0:
            Display.clear(self.options[self.selected].get_primary_text(), hide_top_bar_icons=True)
        elif(self.set_bottom_bar_text_to_selection):
            Display.clear(self.top_bar_text, bottom_bar_text=self.options[self.selected].get_primary_text())
        else:
            Display.clear("", bottom_bar_text="")

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
        self.correct_selected_for_off_list()
        self._clear()

        
        #TODO Get hard coded values for padding from +
        usable_width = Device.get_device().screen_width()
        visible_options, selected_visible_index = self.get_visible_options()

        if(self.fixed_width is None):
            image_width_percentages = self.get_width_percentages()
            #PyUiLogger.get_logger().debug(f"image_width_percentages  = {image_width_percentages}")
            widths = [int(round(percent/100 * usable_width)) for percent in image_width_percentages]
            x_offsets = [0] + [sum(widths[:i]) for i in range(1, len(widths))]
            if(self.sides_hang_off_edge and not self.shrink_further_away):
                #Add one extra that is offscreen
                x_offsets = [-x_offsets[1]] + x_offsets + [x_offsets[len(x_offsets)-1] + (x_offsets[len(x_offsets)-1] - x_offsets[len(x_offsets)-2])]
                widths = [widths[0]] + widths + [widths[len(widths)-1]]
                x_offsets = [x - widths[0]//2 for x in x_offsets]

        else:
            widths = [self.fixed_width for _ in range(self.cols)]
            widths[selected_visible_index] = self.fixed_selected_width               
            # Step 1: cumulative offsets
            x_offsets = [0] + [sum(widths[:i]) for i in range(1, len(widths))]

            # Step 2: center the middle image
            screen_center = Device.get_device().screen_width() // 2
            mid = len(x_offsets) // 2
            middle_width = widths[mid]

            middle_center_x = screen_center - (middle_width // 2)
            shift = middle_center_x - x_offsets[mid]

            # Apply shift
            x_offsets = [x + shift for x in x_offsets]

            # Step 3: fan outward from the center
            x_offsets = [
                x + (i - mid) * self.x_offset
                for i, x in enumerate(x_offsets)
            ]

        #Center the x_offset in its spot
        x_offsets = [x + w // 2 for x, w in zip(x_offsets, widths)]

        # now handle padding
        widths = [w - 2* self.x_pad for w in widths]

        if(self.fixed_width is not None):
            mid = len(x_offsets) // 2
            x_offsets = [
                x + (i - mid) * self.x_offset
                for i, x in enumerate(x_offsets)
            ]


        if(self.prev_visible_options is not None and self.selected != self.prev_selected):
            self.animate_transition()
        else:
            self.animated_count = 0
        
        iterable = list(enumerate(visible_options))

        self.render_images(iterable, x_offsets, widths, render_selected_only=False)
        self.render_images(iterable, x_offsets, widths, render_selected_only=True)

        if self.selected < len(self.options):
            selected = self.options[self.selected]
            overlay = Theme.get_overlay_for_img(selected.get_image_path())
            if(overlay is not None):
                Display.render_image(overlay,
                                     Device.get_device().screen_width()//2,
                                     Device.get_device().screen_height()//2,
                                     RenderMode.MIDDLE_CENTER_ALIGNED)

        self.prev_selected = self.selected
        self.prev_visible_options = visible_options
        self.prev_x_offsets = x_offsets
        self.prev_widths = widths
        if(self.include_index_text):
            letter = ''
            if(self.options_are_sorted):
                letter = self.options[self.selected].get_primary_text()[0]
            Display.add_index_text(self.selected%self.options_length + 1, self.options_length, 
                                   letter=letter)

        Display.present()

    def get_img_render_mode(self):
        if(self.additional_y_offset > 0):
            return RenderMode.BOTTOM_CENTER_ALIGNED

        return RenderMode.MIDDLE_CENTER_ALIGNED

    def render_images(self, iterable, x_offsets, widths, render_selected_only):
        render_mode = self.get_img_render_mode()

        for visible_index, imageTextPair in iterable:
            is_selected = imageTextPair == self.options[self.selected]
            if(render_selected_only and not is_selected):
                continue
            elif(not render_selected_only and is_selected):
                continue
            x_offset = x_offsets[visible_index]
           
            y_image_offset = Display.get_center_of_usable_screen_height() + self.additional_y_offset
            if(is_selected):
                image = imageTextPair.get_image_path_selected_ideal(widths[visible_index],Display.get_usable_screen_height())
            else:
                image = imageTextPair.get_image_path_ideal(widths[visible_index],Display.get_usable_screen_height())

            self._render_image(image, 
                                    x_offset, 
                                    y_image_offset,
                                    render_mode,
                                    target_width=widths[visible_index],
                                    target_height=Display.get_usable_screen_height(),
                                    resize_type=self.resize_type)

    def get_selected_option(self):
        if 0 <= self.selected < len(self.options):
            return self.options[self.selected]
        else:
            return None

    def get_selection(self, select_controller_inputs = [ControllerInput.A]):
        self._render()
        
        if(Controller.get_input()):
            if Controller.last_input() == ControllerInput.DPAD_LEFT:
                self.adjust_selected(-1, skip_by_letter=False)
            elif Controller.last_input() == ControllerInput.DPAD_RIGHT:
                self.adjust_selected(1, skip_by_letter=False)
            elif Controller.last_input() == ControllerInput.L1:
                if(Theme.skip_main_menu()):
                    Display.restore_bg()
                    return Selection(self.get_selected_option(),Controller.last_input(), self.selected)
                else:
                    self.skip_next_animation = True
                    self.adjust_selected(-1* self.cols, skip_by_letter=False)
            elif Controller.last_input() == ControllerInput.R1:
                if(Theme.skip_main_menu()):
                    Display.restore_bg()
                    return Selection(self.get_selected_option(),Controller.last_input(), self.selected)
                else:
                    self.skip_next_animation = True
                    self.adjust_selected(self.cols, skip_by_letter=False)
            elif Controller.last_input() == ControllerInput.L2:
                self.skip_next_animation = True
                self.adjust_selected(-1* self.cols, skip_by_letter=True if not Theme.skip_main_menu() else Device.get_device().get_system_config().get_skip_by_letter())
            elif Controller.last_input() == ControllerInput.R2:
                self.skip_next_animation = True
                self.adjust_selected(self.cols, skip_by_letter=True if not Theme.skip_main_menu() else Device.get_device().get_system_config().get_skip_by_letter())
            elif Controller.last_input() in select_controller_inputs:
                Display.restore_bg()
                return Selection(self.get_selected_option(),Controller.last_input(), self.selected)
            elif Controller.last_input() == ControllerInput.B:
                Display.restore_bg()
                return Selection(self.get_selected_option(),Controller.last_input(), self.selected)
                
        return Selection(self.get_selected_option(),None, self.selected)

    def adjust_selected(self, amount, skip_by_letter):
        amount = self.calculate_amount_to_move_by(amount, skip_by_letter)
        self.selected += amount
        self.current_left += amount
        self.current_right += amount
        self.correct_selected_for_off_list()

    def animate_transition(self):
        if(not self.skip_next_animation):
            animation_frames = math.floor(10 // Device.get_device().animation_divisor()) - self.animated_count
            if Device.get_device().get_system_config().animations_enabled() and animation_frames > 1:
                render_mode = self.get_img_render_mode()
                #frame_duration = 1 / 60.0  # 60 FPS
                #last_frame_time = 0

                diff = (self.selected - self.prev_selected) % (len(self.options) + 1)
                rotate_left = diff > (len(self.options) + 1) // 2
                x_offsets_for_animation = list(self.prev_x_offsets)
                widths_for_animation = list(self.prev_widths)
                image_list = list(self.prev_visible_options)
                new_visible_options, selected_visible_index = self.get_visible_options()
        
                if(not self.sides_hang_off_edge):
                    if rotate_left:
                        image_list.insert(0,new_visible_options[0])
                        x_offsets_for_animation.insert(0, x_offsets_for_animation[0] - (x_offsets_for_animation[1] - x_offsets_for_animation[0]))
                        widths_for_animation.insert(0, widths_for_animation[0])
                        image_list = list(reversed(image_list))
                    else:
                        image_list.append(new_visible_options[-1])
                        x_offsets_for_animation.append(x_offsets_for_animation[-1] + x_offsets_for_animation[-1] - x_offsets_for_animation[-2])
                        widths_for_animation.append(widths_for_animation[-1])

                for frame in range(animation_frames):
                    self._clear()

                    frame_x_offset = []
                    frame_widths = []
                    t = frame / (animation_frames - 1)

                    for i in range(len(x_offsets_for_animation)):
                        start_x_offset = x_offsets_for_animation[i]
                        start_width = widths_for_animation[i]

                        if rotate_left:
                            if i < len(x_offsets_for_animation) - 1:
                                end_x_offset = x_offsets_for_animation[i + 1]
                                end_width = widths_for_animation[i+1]
                            else:
                                # Last item exits to the right
                                end_x_offset = (x_offsets_for_animation[-1] - x_offsets_for_animation[-2]) + x_offsets_for_animation[-1] 
                                end_width = start_width
                        else:
                            if i > 0:
                                end_x_offset = x_offsets_for_animation[i - 1]
                                end_width = widths_for_animation[i - 1]
                            else:
                                # First item exits to the left0+12
                                end_x_offset = x_offsets_for_animation[0] - (x_offsets_for_animation[1] - x_offsets_for_animation[0])
                                end_width = start_width

                        new_x_offset = start_x_offset + (end_x_offset - start_x_offset) * t
                        new_width = start_width + (end_width - start_width) * t
                        frame_x_offset.append(int(new_x_offset))         
                        frame_widths.append(new_width)

                    if(not self.sides_hang_off_edge):
                        if rotate_left:
                            frame_x_offset = list(reversed(frame_x_offset))
                            frame_widths = list(reversed(frame_widths))

                    for visible_index, imageTextPair in enumerate(image_list):
                        x_offset = frame_x_offset[visible_index]

                        y_image_offset = Display.get_center_of_usable_screen_height() + self.additional_y_offset

                        if(imageTextPair == self.options[self.selected] and self.use_selected_image_in_animation):
                            image = imageTextPair.get_image_path_selected_ideal(frame_widths[visible_index],Display.get_usable_screen_height())
                        else:
                            image = imageTextPair.get_image_path_ideal(frame_widths[visible_index],Display.get_usable_screen_height())

                        self._render_image(image, 
                                                x_offset, 
                                                y_image_offset,
                                                render_mode,
                                                target_width=frame_widths[visible_index],
                                                target_height=Display.get_usable_screen_height(),
                                                resize_type=self.resize_type)

                    if(self.include_index_text):
                        letter = ''
                        if(self.options_are_sorted):
                            letter = self.options[self.selected].get_primary_text()[0]

                        Display.add_index_text(self.selected%self.options_length +1, self.options_length,
                                            letter=letter)

                    #curr_time = time.time()
                    #delta_time = curr_time - last_frame_time
                    #if delta_time < frame_duration:
                    #    time.sleep(frame_duration - (delta_time))
                    Display.present()
                    #last_frame_time = time.time()
            
            self.animated_count += 1
        else:
            self.skip_next_animation = False