import json
import os
import threading

from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig


class UserConfig:
    FILEPATH = "/mnt/SDCARD/Saves/pyui-common.json"

    # Kept in py-ui-config.json before this file existed; spruceRestore still puts them back there after an update.
    MIGRATED_KEYS = ("gameSystemSortMode", "gameSystemSortTypePrio", "gameSystemSortBrandPrio",
                     "gameSystemSortYearPrio", "gameSystemSortNamePrio", "showAllGameSystems", "showAmPm",
                     "syncTimeViaNetwork", "turboDelayMs", "use24HourClock")

    _lock = threading.Lock()
    config = {}

    @classmethod
    def reload_config(cls):
        with cls._lock:
            try:
                with open(cls.FILEPATH, 'r') as f:
                    cls.config = json.load(f)
            except json.JSONDecodeError as e:
                PyUiLogger.get_logger().error(f"Error loading pyui-common config {e}")
                cls.config = {}
            except FileNotFoundError:
                cls.config = {}
        cls._migrate_from_pyui_config()

    @classmethod
    def _migrate_from_pyui_config(cls):
        migrated = {key: PyUiConfig.get(key) for key in cls.MIGRATED_KEYS
                    if key not in cls.config and PyUiConfig.get(key) is not None}
        if migrated:
            cls.config.update(migrated)
            try:
                cls.save_config()
            except RuntimeError as e:
                PyUiLogger.get_logger().error(f"Could not save migrated settings: {e}")

    @classmethod
    def save_config(cls):
        with cls._lock:
            try:
                # Deferred: off the startup path.
                import tempfile
                dirpath = os.path.dirname(cls.FILEPATH)

                with tempfile.NamedTemporaryFile(
                    'w',
                    dir=dirpath,
                    delete=False
                ) as tmp:
                    json.dump(cls.config, tmp, indent=4)
                    tmp.flush()
                    os.fsync(tmp.fileno())
                    tempname = tmp.name

                os.replace(tempname, cls.FILEPATH)

            except Exception as e:
                raise RuntimeError(f"Failed to save config: {e}")

    @classmethod
    def get_ignore_articles_when_sorting(cls):
        return cls.config.get("ignoreArticlesWhenSorting", False)

    @classmethod
    def set_ignore_articles_when_sorting(cls, value):
        cls.config["ignoreArticlesWhenSorting"] = value
        cls.save_config()

    @classmethod
    def show_am_pm(cls):
        return cls.config.get("showAmPm",True)

    @classmethod
    def set_show_am_pm(cls, value):
        cls.config["showAmPm"] = value
        cls.save_config()

    @classmethod
    def game_system_sort_mode(cls):
        return cls.config.get("gameSystemSortMode","SortOrderKey")

    @classmethod
    def set_game_system_sort_mode(cls, value):
        cls.config["gameSystemSortMode"] = value
        cls.save_config()

    @classmethod
    def game_system_sort_type_priority(cls):
        return cls.config.get("gameSystemSortTypePrio",1)

    @classmethod
    def set_game_system_sort_type_priority(cls, value):
        cls.config["gameSystemSortTypePrio"] = value
        cls.save_config()

    @classmethod
    def game_system_sort_brand_priority(cls):
        return cls.config.get("gameSystemSortBrandPrio",2)

    @classmethod
    def set_game_system_sort_brand_priority(cls, value):
        cls.config["gameSystemSortBrandPrio"] = value
        cls.save_config()

    @classmethod
    def game_system_sort_year_priority(cls):
        return cls.config.get("gameSystemSortYearPrio",3)
    
    @classmethod
    def set_game_system_sort_year_priority(cls, value):
        cls.config["gameSystemSortYearPrio"] = value
        cls.save_config()

    @classmethod
    def game_system_sort_name_priority(cls):
        return cls.config.get("gameSystemSortNamePrio",4)
    
    @classmethod
    def set_game_system_sort_name_priority(cls, value):
        cls.config["gameSystemSortNamePrio"] = value
        cls.save_config()

    @classmethod
    def get_turbo_delay_ms(cls):
        return cls.config.get("turboDelayMs", 250) / 1000

    @classmethod
    def set_turbo_delay_ms(cls, delay):
        cls.config["turboDelayMs"] = delay
        cls.save_config()

    @classmethod
    def use_24_hour_clock(cls):
        return cls.config.get("use24HourClock",False)

    @classmethod
    def set_use_24_hour_clock(cls, value):
        cls.config["use24HourClock"] = value
        cls.save_config()

    @classmethod
    def show_all_game_systems(cls):
        return cls.config.get("showAllGameSystems",False)

    @classmethod
    def set_show_all_game_systems(cls, value):
        cls.config["showAllGameSystems"] = value
        cls.save_config()

    @classmethod
    def sync_time_via_network(cls):
        # On by default: these handhelds have no battery-backed RTC, so without
        # this a cold boot sits years in the past and every HTTPS request fails
        # with "certificate is not yet valid". Off is a real choice though -
        # some games read the clock, so a user may want it held where they set it.
        return cls.config.get("syncTimeViaNetwork",True)

    @classmethod
    def set_sync_time_via_network(cls, value):
        cls.config["syncTimeViaNetwork"] = value
        cls.save_config()
