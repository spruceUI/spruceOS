from __future__ import annotations

from abc import ABC, abstractmethod
import subprocess
from typing import Any, Optional

from devices.charge.charge_status import ChargeStatus
from devices.miyoo.system_config import SystemConfig
from games.utils.game_entry import GameEntry
from menus.games.utils.rom_info import RomInfo
from utils.image_utils import ImageUtils

class AbstractDevice(ABC):
    system_config: SystemConfig
 
    @abstractmethod
    def screen_width(self) -> int:
        pass

    @abstractmethod
    def screen_height(self) -> int:
        pass

    @abstractmethod
    def screen_rotation(self) -> int:
        pass

    @abstractmethod
    def output_screen_width(self) -> int:
        pass

    @abstractmethod
    def output_screen_height(self) -> int:
        pass

    @abstractmethod
    def should_scale_screen(self) -> bool:
        pass
    
    @abstractmethod
    def lumination(self) -> int:
        pass

    @abstractmethod
    def contrast(self) -> int:
        pass

    @abstractmethod
    def saturation(self) -> int:
        pass

    @abstractmethod
    def input_timeout_default(self) -> float:
        pass

    @abstractmethod
    def get_app_finder(self) -> Any:
        pass

    @abstractmethod
    def get_controller_interface(self) -> Any:
        pass
    
    @abstractmethod
    def get_wifi_status(self) -> Any:
        pass

    @abstractmethod
    def is_wifi_enabled(self) -> bool:
        pass

    @abstractmethod
    def is_bluetooth_enabled(self) -> bool:
        pass

    @abstractmethod
    def disable_bluetooth(self) -> None:
        pass

    @abstractmethod
    def enable_bluetooth(self) -> None:
        pass

    @abstractmethod
    def disable_wifi(self) -> None:
        pass

    @abstractmethod
    def enable_wifi(self) -> None:
        pass

    @abstractmethod
    def get_battery_percent(self) -> int:
        pass

    @abstractmethod
    def get_charge_status(self) -> ChargeStatus:
        pass

    @abstractmethod
    def run_game(self, rom_info) -> subprocess.Popen | None:
        pass

    @abstractmethod
    def run_cmd(self, args, dir = None) -> Any:
        pass

    @abstractmethod
    def run_app(self, folder,launch) -> Any:
        pass

    @abstractmethod
    def map_digital_input(self, sdl_input) -> Any:
        pass

    @abstractmethod
    def map_analog_input(self, sdl_axis, sdl_value) -> Any:
        pass

    @abstractmethod
    def special_input(self, key_code, length_in_seconds) -> None:
        pass

    @abstractmethod
    def map_key(self, key_code) -> Any:   
        pass

    @abstractmethod
    def get_favorites_path(self) -> str:
        pass

    @abstractmethod
    def capture_framebuffer(self) -> None:
        pass

    @abstractmethod
    def restore_framebuffer(self) -> None:
        pass

    @abstractmethod
    def get_recents_path(self) -> str:
        pass

    @abstractmethod
    def get_collections_path(self) -> str:
        pass

    @abstractmethod
    def get_roms_dir(self) -> str:
        pass

    @abstractmethod
    def get_game_system_utils(self) -> Any:
        pass

    @abstractmethod
    def get_apps_config_path(self) -> str:
        pass

    @abstractmethod
    def parse_favorites(self) -> list[GameEntry]:
        pass

    @abstractmethod
    def parse_recents(self) -> list[GameEntry]:
        pass

    @abstractmethod
    def lower_lumination(self) -> None:
        pass

    @abstractmethod
    def raise_lumination(self) -> None:
        pass

    
    @abstractmethod
    def brightness(self) -> int:
        pass

    @abstractmethod
    def lower_brightness(self) -> None:
        pass

    @abstractmethod
    def raise_brightness(self) -> None:
        pass

    @abstractmethod
    def lower_contrast(self) -> None:
        pass

    @abstractmethod
    def raise_contrast(self) -> None:
        pass

    @abstractmethod
    def lower_saturation(self) -> None:
        pass

    @abstractmethod
    def raise_saturation(self) -> None:
        pass
    
    
    @abstractmethod
    def hue(self) -> int:
        pass

    @abstractmethod
    def lower_hue(self) -> None:
        pass

    @abstractmethod
    def raise_hue(self) -> None:
        pass

    @abstractmethod
    def change_volume(self, amount) -> None:
        pass

    @abstractmethod
    def get_volume(self) -> int:
        pass

    @abstractmethod
    def get_display_volume(self) -> int:
        pass

    
    @abstractmethod
    def power_off_cmd(self) -> str:
        pass
    
    @abstractmethod
    def prompt_power_down(self) -> None:
        pass
    
    
    @abstractmethod
    def reboot_cmd(self) -> Optional[str]:
        pass

    @abstractmethod
    def perform_startup_tasks(self) -> None:
        pass

    @abstractmethod
    def get_bluetooth_scanner(self) -> Any:
        pass

    @abstractmethod
    def supports_wifi(self) -> bool:
        pass

    @abstractmethod
    def supports_volume(self) -> bool:
        pass

    def fix_sleep_sound_bug(self) -> None:
        pass

    @abstractmethod
    def get_ip_addr_text(self) -> str:
        pass

    def get_running_processes(self) -> subprocess.CompletedProcess[str] | None:
        pass

    def set_wifi_power(self, value):
        pass

    def start_wpa_supplicant(self):
        pass

    def start_wifi_services(self):
        pass

    def stop_wifi_services(self):
        pass
    
    def launch_stock_os_menu(self) -> None:
        pass
    
    @abstractmethod
    def supports_analog_calibration(self) -> bool:
        pass
        
    @abstractmethod
    def supports_image_resizing(self) -> bool:
        pass

    def calibrate_sticks(self) -> None:
        pass
    
    @abstractmethod
    def get_state_path(self) -> str:
        pass

    @abstractmethod
    def remap_buttons(self) -> None:
        pass

    @abstractmethod
    def get_extra_settings_options(self) -> list[Any]:
        pass

    @abstractmethod
    def take_snapshot(self, path) -> None:
        pass

    @abstractmethod
    def exit_pyui(self) -> None:
        pass

    @abstractmethod
    def double_init_sdl_display(self) -> bool:
        pass

    @abstractmethod
    def get_text_width_measurement_multiplier(self) -> float:
        pass

    @abstractmethod
    def max_texture_width(self) -> int:
        pass

    @abstractmethod
    def max_texture_height(self) -> int:
        pass

    @abstractmethod
    def get_guaranteed_safe_max_text_char_count(self) -> int:
        pass

    @abstractmethod
    def get_system_config(self) -> SystemConfig:
        pass

    @abstractmethod
    def get_wpa_supplicant_conf_path(self) -> str:
        pass

    @abstractmethod
    def supports_brightness_calibration(self) -> bool:
        pass

    @abstractmethod
    def supports_contrast_calibration(self) -> bool:
        pass

    @abstractmethod
    def supports_saturation_calibration(self) -> bool:
        pass

    @abstractmethod
    def supports_rgb_calibration(self) -> bool:
        pass

    @abstractmethod
    def set_disp_red(self,value) -> None:
        pass

    @abstractmethod
    def set_disp_blue(self,value) -> None:
        pass

    @abstractmethod
    def set_disp_green(self,value) -> None:
        pass

    @abstractmethod
    def get_disp_red(self) -> int:
        pass

    @abstractmethod
    def get_disp_blue(self) -> int:
        pass

    @abstractmethod
    def get_disp_green(self) -> int:
        pass

    @abstractmethod
    def supports_hue_calibration(self) -> bool:
        pass

    @abstractmethod
    def supports_popup_menu(self) -> bool:
        pass

    @abstractmethod
    def supports_timezone_setting(self) -> bool:
        pass

    @abstractmethod
    def apply_timezone(self, timezone) -> None:
        pass

    @abstractmethod
    def set_theme(self, theme_path) -> None:
        pass

    @abstractmethod
    def get_core_name_overrides(self, core_name) -> list[str]:
        pass

    @abstractmethod
    def get_core_for_game(self, game_system_config, rom_file_path) -> Optional[str]:
        pass
    
    @abstractmethod
    def prompt_timezone_update(self) -> None:
        pass

    @abstractmethod
    def supports_caching_rom_lists(self) -> bool:
        pass

    @abstractmethod
    def keep_running_on_error(self) -> bool:
        pass

    @abstractmethod
    def get_image_utils(self) -> ImageUtils:
        pass

    @abstractmethod
    def get_boxart_medium_resize_dimensions(self) -> tuple[int, int]:
        pass

    @abstractmethod
    def get_boxart_small_resize_dimensions(self) -> tuple[int, int]:
        pass

    @abstractmethod
    def get_boxart_large_resize_dimensions(self) -> tuple[int, int]:
        pass

    @abstractmethod
    def get_device_name(self) -> str:
        pass

    @abstractmethod
    def supports_qoi(self) -> bool:
        pass

    @abstractmethod
    def get_save_state_image(self, rom_info: RomInfo) -> Optional[str]:
        pass

    @abstractmethod
    def get_audio_system(self):
        pass
    
    @abstractmethod
    def get_about_info_entries(self) -> list[tuple[str, str]]:
        pass

    @abstractmethod
    def startup_init(self, include_wifi) -> None:
        pass

    @abstractmethod
    def might_require_surface_format_conversion(self) -> bool:
        pass

    @abstractmethod
    def perform_sdcard_ro_check(self) -> None:
        pass

    @abstractmethod
    def sync_hw_clock(self) -> None:
        pass

    @abstractmethod
    def animation_divisor(self) -> float:
        pass

    # TODO potentially combine these two wifi methods
    @abstractmethod
    def get_wifi_menu(self) -> Any:
        pass

    @abstractmethod
    def get_new_wifi_scanner(self) -> Any:
        pass

    @abstractmethod
    def post_present_operations(self) -> None:
        pass
