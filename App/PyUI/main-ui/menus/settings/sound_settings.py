
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.settings.settings_menu import SettingsMenu
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

class SoundSettings(SettingsMenu):
    def __init__(self):
        super().__init__()

    def selection_made(self):
        Display.clear_text_cache()

    def toggle_button_press_sound(self, input):
        if (input == ControllerInput.A or input == ControllerInput.DPAD_LEFT or input == ControllerInput.DPAD_RIGHT):
            Device.get_device().get_system_config().set_play_button_press_sound(not Device.get_device().get_system_config().play_button_press_sound())
            Theme.button_press_sounds_changed()

    def toggle_bgm(self, input):
        if (input == ControllerInput.A or input == ControllerInput.DPAD_LEFT or input == ControllerInput.DPAD_RIGHT):
            Device.get_device().get_system_config().set_play_bgm(not Device.get_device().get_system_config().play_bgm())
            Theme.bgm_setting_changed()

    def adjust_bgm_volume(self, input):
        curr_volume = Device.get_device().get_system_config().bgm_volume()

        if (input == ControllerInput.DPAD_LEFT):
            curr_volume = max(curr_volume-1, 1)
            Device.get_device().get_system_config().set_bgm_volume(curr_volume)
            audio_system = Device.get_device().get_audio_system()
            if audio_system is not None:
                audio_system.audio_set_volume(curr_volume)
        elif(input == ControllerInput.DPAD_RIGHT):
            curr_volume = min(curr_volume+1, 10)
            Device.get_device().get_system_config().set_bgm_volume(curr_volume)
            audio_system = Device.get_device().get_audio_system()
            if audio_system is not None:
                audio_system.audio_set_volume(curr_volume)


    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []


        option_list.append(
            GridOrListEntry(
                primary_text=Language.play_button_press_sound(),
                value_text="<    " + str(Device.get_device().get_system_config().play_button_press_sound()) + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.toggle_button_press_sound
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text=Language.play_bgm(),
                value_text="<    " + str(Device.get_device().get_system_config().play_bgm()) + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.toggle_bgm
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text=Language.bgm_volume(),
                value_text="<    " + str(Device.get_device().get_system_config().bgm_volume()) + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.adjust_bgm_volume
            )
        )

        return option_list
