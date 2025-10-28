

from dataclasses import dataclass
import os
import struct
import select
import threading
import time
from typing import OrderedDict

from controller.controller_inputs import ControllerInput
from controller.controller_interface import ControllerInterface
from controller.key_state import KeyState
from utils.logger import PyUiLogger

# Constants for Linux input
EVENT_FORMAT = 'llHHI'
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)
KEY_PRESS = 1
KEY_RELEASE = 0
KEY_REPEAT = 2


@dataclass
class InputResult:
    controller_input: ControllerInput
    key_state: KeyState

@dataclass(frozen=True)
class KeyEvent:
    event_type: int
    code: int
    value: int

    
class KeyWatcherController(ControllerInterface):

    def __init__(self, event_path, key_mappings):
        """
        :param event_path: Path to /dev/input/eventX
        :param repeat_interval: Time between repeats (seconds)
        """
        self.event_path = event_path
        self.key_mappings = key_mappings
        self.held_controller_inputs = OrderedDict()

        try:
            self.fd = os.open(self.event_path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError as e:
            print(f"Error opening {self.event_path}: {e}")
            self.fd = None
        
        self.last_held_input = None
        self.input_polling_thread = threading.Thread(target=self.poll_keyboard, daemon=True)
        self.input_polling_thread.start()

    def still_held_down(self):
        
        if(self.last_held_input is None):
            return False
        elif(self.last_held_input in self.held_controller_inputs):
            return True
        else:
            return False


    def last_input(self):
        return self.last_held_input

    def clear_input(self):
        count = 0
        while(count < 50 and self.get_input(0.001) != (None, None)):
            count += 1

    def cache_last_event(self):
        self.cached_input = self.last_held_input
        self.clear_input()

    def restore_cached_event(self):
        self.last_held_input = self.cached_input


    def poll_keyboard(self):
        while(True):
            now = time.time()
            try:
                rlist, _, _ = select.select([self.fd], [], [], 100)
                if rlist:
                    data = os.read(self.fd, EVENT_SIZE)

                    if len(data) == EVENT_SIZE:
                        _, _, event_type, code, value = struct.unpack(EVENT_FORMAT, data)
                        #PyUiLogger.get_logger().error(f"event_type: {event_type}, code: {code}, value: {value}")
                        key_event = KeyEvent(event_type, code, value)
                        if key_event in self.key_mappings:
                            mapped_events = self.key_mappings[key_event]
                            if(mapped_events is not None and len(mapped_events) > 0):
                                for mapped_event in mapped_events:
                                    if mapped_event.key_state == KeyState.PRESS:
                                        self.held_controller_inputs[mapped_event.controller_input] = now
                                        #PyUiLogger.get_logger().debug(f"Adding {mapped_event.controller_input} to held inputs")
                                    elif mapped_event.key_state == KeyState.RELEASE:
                                        self.held_controller_inputs.pop(mapped_event.controller_input, None)
                                        #PyUiLogger.get_logger().debug(f"Removing {mapped_event.controller_input} from held inputs")
                            else:
                                PyUiLogger.get_logger().error(f"No mapping for event: {key_event}")

            except Exception as e:
                PyUiLogger.get_logger().error(f"Error reading input: {e}")

    def get_input(self, timeoutInMilliseconds):
        start_time = time.time()
        timeout = timeoutInMilliseconds / 1000.0

        self.last_held_input = next(iter(self.held_controller_inputs), None)

        while self.last_held_input is None and (time.time() - start_time) < timeout:
            time.sleep(0.05)  # 1/20 of a second delay
            self.last_held_input = next(iter(self.held_controller_inputs), None)

        return self.last_held_input

    def clear_input_queue(self):
        pass

    def init_controller(self):
        pass
    
    def re_init_controller(self):
        pass
    
    def close(self):
        pass

    def force_refresh(self):
        pass