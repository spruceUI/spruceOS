
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from devices.bluetooth.bluetooth_scanner import BluetoothScanner
from display.display import Display
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class ListOfOptionsSelectionMenu:
    def __init__(self):
        pass

    def get_selected_option_index(self, options, title):
        selected = Selection(None, None, 0)
        option_list = []
        for index, opt in enumerate(options):
            option_list.append(
                GridOrListEntry(
                    primary_text=opt,
                    value=index
                )
            )

        #convert to text and desc and show the theme desc
        #maybe preview too if theyre common
        view = ViewCreator.create_view(
            view_type=ViewType.TEXT_ONLY,
            top_bar_text=title,
            options=option_list,
            selected_index=selected.get_index())

        accepted_inputs = [ControllerInput.A, ControllerInput.B]

        while (True):
            selected = view.get_selection(accepted_inputs)
            if (ControllerInput.A == selected.get_input()):
                return selected.get_selection().get_value()
            elif (ControllerInput.B == selected.get_input()):
                return None
