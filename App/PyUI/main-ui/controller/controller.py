import time
from controller.controller_inputs import ControllerInput
from devices.device import Device

from themes.theme import Theme
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class Controller:
    controller = None
    index = None
    name = None
    mapping = None
    last_input_time = 0
    hold_delay = 0
    additional_button_watchers = []
    is_check_for_hotkey = False
    non_sdl_input = None
    hold_buttons = {ControllerInput.POWER_BUTTON}
    #Used to track certain inputs
    last_press_time_map = {}
    special_non_sdl_event = False
    render_required_callback = None
    last_controller_input = None
    _input_history = []
    gs_triggered = False
    first_check_after_gs_triggered = False
    controller_interface = None
    _watch_for_secret_code = False

    # The sequence we want to detect
    _SECRET_CODE = [
        ControllerInput.DPAD_UP,
        ControllerInput.DPAD_UP,
        ControllerInput.DPAD_DOWN,
        ControllerInput.DPAD_DOWN,
        ControllerInput.DPAD_LEFT,
        ControllerInput.DPAD_RIGHT,
        ControllerInput.DPAD_LEFT,
        ControllerInput.DPAD_RIGHT,
        ControllerInput.B,
        ControllerInput.A,
        ControllerInput.START,
        ControllerInput.SELECT,
    ]
    _SECRET_CODE_PREFIX = [
        ControllerInput.DPAD_UP,
        ControllerInput.DPAD_UP,
        ControllerInput.DPAD_DOWN,
        ControllerInput.DPAD_DOWN,
        ControllerInput.DPAD_LEFT,
        ControllerInput.DPAD_RIGHT,
        ControllerInput.DPAD_LEFT,
        ControllerInput.DPAD_RIGHT,
        ControllerInput.B,
        ControllerInput.A,
    ]


    @staticmethod
    def init():
        Controller.controller_interface = Device.get_device().get_controller_interface()
        Controller._watch_for_secret_code = Device.get_device().get_system_config().game_selection_only_mode_enabled() or Device.get_device().get_system_config().simple_mode_enabled()

    @staticmethod
    def init_controller():
        Controller.controller_interface.init_controller()


    @staticmethod
    def re_init_controller():
        Controller.controller_interface.re_init_controller()

    @staticmethod
    def new_bt_device_paired():
        Controller.re_init_controller()

    @staticmethod
    def close():
        Controller.controller_interface.close()

    @staticmethod
    def still_held_down():
        return Controller.controller_interface.still_held_down()

    @staticmethod
    def clear_last_input():
        #if(Controller.last_controller_input is not None):
        #    PyUiLogger.get_logger().info(f"Clearing last input")
        Controller.last_controller_input = None
        Controller.controller_interface.clear_input()

    @staticmethod
    def _matches_secret_prefix():
        h = Controller._input_history
        p = Controller._SECRET_CODE_PREFIX
        plen = len(p)

        if len(h) < plen:
            return False

        return h[-plen:] == p     
       
    @staticmethod
    def set_last_input(last_input):
        if(last_input == ControllerInput.LEFT_STICK_UP):
            last_input = ControllerInput.DPAD_UP
        elif(last_input == ControllerInput.LEFT_STICK_DOWN):
            last_input = ControllerInput.DPAD_DOWN
        elif(last_input == ControllerInput.LEFT_STICK_LEFT):
            last_input = ControllerInput.DPAD_LEFT
        elif(last_input == ControllerInput.LEFT_STICK_RIGHT):
            last_input = ControllerInput.DPAD_RIGHT

        Controller.last_controller_input = last_input

        if(Controller._watch_for_secret_code and last_input is not None):
            if(Controller._matches_secret_prefix() and Controller.last_controller_input == ControllerInput.A):
                PyUiLogger().get_logger().info(f"Prefix matched so blocking A press")
                Controller.last_controller_input = None
                return

            # Add input to history
            Controller._input_history.append(last_input)

            # Keep history trimmed to the length of the code
            max_len = len(Controller._SECRET_CODE)
            if len(Controller._input_history) > max_len:
                Controller._input_history.pop(0)

            # Check for match
            if Controller._input_history == Controller._SECRET_CODE:
                PyUiLogger().get_logger().info(f"Secret code entered")
                Device.get_device().get_system_config().set_game_selection_only_mode_enabled(False)
                Device.get_device().get_system_config().set_simple_mode_enabled(False)
                Device.get_device().exit_pyui()


            if(Controller._matches_secret_prefix()):
                PyUiLogger().get_logger().info(f"Prefix matched so blocking A press")
                Controller.last_controller_input = None


    @staticmethod
    def get_input(timeout=-2, called_from_check_for_hotkey=False):
        if(Controller.first_check_after_gs_triggered):
            #Let user stop holding menu
            Controller.first_check_after_gs_triggered = False
            time.sleep(0.3)
        DEFAULT_TIMEOUT_FLAG = -2
        INPUT_DEBOUNCE_SECONDS = 0.2
        POLL_INTERVAL_SECONDS = 0.005

        #if(Controller.last_controller_input is not None):
        #    PyUiLogger.get_logger().info(f"Controller.last_controller_input = {Controller.last_controller_input}")

        if(Controller.render_required_callback is not None):
            callback = Controller.render_required_callback
            Controller.render_required_callback = None
            callback()

        if timeout == DEFAULT_TIMEOUT_FLAG:
            timeout = Device.get_device().input_timeout_default()

        now = time.time()
        time_since_last_input = now - Controller.last_input_time

        # Clear stale events if enough time has passed
        if time_since_last_input > INPUT_DEBOUNCE_SECONDS:
            Controller.controller_interface.force_refresh()
            if not Controller.still_held_down():
                Controller.clear_input_queue()

        Controller.controller_interface.force_refresh()
        start_time = time.time()

        # Wait if the input is being held down (anti-repeat logic)
        while Controller.still_held_down() and (time.time() - start_time < Controller.hold_delay):
            Controller.controller_interface.force_refresh()
            time.sleep(POLL_INTERVAL_SECONDS)

        was_hotkey = False
        started_held_down = Controller.still_held_down()
        if not Controller.still_held_down():
            #if(Controller.last_controller_input is not None):
            #    PyUiLogger.get_logger().info(f"Controller input is not longer held down")
            # Reset hold delay and clear any lingering event
            Controller.hold_delay = PyUiConfig.get_turbo_delay_ms()

            # Blocking wait for event until timeout
            elapsed = time.time() - start_time
            remaining_time = timeout - elapsed
            remaining_time = max(remaining_time, 0.001)
            while True:

                ms_remaining = int(remaining_time * 1000)
                input = Controller.controller_interface.get_input(ms_remaining)
                Controller.set_last_input(input)

                if Controller.last_controller_input is not None:
                    Theme.controller_button_pressed(Controller.last_controller_input)
                    if Controller.last_controller_input == ControllerInput.MENU:
                        if not Controller.is_check_for_hotkey and not called_from_check_for_hotkey and not Controller.check_for_hotkey():
                            Controller.set_last_input(ControllerInput.MENU)
                            break  # Treat MENU as valid input
                        else:
                            was_hotkey = True
                            while Controller.still_held_down() and not called_from_check_for_hotkey:
                                Controller.check_for_hotkey()
                    else:
                        break  # Valid non-hotkey input
                elapsed = time.time() - start_time
                remaining_time = timeout - elapsed
                if remaining_time <= 0:
                    break


        #TODO i think this loop is in the wrong place
        # Wait if the input is being held down (anti-repeat logic)
        while started_held_down and Controller.still_held_down() and (time.time() - start_time < Controller.hold_delay):
            Controller.controller_interface.force_refresh()
            time.sleep(POLL_INTERVAL_SECONDS)

        if Controller.still_held_down():
            if(ControllerInput.MENU == Controller.last_input()):
                was_hotkey = called_from_check_for_hotkey or Controller.check_for_hotkey()
                if(not was_hotkey and not Controller.gs_triggered and Controller.allow_pyui_game_switcher()):
                    Controller.gs_triggered = True
                    Controller.first_check_after_gs_triggered = True
                    from menus.games.recents_menu_gs import RecentsMenuGS
                    Controller.clear_last_input()
                    PyUiLogger.get_logger().info("Starting GS().run_rom_selection()")
                    RecentsMenuGS().run_rom_selection()
                    Controller.clear_last_input()
                    Controller.gs_triggered = False
            elif(started_held_down):
                #if(Controller.last_controller_input is not None):
                #    PyUiLogger.get_logger().info(f"Controller input held down but isn't menu")
                Controller.hold_delay = Device.get_device().get_system_config().get_input_rate_limit_ms() / 1000

        Controller.last_input_time = time.time()
        #if(Controller.last_controller_input is not None):
        #    PyUiLogger.get_logger().info(f"returning last_controller_input as: {Controller.last_controller_input}")

        return Controller.last_controller_input is not None and not was_hotkey

    @staticmethod
    def allow_pyui_game_switcher():
        return PyUiConfig.allow_pyui_game_switcher() and Device.get_device().get_system_config().game_switcher_enabled()

    @staticmethod
    def clear_input_queue():
        Controller.controller_interface.clear_input_queue()

    @staticmethod
    def last_input():
        #if(Controller.last_controller_input is not None):
        #    PyUiLogger.get_logger().info(f"Returning last input: {Controller.last_controller_input}")
        return Controller.last_controller_input

    @staticmethod 
    def add_button_watcher(button_watcher):
        Controller.additional_button_watchers.append(button_watcher)

    #return TRUE if it was a hotkey press, FALSE otherwise
    @staticmethod
    def check_for_hotkey():
        Controller.is_check_for_hotkey = True
        cached_event = Controller.last_controller_input
        Controller.controller_interface.cache_last_event()
        Controller.clear_last_input()

        was_hotkey = False
        start_time = time.time()

        while(not was_hotkey and time.time() - start_time < 0.3):
            if(Controller.get_input(timeout=0.05, called_from_check_for_hotkey=True)):
                Controller.perform_hotkey(Controller.last_input())
                time.sleep(0.1)
                was_hotkey = True 
            elif(Controller.non_sdl_input is not None):
                was_hotkey = True 
                Controller.perform_hotkey(Controller.non_sdl_input)
                time.sleep(0.1)

        Controller.non_sdl_input = None
        Controller.set_last_input(cached_event)
        Controller.controller_interface.restore_cached_event()
        Controller.is_check_for_hotkey = False
        return was_hotkey
    
    @staticmethod
    def perform_hotkey(controller_input):
        PyUiLogger.get_logger().info(f"Performing hotkey for {controller_input}")
        #TODO where to let these be user definable
        if(ControllerInput.VOLUME_UP == controller_input):
            Device.get_device().raise_lumination()
        elif(ControllerInput.VOLUME_DOWN == controller_input):
            Device.get_device().lower_lumination()
        
    @staticmethod
    def non_sdl_input_event(controller_input, is_down):
        TRIGGER_TIME_FOR_HOLD_BUTTONS = 2

        if(is_down):
            if(controller_input in Controller.hold_buttons):
                if controller_input not in Controller.last_press_time_map:
                    Controller.last_press_time_map[controller_input] = time.time()   
                else:
                    last_press_time_length = time.time() - Controller.last_press_time_map[controller_input]
                    if(last_press_time_length > TRIGGER_TIME_FOR_HOLD_BUTTONS):
                        PyUiLogger.get_logger().info(f"Starting special non sdl event : {controller_input}")
                        Controller.special_non_sdl_event = True
                        Controller.render_required_callback = lambda ci=controller_input, lpt=last_press_time_length: Device.get_device().special_input(ci, lpt)
                        Controller.non_sdl_input = None
                        Controller.special_non_sdl_event = False
                        PyUiLogger.get_logger().info(f"Ending special non sdl event : {controller_input}")

            else:
                if(not Controller.is_check_for_hotkey):
                    Device.get_device().special_input(controller_input, 0)
                else:
                    Controller.non_sdl_input = controller_input
        elif(not is_down):
            Controller.non_sdl_input = None
            if(controller_input in Controller.hold_buttons):
                last_press_time_length = time.time() - Controller.last_press_time_map[controller_input]
                if(last_press_time_length < TRIGGER_TIME_FOR_HOLD_BUTTONS):
                    Device.get_device().special_input(controller_input, 0)

            Controller.last_press_time_map.pop(controller_input,None)

    @staticmethod
    def wait_for_input(wanted_inputs):
        last_input = None
        Controller.clear_last_input()
        while(last_input not in wanted_inputs):
            Controller.get_input()
            last_input = Controller.last_input()

        PyUiLogger.get_logger().debug(f"Input was : {last_input}")

        return last_input