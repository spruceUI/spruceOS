
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from themes.theme import Theme


class OnScreenKeyboard:
    touch_tap_activates_item = True

    def __init__(self,):
        self.normal_keys = [
            ["`", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "="],       
            ["~", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "+"],      
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "\\"],      
            ["⇪", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "←"],                 
            ["↑", " ", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/","↵"], 
            [" ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " "] 
        ]

        self.shifted_keys = [
            ["`", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "="],
            ["~", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "+"], 
            ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "{", "}", "|"],
            ["⇪", "A", "S", "D", "F", "G", "H", "J", "K", "L", ":", '"', "←"],
            ["↑"," ", "Z", "X", "C", "V", "B", "N", "M", "<", ">", "?","↵"],  
            [" ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " "] 
        ]

    def get_input(self, title_text, starting_text=""):
        previous_touch_view = Controller.touch_navigation_view
        Controller.touch_navigation_view = self
        try:
            return self._get_input(title_text, starting_text)
        finally:
            if Controller.touch_navigation_view is self:
                Controller.touch_navigation_view = previous_touch_view

    def _get_input(self, title_text, starting_text=""):
        from display.display import Display
        self.shifted = False
        self.caps = False
        running = True  
        self.selected_row_index = 0
        self.selected_key_index = 0
        self.entered_text = starting_text
        key_w = Device.get_device().screen_width() // 16 #13 keys, set to 16 for spacing
        key_w_offset = Device.get_device().screen_width() // 13
        key_h = key_w

        while running:
            Display.clear("Keyboard")
            Display.render_image(
                image_path = Theme.keyboard_bg(),
                x = 0,
                y = Display.get_top_bar_height(), 
                render_mode = RenderMode.TOP_LEFT_ALIGNED, 
                target_width=Device.get_device().screen_width(), 
                target_height=Device.get_device().screen_height())

            next_y = Display.get_top_bar_height()
            entry_bar_text_x_offset = 10 #TODO get somewhere better
            if(title_text is not None):
                title_w, title_h = Display.render_text(text=title_text,
                    x = entry_bar_text_x_offset,
                    y = next_y, 
                    purpose = FontPurpose.ON_SCREEN_KEYBOARD, 
                    color=Theme.text_color_selected(FontPurpose.ON_SCREEN_KEYBOARD),
                    render_mode = RenderMode.TOP_LEFT_ALIGNED)
                next_y += title_h

            entry_bar_w, entry_bar_h = Display.render_image(
                image_path = Theme.keyboard_entry_bg(),
                x = 0,
                y = next_y, 
                render_mode = RenderMode.TOP_LEFT_ALIGNED, 
                target_width=None, 
                target_height=key_h)

            if(self.entered_text):
                Display.render_text(text=self.entered_text,
                    x = entry_bar_text_x_offset,
                    y = next_y, 
                    purpose = FontPurpose.ON_SCREEN_KEYBOARD, 
                    color=Theme.text_color_selected(FontPurpose.ON_SCREEN_KEYBOARD),
                    render_mode = RenderMode.TOP_LEFT_ALIGNED)

            keys = self.shifted_keys if self.shifted or self.caps else self.normal_keys
            x_pad = 10
            next_y += entry_bar_h
            self.touch_key_width = key_w
            self.touch_key_height = key_h
            self.touch_key_x_offset = key_w_offset
            self.touch_key_x_pad = x_pad
            self.touch_key_y = next_y
            
            for row_index, key_row in enumerate(keys):
                y = next_y
                for key_index, key in enumerate(key_row):
                    x = x_pad + key_w_offset * key_index
                    
                    selected = False
                    if ((row_index == self.selected_row_index and key_index == self.selected_key_index) or
                        ("⇪" == key and self.caps) or
                        ("↑" == key and self.shifted)
                        ):
                        color = Theme.text_color_selected(FontPurpose.ON_SCREEN_KEYBOARD)
                        selected = True
                        Display.render_image(
                            image_path = Theme.key_selected_bg() if selected else Theme.key_bg(),
                            x = x,
                            y = y, 
                            render_mode = RenderMode.TOP_LEFT_ALIGNED, 
                            target_width=key_w, 
                            target_height=key_h)

                    else:
                        color = Theme.text_color(FontPurpose.ON_SCREEN_KEYBOARD)


                    Display.render_text(text=key,
                                            x = x + key_w //2,
                                            y = y + key_h //2, 
                                            purpose = FontPurpose.ON_SCREEN_KEYBOARD, 
                                            color=color,
                                            render_mode = RenderMode.MIDDLE_CENTER_ALIGNED)
                next_y += key_h
                
            Display.present()
            if(Controller.get_input()):
                if Controller.last_input() == ControllerInput.DPAD_UP:
                    if self.selected_row_index > 0:
                        self.selected_row_index -=1
                    else:
                        self.selected_row_index = len(self.normal_keys)-1
                elif Controller.last_input() == ControllerInput.DPAD_DOWN:
                    if self.selected_row_index < len(self.normal_keys)-1:
                        self.selected_row_index +=1
                    else:
                        self.selected_row_index = 0
                if Controller.last_input() == ControllerInput.DPAD_LEFT:
                    if self.selected_key_index > 0:
                        self.selected_key_index -=1
                    else:
                        self.selected_key_index = len(self.normal_keys[0])-1
                elif Controller.last_input() == ControllerInput.DPAD_RIGHT:
                    if self.selected_key_index < len(self.normal_keys[0])-1:
                        self.selected_key_index +=1
                    else:
                        self.selected_key_index = 0
                elif Controller.last_input() == ControllerInput.L1:
                    self.shifted = not self.shifted
                elif Controller.last_input() == ControllerInput.R1:
                    self.caps = not self.caps
                    self.shifted = False
                elif Controller.last_input() == ControllerInput.B:
                    if self.entered_text:
                        self.entered_text = self.entered_text[:-1]
                    else:
                        return None
                elif Controller.last_input() == ControllerInput.START:
                    return self.entered_text
                elif Controller.last_input() == ControllerInput.A:
                    selected_key = keys[self.selected_row_index][self.selected_key_index]
                    if self._activate_key(selected_key):
                        return self.entered_text
                elif Controller.last_input() == ControllerInput.TOUCH_TAP:
                    key_position = self.touch_key_position_at(Controller.take_touch_point())
                    if key_position is not None:
                        self.selected_row_index, self.selected_key_index = key_position
                        selected_key = keys[self.selected_row_index][self.selected_key_index]
                        if self._activate_key(selected_key):
                            return self.entered_text
                elif Controller.last_input() == ControllerInput.TOUCH_DRAG:
                    key_position = self.touch_key_position_at(Controller.take_touch_point())
                    if key_position is not None:
                        self.selected_row_index, self.selected_key_index = key_position

    @property
    def selected(self):
        return self.selected_row_index * len(self.normal_keys[0]) + self.selected_key_index

    def touch_index_at(self, point):
        key_position = self.touch_key_position_at(point)
        if key_position is None:
            return None
        row, column = key_position
        return row * len(self.normal_keys[0]) + column

    def touch_drag_index_at(self, point):
        return self.touch_index_at(point)

    def touch_follows_finger_from_anywhere(self, point):
        return self.touch_index_at(point) is not None

    def touch_uses_dpad_swipe(self, point):
        return self.touch_index_at(point) is None

    def touch_tap_input(self, point):
        if (
            point is not None
            and hasattr(self, "touch_key_y")
            and point[1] >= self.touch_key_y
            + (len(self.normal_keys) - 1) * self.touch_key_height
        ):
            return ControllerInput.A
        return None

    @staticmethod
    def touch_swipe_sensitivity():
        return 2

    @staticmethod
    def touch_swipe_direction(dx, dy):
        if abs(dx) >= abs(dy):
            return ControllerInput.DPAD_RIGHT if dx > 0 else ControllerInput.DPAD_LEFT
        return ControllerInput.DPAD_DOWN if dy > 0 else ControllerInput.DPAD_UP

    def touch_key_position_at(self, point):
        if point is None or not hasattr(self, "touch_key_y"):
            return None

        x, y = point
        column = (x - self.touch_key_x_pad) // self.touch_key_x_offset
        row = (y - self.touch_key_y) // self.touch_key_height
        if (
            x < self.touch_key_x_pad
            or column < 0
            or column >= len(self.normal_keys[0])
            or row < 0
            or row >= len(self.normal_keys) - 1
            or x >= self.touch_key_x_pad + self.touch_key_x_offset * len(self.normal_keys[0])
        ):
            return None
        return int(row), int(column)

    def _activate_key(self, selected_key):
        if selected_key == "⇪":
            self.caps = not self.caps
            self.shifted = False
        elif selected_key == "↑":
            self.shifted = not self.shifted
        elif selected_key == "←":
            self.entered_text = self.entered_text[:-1] if self.entered_text else self.entered_text
        elif selected_key == "↵":
            return True
        else:
            self.entered_text += selected_key
            self.shifted = False
        return False
