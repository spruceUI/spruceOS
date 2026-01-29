from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.font_purpose import FontPurpose
from display.display import Display
from menus.language.language import Language
from controller.controller import Controller
from themes.theme import Theme
from views.selection import Selection
from views.view import View

class EmptyView(View):
    def __init__(self):
        super().__init__()

    def set_options(self, options):
        pass

    def _render(self):
        Display.clear(Language.no_entries_found())
        Display.render_text_centered(Language.no_entries_found(),Device.get_device().screen_width()//2, Device.get_device().screen_height()//2,Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)
        Display.present()
        

    def get_selection(self, select_controller_inputs = [ControllerInput.A]):
        self._render()
        if(Controller.get_input()):
            return Selection(None,Controller.last_input(), None)
        else:
            return Selection(None,None, None)
