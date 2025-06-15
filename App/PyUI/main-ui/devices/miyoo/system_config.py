import json
import threading

from controller.controller_inputs import ControllerInput

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
    
    def set_volume(self, value):
        if(value == 0):
            self.config["mute"] = 1
        else:
            self.config["mute"] = 0
        self.config["vol"] = value //5

    def set_wifi(self, value):
        self.config["wifi"] = value

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

    def get_theme_path(self):
        return self.config.get("theme")

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
                print(f"Skipping invalid enum mapping: {k} -> {v}")
                continue

        return mapping