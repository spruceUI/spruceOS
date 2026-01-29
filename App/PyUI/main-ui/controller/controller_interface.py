
from abc import ABC, abstractmethod


class ControllerInterface(ABC):
    @abstractmethod
    def init_controller(self):
        pass
    
    @abstractmethod
    def re_init_controller(self):
        pass

    @abstractmethod
    def close():
        pass

    @abstractmethod
    def still_held_down():
        pass

    @abstractmethod
    def force_refresh():
        pass

    @abstractmethod
    def get_input(timeout):
        pass

    @abstractmethod
    def clear_input(timeout):
        pass

    @abstractmethod
    def clear_input_queue():
        pass

    #TODO These 2 things are too tied to SDL
    #and really should be removed in the future
    @abstractmethod
    def cache_last_event(self):
        pass

    @abstractmethod
    def restore_cached_event(self):
        pass
