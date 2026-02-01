
import time


class AnbernicPoller:
    def __init__(self, device):
        self.headphone_status = None
        self.device = device

    def check_audio(self):
        pass
        
    def check_lid(self):
        pass

    def continuously_monitor(self):
        self.last_run_time = time.time()
        while(True):
            self.check_audio()
            self.check_lid()
            self.last_run_time = time.time()
            time.sleep(1)  # Sleep for 1 second
