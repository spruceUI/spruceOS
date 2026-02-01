
import time
from devices.device import Device
import sdl2

from controller.controller_interface import ControllerInterface
from utils.logger import PyUiLogger
from ctypes import byref

from utils.time_logger import log_timing


class Sdl2ControllerInterface(ControllerInterface):

    def __init__(self):
        with log_timing("SDL2 Controller initialization", PyUiLogger.get_logger()):    
            self.event = sdl2.SDL_Event()
            self.controller = None
            self.print_key_changes = False

            self.clear_input_queue()
            self.init_controller()

    def print_key_state_changes(self):
        self.print_key_changes = True

    def init_controller(self):
        SDL_ENABLE = 1
        SDL_INIT_GAMECONTROLLER = 0x00002000

        sdl2.SDL_GameControllerEventState(SDL_ENABLE)
        sdl2.SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER)
        #PyUiLogger.get_logger().info("Checking for a controller")
        count = sdl2.SDL_NumJoysticks()
        for index in range(count):
           # PyUiLogger.get_logger().info(f"Checking index {index}")
            if sdl2.SDL_IsGameController(index):
                controller = sdl2.SDL_GameControllerOpen(index)
                if controller:
                    self.controller = controller
                    self.index = index
                    self.name = sdl2.SDL_GameControllerName(controller).decode()
                    self.mapping = sdl2.SDL_GameControllerMapping(controller).decode()
                    #PyUiLogger.get_logger().info(f"Opened GameController {index}: {self.name}")
                    #PyUiLogger.get_logger().info(f" {self.mapping}")
    
    def re_init_controller(self):
        sdl2.SDL_QuitSubSystem(sdl2.SDL_INIT_GAMECONTROLLER)
        time.sleep(0.2)
        sdl2.SDL_InitSubSystem(sdl2.SDL_INIT_GAMECONTROLLER)
        # 5. Pump events to make SDL notice new controllers
        for _ in range(10):
            sdl2.SDL_PumpEvents()
            time.sleep(0.1)
        self.init_controller()

    def close(self):
        if self.controller:
            sdl2.SDL_GameControllerClose(self.controller)
            self.controller = None

    def still_held_down(self):
        held_down = sdl2.SDL_GameControllerGetButton(self.controller, self.event.cbutton.button)
        return held_down

    def force_refresh(self):
        sdl2.SDL_PumpEvents()

    def get_input(self, timeout):
        event_available = sdl2.SDL_WaitEventTimeout(byref(self.event), timeout)
        
        if event_available:
            self.print_last_event()
            if self.event.type == sdl2.SDL_CONTROLLERDEVICEADDED:
                PyUiLogger.get_logger().info("New controller detected")
                self.init_controller()
            else:
                return self.last_input()
        
        return None
    
    def print_last_event(self):
        if(self.print_key_changes):
            if self.event.type == sdl2.SDL_CONTROLLERBUTTONDOWN:
                mapping = Device.get_device().map_digital_input(self.event.cbutton.button)
                if(mapping is not None):
                    print(f"KEY,{mapping},PRESS")
            elif self.event.type == sdl2.SDL_CONTROLLERBUTTONUP:
                mapping = Device.get_device().map_digital_input(self.event.cbutton.button)
                if(mapping is not None):
                    print(f"KEY,{mapping},RELEASE")
            elif self.event.type == sdl2.SDL_CONTROLLERAXISMOTION:
                mapping = Device.get_device().map_analog_input(self.event.cbutton.button,self.event.caxis.value)
                if(mapping is not None):
                    print(f"ANALOG,{mapping}")

    def last_input(self):
        if self.event.type == sdl2.SDL_CONTROLLERBUTTONDOWN:
            return Device.get_device().map_digital_input(self.event.cbutton.button)
        elif self.event.type == sdl2.SDL_CONTROLLERAXISMOTION:
            return Device.get_device().map_analog_input(self.event.caxis.axis, self.event.caxis.value)
        return None

    def clear_input(self):
        self.event.type = 0

    def cache_last_event(self):
        self.cached_event = self.event
        self.clear_input()

    def restore_cached_event(self):
        self.event = self.cached_event

    def clear_input_queue(self):
        count = 0
        while count < 50:
            sdl2.SDL_PollEvent(byref(self.event))
            if self.event.cbutton.button == 0:
                count += 1
            else:
                count = 0

    def get_left_analog_x(self):
        sdl2.SDL_PumpEvents()
        return sdl2.SDL_GameControllerGetAxis(self.controller, sdl2.SDL_CONTROLLER_AXIS_LEFTX)

    def get_left_analog_y(self):
        sdl2.SDL_PumpEvents()
        return sdl2.SDL_GameControllerGetAxis(self.controller, sdl2.SDL_CONTROLLER_AXIS_LEFTY)

    def get_right_analog_x(self):
        sdl2.SDL_PumpEvents()
        return sdl2.SDL_GameControllerGetAxis(self.controller, sdl2.SDL_CONTROLLER_AXIS_RIGHTX)

    def get_right_analog_y(self):
        sdl2.SDL_PumpEvents()
        return sdl2.SDL_GameControllerGetAxis(self.controller, sdl2.SDL_CONTROLLER_AXIS_RIGHTY)
