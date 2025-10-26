from devices.abstract_device import AbstractDevice
from utils.image_utils import ImageUtils


class Device:
    _impl: AbstractDevice = None

    @staticmethod
    def init(impl: AbstractDevice):
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
    def screen_rotation():
        return Device._impl.screen_rotation

    @staticmethod
    def output_screen_width():
        return Device._impl.output_screen_width

    @staticmethod
    def output_screen_height():
        return Device._impl.output_screen_height

    @staticmethod
    def should_scale_screen():
        return Device._impl.should_scale_screen()

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
    def run_game(rom_info):
        return Device._impl.run_game(rom_info)

    @staticmethod
    def run_cmd(args, dir=None):
        return Device._impl.run_cmd(args, dir)

    @staticmethod
    def run_app(folder,launch):
        return Device._impl.run_app(folder,launch)

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
    def get_collections_path():
        return Device._impl.get_collections_path()

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
    def get_hue():
        return Device._impl.hue

    @staticmethod
    def lower_hue():
        return Device._impl.lower_hue()

    @staticmethod
    def raise_hue():
        return Device._impl.raise_hue()

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
    def prompt_power_down():
        return Device._impl.prompt_power_down()

    @staticmethod
    def reboot_cmd():
        return Device._impl.reboot_cmd

    @staticmethod
    def perform_startup_tasks():
        return Device._impl.perform_startup_tasks()

    @staticmethod
    def get_bluetooth_scanner():
        return Device._impl.get_bluetooth_scanner()
    
    @staticmethod  
    def supports_wifi():
        return Device._impl.supports_wifi()
    
    @staticmethod  
    def supports_volume():
        return Device._impl.supports_volume()

    @staticmethod  
    def get_ip_addr_text():
        return Device._impl.get_ip_addr_text()
    
    @staticmethod  
    def launch_stock_os_menu():
        return Device._impl.launch_stock_os_menu()
    
    @staticmethod  
    def supports_analog_calibration():
        return Device._impl.supports_analog_calibration()
    
    @staticmethod  
    def supports_image_resizing():
        return Device._impl.supports_image_resizing()
    
    @staticmethod  
    def calibrate_sticks():
        return Device._impl.calibrate_sticks()
    
    @staticmethod  
    def get_state_path():
        return Device._impl.get_state_path()
    
    @staticmethod
    def remap_buttons():
        return Device._impl.remap_buttons()
    
    @staticmethod
    def get_controller_interface():
        return Device._impl.get_controller_interface()

    @staticmethod
    def clear_framebuffer():
        return Device._impl.clear_framebuffer()

    @staticmethod
    def capture_framebuffer():
        return Device._impl.capture_framebuffer()

    @staticmethod
    def restore_framebuffer():
        return Device._impl.restore_framebuffer()
    
    @staticmethod
    def get_game_system_utils():
        return Device._impl.get_game_system_utils()
    
    @staticmethod
    def get_roms_dir():
        return Device._impl.get_roms_dir()
        
    @staticmethod
    def get_extra_settings_options():
        return Device._impl.get_extra_settings_options()

    @staticmethod
    def take_snapshot(path):
        return Device._impl.take_snapshot(path)

    @staticmethod
    def exit_pyui():
        return Device._impl.exit_pyui()

    @staticmethod
    def double_init_sdl_display():
        return Device._impl.double_init_sdl_display()

    @staticmethod
    def get_text_width_measurement_multiplier():
        return Device._impl.get_text_width_measurement_multiplier()
    
    @staticmethod
    def max_texture_width():
        return Device._impl.max_texture_width()
    
    @staticmethod
    def max_texture_height():
        return Device._impl.max_texture_height()

    @staticmethod
    def get_guaranteed_safe_max_text_char_count():
        return Device._impl.get_guaranteed_safe_max_text_char_count()

    @staticmethod
    def get_system_config():
        return Device._impl.get_system_config()

    @staticmethod
    def get_wpa_supplicant_conf_path():
        return Device._impl.get_wpa_supplicant_conf_path()

    @staticmethod
    def supports_brightness_calibration():
        return Device._impl.supports_brightness_calibration()

    @staticmethod
    def supports_contrast_calibration():
        return Device._impl.supports_contrast_calibration()

    @staticmethod
    def supports_saturation_calibration():
        return Device._impl.supports_saturation_calibration()

    @staticmethod
    def supports_hue_calibration():
        return Device._impl.supports_hue_calibration()

    @staticmethod
    def supports_popup_menu():
        return Device._impl.supports_popup_menu()

    @staticmethod
    def get_image_utils() -> ImageUtils:
        return Device._impl.get_image_utils()

    @staticmethod
    def get_boxart_resize_dimensions():
        return Device._impl.get_boxart_resize_dimensions()
    
    @staticmethod
    def get_boxart_small_resize_dimensions():
        return Device._impl.get_boxart_small_resize_dimensions()

