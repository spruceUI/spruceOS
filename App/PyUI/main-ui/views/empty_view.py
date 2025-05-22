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
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view import View

class EmptyView(View):
    def __init__(self):
        super().__init__()

    def set_options(self, options):
        pass

    def _render(self):
        Display.clear("No Entries Found")
        Display.render_text_centered(f"No Entries Found",Device.screen_width()//2, Device.screen_height()//2,Theme.text_color_selected(FontPurpose.LIST), purpose=FontPurpose.LIST)
        Display.present()
        

    def get_selection(self, select_controller_inputs = [ControllerInput.A]):
        self._render()
        if(Controller.get_input() and Controller.last_input() == ControllerInput.B):
            return Selection(None,ControllerInput.B, None)
        else:
            return Selection(None,None, None)
