import json
import os
import shutil
import subprocess
import time

from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from display.display import Display
from menus.language.language import Language
from menus.apps.trimui_input_helpers import TrimuiInputHelpers
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType

FN_EDITOR_DIR = "/mnt/SDCARD/App/fn_editor"
STOCK_FN_EDITOR_DIR = "/usr/trimui/apps/fn_editor"
SCENE_DIR = "/usr/trimui/scene"
GPIO363_VALUE = "/sys/class/gpio/gpio363/value"
THERMAL_PROFILE = "/mnt/SDCARD/spruce/smartpros/etc/thermal-watchdog/active_profile"
CPU4_DIR = "/sys/devices/system/cpu/cpu4/cpufreq"
FAN_STATE = "/sys/class/thermal/cooling_device0/cur_state"


class TrimuiFnSettingsApp:
    """PyUI menu for the stock TrimUI function-key scene settings."""

    def run(self, _input=None):
        while True:
            selected = Selection(None, None, 0)
            options = self._build_options()
            view = ViewCreator.create_view(
                view_type=ViewType.ICON_AND_DESC,
                top_bar_text=Language.get("fnKeySettings", "Fn Key Settings"),
                options=options,
                selected_index=selected.get_index(),
            )
            while selected is not None:
                picked = view.get_selection(
                    [
                        ControllerInput.A,
                        ControllerInput.B,
                        ControllerInput.DPAD_LEFT,
                        ControllerInput.DPAD_RIGHT,
                        ControllerInput.L1,
                        ControllerInput.R1,
                    ]
                )
                if picked.get_input() == ControllerInput.B:
                    return
                if picked.get_input() in (
                    ControllerInput.A,
                    ControllerInput.DPAD_LEFT,
                    ControllerInput.DPAD_RIGHT,
                    ControllerInput.L1,
                    ControllerInput.R1,
                ):
                    picked.get_selection().get_value()(picked.get_input())
                    options = self._build_options()
                    view.set_options(options)

    def _build_options(self):
        return [
            GridOrListEntry(
                primary_text=Language.get("functionKeyActions", "Function key actions"),
                value_text=None,
                image_path=None,
                image_path_selected=None,
                description=Language.get("functionKeyActionsDesc", "Stock TrimUI actions for the hardware switch"),
                icon=None,
                value=self._switch_actions_menu,
            ),
            GridOrListEntry(
                primary_text=Language.get("joystickMode", "Joystick mode"),
                value_text="<    " + ("On" if TrimuiInputHelpers.is_joystick_mode() else "Off") + "    >",
                image_path=None,
                image_path_selected=None,
                description=Language.get("joystickModeDesc", "D-pad as left stick"),
                icon=None,
                value=self._toggle_joystick,
            ),
            GridOrListEntry(
                primary_text=Language.get("fnDiagnostics", "Diagnostics"),
                value_text=self._dip_state_label(),
                image_path=None,
                image_path_selected=None,
                description=Language.get("fnDiagnosticsDesc", "Fn switch, CPU, fan, and scene status"),
                icon=None,
                value=self._show_diagnostics,
            ),
        ]

    def _switch_actions_menu(self, _input):
        scripts = self._load_scripts("scripts.json")
        if not scripts:
            return
        selected = Selection(None, None, 0)
        options = self._build_switch_options(scripts)
        view = ViewCreator.create_view(
            view_type=ViewType.ICON_AND_DESC,
                top_bar_text=Language.get("dipSwitchActions", "DIP switch actions"),
            options=options,
            selected_index=selected.get_index(),
        )
        while True:
            picked = view.get_selection([ControllerInput.A, ControllerInput.B])
            if picked.get_input() == ControllerInput.B:
                return
            if picked.get_input() == ControllerInput.A:
                picked.get_selection().get_value()(picked.get_input())
                Controller.clear_input_queue()
                time.sleep(0.25)
                options = self._build_switch_options(scripts)
                view.set_options(options)

    def _build_switch_options(self, scripts):
        options = []
        for entry in scripts:
            active = self._is_scene_script_enabled(entry)
            options.append(
                GridOrListEntry(
                    primary_text=entry.get("name", entry.get("launch", "?")),
                    value_text="On" if active else "Off",
                    image_path=None,
                    image_path_selected=None,
                    description=entry.get("launch"),
                    icon=None,
                    value=lambda _input, script=entry: self._toggle_scene_script(script),
                )
            )
        return options

    def _toggle_joystick(self, input_value):
        if input_value in (ControllerInput.DPAD_LEFT, ControllerInput.L1):
            TrimuiInputHelpers.set_joystick_mode(False)
        elif input_value in (ControllerInput.DPAD_RIGHT, ControllerInput.R1, ControllerInput.A):
            TrimuiInputHelpers.set_joystick_mode(True)

    def _show_diagnostics(self, _input):
        lines = [
            Language.get("fnDiagnostics", "Diagnostics"),
            f"DIP: {self._read_file(GPIO363_VALUE, '?')}",
            f"Thermal: {self._read_file(THERMAL_PROFILE, '?')}",
            f"Fan: {self._read_file(FAN_STATE, '?')}",
            f"CPU4: {self._cpu4_summary()}",
            f"Scenes: {self._scene_summary()}",
            f"CPU scene: {self._process_count('com.trimui.cpuperformance.sh')}",
        ]
        Display.display_message("\n".join(lines), duration_ms=7000)

    def _dip_state_label(self):
        state = self._read_file(GPIO363_VALUE, "?")
        if state == "1":
            return "On"
        if state == "0":
            return "Off"
        return state

    def _read_file(self, path, default=""):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read().strip() or default
        except Exception:
            return default

    def _cpu4_summary(self):
        governor = self._read_file(os.path.join(CPU4_DIR, "scaling_governor"), "?")
        min_freq = self._read_file(os.path.join(CPU4_DIR, "scaling_min_freq"), "?")
        max_freq = self._read_file(os.path.join(CPU4_DIR, "scaling_max_freq"), "?")
        cur_freq = self._read_file(os.path.join(CPU4_DIR, "scaling_cur_freq"), "?")
        return f"{governor} {min_freq}-{max_freq} ({cur_freq})"

    def _scene_summary(self):
        try:
            names = sorted(name for name in os.listdir(SCENE_DIR) if name.endswith(".sh"))
        except Exception:
            return "?"
        if not names:
            return "None"
        return ", ".join(names[:3]) + ("..." if len(names) > 3 else "")

    def _process_count(self, pattern):
        try:
            output = subprocess.check_output(["pgrep", "-f", pattern], stderr=subprocess.DEVNULL, text=True)
            count = len([line for line in output.splitlines() if line.strip()])
        except Exception:
            count = 0
        return str(count)

    def _load_scripts(self, filename):
        path = os.path.join(FN_EDITOR_DIR, filename)
        if not os.path.isfile(path):
            path = os.path.join(STOCK_FN_EDITOR_DIR, filename)
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, list):
                return data
        except Exception as e:
            PyUiLogger.get_logger().error(f"Cannot read {path}: {e}")
        return []

    def _scene_script_path(self, entry):
        launch = entry.get("launch")
        if not launch:
            return None
        return os.path.join(SCENE_DIR, os.path.basename(launch))

    def _is_scene_script_enabled(self, entry):
        script = self._scene_script_path(entry)
        return script is not None and os.path.exists(script)

    def _toggle_scene_script(self, entry):
        target = self._scene_script_path(entry)
        launch = entry.get("launch")
        if not target or not launch:
            return
        source = os.path.join(FN_EDITOR_DIR, launch)
        if not os.path.isfile(source):
            source = os.path.join(STOCK_FN_EDITOR_DIR, launch)
        os.makedirs(SCENE_DIR, exist_ok=True)
        if os.path.exists(target):
            self._run_switch_script(target, "0")
            time.sleep(0.5)
            subprocess.run(f"pkill -f {launch}", shell=True)
            try:
                os.remove(target)
            except Exception as e:
                PyUiLogger.get_logger().error(f"Failed to remove target: {e}")
            self._restart_trimui_service("trimui_scened")
            return
        if not os.path.isfile(source):
            PyUiLogger.get_logger().error(f"Fn switch script missing: {source}")
            return
        subprocess.run(f"pkill -f {launch}", shell=True)
        shutil.copy(source, target)
        os.chmod(target, 0o755)
        self._run_switch_script(target, "1")
        self._restart_trimui_service("trimui_scened")

    def _run_switch_script(self, script, state):
        try:
            subprocess.Popen(
                ["sh", script, state],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to run switch script {script}: {e}")

    def _restart_trimui_service(self, service):
        try:
            subprocess.Popen(
                f"killall -9 {service} 2>/dev/null; cd /usr/trimui/bin; LD_LIBRARY_PATH=/usr/trimui/lib ./{service} &",
                shell=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to restart {service}: {e}")

    def _run_fn_script(self, launch, extra_arg):
        script = os.path.join(FN_EDITOR_DIR, launch)
        if not os.path.isfile(script):
            PyUiLogger.get_logger().error(f"Fn script missing: {script}")
            return
        try:
            cmd = ["sh", script]
            if extra_arg is not None:
                cmd.append(extra_arg)
            subprocess.run(cmd, cwd=FN_EDITOR_DIR, check=False, timeout=10)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Fn script failed {script}: {e}")
