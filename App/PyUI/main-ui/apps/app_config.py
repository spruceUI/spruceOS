
from abc import ABC, abstractmethod


class AppConfig(ABC):
    def __init__(self):
        pass

    @abstractmethod
    def get_label(self):
        pass

    @abstractmethod
    def get_icontop(self):
        pass

    @abstractmethod
    def get_icon(self):
        pass

    @abstractmethod
    def get_launch(self):
        pass

    @abstractmethod
    def get_description(self):
        pass
    
    @abstractmethod
    def get_folder(self):
        pass
    
    @abstractmethod
    def is_hidden(self):
        pass
    
    @abstractmethod
    def get_devices(self):
        pass
    
    @abstractmethod
    def get_hide_in_simple_mode(self):
        pass

    def get_pyui_entry(self):
        """The "<module>:<function>" PyUI runs in its own process (apps/native_app.py), or None."""
        return None

    def get_launch_in_pyui(self):
        """Whether PyUI runs the launch script itself and shows its messages (apps/script_app.py)."""
        return False
