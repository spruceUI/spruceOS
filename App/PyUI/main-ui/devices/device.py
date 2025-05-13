from abc import ABC, abstractmethod

from games.utils.game_entry import GameEntry

class Device(ABC):
 
    @property
    @abstractmethod
    def screen_width(self):
        pass

    @property
    @abstractmethod
    def screen_height(self):
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
    def font_size_small(self):
        pass    

    @property
    @abstractmethod
    def font_size_medium(self):
        pass   

    @property
    @abstractmethod
    def font_size_large(self):
        pass

    @property
    @abstractmethod
    def large_grid_x_offset(self):
        pass

    @property
    @abstractmethod
    def large_grid_y_offset(self):
        pass
    
    @property
    @abstractmethod
    def large_grid_spacing_multiplier(self):
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
    def run_game(self, path):
        pass

    @abstractmethod
    def run_app(self, args, dir = None):
        pass

    @abstractmethod
    def map_input(self, sdl_input):
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
    def change_volume(self, amount):
        pass

    @abstractmethod
    def get_volume(self):
        pass

    @property
    @abstractmethod
    def power_off_cmd(self):
        pass
    
    @property
    @abstractmethod
    def reboot_cmd(self):
        pass

    @abstractmethod
    def get_rom_utils(self):
        pass

    @abstractmethod
    def perform_startup_tasks(self):
        pass
