
import time
from devices.device import Device
from devices.utils.process_runner import ProcessRunner


class MiyooFlipPoller:
    def __init__(self, device):
        self.headphone_status = None
        self.device = device

    def check_audio(self):
        try:
            new_headphone_status = self.device.are_headphones_plugged_in()
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
            if(self.device.is_lid_closed()):
                self.device.sleep()
        except:
            pass

    def continuously_monitor(self):
        while(True):
            self.check_audio()
            self.check_lid()
            time.sleep(1)  # Sleep for 1 second
