
from abc import ABC, abstractmethod


class AppConfig(ABC):
    def __init__(self):
        pass

    @abstractmethod
    def get_label(self) -> str:
        pass

    @abstractmethod
    def get_icontop(self) -> str | None:
        pass

    @abstractmethod
    def get_icon(self) -> str | None:
        pass

    @abstractmethod
    def get_launch(self) -> str:
        pass

    @abstractmethod
    def get_description(self) -> str | None:
        pass
    
    @abstractmethod
    def get_folder(self) -> str:
        pass
    
    @abstractmethod
    def is_hidden(self) -> bool:
        pass
    
    @abstractmethod
    def get_devices(self) -> list[str]:
        pass
    
    @abstractmethod
    def get_hide_in_simple_mode(self) -> bool:
        pass

