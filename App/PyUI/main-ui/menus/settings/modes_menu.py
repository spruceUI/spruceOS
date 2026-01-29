

from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from utils.user_prompt import UserPrompt
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

class ModesMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def prompt_games_only_mode(self,input):
        if(ControllerInput.A == input):
            if UserPrompt.prompt_yes_no("Game Selection Only Mode",
                                        ["Would you like to enter game selection only mode?", 
                                         "Boot straight into the game selection screen", 
                                         "To exit enter the Konami Code", 
                                         "↑↑↓↓←→←→BA,START,SELECT"]):
                Device.get_device().get_system_config().set_game_selection_only_mode_enabled(True)
                Device.get_device().exit_pyui()
            else:
                return

    def prompt_simple_mode(self,input):
        if(ControllerInput.A == input):
            if UserPrompt.prompt_yes_no("Simple Mode",
                                        ["Would you like to enter simple mode?", 
                                         "It has restricted access to settings", 
                                         "To exit enter the Konami Code", 
                                         "↑↑↓↓←→←→BA,START,SELECT"]):
                Device.get_device().get_system_config().set_simple_mode_enabled(True)
                Device.get_device().exit_pyui()
            else:
                return

    def build_options_list(self):
        option_list = []
        

        option_list.append(
            GridOrListEntry(
                primary_text=Language.enter_game_selection_only_mode(),
                value_text=None,
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.prompt_games_only_mode
                )
            )
        option_list.append(
            GridOrListEntry(
                primary_text=Language.enter_simple_mode(),
                value_text=None,
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.prompt_simple_mode
                )
            )


        return option_list
