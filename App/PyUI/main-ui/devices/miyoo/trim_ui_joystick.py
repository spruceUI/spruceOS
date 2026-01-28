import time
import threading

from utils.logger import PyUiLogger

class TrimUIJoystick:
    SYSTEM_SUSPEND_FLAG = "/tmp/system_suspend"
    TRIMUI_PAD_FRAME_LEN = 6  # size of struct: 6 bytes total
    TM_PLAYER_MAGIC = 0xFF     # example, replace with actual magic from your C code
    TM_PLAYER_MAGIC_END = 0xFE # example, replace with actual magic from your C code

    def __init__(self, port="/dev/ttyS1", baudrate=9600):
        self.port = port
        self.baudrate = baudrate
        self.serial = None
        self.running = False
        self.lock = threading.Lock()
        
        # latest parsed frame data
        self.axisYL = 0
        self.axisXL = 0
        self.axisYR = 0
        self.axisXR = 0
        
        self.thread = threading.Thread(target=self._poll_thread, daemon=True)
    
    def open(self):
        import serial
        self.serial = serial.Serial(
            self.port,
            self.baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=1
        )
        self.running = True
        self.thread.start()
    
    def close(self):
        self.running = False
        if self.thread.is_alive():
            self.thread.join()
        if self.serial and self.serial.is_open:
            self.serial.close()
    
    def _poll_thread(self):
        while self.running:
            # read exactly TRIMUI_PAD_FRAME_LEN bytes
            frame = self.serial.read(self.TRIMUI_PAD_FRAME_LEN)
            
            if len(frame) != self.TRIMUI_PAD_FRAME_LEN:
                # incomplete frame, skip
                continue
            
            # Check for suspend flag file
            try:
                with open(self.SYSTEM_SUSPEND_FLAG, "r"):
                    # If file exists, skip processing
                    continue
            except FileNotFoundError:
                pass
            
            # Parse frame and validate magic bytes
            magic = frame[0]
            axisYL = frame[1]
            axisXL = frame[2]
            axisYR = frame[3]
            axisXR = frame[4]
            magicEnd = frame[5]
            
            if magic != self.TM_PLAYER_MAGIC or magicEnd != self.TM_PLAYER_MAGIC_END:
                continue  # invalid frame, skip
            
            # Update values atomically
            with self.lock:
                self.axisYL = axisYL
                self.axisXL = axisXL
                self.axisYR = axisYR
                self.axisXR = axisXR
            
            # Sleep about 8ms (matches ~60Hz polling: usleep(16666/2) ~ 8333us)
            time.sleep(0.008)
    
    def get_axes(self):
        with self.lock:
            return {
                "axisYL": self.axisYL,
                "axisXL": self.axisXL,
                "axisYR": self.axisYR,
                "axisXR": self.axisXR,
            }


    def sample_axes_stats(self, duration=2.0):
        samples = {
            "axisYL": [],
            "axisXL": [],
            "axisYR": [],
            "axisXR": [],
        }

        start_time = time.time()
        #Get it going
        while time.time() - start_time < duration:
            axes = self.get_axes()

        start_time = time.time()
        while time.time() - start_time < duration:
            axes = self.get_axes()
            for axis, value in axes.items():
                samples[axis].append(value)
            #PyUiLogger.get_logger().info(axes)
            time.sleep(0.01)  # Sample every 10ms to avoid busy looping

        stats = {}
        for axis, values in samples.items():
            if values:
                stats[axis] = {
                    "min": min(values),
                    "max": max(values),
                    "avg": sum(values) / len(values),
                }
            else:
                stats[axis] = {
                    "min": None,
                    "max": None,
                    "avg": None,
                }

        return stats
