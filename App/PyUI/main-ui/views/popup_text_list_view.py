
from typing import List
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from display.render_mode import RenderMode
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.text_list_view import TextListView


class PopupTextListView(TextListView):
    def __init__(self, options: List[GridOrListEntry], 
                 selected_index : int, show_icons : bool, image_render_mode: RenderMode, selected_bg = None):
        super().__init__(top_bar_text=Display.get_current_top_bar_title(),
                         options=options,
                         selected_index=selected_index,
                         show_icons=show_icons,
                         image_render_mode=image_render_mode,
                         selected_bg=selected_bg,
                         usable_height=int(Display.get_image_dimensions(Theme.menu_popup_bg_large())[1]),
                         allow_scrolling=False)

        self.clear_display_each_render_cycle = False
        self.include_index_text = False


        self.view_x = int(Theme.pop_menu_x_offset() * Device.get_device().screen_width())
        self.view_y = int(Theme.pop_menu_y_offset() * Device.get_device().screen_height())
        if(Theme.pop_menu_add_top_bar_height_to_y_offset()):
            self.view_y += Display.get_top_bar_height()
        self.popup_width, self.popup_height = Display.get_image_dimensions(Theme.menu_popup_bg_large())

        self.starting_x_offset = self.view_x + Theme.pop_menu_text_padding()
        self.base_y_offset = self.view_y
        Device.get_device().screen_width()//4
        Display.render_image(
            image_path=Theme.menu_popup_bg_large(),
            x=self.view_x,
            y=self.view_y,
            render_mode=RenderMode.TOP_LEFT_ALIGNED
        )
        Display.present()
        Display.lock_current_image()

    def view_finished(self):
        Display.unlock_current_image()

    def touch_point_is_inside_popup(self, point):
        if point is None:
            return False
        x, y = point
        return (
            self.view_x <= x < self.view_x + self.popup_width
            and self.view_y <= y < self.view_y + self.popup_height
        )

    def touch_index_at(self, point):
        if not self.touch_point_is_inside_popup(point):
            return None
        return super().touch_index_at(point)

    def touch_follows_finger_from_anywhere(self, point):
        return self.touch_point_is_inside_popup(point)

    def touch_starts_scroll(self, point):
        if point is None:
            return False
        if point[0] >= self.view_x + self.popup_width:
            return True
        return self.touch_index_at(point) is not None

    def touch_uses_dpad_swipe(self, point):
        if point is None:
            return False
        x, y = point
        return (
            x >= self.view_x + self.popup_width
            and self.view_y <= y < self.view_y + self.popup_height
        )

    def touch_swipe_direction(self, dx, dy):
        if abs(dx) >= abs(dy):
            return super().touch_swipe_direction(dx, dy)
        return ControllerInput.DPAD_DOWN if dy > 0 else ControllerInput.DPAD_UP
