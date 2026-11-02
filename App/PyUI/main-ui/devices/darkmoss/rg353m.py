import threading
from pathlib import Path

from devices.darkmoss.darkmoss_device import DarkmossDevice
from utils.logger import PyUiLogger


class Rg353m(DarkmossDevice):
    """Anbernic RG353M on dArkMoss: RK3566, 640x480."""

    JOYPAD_NODE = "/dev/input/by-path/platform-singleadc-joypad-event-joystick"
    SYSTEM_JSON_NAME = "rg353m-system.json"
    # Mirrors SYSTEM_BACKLIGHT_LEVEL_0..10 in spruce/scripts/platform/RG353M.cfg.
    BACKLIGHT_TABLE = (4, 6, 10, 16, 32, 48, 64, 96, 128, 192, 255)
    MENU_KEY = 316  # BTN_MODE, the FN key the RGB30 lacks

    def __init__(self, device_name):
        super().__init__(device_name)
        event_path = self._touch_event_path()
        if event_path is None:
            PyUiLogger.get_logger().warning("RG353M touchscreen not found; touch off")
            return

        from controller.touch_watcher import TouchWatcher
        self.touch_watcher = TouchWatcher(event_path, self)
        threading.Thread(target=self.touch_watcher.poll, daemon=True).start()

    @staticmethod
    def _touch_event_path():
        for capabilities_path in sorted(Path("/sys/class/input").glob("event*/device/capabilities/abs")):
            try:
                abs_capabilities = int(capabilities_path.read_text().split()[-1], 16)
            except (OSError, ValueError, IndexError):
                continue
            if abs_capabilities & (1 << 53):
                return f"/dev/input/{capabilities_path.parents[2].name}"
        return None

    def screen_width(self):
        return 640

    def screen_height(self):
        return 480
