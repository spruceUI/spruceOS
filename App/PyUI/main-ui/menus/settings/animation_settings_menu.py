
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

class AnimationSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def build_options_list(self):
        option_list = []
        
        option_list.append(
            self.build_enabled_disabled_entry(
                primary_text=Language.animations_enabled(),
                get_value_func=Device.get_device().get_system_config().animations_enabled,
                set_value_func=Device.get_device().get_system_config().set_animations_enabled,
            )
        )

        option_list.append(
            self.build_defined_list_entry(
                primary_text=Language.animation_speed(),
                all_options=[0.5, 1, 1.5, 2, 2.5, 3],
                get_value_func=Device.get_device().animation_divisor,
                set_value_func=Device.get_device().get_system_config().set_animation_speed,
            )
        )
       

        return option_list
