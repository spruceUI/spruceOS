import time
from devices.device import Device
import sdl2
import ctypes
from ctypes import byref
import time

from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class Controller:
    controller = None
    index = None
    name = None
    mapping = None
    event = sdl2.SDL_Event()
    last_input_time = 0
    hold_delay = 0

    @staticmethod
    def init():
        Controller.clear_input_queue()
        PyUiLogger.get_logger().info("Checking for a controller")
        count = sdl2.SDL_NumJoysticks()
        for index in range(count):
            PyUiLogger.get_logger().info(f"Checking index {index}")
            if sdl2.SDL_IsGameController(index):
                controller = sdl2.SDL_GameControllerOpen(index)
                if controller:
                    Controller.controller = controller
                    Controller.index = index
                    Controller.name = sdl2.SDL_GameControllerName(controller).decode()
                    Controller.mapping = sdl2.SDL_GameControllerMapping(controller).decode()
                    PyUiLogger.get_logger().info(f"Opened GameController {index}: {Controller.name}")
                    PyUiLogger.get_logger().info(f" {Controller.mapping}")

    @staticmethod
    def new_bt_device_paired():
        Controller.init_controller()

    @staticmethod
    def get_controller():
        return Controller.controller

    @staticmethod
    def close():
        if Controller.controller:
            sdl2.SDL_GameControllerClose(Controller.controller)
            Controller.controller = None

    @staticmethod
    def still_held_down():
        return sdl2.SDL_GameControllerGetButton(Controller.controller, Controller.event.cbutton.button)

    @staticmethod
    def get_input(timeout=-2):
        if timeout == -2:
            timeout = Device.input_timeout_default()

        if time.time() - Controller.last_input_time > 0.2:
            sdl2.SDL_PumpEvents()
            Controller.clear_input_queue()

        sdl2.SDL_PumpEvents()
        start_time = time.time()

        while Controller.still_held_down() and (time.time() - start_time < Controller.hold_delay):
            sdl2.SDL_PumpEvents()
            time.sleep(0.005)

        if not Controller.still_held_down():
            Controller.hold_delay = PyUiConfig.get_turbo_delay_ms()
            Controller._last_event().type = 0
            reached_timeout = False

            while not reached_timeout:
                elapsed = time.time() - start_time
                remaining_time = timeout - elapsed
                if remaining_time <= 0:
                    break

                ms_remaining = int(remaining_time * 1000)
                event_available = sdl2.SDL_WaitEventTimeout(byref(Controller.event), ms_remaining)

                if event_available and Controller.last_input() is not None:
                    break
                elif event_available and Controller._last_event().type == sdl2.SDL_CONTROLLERDEVICEADDED:
                    PyUiLogger.get_logger().info("New controller detected")
                    Controller.init_controller()
        else:
            Controller.hold_delay = 0.0

        Controller.last_input_time = time.time()
        return Controller.last_event_was_controller()

    @staticmethod
    def clear_input_queue():
        count = 0
        while count < 50:
            sdl2.SDL_PollEvent(byref(Controller.event))
            if Controller.event.cbutton.button == 0:
                count += 1
            else:
                count = 0

    @staticmethod
    def last_event_was_controller():
        return Controller._last_event().type in (
            sdl2.SDL_CONTROLLERBUTTONDOWN,
            sdl2.SDL_CONTROLLERAXISMOTION
        )

    @staticmethod
    def _last_event():
        return Controller.event

    @staticmethod
    def last_input():
        event = Controller._last_event()
        if event.type == sdl2.SDL_CONTROLLERBUTTONDOWN:
            return Device.map_digital_input(event.cbutton.button)
        elif event.type == sdl2.SDL_CONTROLLERAXISMOTION:
            return Device.map_analog_input(event.caxis.axis, event.caxis.value)
        return None

    @staticmethod
    def get_left_analog_x():
        sdl2.SDL_PumpEvents()
        return sdl2.SDL_GameControllerGetAxis(Controller.controller, sdl2.SDL_CONTROLLER_AXIS_LEFTX)

    @staticmethod
    def get_left_analog_y():
        sdl2.SDL_PumpEvents()
        return sdl2.SDL_GameControllerGetAxis(Controller.controller, sdl2.SDL_CONTROLLER_AXIS_LEFTY)

    @staticmethod
    def get_right_analog_x():
        sdl2.SDL_PumpEvents()
        return sdl2.SDL_GameControllerGetAxis(Controller.controller, sdl2.SDL_CONTROLLER_AXIS_RIGHTX)

    @staticmethod
    def get_right_analog_y():
        sdl2.SDL_PumpEvents()
        return sdl2.SDL_GameControllerGetAxis(Controller.controller, sdl2.SDL_CONTROLLER_AXIS_RIGHTY)
