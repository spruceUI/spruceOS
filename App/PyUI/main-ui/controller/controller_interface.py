
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

    # Queue an input that did not come from this interface's own device (touch
    # gestures, for one). Interfaces that cannot take injected inputs ignore it.
    def inject_input(self, controller_input):
        pass

    # End a get_input() wait early, from any thread, without an input: it
    # returns None as on a timeout (Controller.request_redraw). Interfaces that
    # cannot be woken ignore it, and their wait runs to its timeout.
    def wake(self):
        pass

    # The write end of a nonblocking pipe for signal.set_wakeup_fd: a signal ends
    # a get_input() wait as wake() does (utils/shutdown.py). None where the
    # interface cannot watch one; the wait then runs to its timeout.
    def signal_wakeup_fd(self):
        return None
