
import os

from apps.muos.muos_app_config import MuosAppConfig
from utils.logger import PyUiLogger

class MuosAppFinder:

    def __init__(self):
        self.app_dir = "/mnt/mmc/MUOS/application/"

    def get_apps(self):
        app_configs = []
        if os.path.isdir(self.app_dir):
            PyUiLogger.get_logger().info(f"Scanning dir for apps: {self.app_dir}")
            for entry in os.listdir(self.app_dir):
                folder_path = os.path.join(self.app_dir, entry)
                PyUiLogger.get_logger().info(f"Checking dir: {folder_path}")
                launch_path = os.path.join(folder_path, "mux_launch.sh")

                if os.path.isdir(folder_path) and os.path.isfile(launch_path):
                    try:
                        config = MuosAppConfig(folder_path)
                        app_configs.append(config)
                    except Exception as e:
                        PyUiLogger.get_logger().error(f"Error processing app dir [{self.app_dir}] : {e}")
        else:            
            PyUiLogger.get_logger().info(f"App directory not found: {self.app_dir}")
        return app_configs