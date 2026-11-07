
from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

class ControllerSettingsMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def calibrate_sticks(self,input):
        if(ControllerInput.A == input):
            Device.get_device().calibrate_sticks()

    def remap_buttons(self,input):
        if(ControllerInput.A == input):
            Device.get_device().remap_buttons()

    def build_options_list(self):
        option_list = []
        
        if(Device.get_device().supports_analog_calibration()):
            option_list.append(
                    GridOrListEntry(
                            primary_text=Language.calibrate_analog_sticks(),
                            value_text=None,
                            image_path=None,
                            image_path_selected=None,
                            description=None,
                            icon=None,
                            value=self.calibrate_sticks
                        )
                )

        option_list.append(
                GridOrListEntry(
                        primary_text=Language.remap_buttons(),
                        image_path=None,
                        image_path_selected=None,
                        description=None,
                        icon=None,
                        value=self.remap_buttons
                )
        )

        option_list.append(
            self.build_numeric_entry(
                primary_text=Language.input_rate_limit_ms(),
                get_value_func=Device.get_device().get_system_config().get_input_rate_limit_ms,
                set_value_func=Device.get_device().get_system_config().set_input_rate_limit_ms,
            )
        )

        device = Device.get_device()
        if device.supports_touch():
            system_config = device.get_system_config()
            option_list.extend((
                self.build_numeric_entry(
                    primary_text=Language.label("touchLongPressSeconds", "Touch Long Press (s)"),
                    get_value_func=system_config.get_touch_long_press_seconds,
                    set_value_func=system_config.set_touch_long_press_seconds,
                    min=0.2,
                    max=2.0,
                    step=0.1,
                ),
                self.build_numeric_entry(
                    primary_text=Language.label("touchDoubleTapSeconds", "Touch Double Tap (s)"),
                    get_value_func=system_config.get_touch_double_tap_seconds,
                    set_value_func=system_config.set_touch_double_tap_seconds,
                    min=0.10,
                    max=1.0,
                    step=0.05,
                ),
                self.build_numeric_entry(
                    primary_text=Language.label("touchEdgeScrollIntervalSeconds", "Touch Edge Scroll Interval (s)"),
                    get_value_func=system_config.get_touch_edge_scroll_interval_seconds,
                    set_value_func=system_config.set_touch_edge_scroll_interval_seconds,
                    min=0.10,
                    max=1.0,
                    step=0.05,
                ),
                self.build_numeric_entry(
                    primary_text=Language.label("touchEdgeScrollMarginRatio", "Touch Edge Scroll Margin Ratio"),
                    get_value_func=system_config.get_touch_edge_scroll_margin_ratio,
                    set_value_func=system_config.set_touch_edge_scroll_margin_ratio,
                    min=0.05,
                    max=0.25,
                    step=0.01,
                ),
            ))

        option_list.extend(
            self.build_options_list_from_related_config_categories(Language.controller_settings())
        )
        return option_list
