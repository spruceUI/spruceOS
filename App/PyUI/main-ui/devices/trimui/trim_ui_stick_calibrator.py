import fcntl
import math
import os
import struct
import time

from menus.language.language import Language
from utils.logger import PyUiLogger


class TrimUIStickCalibrator:
    LEFT_CONFIG = "/mnt/UDISK/joypad.config"
    RIGHT_CONFIG = "/mnt/UDISK/joypad_right.config"
    CAL_UPDATE_FLAG = "/tmp/trimui_inputd/cal_update"

    # Centre at 1 puts every reading on the positive side, so raw = |axis| * 4094 / 32760 + 1
    # whatever sign inputd emits the axis with. A zero equal to min or max makes inputd use its defaults.
    MEASURE_VALUES = {"x_min": 0, "x_max": 4095, "y_min": 0, "y_max": 4095, "x_zero": 1, "y_zero": 1, "deadzone": "0.01"}
    AXIS_RANGE = 32760
    RAW_SPAN = 4094

    EVIOCGABS = 0x80184540
    ABS_X, ABS_Y, ABS_RX, ABS_RY = 0, 1, 3, 4

    ROTATE_SECONDS = 10
    RELEASE_SECONDS = 5
    SETTLE_SECONDS = 1
    SAMPLE_INTERVAL = 0.01
    MIN_RAW_RANGE = 1000
    MIN_CENTER_MARGIN = 100

    def __init__(self, event_path, apply_config):
        self.event_path = event_path
        self.apply_config = apply_config
        self.sticks = [
            (self.LEFT_CONFIG, self.ABS_X, self.ABS_Y,
             Language.label("rotateLeftStick", "Rotate the left stick in full circles"),
             Language.label("releaseLeftStick", "Let go of the left stick")),
            (self.RIGHT_CONFIG, self.ABS_RX, self.ABS_RY,
             Language.label("rotateRightStick", "Rotate the right stick in full circles"),
             Language.label("releaseRightStick", "Let go of the right stick")),
        ]

    def run(self):
        from controller.controller import Controller
        from controller.controller_inputs import ControllerInput
        from display.display import Display

        Display.display_message_multiline([
            Language.calibrate_analog_sticks(),
            Language.label("stickCalibrationStart", "Press A to start, B to cancel"),
        ])
        if Controller.wait_for_input([ControllerInput.A, ControllerInput.B]) != ControllerInput.A:
            return

        backups = {path: self._read(path) for path, *_ in self.sticks}
        try:
            for path, *_ in self.sticks:
                self._write(path, self._merge(backups[path], self.MEASURE_VALUES))
            self.apply_config()

            results = {path: self._measure_stick(*stick) for path, *stick in self.sticks}

            for path, *_ in self.sticks:
                self._write(path, self._merge(backups[path], results[path]))
            self.apply_config()
            PyUiLogger.get_logger().info(f"Stick calibration saved: {results}")
            message = Language.label("stickCalibrationSaved", "Stick calibration saved")
        except Exception as e:
            PyUiLogger.get_logger().exception(f"Stick calibration failed: {e}")
            self._restore(backups)
            message = Language.label("stickCalibrationFailed", "Stick calibration failed, previous calibration kept")

        Controller.clear_input_queue()
        Display.display_message(message, 2000)

    def _measure_stick(self, x_code, y_code, rotate_message, release_message):
        fd = self._open_pad()
        try:
            xs, ys = [], []
            self._countdown(rotate_message, self.ROTATE_SECONDS, fd, x_code, y_code, xs, ys)
            center_xs, center_ys = [], []
            self._countdown(release_message, self.RELEASE_SECONDS, fd, x_code, y_code, center_xs, center_ys,
                            sample_after=self.SETTLE_SECONDS)
        finally:
            os.close(fd)

        result = {
            "x_min": round(min(xs)), "x_max": round(max(xs)),
            "y_min": round(min(ys)), "y_max": round(max(ys)),
            "x_zero": round(sum(center_xs) / len(center_xs)),
            "y_zero": round(sum(center_ys) / len(center_ys)),
        }
        for axis in ("x", "y"):
            low, high, zero = result[f"{axis}_min"], result[f"{axis}_max"], result[f"{axis}_zero"]
            if high - low < self.MIN_RAW_RANGE or not (low + self.MIN_CENTER_MARGIN < zero < high - self.MIN_CENTER_MARGIN):
                raise ValueError(f"implausible {axis} axis on {self.event_path}: {result}")
        return result

    def _countdown(self, message, seconds, fd, x_code, y_code, xs, ys, sample_after=0):
        from display.display import Display

        end = time.monotonic() + seconds
        shown = None
        while (remaining := end - time.monotonic()) > 0:
            if math.ceil(remaining) != shown:
                shown = math.ceil(remaining)
                Display.display_message_multiline([message, str(shown)])
            # Skip the moment the stick is springing back to centre
            if seconds - remaining >= sample_after:
                xs.append(self._raw(fd, x_code))
                ys.append(self._raw(fd, y_code))
            time.sleep(self.SAMPLE_INTERVAL)

    def _raw(self, fd, code):
        absinfo = bytearray(24)
        fcntl.ioctl(fd, self.EVIOCGABS + code, absinfo)
        value = struct.unpack_from("i", absinfo)[0]
        return abs(value) * self.RAW_SPAN / self.AXIS_RANGE + 1

    def _open_pad(self):
        # The Smart Pro recreates the pad when inputd restarts, so give it a moment to come back.
        deadline = time.monotonic() + 5
        while True:
            fd = None
            try:
                fd = os.open(self.event_path, os.O_RDONLY | os.O_NONBLOCK)
                self._raw(fd, self.ABS_X)
                return fd
            except OSError:
                if fd is not None:
                    os.close(fd)
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.2)

    def _restore(self, backups):
        try:
            for path, text in backups.items():
                if text is None:
                    if os.path.exists(path):
                        os.remove(path)
                else:
                    self._write(path, text)
            self.apply_config()
        except Exception as e:
            PyUiLogger.get_logger().exception(f"Restoring stick calibration failed: {e}")

    @staticmethod
    def _read(path):
        try:
            with open(path, "r") as f:
                return f.read()
        except FileNotFoundError:
            return None

    @staticmethod
    def _write(path, text):
        with open(path, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())

    @staticmethod
    def _merge(original_text, values):
        lines, seen = [], set()
        for line in (original_text or "").splitlines():
            key = line.split("=", 1)[0].strip()
            if key in values:
                lines.append(f"{key}={values[key]}")
                seen.add(key)
            elif line.strip():
                lines.append(line.strip())
        lines.extend(f"{key}={value}" for key, value in values.items() if key not in seen)
        return "\n".join(lines) + "\n"

    @classmethod
    def reload_via_cal_update(cls):
        os.makedirs(os.path.dirname(cls.CAL_UPDATE_FLAG), exist_ok=True)
        open(cls.CAL_UPDATE_FLAG, "a").close()
        deadline = time.monotonic() + 5
        while os.path.exists(cls.CAL_UPDATE_FLAG):
            if time.monotonic() > deadline:
                raise TimeoutError("trimui_inputd did not pick up cal_update")
            time.sleep(0.1)
        time.sleep(0.3)
