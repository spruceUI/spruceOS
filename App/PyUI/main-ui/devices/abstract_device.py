from abc import ABC, abstractmethod
import subprocess

from devices.miyoo.system_config import SystemConfig
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from utils.image_utils import ImageUtils

class AbstractDevice(ABC):
 
    @abstractmethod
    def screen_width(self):
        pass

    @abstractmethod
    def screen_height(self):
        pass

    @abstractmethod
    def screen_rotation(self):
        pass

    @abstractmethod
    def output_screen_width(self):
        pass

    @abstractmethod
    def output_screen_height(self):
        pass

    @abstractmethod
    def should_scale_screen(self):
        pass
    
    @abstractmethod
    def lumination(self):
        pass

    @abstractmethod
    def contrast(self):
        pass

    @abstractmethod
    def saturation(self):
        pass

    @abstractmethod
    def input_timeout_default(self):
        pass

    @abstractmethod
    def get_app_finder(self):
        pass
    
    @abstractmethod
    def get_wifi_status(self):
        pass
    
    @abstractmethod
    def get_wifi_status(self):
        pass

    @abstractmethod
    def is_wifi_enabled(self):
        pass

    @abstractmethod
    def is_bluetooth_enabled(self):
        pass

    @abstractmethod
    def disable_bluetooth(self):
        pass

    @abstractmethod
    def enable_bluetooth(self):
        pass

    @abstractmethod
    def disable_wifi(self):
        pass

    @abstractmethod
    def enable_wifi(self):
        pass

    @abstractmethod
    def get_battery_percent(self):
        pass

    @abstractmethod
    def run_game(self, rom_info) -> subprocess.Popen:
        pass

    @abstractmethod
    def run_cmd(self, args, dir = None):
        pass

    @abstractmethod
    def run_app(self, folder,launch):
        pass

    @abstractmethod
    def map_digital_input(self, sdl_input):
        pass

    @abstractmethod
    def map_analog_input(self, sdl_axis, sdl_value):
        pass

    @abstractmethod
    def special_input(self, key_code, length_in_seconds):   
        pass

    @abstractmethod
    def map_key(self, key_code):   
        pass

    @abstractmethod
    def get_favorites_path(self):
        pass

    @abstractmethod
    def get_recents_path(self):
        pass

    @abstractmethod
    def get_collections_path(self):
        pass

    @abstractmethod
    def get_apps_config_path(self):
        pass

    @abstractmethod
    def parse_favorites(self) -> list[GameEntry]:
        pass

    @abstractmethod
    def parse_recents(self) -> list[GameEntry]:
        pass

    @abstractmethod
    def lower_lumination(self):
        pass

    @abstractmethod
    def raise_lumination(self):
        pass

    
    @abstractmethod
    def brightness(self):
        pass

    @abstractmethod
    def lower_brightness(self):
        pass

    @abstractmethod
    def raise_brightness(self):
        pass

    @abstractmethod
    def lower_contrast(self):
        pass

    @abstractmethod
    def raise_contrast(self):
        pass

    @abstractmethod
    def lower_saturation(self):
        pass

    @abstractmethod
    def raise_saturation(self):
        pass
    
    
    @abstractmethod
    def hue(self):
        pass

    @abstractmethod
    def lower_hue(self):
        pass

    @abstractmethod
    def raise_hue(self):
        pass

    @abstractmethod
    def change_volume(self, amount):
        pass

    @abstractmethod
    def get_volume(self):
        pass

    @abstractmethod
    def get_display_volume(self):
        pass

    
    @abstractmethod
    def power_off_cmd(self):
        pass
    
    @abstractmethod
    def prompt_power_down(self):
        pass
    
    
    @abstractmethod
    def reboot_cmd(self):
        pass

    @abstractmethod
    def perform_startup_tasks(self):
        pass

    @abstractmethod
    def get_bluetooth_scanner(self):
        pass

    @abstractmethod
    def get_ip_addr_text(self):
        pass
    
    @staticmethod  
    def launch_stock_os_menu(self):
        pass
    
    @staticmethod  
    def supports_analog_calibration(self):
        pass
        
    @staticmethod  
    def supports_image_resizing(self):
        pass

    @staticmethod  
    def calibrate_sticks(self):
        pass
    
    @staticmethod  
    def get_state_path(self):
        pass

    @abstractmethod
    def remap_buttons(self):
        pass

    @abstractmethod
    def get_extra_settings_options(self):
        pass

    @abstractmethod
    def take_snapshot(self, path):
        pass

    @abstractmethod
    def exit_pyui(self):
        pass

    @abstractmethod
    def double_init_sdl_display(self):
        pass

    @abstractmethod
    def get_text_width_measurement_multiplier(self):
        pass

    @abstractmethod
    def max_texture_width(self):
        pass

    @abstractmethod
    def max_texture_height(self):
        pass

    @abstractmethod
    def get_guaranteed_safe_max_text_char_count(self):
        pass

    @abstractmethod
    def get_system_config(self) -> SystemConfig:
        pass

    @abstractmethod
    def get_wpa_supplicant_conf_path(self):
        pass

    @abstractmethod
    def supports_brightness_calibration(self):
        pass

    @abstractmethod
    def supports_contrast_calibration(self):
        pass

    @abstractmethod
    def supports_saturation_calibration(self):
        pass

    @abstractmethod
    def supports_rgb_calibration(self):
        pass

    @abstractmethod
    def set_disp_red(self,value):
        pass

    @abstractmethod
    def set_disp_blue(self,value):
        pass

    @abstractmethod
    def set_disp_green(self,value):
        pass

    @abstractmethod
    def get_disp_red(self):
        pass

    @abstractmethod
    def get_disp_blue(self):
        pass

    @abstractmethod
    def get_disp_green(self):
        pass

    @abstractmethod
    def supports_hue_calibration(self):
        pass

    @abstractmethod
    def supports_popup_menu(self):
        pass

    @abstractmethod
    def supports_timezone_setting(self):
        pass

    @abstractmethod
    def apply_timezone(self, timezone):
        pass

    @abstractmethod
    def set_theme(self, theme_path):
        pass

    @abstractmethod
    def get_core_name_overrides(self, core_name):
        pass

    @abstractmethod
    def get_core_for_game(self, game_system_config, rom_file_path):
        pass
    
    @abstractmethod
    def prompt_timezone_update(self):
        pass

    @abstractmethod
    def supports_caching_rom_lists(self):
        pass

    @abstractmethod
    def keep_running_on_error(self):
        pass

    @abstractmethod
    def get_image_utils(self) -> ImageUtils:
        pass

    @abstractmethod
    def get_boxart_medium_resize_dimensions(self):
        pass

    @abstractmethod
    def get_boxart_small_resize_dimensions(self):
        pass

    @abstractmethod
    def get_boxart_large_resize_dimensions(self):
        pass

    @abstractmethod
    def get_device_name(self):
        pass

    @abstractmethod
    def supports_qoi(self):
        pass

    @abstractmethod
    def get_save_state_image(self, rom_info: RomInfo):
        pass

    @abstractmethod
    def get_audio_system(self):
        pass
    
    @abstractmethod
    def get_about_info_entries(self):
        pass

    @abstractmethod
    def startup_init(self, include_wifi):
        pass

    @abstractmethod
    def might_require_surface_format_conversion(self):
        pass

    @abstractmethod
    def perform_sdcard_ro_check(self):
        pass

    @abstractmethod
    def sync_hw_clock(self):
        pass

    @abstractmethod
    def animation_divisor(self):
        pass

    # TODO potentially combine these two wifi methods
    @abstractmethod
    def get_wifi_menu(self):
        pass

    @abstractmethod
    def get_new_wifi_scanner(self):
        pass