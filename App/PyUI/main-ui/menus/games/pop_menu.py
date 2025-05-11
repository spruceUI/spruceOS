
from typing import List
from controller.controller import Controller
from devices.device import Device
from display.display import Display
from display.render_mode import RenderMode
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.text_list_view import TextListView


class PopupMenu(TextListView):
    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme,
                 options: List[GridOrListEntry], 
                 selected_index : int, show_icons : bool, image_render_mode: RenderMode, selected_bg = None):
        super().__init__(display=display,
                        controller=controller,
                         device=device,
                         theme=theme,
                         top_bar_text="",
                         options=options,
                         selected_index=selected_index,
                         show_icons=show_icons,
                         image_render_mode=image_render_mode,
                         selected_bg=selected_bg)

        self.display : Display= display
        self.controller : Controller = controller
        self.device : Device= device
        self.theme : Theme= theme
        self.clear_display_each_render_cycle = False
        self.starting_x_offset = device.screen_width//4 + 20 #TODO get 20 from somewhere
        self.base_y_offset = device.screen_height//4
        self.device.screen_width//4
        self.display.render_box(
            color=(0,0,0), 
            x=device.screen_width//4, 
            y=device.screen_height//4, 
            w=device.screen_width//4 * 2, 
            h=device.screen_height//4 * 2)

