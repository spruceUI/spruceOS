
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

class GameSelectSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
    
    def adjust_skip_by_letter(self, input: ControllerInput):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input):
            system_config = Device.get_device().get_system_config()
            system_config.set_skip_by_letter(not system_config.get_skip_by_letter())

    def build_options_list(self):
        option_list = []

        option_list.append(
                GridOrListEntry(
                        primary_text=Language.l2_r2_skip_by_letter_for_daijisho_themes(),
                        value_text="<    " + str(Device.get_device().get_system_config().get_skip_by_letter()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.adjust_skip_by_letter
                    )
            )

        return option_list
