from devices.device_common import DeviceCommon


class Device:
    _impl: DeviceCommon = None

    @staticmethod
    def init(impl: DeviceCommon):
        Device._impl = impl

    @staticmethod
    def _require_impl():
        if Device._impl is None:
            raise RuntimeError("Device implementation not set")

    @staticmethod
    def screen_width():
        return Device._impl.screen_width

    @staticmethod
    def screen_height():
        return Device._impl.screen_height

    @staticmethod
    def output_screen_width():
        return Device._impl.output_screen_width()

    @staticmethod
    def output_screen_height():
        return Device._impl.output_screen_height()

    @staticmethod
    def should_scale_screen():
        return Device._impl.should_scale_screen()

    @staticmethod
    def font_size_small():
        return Device._impl.font_size_small

    @staticmethod
    def font_size_medium():
        return Device._impl.font_size_medium

    @staticmethod
    def font_size_large():
        return Device._impl.font_size_large

    @staticmethod
    def large_grid_x_offset():
        return Device._impl.large_grid_x_offset

    @staticmethod
    def large_grid_y_offset():
        return Device._impl.large_grid_y_offset

    @staticmethod
    def large_grid_spacing_multiplier():
        return Device._impl.large_grid_spacing_multiplier

    @staticmethod
    def lumination():
        return Device._impl.lumination

    @staticmethod
    def contrast():
        return Device._impl.contrast

    @staticmethod
    def saturation():
        return Device._impl.saturation

    @staticmethod
    def input_timeout_default():
        return Device._impl.input_timeout_default

    @staticmethod
    def get_app_finder():
        return Device._impl.get_app_finder()

    @staticmethod
    def get_charge_status():
        return Device._impl.get_charge_status()

    @staticmethod
    def get_wifi_status():
        return Device._impl.get_wifi_status()

    @staticmethod
    def is_wifi_enabled():
        return Device._impl.is_wifi_enabled()

    @staticmethod
    def is_bluetooth_enabled():
        return Device._impl.is_bluetooth_enabled()

    @staticmethod
    def disable_bluetooth():
        return Device._impl.disable_bluetooth()

    @staticmethod
    def enable_bluetooth():
        return Device._impl.enable_bluetooth()

    @staticmethod
    def disable_wifi():
        return Device._impl.disable_wifi()

    @staticmethod
    def enable_wifi():
        return Device._impl.enable_wifi()
    
    @staticmethod
    def wifi_error_detected():
        return Device._impl.enable_wifi()


    @staticmethod
    def get_battery_percent():
        return Device._impl.get_battery_percent()

    @staticmethod
    def run_game(path):
        return Device._impl.run_game(path)

    @staticmethod
    def run_app(args, dir=None):
        return Device._impl.run_app(args, dir)

    @staticmethod
    def map_digital_input(sdl_input):
        return Device._impl.map_digital_input(sdl_input)

    @staticmethod
    def map_analog_input(sdl_axis, sdl_value):
        return Device._impl.map_analog_input(sdl_axis, sdl_value)

    @staticmethod
    def special_input(key_code, length_in_seconds):
        return Device._impl.special_input(key_code, length_in_seconds)

    @staticmethod
    def map_key(key_code):
        return Device._impl.map_key(key_code)

    @staticmethod
    def get_favorites_path():
        return Device._impl.get_favorites_path()

    @staticmethod
    def get_recents_path():
        return Device._impl.get_recents_path()

    @staticmethod
    def parse_favorites():
        return Device._impl.parse_favorites()

    @staticmethod
    def parse_recents():
        return Device._impl.parse_recents()

    @staticmethod
    def get_lumination():
        return Device._impl.lumination

    @staticmethod
    def lower_lumination():
        return Device._impl.lower_lumination()

    @staticmethod
    def raise_lumination():
        return Device._impl.raise_lumination()

    @staticmethod
    def get_brightness():
        return Device._impl.brightness

    @staticmethod
    def lower_brightness():
        return Device._impl.lower_brightness()

    @staticmethod
    def raise_brightness():
        return Device._impl.raise_brightness()

    @staticmethod
    def get_contrast():
        return Device._impl.contrast
    
    @staticmethod
    def lower_contrast():
        return Device._impl.lower_contrast()

    @staticmethod
    def raise_contrast():
        return Device._impl.raise_contrast()
    
    @staticmethod
    def get_saturation():
        return Device._impl.saturation

    @staticmethod
    def lower_saturation():
        return Device._impl.lower_saturation()

    @staticmethod
    def raise_saturation():
        return Device._impl.raise_saturation()

    @staticmethod
    def change_volume(amount):
        return Device._impl.change_volume(amount)

    @staticmethod
    def get_volume():
        return Device._impl.get_volume()

    @staticmethod
    def get_display_volume():
        return Device._impl.get_display_volume()

    @staticmethod
    def power_off_cmd():
        return Device._impl.power_off_cmd

    @staticmethod
    def reboot_cmd():
        return Device._impl.reboot_cmd

    @staticmethod
    def get_rom_utils():
        return Device._impl.get_rom_utils()

    @staticmethod
    def perform_startup_tasks():
        return Device._impl.perform_startup_tasks()

    @staticmethod
    def get_bluetooth_scanner():
        return Device._impl.get_bluetooth_scanner()

    @staticmethod  
    def get_ip_addr_text():
        return Device._impl.get_ip_addr_text()
    
    @staticmethod  
    def launch_stock_os_menu():
        return Device._impl.launch_stock_os_menu()
    
    @staticmethod  
    def calibrate_sticks():
        return Device._impl.calibrate_sticks()
    
    