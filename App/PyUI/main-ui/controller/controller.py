import time
from devices.device import Device
import sdl2
import ctypes
from ctypes import byref
import time

from utils.py_ui_config import PyUiConfig

class Controller:
    def __init__(self, device: Device, config: PyUiConfig):
        self.controller = None
        self.index = None
        self.name = None
        self.mapping = None
        self._init_controller()
        self.event = sdl2.SDL_Event()
        self.device = device
        self.last_input_time = 0
        self.config = config


    def _init_controller(self):
        print("Checking for a controller")
        count = sdl2.SDL_NumJoysticks()
        for index in range(count):
            print(f"Checking index {index}")
            if sdl2.SDL_IsGameController(index):
                controller = sdl2.SDL_GameControllerOpen(index)
                if controller:
                    self.controller = controller
                    self.index = index
                    self.name = sdl2.SDL_GameControllerName(controller).decode()
                    self.mapping = sdl2.SDL_GameControllerMapping(controller).decode()
                    print(f"Opened GameController {index}: {self.name}")
                    print(f" {self.mapping}")
                    return
        print("No game controller found.")

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

        sdl2.SDL_PumpEvents()
        start_time = time.time()

        # Optional: delay if input is still being held from a prior press
        while self.still_held_down() and (time.time() - start_time < 0.12):
            sdl2.SDL_PumpEvents()
            time.sleep(0.005)  # Prevent tight CPU loop

        if not self.still_held_down():
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