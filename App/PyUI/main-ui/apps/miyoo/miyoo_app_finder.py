
import os

from apps.miyoo.miyoo_app_config import MiyooAppConfig
from utils.cached_exists import CachedExists

class MiyooAppFinder:

    def __init__(self):
        self.app_dir = "/mnt/SDCARD/App/"
        if(not CachedExists.exists(self.app_dir)):
            self.app_dir = "/mnt/SDCARD/Apps/"

    def get_apps(self):
        app_configs = []
        if os.path.isdir(self.app_dir):
            for entry in os.listdir(self.app_dir):
                folder_path = os.path.join(self.app_dir, entry)
                config_path = os.path.join(folder_path, "config.json")

                if os.path.isdir(folder_path) and os.path.isfile(config_path):
                    try:
                        config = MiyooAppConfig(config_path)
                        app_configs.append(config)
                    except Exception as e:
                        # Optional: log or print error if needed
                        continue
        return app_configs