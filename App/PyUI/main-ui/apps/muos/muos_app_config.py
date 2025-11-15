import os

from apps.app_config import AppConfig
from utils.logger import PyUiLogger

GLYPH_BASE = "/opt/muos/default/MUOS/theme/active/1280x720/glyph/muxapp/"

class MuosAppConfig(AppConfig):

    def __init__(self, folder_path):       
        self.folder = folder_path
        folder_name = os.path.basename(folder_path) 
        self.label = folder_name
        self.icontop = None
        self.launch = os.path.join(self.folder,"mux_launch.sh")
        self.description = self._get_help_from_launch()
        #self.icon = self._get_icon_from_name()
        #if(self.icon is None):
        self.icon = self._get_icon_from_launch()


    def _get_icon_from_name(self):
        # Don't like how these look...
        #icon = os.path.join("/mnt/sdcard/MUOS/info/catalogue/Application/box/1280x720", self.label + ".png")
        #if(os.path.exists(icon)):
        #    return icon
        return None

    def _get_icon_from_launch(self):
        try:
            with open(self.launch, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("# ICON:"):
                        icon_value = line.split(":", 1)[1].strip()
                        #
                        return os.path.join(GLYPH_BASE, icon_value + ".png")
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Could not read {self.launch}: {e}")
            
        return "/opt/muos/default/MUOS/theme/active/1280x720/glyph/muxapp/app.png"
        #return "/opt/muos/default/MUOS/theme/active/glyph/muxapp/app.png"

    def _get_help_from_launch(self):
        try:
            with open(self.launch, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("# HELP:"):
                        return line.split(":", 1)[1].strip()
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Could not read {self.launch}: {e}")
            
        return ""

    def get_label(self):
        return self.label

    def get_icontop(self):
        return self.icontop

    def get_icon(self):
        return self.icon

    def get_launch(self):
        return self.launch

    def get_description(self):
        return self.description
    
    def get_folder(self):
        return self.folder
    
    def is_hidden(self):
        return False

    def get_devices(self):
        return []

    def get_hide_in_simple_mode(self):
        return False