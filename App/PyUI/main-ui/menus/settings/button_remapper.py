

from controller.controller_inputs import ControllerInput
from devices.miyoo.device_user_config import DeviceUserConfig
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class ButtonRemapper:
    REQUIRED_BUTTONS = {
        ControllerInput.A,
        ControllerInput.B,
        ControllerInput.DPAD_UP,
        ControllerInput.DPAD_DOWN,
        ControllerInput.DPAD_LEFT,
        ControllerInput.DPAD_RIGHT,
    }

    def __init__(self, system_config : DeviceUserConfig):
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

    def check_required_buttons_after_mapping(self, physical_button, virtual_value):
        """
        Simulate updating a mapping and check whether any REQUIRED_BUTTONS
        would no longer be covered in the resulting virtual mapping.

        Returns:
            set: Missing required virtual buttons (empty set if safe)
        """

        # start with identity mapping for all buttons
        temp_mapping = {btn: btn for btn in ControllerInput}

        # apply existing overrides
        temp_mapping.update(self.button_mapping)

        # apply the proposed change
        temp_mapping[physical_button] = virtual_value

        # compute resulting virtual values
        mapped_values = set(temp_mapping.values())

        # check required coverage
        missing = self.REQUIRED_BUTTONS - mapped_values

        return missing

    def update_map(self, physical_button, virtual_value): 
        if physical_button == virtual_value: 
            self.button_mapping.pop(physical_button, None) 
        else: 
            self.button_mapping[physical_button] = virtual_value

    def get_physical_key_for_value(self, virtual_value, target_value):
        PyUiLogger.get_logger().info(f"    Looking up physical key for {virtual_value.name}")
        
        if(self.get_mappping(target_value) == virtual_value):
            PyUiLogger.get_logger().info(f"    target of {target_value.name} maps to {virtual_value.name} so returning it")
            return target_value
        
        if(virtual_value not in self.button_mapping):
            PyUiLogger.get_logger().info(f"    {virtual_value.name} is unmapped so returning itself")
            return virtual_value # key maps to itself

        
        for c in ControllerInput:
            if(c in self.button_mapping and self.button_mapping[c] == virtual_value):
                PyUiLogger.get_logger().info(f"    {virtual_value.name} is mapped to {c.name}")
                return c
        
        return None

    def update_mapping(self,physical_button,virtual_value):
        PyUiLogger.get_logger().info(f"Requesting mapping of {physical_button.name} to {virtual_value.name}")

        missing = self.check_required_buttons_after_mapping(physical_button, virtual_value)
        if not missing:
            PyUiLogger.get_logger().info(f"    Update is allowed, no required buttons will be unmapped")
            #Safe to update
            self.update_map(physical_button,virtual_value)
        else:
            # Get what the physical button currently maps to
            current_virtual_value = self.get_mappping(physical_button)
            current_phyical_button_for_virtual_value = self.get_physical_key_for_value(virtual_value, current_virtual_value)
            PyUiLogger.get_logger().info(f"    {physical_button.name} is currently mapped to {current_virtual_value.name}")
            PyUiLogger.get_logger().info(f"    {current_phyical_button_for_virtual_value.name} is currently mapped to {current_virtual_value.name}")
            PyUiLogger.get_logger().info(f"    Setting {physical_button.name} to {virtual_value.name}")
            PyUiLogger.get_logger().info(f"    Setting {current_phyical_button_for_virtual_value.name} to {current_virtual_value.name}")
            # Swap the two physical buttons
            self.update_map(physical_button,virtual_value)
            self.update_map(current_phyical_button_for_virtual_value,current_virtual_value)

        self.system_config.set_button_mapping(self.button_mapping)
        self.system_config.save_config()

    def remap_single_button(self, physical_button):
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
                    top_bar_text=f"Remapping {physical_button.name}", 
                    options=option_list,
                    selected_index=selected.get_index())
        while(selected is not None):               
            control_options = [ControllerInput.A]
            selected = list_view.get_selection(control_options)

            if(selected.get_input() in control_options):
                virtual_value = selected.get_selection().get_value()
                self.update_mapping(physical_button,virtual_value)
                return
            elif(ControllerInput.B == selected.get_input()):
                selected = None


