import json
import os

from utils.logger import PyUiLogger

class FileBasedGameSystemConfig():
    def __init__(self, system_name):
        self.system_name = system_name
        self.emu_folder = f"/mnt/SDCARD/Emu/{system_name}"
        if(not os.path.exists(self.emu_folder)):
            self.emu_folder =  f"/mnt/SDCARD/Emus/{system_name}"
        self.config_path = f"{self.emu_folder}/config.json"
        self.reload_config()

    def reload_config(self):
        with open(self.config_path, 'r', encoding='utf-8') as f:
            self._data = json.load(f)

    def __str__(self):
        return f"GameSystemConfig(GameSystemConfig='{self.emu_folder}')"
    
    def get_emu_folder(self):
        return self.emu_folder

    def get_label(self):
        return self._data.get('label')

    def get_icon(self):
        return self._data.get('icon')

    def get_icon_selected(self):
        return self._data.get('iconsel')

    def get_launch(self):
        return self._data.get('launch')

    def get_devices(self):
        return self._data.get('devices', [])

    def get_extlist(self):
        return {f".{ext}" for ext in (self._data.get('extlist') or '').lower().split("|") if ext}

    def get_launchlist(self):
        return self._data.get('launchlist', [])
    
    def run_in_game_menu(self):
        return bool(self._data.get('ingamemenu', 0))
    
    def uses_retroarch(self):
        return bool(self._data.get('uses_retroarch', 0))
    
    def subfolder_launch_file(self):
        return self._data.get('subfolder_launch_file')
    
    def required_files_groups(self):
        return self._data.get('requiredfiles', [])

    def get_cpu_options(self):
        return self._data.get('cpuOptions', [])
    
    def get_selected_cpu(self):
        return self._data.get('selectedCpu', None)
    
    def get_sort_order(self):
        return self._data.get('sortOrder', 9999999)
    
    def get_brand(self):
        return self._data.get('brand', "Other")
    
    def get_type(self):
        return self._data.get('type', "Unknown")
    
    def get_release_year(self):
        return self._data.get('releaseYear', 9999999)
        
    def save_config(self):
        with open(self.config_path, 'w', encoding='utf-8') as f:
            json.dump(self._data, f, indent=4)
        self.reload_config()

    def get_menu_options(self):
        """Return the full menuOptions dict."""
        return self._data.get('menuOptions', {})

    def get_menu_option(self, name):
        """Return a specific menu option by name, or None if not found."""
        return self._data.get('menuOptions', {}).get(name)

    def set_menu_option(self, name, selected_value):
        """
        Update a specific menu option's selected value by name.
        """
        menu_options = self._data.get('menuOptions', {})
        if name in menu_options:
            menu_options[name]['selected'] = selected_value
            self.save_config()
            self.reload_config()
        else:
            # Optional: log or raise if not found
            # raise ValueError(f"Menu option '{name}' not found.")
            pass

    def set_menu_override(self, option_name, override_key, override_value):
        """
        Save or update an override for a given menu option and core key.
        Creates the overrides dict if missing.
        """
        menu_options = self._data.get('menuOptions', {})
        if option_name in menu_options:
            option = menu_options[option_name]
            overrides = option.setdefault('overrides', {})
            overrides[override_key] = override_value
            self.save_config()
            self.reload_config()
        else:
            PyUiLogger.get_logger().info(f"No menu option found for {option_name}, cannot set override.")

    def get_effective_menu_selection(self, option_name, override_key=None):
        """
        Return the effective selected value for `option_name`.
        - If `override_key` is provided, return the override for that key if present,
        otherwise return the option's base 'selected' value.
        - If `override_key` is None, simply return the option's base 'selected' value.
        Returns None if the option doesn't exist.
        """
        menu_options = self._data.get('menuOptions', {})
        option = menu_options.get(option_name)
        if not option:
            PyUiLogger.get_logger().info(f"No menu option found for {option_name}")
            return None

        if override_key is None:
            return option.get('selected')

        overrides = option.get('overrides') or {}
        return overrides.get(override_key, option.get('selected'))

    def delete_menu_override(self, option_name, override_key):
        """
        Delete an override for a given menu option and core key.
        Does nothing if the option or override doesn't exist.
        """
        menu_options = self._data.get('menuOptions', {})
        if option_name not in menu_options:
            return

        option = menu_options[option_name]
        overrides = option.get('overrides', {})

        if override_key in overrides:
            del overrides[override_key]
            # Clean up empty dict to keep JSON tidy
            if not overrides:
                option.pop('overrides', None)
            self.save_config()
            self.reload_config()
        else:
            PyUiLogger.get_logger().info(f"No menu option found for {option_name}, cannot delete override.")

    def contains_menu_override(self, option_name, override_key):
        """
        Check if an override exists for a given menu option and core key.
        Returns True if it exists, False otherwise.
        """
        menu_options = self._data.get('menuOptions', {})
        option = menu_options.get(option_name)
        if not option:
            return False

        overrides = option.get('overrides', {})
        return override_key in overrides

            
    def scan_subfolders(self):
        return self._data.get('scanSubfolders', True)
        
