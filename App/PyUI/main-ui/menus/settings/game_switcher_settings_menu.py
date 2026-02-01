
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.resize_type import ResizeType, get_next_resize_type
from menus.settings import settings_menu
from themes.theme import Theme
from utils.consts import GAME_SWITCHER
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.view_type import ViewType, get_next_view_type


from menus.language.language import Language

class GameSwitcherSettingsMenu(settings_menu.SettingsMenu):
    SETTINGS_NAME = "Game Switcher Settings"

    def __init__(self):
        super().__init__()

    def toggle_game_switcher(self, input):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input):
            Device.get_device().get_system_config().set_game_switcher_enabled(not Device.get_device().get_system_config().game_switcher_enabled())

    def toggle_use_custom_gameswitcher_path(self, input):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input):
            Device.get_device().get_system_config().set_use_custom_gameswitcher_path(not Device.get_device().get_system_config().use_custom_gameswitcher_path())

    def toggle_game_switcher_screenshot_preference(self, input, screen):
        if(ControllerInput.DPAD_LEFT == input or ControllerInput.DPAD_RIGHT == input):
            Device.get_device().get_system_config().set_use_savestate_screenshots(screen,
                not Device.get_device().get_system_config().use_savestate_screenshots(screen))

    def update_game_switcher_game_count(self, input):
        if(ControllerInput.DPAD_LEFT == input):
            Device.get_device().get_system_config().set_game_switcher_game_count(Device.get_device().get_system_config().game_switcher_game_count() - 1)
        elif(ControllerInput.DPAD_RIGHT == input):
            Device.get_device().get_system_config().set_game_switcher_game_count(Device.get_device().get_system_config().game_switcher_game_count() + 1)

    def build_options_list(self):
        option_list = []
        
        option_list.append(
                GridOrListEntry(
                        primary_text=Language.hold_menu_for_gameswitcher(),
                        value_text="<    " + str(Device.get_device().get_system_config().game_switcher_enabled()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.toggle_game_switcher
                    )
            )

        option_list.append(
                GridOrListEntry(
                        primary_text=Language.prefer_savestate_screenshots(),
                        value_text="<    " + str(Device.get_device().get_system_config().use_savestate_screenshots(GAME_SWITCHER)) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=lambda input_value, screen=GAME_SWITCHER: self.toggle_game_switcher_screenshot_preference(input_value, screen)
                    )
            )

        option_list.append(
                GridOrListEntry(
                        primary_text=Language.game_count(),
                        value_text="<    " + str(Device.get_device().get_system_config().game_switcher_game_count()) + "    >",
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.update_game_switcher_game_count
                    )
            )
            

                    
        option_list.append(
            self.build_enum_entry(
                primary_text=Language.view_type(),
                get_value_func=Theme.get_view_type_for_game_switcher,
                set_value_func=Theme.set_view_type_for_game_switcher,
                get_next_enum_type=get_next_view_type
            )
        )

        if(ViewType.FULLSCREEN_GRID == Theme.get_view_type_for_game_switcher()):
            option_list.append(
                self.build_enum_entry(
                    primary_text=Language.full_screen_resize_type(),
                    get_value_func=Theme.get_resize_type_for_game_switcher,
                    set_value_func=Theme.set_resize_type_for_game_switcher,
                    get_next_enum_type=get_next_resize_type
                )
            )

            if(ResizeType.ZOOM == Theme.get_resize_type_for_game_switcher()):
                option_list.append(
                    self.build_enabled_disabled_entry(
                        primary_text=Language.true_full_screen(),
                        get_value_func=Theme.true_full_screen_game_switcher,
                        set_value_func=Theme.set_true_full_screen_game_switcher,
                    )
                )

            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text=Language.topbar_gamename(),
                    get_value_func=Theme.get_set_top_bar_text_to_game_selection,
                    set_value_func=Theme.set_set_top_bar_text_to_game_selection,
                )
            )


        if(ViewType.CAROUSEL == Theme.get_view_type_for_game_switcher()):
            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text=Language.topbar_gamename(),
                    get_value_func=Theme.get_set_top_bar_text_to_game_selection,
                    set_value_func=Theme.set_set_top_bar_text_to_game_selection,
                )
            )


        if(PyUiConfig.get_gameswitcher_path() is not None ):
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.use_recents_for_gameswitcher(),
                            value_text="<    " + ("No" if Device.get_device().get_system_config().use_custom_gameswitcher_path() else "Yes") + "    >",
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.toggle_use_custom_gameswitcher_path
                        )
                )
            
        menu_options = self.build_options_list_from_config_menu_options(GameSwitcherSettingsMenu.SETTINGS_NAME)
        option_list.extend(menu_options)

        return option_list
