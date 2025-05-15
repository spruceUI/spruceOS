import time
from devices.device import Device
import sdl2
import ctypes
from ctypes import byref
import time

from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class Controller:
    def __init__(self, device: Device, config: PyUiConfig):
        self.controller = None
        self.index = None
        self.name = None
        self.mapping = None
        self.event = sdl2.SDL_Event()
        self._init_controller()
        self.device = device
        self.last_input_time = 0
        self.config = config
        self.hold_delay = config.get_turbo_delay_ms()

    def _init_controller(self):
        #Force new connection to be processed byt SDL by polling it off the queue
        self.clear_input_queue()
        PyUiLogger.get_logger().info("Checking for a controller")
        count = sdl2.SDL_NumJoysticks()
        for index in range(count):
            PyUiLogger.get_logger().info(f"Checking index {index}")
            if sdl2.SDL_IsGameController(index):
                controller = sdl2.SDL_GameControllerOpen(index)
                if controller:
                    self.controller = controller
                    self.index = index
                    self.name = sdl2.SDL_GameControllerName(controller).decode()
                    self.mapping = sdl2.SDL_GameControllerMapping(controller).decode()
                    PyUiLogger.get_logger().info(f"Opened GameController {index}: {self.name}")
                    PyUiLogger.get_logger().info(f" {self.mapping}")

    def new_bt_device_paired(self):
        self._init_controller()

    def get_controller(self):
        return self.controller

    def close(self):
        if self.controller:
            sdl2.SDL_GameControllerClose(self.controller)
            self.controller = None
            

    def still_held_down(self):
        return sdl2.SDL_GameControllerGetButton(self.controller, self.event.cbutton.button)
    
    def get_input(self, timeout=-2):
        if timeout == -2:
            timeout = self.device.input_timeout_default

        #If a long render occurred, clear the input queue
        if time.time() - self.last_input_time > 0.2:
            sdl2.SDL_PumpEvents()
            self.clear_input_queue()

        sdl2.SDL_PumpEvents()
        start_time = time.time()

        # Optional: delay if input is still being held from a prior press
        while self.still_held_down() and (time.time() - start_time < self.hold_delay):
            sdl2.SDL_PumpEvents()
            time.sleep(0.005)  # Prevent tight CPU loop

        if not self.still_held_down():
            self.hold_delay = self.config.get_turbo_delay_ms()
            self._last_event().type = 0  # Clear last event
            reached_timeout = False

            while not reached_timeout:
                elapsed = time.time() - start_time
                remaining_time = timeout - elapsed
                if remaining_time <= 0:
                    reached_timeout = True
                    break

                ms_remaining = int(remaining_time * 1000)
                event_available = sdl2.SDL_WaitEventTimeout(byref(self.event), ms_remaining)

                if event_available and self._last_event().type == sdl2.SDL_CONTROLLERBUTTONDOWN:
                    break
                elif(event_available and self._last_event().type == sdl2.SDL_CONTROLLERDEVICEADDED):
                    PyUiLogger.get_logger().info("New controller detected")
                    self._init_controller()
        else:
            self.hold_delay = 0.0

        self.last_input_time = time.time()
        return self.last_event_was_controller() 

    def clear_input_queue(self):
        # SDL is super weird on the flip, disabling and clearing do not work
        # There is also strings of 0s between inputs once resuming
        # To get around this wait for 50s in a row
        count = 0
        while count < 50:
            sdl2.SDL_PollEvent(byref(self.event))
            if(self.event.cbutton.button == 0):
                count+=1
            else:
                count=0

    def last_event_was_controller(self):
        return self._last_event().type == sdl2.SDL_CONTROLLERBUTTONDOWN

    def _last_event(self):
        return self.event
        
    def last_input(self):
        return self.device.map_input(self.event.cbutton.button)