import threading
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller import DictKeyMappingProvider, KeyWatcherController
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.miyoo.flip.miyoo_flip_poller import MiyooFlipPoller
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.muos.muos_device import MuosDevice
from devices.utils.process_runner import ProcessRunner
from utils import throttle
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

class MuosAnbernicRGXX(MuosDevice):

    def __init__(self, device_name):
        self.device_name = device_name
        
        self.setup_system_config()


        self.miyoo_games_file_parser = MiyooGamesFileParser()        
        threading.Thread(target=self.monitor_wifi, daemon=True).start()
        self.hardware_poller = MiyooFlipPoller(self)
        threading.Thread(target=self.hardware_poller.continuously_monitor, daemon=True).start()

        #self._set_lumination_to_config()
        #self._set_contrast_to_config()
        #self._set_saturation_to_config()
        #self._set_brightness_to_config()
        #self._set_hue_to_config()
        #self._set_volume(self.system_config.get_volume())

        if(PyUiConfig.enable_button_watchers()):
            from controller.controller import Controller
            #/dev/miyooio if we want to get rid of miyoo_inputd
            # debug in terminal: hexdump  /dev/miyooio
            self.volume_key_watcher = KeyWatcher("/dev/input/event0")
            Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
            volume_key_polling_thread = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
            volume_key_polling_thread.start()
            self.power_key_watcher = KeyWatcher("/dev/input/event2")
            power_key_polling_thread = threading.Thread(target=self.power_key_watcher.poll_keyboard, daemon=True)
            power_key_polling_thread.start()
            self.controller_watcher = KeyWatcher("/dev/input/event1")
            Controller.add_button_watcher(self.controller_watcher.poll_keyboard)
            controller_watching_thread = threading.Thread(target=self.controller_watcher.poll_keyboard, daemon=True)
            controller_watching_thread.start()

        super().__init__()

    def get_controller_interface(self):
        key_mappings = {}  
        key_mappings[KeyEvent(1, 304, 0)] = [InputResult(ControllerInput.A, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 304, 1)] = [InputResult(ControllerInput.A, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 305, 0)] = [InputResult(ControllerInput.B, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 305, 1)] = [InputResult(ControllerInput.B, KeyState.PRESS)]   
        key_mappings[KeyEvent(1, 306, 0)] = [InputResult(ControllerInput.Y, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 306, 1)] = [InputResult(ControllerInput.Y, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 307, 0)] = [InputResult(ControllerInput.X, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 307, 1)] = [InputResult(ControllerInput.X, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 311, 0)] = [InputResult(ControllerInput.START, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 311, 1)] = [InputResult(ControllerInput.START, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 310, 0)] = [InputResult(ControllerInput.SELECT, KeyState.RELEASE)]   
        key_mappings[KeyEvent(1, 310, 1)] = [InputResult(ControllerInput.SELECT, KeyState.PRESS)]   

        key_mappings[KeyEvent(1, 312, 0)] = [InputResult(ControllerInput.MENU, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 312, 1)] = [InputResult(ControllerInput.MENU, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 308, 0)] = [InputResult(ControllerInput.L1, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 308, 1)] = [InputResult(ControllerInput.L1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 314, 0)] = [InputResult(ControllerInput.L2, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 314, 1)] = [InputResult(ControllerInput.L2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 313, 0)] = [InputResult(ControllerInput.L3, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 313, 1)] = [InputResult(ControllerInput.L3, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 309, 0)] = [InputResult(ControllerInput.R1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 309, 1)] = [InputResult(ControllerInput.R1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 315, 0)] = [InputResult(ControllerInput.R2, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 315, 1)] = [InputResult(ControllerInput.R2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 316, 0)] = [InputResult(ControllerInput.R3, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 316, 1)] = [InputResult(ControllerInput.R3, KeyState.PRESS)]

        key_mappings[KeyEvent(3, 17, 4294967295)] = [InputResult(ControllerInput.DPAD_UP, KeyState.PRESS)]
        key_mappings[KeyEvent(3, 17, 1)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.PRESS)]
        key_mappings[KeyEvent(3, 17, 0)] = [InputResult(ControllerInput.DPAD_UP, KeyState.RELEASE), InputResult(ControllerInput.DPAD_DOWN, KeyState.RELEASE)]
        key_mappings[KeyEvent(3, 16, 4294967295)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.PRESS)]
        key_mappings[KeyEvent(3, 16, 1)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.PRESS)]
        key_mappings[KeyEvent(3, 16, 0)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.RELEASE), InputResult(ControllerInput.DPAD_RIGHT, KeyState.RELEASE)]

        
        return KeyWatcherController(event_path="/dev/input/event1", mapping_provider=DictKeyMappingProvider(key_mappings))


    def are_headphones_plugged_in(self):
        return False
        
    def is_lid_closed(self):
        try:
            with open("/sys/class/power_supply/axp2202-battery/hallkey", "r") as f:
                value = f.read().strip()
                return "0" == value 
        except (FileNotFoundError, IOError) as e:
            return False

    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        return False
    

    def map_key(self, key_code):
        if(114 == key_code):
            return self.button_remapper.get_mappping(ControllerInput.VOLUME_DOWN)
        elif(115 == key_code):
            return self.button_remapper.get_mappping(ControllerInput.VOLUME_UP)
        elif(116 == key_code):
            return self.button_remapper.get_mappping(ControllerInput.POWER_BUTTON)
        else:
            PyUiLogger.get_logger().debug(f"Unrecognized keycode {key_code}")
            return None
        
    def capture_framebuffer(self):
        ProcessRunner.run(["dd", "if=/dev/fb0", f"of=/tmp/fb_backup.raw", "bs=4096"])

    def restore_framebuffer(self):
        ProcessRunner.run(["dd", f"if=/tmp/fb_backup.raw", "of=/dev/fb0", "bs=4096"])

    def clear_framebuffer(self):
        ProcessRunner.run(["dd", "if=/dev/zero", "of=/dev/fb0", "bs=4096"])

    def get_image_utils(self):
        return FfmpegImageUtils()

    def get_device_name(self):
        return self.device_name