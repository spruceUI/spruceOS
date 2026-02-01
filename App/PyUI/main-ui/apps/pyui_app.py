

from apps.app_config import AppConfig

class PyUiAppConfig(AppConfig):
    def __init__(self, label):
        self.label = label
        self.icontop = None
        self.icon = None
        self.launch = label
        self.folder = None
        self.description = None
        self.hide = False
        self.devices = []
        self.hide_in_simple_mode = None

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
        return self.hide
    
    def get_devices(self):
        return self.devices

    def get_hide_in_simple_mode(self):
        return self.hide_in_simple_mode