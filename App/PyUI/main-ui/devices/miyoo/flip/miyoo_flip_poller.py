
import time
from utils.logger import PyUiLogger
from devices.utils.process_runner import ProcessRunner

class MiyooFlipPoller:
    def __init__(self, device):
        self.device = device
        self.headphone_status = None

    def check_audio(self):
        try:
            new_headphone_status = self.device.get_device().are_headphones_plugged_in()
            if(new_headphone_status != self.headphone_status):
                self.headphone_status = new_headphone_status
                if(self.headphone_status):
                    ProcessRunner.run(["amixer","sset","Playback Path","HP"])
                else:
                    ProcessRunner.run(["amixer","sset","Playback Path","SPK"])
        except:
            pass
        
    def check_lid(self):
        try:
            if(self.device.get_device().is_lid_closed()):
                self.device.get_device().sleep()
                time.sleep(1) #ensure sleep occurs
                time.sleep(1) #give time on wakeup
                self.device.get_device().fix_sleep_sound_bug()

        except:
            pass

    def continuously_monitor(self):
        self.last_run_time = time.time()
        while(True):
            self.check_audio()
            self.check_lid()
            self.last_run_time = time.time()
            time.sleep(1)  # Sleep for 1 second
