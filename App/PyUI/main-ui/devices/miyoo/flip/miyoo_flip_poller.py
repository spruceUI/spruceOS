
import time
from utils.logger import PyUiLogger


class MiyooFlipPoller:
    def __init__(self, device):
        self.device = device

    def check_audio(self):
        # The headphone jack belongs to the shell: spruce/flip/mixer_watchdog.sh
        # re-applies route and gain through Flip.sh on every GPIO edge. A
        # route-only write from here landed the codec on the driver's raw
        # stored gain with nothing to correct it (SPR-MED-204, SPR-LOW-172).
        if(time.time() - self.last_run_time > 3):
            time.sleep(1) #wait for full wake up
            PyUiLogger.get_logger().info("Running fixes for sleep sound bug")
            self.device.get_device().fix_sleep_sound_bug()
        
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
