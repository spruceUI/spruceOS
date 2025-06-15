from abc import ABC, abstractmethod
import subprocess

from games.utils.game_entry import GameEntry

class AbstractDevice(ABC):
 
    @property
    @abstractmethod
    def screen_width(self):
        pass

    @property
    @abstractmethod
    def screen_height(self):
        pass

    @property
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
    
    @property
    @abstractmethod
    def lumination(self):
        pass

    @property
    @abstractmethod
    def contrast(self):
        pass

    @property
    @abstractmethod
    def saturation(self):
        pass

    @property
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
    def run_app(self, args, dir = None):
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

    @property
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
    
    @property
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

    @property
    @abstractmethod
    def power_off_cmd(self):
        pass
    
    @abstractmethod
    def prompt_power_down(self):
        pass
    
    @property
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
    def calibrate_sticks(self):
        pass
    
    @staticmethod  
    def get_state_path(self):
        pass

    @abstractmethod
    def remap_buttons(self):
        pass