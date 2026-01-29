import subprocess
from pathlib import Path

from devices.utils.process_runner import ProcessRunner
from utils.logger import PyUiLogger

class MiyooMiniFlipSharedMemoryWriter:
    MONITOR_VOLUME = 0
    MONITOR_BRIGHTNESS = 1
    MONITOR_KEYMAP = 2
    MONITOR_MUTE = 3
    MONITOR_VOLUME_CHANGED = 4
    MONITOR_BGM_VOLUME = 5
    MONITOR_HIBERNATE_DELAY = 6
    MONITOR_ADC_VALUE = 7
    MONITOR_LUMINATION = 8
    MONITOR_HUE = 9
    MONITOR_SATURATION = 10
    MONITOR_CONTRAST = 11
    MONITOR_UNUSED = 12
    MONITOR_AUDIOFIX = 13

    def __init__(self):
        script_dir = Path(__file__).resolve().parent
        self.shared_memory_executable = script_dir / 'set_shared_memory'

    def _set_value(self, key: int, value: int):
        """Internal helper to call the binary."""
        try:
            ProcessRunner.run(
                [str(self.shared_memory_executable), str(key), str(value)]
            )
        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Failed to set shared memory key {key} to {value}: {e}")

    # Convenience methods
    def set_volume(self, value: int):
        self._set_value(self.MONITOR_VOLUME, value)

    def set_brightness(self, value: int):
        self._set_value(self.MONITOR_BRIGHTNESS, value)

    def set_keymap(self, value: int):
        self._set_value(self.MONITOR_KEYMAP, value)

    def set_mute(self, value: int):
        self._set_value(self.MONITOR_MUTE, value)

    def set_volume_changed(self, value: int):
        self._set_value(self.MONITOR_VOLUME_CHANGED, value)

    def set_bgm_volume(self, value: int):
        self._set_value(self.MONITOR_BGM_VOLUME, value)

    def set_hibernate_delay(self, value: int):
        self._set_value(self.MONITOR_HIBERNATE_DELAY, value)

    def set_adc_value(self, value: int):
        self._set_value(self.MONITOR_ADC_VALUE, value)

    def set_lumination(self, value: int):
        self._set_value(self.MONITOR_LUMINATION, value)

    def set_hue(self, value: int):
        self._set_value(self.MONITOR_HUE, value)

    def set_saturation(self, value: int):
        self._set_value(self.MONITOR_SATURATION, value)

    def set_contrast(self, value: int):
        self._set_value(self.MONITOR_CONTRAST, value)

    def set_unused(self, value: int):
        self._set_value(self.MONITOR_UNUSED, value)

    def set_audiofix(self, value: int):
        self._set_value(self.MONITOR_AUDIOFIX, value)
