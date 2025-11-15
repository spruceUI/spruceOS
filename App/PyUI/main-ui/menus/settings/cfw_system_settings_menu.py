
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from menus.settings.cfw_system_settings_menu_for_category import CfwSystemSettingsMenuForCategory
from utils.cfw_system_config import CfwSystemConfig
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry


class CfwSystemSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def launch_settings_for_category(self,input, category):
        if(ControllerInput.A == input):
            CfwSystemSettingsMenuForCategory(category).show_menu()


    def build_options_list(self):
        option_list = []
        
        for category in CfwSystemConfig.get_categories():
            menu_options = CfwSystemConfig.get_menu_options(category=category)
            contains_entry_for_device = False
            for name, option in menu_options.items():
                PyUiLogger.get_logger().info(f"{option}")
                devices = option.get('devices')
                supported_device = not devices or Device.get_device_name() in devices
                if(supported_device):
                    contains_entry_for_device = True
                    break

            if(contains_entry_for_device):
                option_list.append(
                        GridOrListEntry(
                                primary_text=category,
                                value_text=None,
                                image_path=None,
                                image_path_selected=None,
                                description=None,
                                icon=None,
                                value=lambda 
                                    input_value, 
                                    category=category: self.launch_settings_for_category(input_value, category)
                            )
                    )

        return option_list
