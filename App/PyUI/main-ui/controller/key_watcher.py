
import os
import struct
import select
import time

from devices.device import Device
from utils.logger import PyUiLogger




# Constants for Linux input
EVENT_FORMAT = 'llHHI'
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)
EV_KEY = 0x01  # Event type for keyboard
KEY_PRESS = 1
KEY_RELEASE = 0
KEY_REPEAT = 2

class KeyWatcher:

    def __init__(self, event_path):
        self.event_path = event_path
        self.held_keys = {}  # Maps keycode -> last seen time
        self.repeat_interval = 0.2  # seconds
        try:
            self.fd = os.open(self.event_path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError as e:
            PyUiLogger.get_logger().warning(f"Unable to open {self.event_path}: {e}")
            return (None, None)

    def read_keyboard_input(self, timeout=1.0):
        """
        Polls for a single key event or simulates a repeat if a key is held.

        Returns:
            tuple: (keycode, is_down)
        """
        now = time.time()


        try:
            rlist, _, _ = select.select([self.fd], [], [], timeout)
            if rlist:
                data = os.read(self.fd, EVENT_SIZE)
                if len(data) == EVENT_SIZE:
                    _, _, event_type, code, value = struct.unpack(EVENT_FORMAT, data)
                    if event_type == EV_KEY:
                        if value == KEY_PRESS:
                            self.held_keys[code] = now
                            return (code, True)
                        elif value == KEY_REPEAT:
                            self.held_keys[code] = now
                            return (code, True)
                        elif value == KEY_RELEASE:
                            self.held_keys.pop(code, None)
                            return (code, False)
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Could not read input: {e}")

        # Simulate repeat for held keys
        for code, last_time in list(self.held_keys.items()):
            if now - last_time >= self.repeat_interval:
                self.held_keys[code] = now
                return (code, True)
    
        return (None, None)
        
    def poll_keyboard(self):
        last_recorded_time = 0
        while(True):
            code, is_key_down = self.read_keyboard_input()
            if(code is not None):
               if(time.time() - last_recorded_time > 0.1):
                    from controller.controller import Controller
                    controller_input = Device.get_device().map_key(code)
                    Controller.non_sdl_input_event(controller_input, is_key_down)
                    last_recorded_time = time.time()