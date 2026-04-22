import os
from pathlib import Path
import sys
import threading
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller import DictKeyMappingProvider, KeyWatcherController
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.miyoo.flip.miyoo_flip_poller import MiyooFlipPoller
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.rocknix.rocknix_device import RocknixDevice
from devices.utils.process_runner import ProcessRunner
from utils import throttle
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class RocknixRgds(RocknixDevice):

    def __init__(self, device_name):
        self.device_name = device_name
        self.load_rgds_system_json()
        self.miyoo_games_file_parser = MiyooGamesFileParser("/storage/roms/")        

        super().__init__()

    def load_rgds_system_json(self):
        base_dir = os.path.abspath(sys.path[0])
        PyUiLogger.get_logger().info(f"base_dir is {base_dir}")
        self.script_dir = os.path.join(base_dir, "devices","rocknix")
        self.parent_dir = os.path.dirname(base_dir)
        source = os.path.join(self.script_dir,"rgds-system.json") 
        system_json_path = "/storage/pyui/config/rgds-system.json"
        self._load_system_config(system_json_path, Path(source))

    
    def get_controller_interface(self):
        key_mappings = {}  
        key_mappings[KeyEvent(1, 305, 0)] = [InputResult(ControllerInput.A, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 305, 1)] = [InputResult(ControllerInput.A, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 304, 0)] = [InputResult(ControllerInput.B, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 304, 1)] = [InputResult(ControllerInput.B, KeyState.PRESS)]   
        key_mappings[KeyEvent(1, 308, 0)] = [InputResult(ControllerInput.Y, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 308, 1)] = [InputResult(ControllerInput.Y, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 307, 0)] = [InputResult(ControllerInput.X, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 307, 1)] = [InputResult(ControllerInput.X, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 315, 0)] = [InputResult(ControllerInput.START, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 315, 1)] = [InputResult(ControllerInput.START, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 314, 0)] = [InputResult(ControllerInput.SELECT, KeyState.RELEASE)]   
        key_mappings[KeyEvent(1, 314, 1)] = [InputResult(ControllerInput.SELECT, KeyState.PRESS)]   

        key_mappings[KeyEvent(1, 316, 0)] = [InputResult(ControllerInput.MENU, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 316, 1)] = [InputResult(ControllerInput.MENU, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 310, 0)] = [InputResult(ControllerInput.L1, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 310, 1)] = [InputResult(ControllerInput.L1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 311, 0)] = [InputResult(ControllerInput.L2, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 311, 1)] = [InputResult(ControllerInput.L2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 317, 0)] = [InputResult(ControllerInput.L3, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 317, 1)] = [InputResult(ControllerInput.L3, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 311, 0)] = [InputResult(ControllerInput.R1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 311, 1)] = [InputResult(ControllerInput.R1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 313, 0)] = [InputResult(ControllerInput.R2, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 313, 1)] = [InputResult(ControllerInput.R2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 318, 0)] = [InputResult(ControllerInput.R3, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 318, 1)] = [InputResult(ControllerInput.R3, KeyState.PRESS)]

        key_mappings[KeyEvent(1, 544, 1)] = [InputResult(ControllerInput.DPAD_UP, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 544, 0)] = [InputResult(ControllerInput.DPAD_UP, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 545, 1)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 545, 0)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 546, 1)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 546, 0)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 547, 1)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 547, 0)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.RELEASE)]

        
        return KeyWatcherController(event_path="/dev/input/event6", mapping_provider=DictKeyMappingProvider(key_mappings))

    def get_device_name(self):
        return self.device_name

    def screen_width(self):
        return 640

    def screen_height(self):
        return 480
    
    def screen_rotation(self):
        return 0

