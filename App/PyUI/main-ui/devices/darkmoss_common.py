import os
import subprocess
import threading

from utils.logger import PyUiLogger

PANEL_DRM_TOOL = "/usr/local/bin/panel_drm_tool"
PANEL_PROPERTIES = ("brightness", "contrast", "saturation", "hue")


def darkmoss_fw_version():
    """The dArkMoss version for the About screen.

    dArkMoss stamps OS_VERSION into os-release at build time: the release tag
    when CI cut one, the build date otherwise. Images older than that stamp
    only carry the build date in dArkOS's own .VERSION file.
    """
    values = {}
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if "=" in line:
                    key, value = line.rstrip("\n").split("=", 1)
                    values[key] = value.strip('"')
    except OSError:
        return None
    if values.get("OS_NAME") != "DARKMOSS":
        return None
    version = values.get("OS_VERSION")
    if not version:
        try:
            with open("/home/ark/.config/.VERSION") as f:
                version = f.read().strip()
        except OSError:
            version = ""
    return f"dArkMoss {version}".strip() if version else "dArkMoss"



def _read_panel():
    """(card, connector, colour properties) of the connector driving the panel,
    or (None, None, empty set) when the base has no panel_drm_tool or the
    panel exposes none of them. dArkOS's panel_set.sh hard-codes 130, which is
    only the RGB30's connector."""
    try:
        out = subprocess.run([PANEL_DRM_TOOL, "list"], capture_output=True,
                             text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return None, None, frozenset()
    card = connector = None
    has_mode, props = False, set()
    for line in out.splitlines() + ["Connector: end"]:
        line = line.strip()
        if line.startswith("Card "):
            card = line.split(" ", 1)[1].strip()
        elif line.startswith("Connector:"):
            if has_mode and props:
                return panel_card, connector, frozenset(props)
            connector, has_mode, props, panel_card = line.split(":", 1)[1].strip(), False, set(), card
        elif line.startswith("mode") and connector:
            has_mode = True
        elif line.startswith("property") and "):" in line and "=" in line:
            name = line.split("):", 1)[1].split("=", 1)[0].strip()
            if name in PANEL_PROPERTIES:
                props.add(name)
    return None, None, frozenset()


class DarkmossPanelCalibration:
    """Display Settings brightness/contrast/saturation/hue on any dArkOS base,
    offered only where the panel exposes the property. PyUI stores 0-20; the
    Rockchip BSP properties run 0-100 with 50 neutral, hence the x5."""

    PANEL_SCALE = 5
    _panel = None

    def _panel_info(self):
        if DarkmossPanelCalibration._panel is None:
            DarkmossPanelCalibration._panel = _read_panel()
        return DarkmossPanelCalibration._panel

    def _set_panel(self, name, value):
        card, connector, props = self._panel_info()
        if name not in props:
            return
        try:
            subprocess.run([PANEL_DRM_TOOL, "set", card, connector, name,
                            str(value * self.PANEL_SCALE)], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=5)
        except (OSError, subprocess.SubprocessError) as e:
            PyUiLogger.get_logger().error(f"dArkMoss: setting panel {name} failed: {e}")

    def _set_brightness_to_config(self):
        self._set_panel("brightness", self.system_config.brightness)

    def _set_contrast_to_config(self):
        self._set_panel("contrast", self.system_config.contrast)

    def _set_saturation_to_config(self):
        self._set_panel("saturation", self.system_config.saturation)

    def _set_hue_to_config(self):
        self._set_panel("hue", self.system_config.hue)

    def supports_brightness_calibration(self):
        return "brightness" in self._panel_info()[2]

    def supports_contrast_calibration(self):
        return "contrast" in self._panel_info()[2]

    def supports_saturation_calibration(self):
        return "saturation" in self._panel_info()[2]

    def supports_hue_calibration(self):
        return "hue" in self._panel_info()[2]

    def _apply_panel_calibration(self):
        self._set_brightness_to_config()
        self._set_contrast_to_config()
        self._set_saturation_to_config()
        self._set_hue_to_config()

    def startup_init(self, include_wifi=True):
        threading.Thread(target=self._apply_panel_calibration, daemon=True).start()
