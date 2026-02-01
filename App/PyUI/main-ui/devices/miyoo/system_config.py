import json
import os
import threading

from controller.controller_inputs import ControllerInput
from utils.consts import GAME_SWITCHER, RECENTS
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class SystemConfig:
    def __init__(self, filepath):
        self._lock = threading.Lock()
        self.filepath = filepath
        self.reload_config()
        

    def reload_config(self):
        with self._lock:
            try:
                with open(self.filepath, 'r') as f:
                    self.config = json.load(f)
            except (json.JSONDecodeError) as e:
                raise RuntimeError(f"Failed to load config: {e}")

    def save_config(self):
        with self._lock:
            try:
                with open(self.filepath, 'w') as f:
                    json.dump(self.config, f, indent=8)
            except Exception as e:
                raise RuntimeError(f"Failed to save config: {e}")
        
    def get_volume(self):
        return self.config.get("vol", 0) * 5

    def get_keymap(self):
        return self.config.get("keymap")

    def is_muted(self):
        return self.config.get("mute", 0) == 1

    def get_bgm_volume(self):
        return self.config.get("bgmvol", 0)

    @property
    def brightness(self):
        return self.config.get("brightness", 10)

    def get_brightness(self):
        return self.config.get("brightness", 10)

    def set_brightness(self, value):
        self.config["brightness"] = value

    @property
    def backlight(self):
        return self.config.get("backlight", 10)
    
    def set_backlight(self, value):
        self.config["backlight"] = value
    
    def get_backlight(self):
        return self.config.get("backlight", 10)

    def set_contrast(self, value):
        self.config["contrast"] = value
    
    def set_saturation(self, value):
        self.config["saturation"] = value

    @property
    def hue(self):
        return self.config.get("hue", 10)

    def get_hue(self):
        return self.config.get("hue")

    def set_hue(self, value):
        self.config["hue"] = value

    @property
    def disp_red(self):
        return self.config.get("disp_red", 128)

    def get_disp_red(self):
        return self.config.get("disp_red", 128)

    def set_disp_red(self, value):
        self.config["disp_red"] = value  
        
    @property
    def disp_blue(self):
        return self.config.get("disp_blue", 128)

    def get_disp_blue(self):
        return self.config.get("disp_blue", 128)

    def set_disp_blue(self, value):
        self.config["disp_blue"] = value   

    @property
    def disp_green(self):
        return self.config.get("disp_green", 128)

    def get_disp_green(self):
        return self.config.get("disp_green", 128)

    def set_disp_green(self, value):
        self.config["disp_green"] = value        
    
    def set_volume(self, value):
        if(value == 0):
            self.config["mute"] = 1
        else:
            self.config["mute"] = 0
        self.config["vol"] = value //5

    def set_wifi(self, value):
        self.config["wifi"] = value
        self.save_config()

    def set_bluetooth(self, value):
        self.config["bluetooth"] = value
        self.save_config()

    def get_language(self):
        return self.config.get("language")

    def get_hibernate(self):
        return self.config.get("hibernate")

    def get_hue(self):
        return self.config.get("hue")

    @property
    def saturation(self):
        return self.config.get("saturation", 10)

    def get_saturation(self):
        return self.config.get("saturation", 10)

    @property
    def contrast(self):
        return self.config.get("contrast", 10)

    def get_contrast(self):
        return self.config.get("contrast", 10)

    def get_fontsize(self):
        return self.config.get("fontsize")

    def is_audiofix_enabled(self):
        return self.config.get("audiofix") == 1

    def is_wifi_enabled(self):
        return self.config.get("wifi") == 1

    def is_runee_enabled(self):
        return self.config.get("runee") == 1

    def is_turboA_enabled(self):
        return self.config.get("turboA") == 1

    def is_turboB_enabled(self):
        return self.config.get("turboB") == 1

    def is_turboX_enabled(self):
        return self.config.get("turboX") == 1

    def is_turboY_enabled(self):
        return self.config.get("turboY") == 1

    def is_turboL_enabled(self):
        return self.config.get("turboL") == 1

    def is_turboR_enabled(self):
        return self.config.get("turboR") == 1

    def is_turboL2_enabled(self):
        return self.config.get("turboL2") == 1

    def is_turboR2_enabled(self):
        return self.config.get("turboR2") == 1

    def is_bluetooth_enabled(self):
        return self.config.get("bluetooth") == 1

    def get_skip_by_letter(self):
        return self.config.get("skipByLetter", False)

    def set_skip_by_letter(self,value):
        self.config["skipByLetter"] = value
        self.save_config()

    def game_switcher_enabled(self):
        return self.config.get("gameSwitcherEnabled", True)

    def set_game_switcher_enabled(self,value):
        self.config["gameSwitcherEnabled"] = value
        self.save_config()

    def game_switcher_game_count(self):
        return self.config.get("gameSwitcherGameCount", 8)

    def never_prompt_boxart_resize(self):
        return self.config.get("neverPromptBoxartResize", False)

    def set_never_prompt_boxart_resize(self,value):
        self.config["neverPromptBoxartResize"] = value
        self.save_config()

    def set_game_switcher_game_count(self, value):
        if(value < 1):
            value = 1
        self.config["gameSwitcherGameCount"] = value
        self.save_config()

    def get(self, property):
        return self.config.get(property)
    
    def set(self, property, value):
        if isinstance(property, dict):
            for k, v in property.items():
                self.config[k] = v
        else:
            self.config[property] = value
    
    def set_button_mapping(self, mapping):
        if not isinstance(mapping, dict):
            raise ValueError("Mapping must be a dictionary.")
        for k, v in mapping.items():
            if not isinstance(k, ControllerInput) or not isinstance(v, ControllerInput):
                raise ValueError("Keys and values must be ControllerInput enums")

        serialized = {str(k.value): v.value for k, v in mapping.items()}
        self.config["button_mapping"] = serialized        
        
    def get_button_mapping(self):
        raw_map = self.config.get("button_mapping", {})
        mapping = {}

        for k, v in raw_map.items():
            try:
                key_enum = ControllerInput(int(k))
                val_enum = ControllerInput(v)
                mapping[key_enum] = val_enum
            except ValueError:
                PyUiLogger.get_logger().info(f"Skipping invalid enum mapping: {k} -> {v}")
                continue

        return mapping
    
    def get_theme(self):
        theme = self.config.get("theme", None)
        if(theme is None):
            theme = PyUiConfig.get("theme")
            PyUiLogger.get_logger().info(f"Current user config does not have theme set, so loading from PyUIConfig as {theme}")
            self.set_theme(theme)
            from devices.device import Device
            Device.get_device().set_theme(os.path.join(PyUiConfig.get("themeDir"), theme))
        return theme

    def set_theme(self, theme):
        self.config["theme"] = theme
        self.save_config()

    def delete_theme_entry(self):
        if "theme" in self.config:
            del self.config["theme"]
            PyUiLogger.get_logger().info("Deleted 'theme' entry from user config")
            self.save_config()
        else:
            PyUiLogger.get_logger().info("'theme' entry not found in user config; nothing to delete")

    def use_savestate_screenshots(self, screen):
        default_value_if_missing = False
        if(RECENTS == screen or GAME_SWITCHER == screen):
            default_value_if_missing = True
            
        return self.config.get("preferSaveStateScreenshots"+screen, default_value_if_missing)

    def set_use_savestate_screenshots(self,screen, value):
        self.config["preferSaveStateScreenshots"+screen] = value
        self.save_config()


    def get_timezone(self):
        return self.config.get("timezone",'America/New_York')
       
    def set_timezone(self, value):
        self.config["timezone"] = value
        self.save_config()

    def play_button_press_sound(self):
        return self.config.get("playButtonPressSound", True)

    def set_play_button_press_sound(self,value):
        self.config["playButtonPressSound"] = value
        self.save_config()

    def play_bgm(self):
        return self.config.get("playBgm", True)

    def set_play_bgm(self,value):
        self.config["playBgm"] = value
        self.save_config()

    def bgm_volume(self):
        return self.config.get("bgmVolume", 10)

    def set_bgm_volume(self,value):
        self.config["bgmVolume"] = value
        self.save_config()

    def use_custom_gameswitcher_path(self):
        return self.config.get("useCustomGameSwitcherPath", True)

    def set_use_custom_gameswitcher_path(self,value):
        self.config["useCustomGameSwitcherPath"] = value
        self.save_config()

    def game_selection_only_mode_enabled(self):
        return self.config.get("gameSelectionOnlyMode", False)

    def set_game_selection_only_mode_enabled(self,value):
        self.config["gameSelectionOnlyMode"] = value
        self.save_config()

    def simple_mode_enabled(self):
        return self.config.get("simpleMode", False)

    def set_simple_mode_enabled(self,value):
        self.config["simpleMode"] = value
        self.save_config()

    def get_preferred_region(self):
        return self.config.get("preferredRegion", "USA")

    def set_preferred_region(self,value):
        self.config["preferredRegion"] = value
        self.save_config()

    def animations_enabled(self):
        return self.config.get("animationsEnabled", True)

    def set_animations_enabled(self, value):
        self.config["animationsEnabled"] = value
        self.save_config()

    def animation_speed(self, default_value):
        return self.config.get("animationSpeed", default_value)

    def set_animation_speed(self, value):
        self.config["animationSpeed"] = value
        self.save_config()

    def get_input_rate_limit_ms(self):
        return self.config.get("inputRateLimitMs", 16)

    def set_input_rate_limit_ms(self, value):
        self.config["inputRateLimitMs"] = value
        self.save_config()
