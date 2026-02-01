
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from utils.consts import COLLECTIONS, FAVORITES, GAME_SELECT, GAME_SWITCHER, RECENTS
from views.grid_or_list_entry import GridOrListEntry


class GameArtDisplaySettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def toggle_game_screenshot_preference(self, input, screen):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input):
            Device.get_device().get_system_config().set_use_savestate_screenshots(screen,
                not Device.get_device().get_system_config().use_savestate_screenshots(screen))

    def build_options_list(self):
        option_list = []
        
        for screen_type in [COLLECTIONS,FAVORITES,GAME_SELECT,RECENTS,GAME_SWITCHER]:
            option_list.append(
                    GridOrListEntry(
                            primary_text=screen_type,
                            value_text="<    " + ("Screenshot" if Device.get_device().get_system_config().use_savestate_screenshots(screen_type) else "Boxart") + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=lambda input_value, screen=screen_type: self.toggle_game_screenshot_preference(input_value, screen)
                        )
                )

        return option_list
