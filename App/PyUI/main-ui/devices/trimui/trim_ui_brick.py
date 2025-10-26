from pathlib import Path
import threading
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller import InputResult, KeyEvent, KeyWatcherController
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo.system_config import SystemConfig
from devices.trimui.trim_ui_device import TrimUIDevice
import sdl2
from utils import throttle

from utils.config_copier import ConfigCopier
from utils.pil_image_utils import PilImageUtils
from utils.py_ui_config import PyUiConfig

class TrimUIBrick(TrimUIDevice):
    
    def __init__(self):
        self.path = self
        self.sdl_button_to_input = {
            sdl2.SDL_CONTROLLER_BUTTON_A: ControllerInput.B,
            sdl2.SDL_CONTROLLER_BUTTON_B: ControllerInput.A,
            sdl2.SDL_CONTROLLER_BUTTON_X: ControllerInput.Y,
            sdl2.SDL_CONTROLLER_BUTTON_Y: ControllerInput.X,
            sdl2.SDL_CONTROLLER_BUTTON_GUIDE: ControllerInput.MENU,
            sdl2.SDL_CONTROLLER_BUTTON_DPAD_UP: ControllerInput.DPAD_UP,
            sdl2.SDL_CONTROLLER_BUTTON_DPAD_DOWN: ControllerInput.DPAD_DOWN,
            sdl2.SDL_CONTROLLER_BUTTON_DPAD_LEFT: ControllerInput.DPAD_LEFT,
            sdl2.SDL_CONTROLLER_BUTTON_DPAD_RIGHT: ControllerInput.DPAD_RIGHT,
            sdl2.SDL_CONTROLLER_BUTTON_LEFTSHOULDER: ControllerInput.L1,
            sdl2.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: ControllerInput.R1,
            sdl2.SDL_CONTROLLER_BUTTON_LEFTSTICK: ControllerInput.L3,
            sdl2.SDL_CONTROLLER_BUTTON_RIGHTSTICK: ControllerInput.R3,
            sdl2.SDL_CONTROLLER_BUTTON_START: ControllerInput.START,
            sdl2.SDL_CONTROLLER_BUTTON_BACK: ControllerInput.SELECT,
        }

        script_dir = Path(__file__).resolve().parent
        source = script_dir / 'brick-system.json'
        ConfigCopier.ensure_config("/mnt/SDCARD/Saves/brick-system.json", source)
        self.system_config = SystemConfig("/mnt/SDCARD/Saves/brick-system.json")


        self.miyoo_games_file_parser = MiyooGamesFileParser()        
        self._set_lumination_to_config()
        self._set_contrast_to_config()
        self._set_saturation_to_config()
        self._set_brightness_to_config()
        self._set_hue_to_config()
        self.ensure_wpa_supplicant_conf()
        threading.Thread(target=self.monitor_wifi, daemon=True).start()
        if(PyUiConfig.enable_button_watchers()):
            from controller.controller import Controller
            #/dev/miyooio if we want to get rid of miyoo_inputd
            # debug in terminal: hexdump  /dev/miyooio
            self.volume_key_watcher = KeyWatcher("/dev/input/event3")
            Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
            volume_key_polling_thread = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
            volume_key_polling_thread.start()
            self.power_key_watcher = KeyWatcher("/dev/input/event1")
            power_key_polling_thread = threading.Thread(target=self.power_key_watcher.poll_keyboard, daemon=True)
            power_key_polling_thread.start()
            
        config_volume = self.system_config.get_volume()
        self._set_volume(config_volume)
        super().__init__()
            
    #Untested
    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        return False

    def should_scale_screen(self):
        return self.is_hdmi_connected()

    @property
    def screen_width(self):
        return 1024

    @property
    def screen_height(self):
        return 768
    
    
    @property
    def output_screen_width(self):
        return 1920

    @property
    def output_screen_height(self):
        return 1080

    def get_scale_factor(self):
        if(self.is_hdmi_connected()):
            return 2.25
        else:
            return 1
        
    def supports_brightness_calibration(self):
        return True

    def supports_contrast_calibration(self):
        return True

    def supports_saturation_calibration(self):
        return True

    def supports_hue_calibration(self):
        return True

    def get_image_utils(self):
        return PilImageUtils()


    def get_controller_interface(self):
        key_mappings = {}  
        key_mappings[KeyEvent(1, 304, 0)] = [InputResult(ControllerInput.B, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 304, 1)] = [InputResult(ControllerInput.B, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 305, 0)] = [InputResult(ControllerInput.A, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 305, 1)] = [InputResult(ControllerInput.A, KeyState.PRESS)]   
        key_mappings[KeyEvent(1, 306, 0)] = [InputResult(ControllerInput.X, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 306, 1)] = [InputResult(ControllerInput.X, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 307, 0)] = [InputResult(ControllerInput.Y, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 307, 1)] = [InputResult(ControllerInput.Y, KeyState.PRESS)]  


        key_mappings[KeyEvent(3, 17, 4294967295)] = [InputResult(ControllerInput.DPAD_UP, KeyState.PRESS)]
        key_mappings[KeyEvent(3, 17, 1)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.PRESS)]
        key_mappings[KeyEvent(3, 17, 0)] = [InputResult(ControllerInput.DPAD_UP, KeyState.RELEASE), InputResult(ControllerInput.DPAD_DOWN, KeyState.RELEASE)]
        key_mappings[KeyEvent(3, 16, 4294967295)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.PRESS)]
        key_mappings[KeyEvent(3, 16, 1)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.PRESS)]
        key_mappings[KeyEvent(3, 16, 0)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.RELEASE), InputResult(ControllerInput.DPAD_RIGHT, KeyState.RELEASE)]


        key_mappings[KeyEvent(1, 311, 0)] = [InputResult(ControllerInput.R1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 311, 1)] = [InputResult(ControllerInput.R1, KeyState.PRESS)]  
        key_mappings[KeyEvent(3, 5, 0)] = [InputResult(ControllerInput.R2, KeyState.RELEASE)]  
        key_mappings[KeyEvent(3, 5, 255)] = [InputResult(ControllerInput.R2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 310, 0)] = [InputResult(ControllerInput.L1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 310, 1)] = [InputResult(ControllerInput.L1, KeyState.PRESS)]  
        key_mappings[KeyEvent(3, 2, 0)] = [InputResult(ControllerInput.L2, KeyState.RELEASE)]  
        key_mappings[KeyEvent(3, 2, 255)] = [InputResult(ControllerInput.L2, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 316, 0)] = [InputResult(ControllerInput.MENU, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 316, 1)] = [InputResult(ControllerInput.MENU, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 315, 0)] = [InputResult(ControllerInput.START, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 315, 1)] = [InputResult(ControllerInput.START, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 314, 0)] = [InputResult(ControllerInput.SELECT, KeyState.RELEASE)]   
        key_mappings[KeyEvent(1, 314, 1)] = [InputResult(ControllerInput.SELECT, KeyState.PRESS)]   

        return KeyWatcherController(event_path="/dev/input/event3", key_mappings=key_mappings)