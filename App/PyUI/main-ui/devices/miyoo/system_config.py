import json

class SystemConfig:
    def __init__(self, filepath):
        self.filepath = filepath
        self.reload_config()
        
    def reload_config(self):
        try:
            with open(self.filepath, 'r') as f:
                self.config = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError) as e:
            raise RuntimeError(f"Failed to load config: {e}")

    def save_config(self):
        try:
            with open(self.filepath, 'w') as f:
                json.dump(self.config, f, indent=8)
        except Exception as e:
            raise RuntimeError(f"Failed to save config: {e}")
        
    def get_volume(self):
        return self.config.get("vol")

    def get_keymap(self):
        return self.config.get("keymap")

    def is_muted(self):
        return self.config.get("mute") == 1

    def get_bgm_volume(self):
        return self.config.get("bgmvol")

    @property
    def brightness(self):
        return self.config.get("lumination")

    def get_brightness(self):
        return self.config.get("lumination")

    def set_brightness(self, value):
        self.config["lumination"] = value

    @property
    def backlight(self):
        return self.config.get("brightness")
    
    def set_backlight(self, value):
        self.config["brightness"] = value
    
    def get_backlight(self):
        return self.config.get("brightness")

    
    def set_contrast(self, value):
        self.config["contrast"] = value
    
    def set_saturation(self, value):
        self.config["saturation"] = value
    
    def set_volume(self, value):
        self.config["vol"] = value

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
        return self.config.get("saturation")

    def get_saturation(self):
        return self.config.get("saturation")

    @property
    def contrast(self):
        return self.config.get("contrast")

    def get_contrast(self):
        return self.config.get("contrast")

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
