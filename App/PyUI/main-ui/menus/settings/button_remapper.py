

from controller.controller_inputs import ControllerInput
from devices.miyoo.system_config import SystemConfig
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class ButtonRemapper:
    def __init__(self, system_config : SystemConfig):
        self.system_config = system_config
        self.button_mapping = self.system_config.get_button_mapping()
        #PyUiLogger.get_logger().info(f"Button Mapping = {self.button_mapping}")
    
    def get_mappping(self, controller_input):
        if(controller_input in self.button_mapping):
            controller_input = self.button_mapping[controller_input]
        return controller_input

    def build_remap_buttons_options(self):
        option_list = []

        for controller_input in ControllerInput:
            current_value = controller_input.name
            if(controller_input in self.button_mapping):
                current_value = self.button_mapping[controller_input].name

            option_list.append(
                    GridOrListEntry(
                            primary_text=controller_input.name,
                            value_text=current_value,
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=lambda button=controller_input : self.remap_single_button(button)
                        )
                )
        return option_list

    def remap_buttons(self):

        selected = Selection(None,None,0)
        list_view = ViewCreator.create_view(
                    view_type=ViewType.ICON_AND_DESC,
                    top_bar_text=f"Button Remapper", 
                    options=self.build_remap_buttons_options(),
                    selected_index=selected.get_index())
        while(selected is not None):    
            control_options = [ControllerInput.A]
            selected = list_view.get_selection(control_options)

            if(selected.get_input() in control_options):
                selected.get_selection().get_value()()
                list_view.set_options(self.build_remap_buttons_options())
            elif(ControllerInput.B == selected.get_input()):
                selected = None



    def remap_single_button(self, button):
        option_list = []

        for controller_input in ControllerInput:
            option_list.append(
                    GridOrListEntry(
                            primary_text=controller_input.name,
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=controller_input
                        )
                )
        
        selected = Selection(None,None,0)
        list_view = ViewCreator.create_view(
                    view_type=ViewType.TEXT_ONLY,
                    top_bar_text=f"Remapping {button.name}", 
                    options=option_list,
                    selected_index=selected.get_index())
        while(selected is not None):               
            control_options = [ControllerInput.A]
            selected = list_view.get_selection(control_options)

            if(selected.get_input() in control_options):
                PyUiLogger.get_logger().info(f"Remapping {button.name} to {selected.get_selection().get_value().name}")
                self.button_mapping[button] = selected.get_selection().get_value()
                self.system_config.set_button_mapping(self.button_mapping)
                self.system_config.save_config()
                return
            elif(ControllerInput.B == selected.get_input()):
                selected = None


