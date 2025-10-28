
from controller.controller_inputs import ControllerInput
from menus.settings import settings_menu
from menus.settings.cfw_system_settings_menu_for_category import CfwSystemSettingsMenuForCategory
from utils.cfw_system_config import CfwSystemConfig
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
