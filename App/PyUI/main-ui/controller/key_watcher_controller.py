

from collections import deque
import errno
import os
import struct
import threading
import time
from typing import OrderedDict

from controller.controller_interface import ControllerInterface
from controller.key_state import KeyState
from controller.key_watcher_controller_dataclasses import KeyEvent
from utils.logger import PyUiLogger

# Constants for Linux input
EVENT_FORMAT = 'llHHI'
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)
KEY_PRESS = 1
KEY_RELEASE = 0
KEY_REPEAT = 2

class KeyWatcherController(ControllerInterface):

    def __init__(self, event_path, key_mappings):
        """
        :param event_path: Path to /dev/input/eventX
        :param repeat_interval: Time between repeats (seconds)
        """
        self.event_path = event_path
        self.key_mappings = key_mappings
        self.held_controller_inputs = OrderedDict()
        self.input_queue = deque()
        
        try:
            self.fd = os.open(self.event_path, os.O_RDONLY)
        except OSError as e:
            PyUiLogger.get_logger().warning(f"Could not open {self.event_path}: {e}")
            self.fd = None
        
        self.last_held_input = None
        self.lock = threading.Lock()  # add a lock
        self.input_polling_thread = threading.Thread(target=self.poll_keyboard, daemon=True)
        self.input_polling_thread.start()
        self.print_key_changes = False

    def print_key_state_changes(self):
        self.print_key_changes = True

    def still_held_down(self):
        
        with self.lock:
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
        
    def read_event(self, fd):
        """Read exactly one input_event from fd (blocking)."""
        buf = b''
        while len(buf) < EVENT_SIZE:
            try:
                chunk = os.read(fd, EVENT_SIZE - len(buf))
            except BlockingIOError:
                continue
            if not chunk:
                PyUiLogger.get_logger().debug("EOF or no data read from fd")
                return None
            buf += chunk

        event = struct.unpack(EVENT_FORMAT, buf)
        return event



    def poll_keyboard(self):
        logger = PyUiLogger.get_logger()
        if self.fd is None:
            logger.error("File descriptor is None, cannot poll keyboard.")
            return
            
        while True:
            now = time.time()
            try:

                try:
                    data = os.read(self.fd, EVENT_SIZE)
                except OSError as e:
                    if e.errno == errno.EINTR:
                        continue

                    if e.errno in (errno.EBADF, errno.ENODEV, errno.EIO):
                        logger.error(
                            "Keyboard device became unavailable (errno=%d)",
                            e.errno,
                        )
                        return

                    logger.exception("Unexpected OSError while reading input")
                    return
                
                if len(data) != EVENT_SIZE:
                    logger.error("Short read: got %d bytes, expected %d", len(data), EVENT_SIZE)
                    continue

                tv_sec, tv_usec, event_type, code, value = struct.unpack(EVENT_FORMAT, data)

                key_event = KeyEvent(event_type, code, value)

                if key_event in self.key_mappings:
                    mapped_events = self.key_mappings[key_event]
                    if mapped_events:
                        for mapped_event in mapped_events:
                            if mapped_event.key_state == KeyState.PRESS:
                                with self.lock:
                                    self.held_controller_inputs[mapped_event.controller_input] = now
                                    if mapped_event.controller_input not in self.input_queue:
                                        self.input_queue.append(mapped_event.controller_input)
                                self.key_change(mapped_event.controller_input,"PRESS")
                            elif mapped_event.key_state == KeyState.RELEASE:
                                with self.lock:
                                    self.key_change(mapped_event.controller_input,"RELEASE")
                                self.held_controller_inputs.pop(mapped_event.controller_input, None)
                    else:
                        logger.error("No mapping for event: %s", key_event)
                elif(key_event.event_type != 0 or key_event.code !=0 or key_event.value != 0):
                    #logger.debug("Unmapped key event: %s", key_event)
                    pass

            except Exception as e:
                logger.exception("Error processing input: %s", e)

    def key_change(self, controller_input, direction):
        if(self.print_key_changes):
            print(f"KEY,{controller_input},{direction}")

    def get_input(self, timeoutInMilliseconds):
        start_time = time.time()
        timeout = timeoutInMilliseconds / 1000.0

        while (time.time() - start_time) < timeout:
            with self.lock:
                # First, check the event queue
                if self.input_queue:
                    value = self.input_queue.popleft()
                    self.last_held_input = value
                    return value
                
                # Fallback: return the first currently held key
                if self.held_controller_inputs:
                    value = next(iter(self.held_controller_inputs))
                    self.last_held_input = value
                    return value

            time.sleep(0.005)

        self.last_held_input = None
        return None

    
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