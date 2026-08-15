import ctypes
import re
import tempfile
import time
from asyncio import sleep
import json
from pathlib import Path
import subprocess
import threading
import os
from controller.key_watcher_controller import DictKeyMappingProvider, KeyWatcherController
from display.display import Display
from utils.logger import PyUiLogger
from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher import KeyWatcher
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.miyoo.mini.miyoo_mini_flip_shared_memory_writer import MiyooMiniFlipSharedMemoryWriter
from devices.miyoo.mini.miyoo_mini_flip_specific_model_variables import MiyooMiniSpecificModelVariables
from devices.miyoo.miyoo_device import MiyooDevice
from devices.miyoo.miyoo_games_file_parser import MiyooGamesFileParser
from devices.miyoo.device_user_config import DeviceUserConfig
from devices.miyoo_trim_common import MiyooTrimCommon
from devices.utils.file_watcher import FileWatcher
from devices.utils.process_runner import ProcessRunner
from menus.games.utils.rom_info import RomInfo
from utils import throttle
from utils.config_copier import ConfigCopier
from utils.ffmpeg_image_utils import FfmpegImageUtils
from utils.py_ui_config import PyUiConfig
from utils.time_logger import log_timing

MAX_VOLUME = 20
MIN_RAW_VALUE = -60
MAX_RAW_VALUE = 30

MI_AO_SETVOLUME = 0x4008690b
MI_AO_GETVOLUME = 0xc008690c
MI_AO_SETMUTE   = 0x4008690d


class MiDispCsc(ctypes.Structure):
    """MI_DISP_Csc_t. Every field 0-100; stock defaults are 50 except saturation at 40."""
    _fields_ = [
        ("eCscMatrix", ctypes.c_uint32),
        ("u32Luma", ctypes.c_uint32),
        ("u32Contrast", ctypes.c_uint32),
        ("u32Hue", ctypes.c_uint32),
        ("u32Saturation", ctypes.c_uint32),
    ]


class MiDispLcdParam(ctypes.Structure):
    """MI_DISP_LcdParam_t -- 24 bytes, six u32."""
    _fields_ = [
        ("stCsc", MiDispCsc),
        ("u32Sharpness", ctypes.c_uint32),
    ]


class MiDispSyncInfo(ctypes.Structure):
    """MI_DISP_SyncInfo_t. Read back and sent again untouched; only the size matters."""
    _fields_ = [
        ("bSynm", ctypes.c_uint8),
        ("bIop", ctypes.c_uint8),
        ("u8Intfb", ctypes.c_uint8),
        ("u16Vact", ctypes.c_uint16),
        ("u16Vbb", ctypes.c_uint16),
        ("u16Vfb", ctypes.c_uint16),
        ("u16Hact", ctypes.c_uint16),
        ("u16Hbb", ctypes.c_uint16),
        ("u16Hfb", ctypes.c_uint16),
        ("u16Hmid", ctypes.c_uint16),
        ("u16Bvact", ctypes.c_uint16),
        ("u16Bvbb", ctypes.c_uint16),
        ("u16Bvfb", ctypes.c_uint16),
        ("u16Hpw", ctypes.c_uint16),
        ("u16Vpw", ctypes.c_uint16),
        ("bIdv", ctypes.c_uint8),
        ("bIhs", ctypes.c_uint8),
        ("bIvs", ctypes.c_uint8),
        ("u32FrameRate", ctypes.c_uint32),
    ]


class MiDispPubAttr(ctypes.Structure):
    """MI_DISP_PubAttr_t."""
    _fields_ = [
        ("u32BgColor", ctypes.c_uint32),
        ("eIntfType", ctypes.c_uint32),
        ("eIntfSync", ctypes.c_uint32),
        ("stSyncInfo", MiDispSyncInfo),
    ]


E_MI_DISP_INTF_LCD = 6
E_MI_DISP_OUTPUT_USER = 32

class MiyooMiniCommon(MiyooDevice):
    OUTPUT_MIXER = 2
    SOUND_DISABLED = 0


    def __init__(self, device_name, main_ui_mode, miyoo_mini_specific_model_variables: MiyooMiniSpecificModelVariables):

        self.device_name = device_name
        self.miyoo_mini_specific_model_variables = miyoo_mini_specific_model_variables
        self.controller_interface = self.build_controller_interface()

        self._load_system_config("/mnt/SDCARD/Saves/mini-flip-system.json", Path(__file__).resolve().parent  / 'mini-flip-system.json')
        
        if(main_ui_mode):
            self.miyoo_mini_flip_shared_memory_writer = MiyooMiniFlipSharedMemoryWriter()
            self.miyoo_games_file_parser = MiyooGamesFileParser()        
            self.mainui_volume = None
            self.mainui_config_thread, self.mainui_config_thread_stop_event = FileWatcher().start_file_watcher(
                "/appconfigs/system.json", self.on_mainui_config_change, interval=0.2)
            threading.Thread(target=self.startup_init, daemon=True).start()

        super().__init__()


    def on_mainui_config_change(self):
        path = "/appconfigs/system.json"
        if not os.path.exists(path):
            PyUiLogger.get_logger().warning(f"File not found: {path}")
            return

        volume = None

        try:
            # First try normal JSON parsing
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
                volume = data.get("vol")

        except Exception as e:
            PyUiLogger.get_logger().warning(
                f"JSON parse failed for {path}, attempting fallback parse: {e}"
            )

            # Fallback: scan file text for `"vol" : number`
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as f:
                    for line in f:
                        # Match: "vol" : 23   (allow spaces)
                        m = re.search(r'"vol"\s*:\s*(\d+)', line)
                        if m:
                            volume = int(m.group(1))
                            break
            except Exception as e2:
                PyUiLogger.get_logger().warning(
                    f"Fallback parse failed for {path}: {e2}"
                )
                return

        if volume is None:
            return

        old_volume = self.mainui_volume
        self.mainui_volume = volume

        if old_volume != self.mainui_volume:
            from display.display import Display
            Display.volume_changed(self.mainui_volume * 5)

    def startup_init(self, include_wifi=True):
        if(self.is_wifi_enabled()):
            self.start_wifi_services(foreground_call=False)
        self.on_mainui_config_change()
        self._set_lumination_to_config()
        self._set_contrast_to_config()
        self._set_saturation_to_config()
        self._set_brightness_to_config()
        self.ensure_wpa_supplicant_conf()
        self.init_gpio()
        if(PyUiConfig.enable_button_watchers()):
            from controller.controller import Controller
            #/dev/miyooio if we want to get rid of miyoo_inputd
            # debug in terminal: hexdump  /dev/miyooio
            self.volume_key_watcher = KeyWatcher("/dev/input/event0")
            Controller.add_button_watcher(self.volume_key_watcher.poll_keyboard)
            volume_key_polling_thread = threading.Thread(target=self.volume_key_watcher.poll_keyboard, daemon=True)
            volume_key_polling_thread.start()

    def build_controller_interface(self):
        key_mappings = {}  
        key_mappings[KeyEvent(1, 57, 0)] = [InputResult(ControllerInput.A, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 57, 1)] = [InputResult(ControllerInput.A, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 29, 0)] = [InputResult(ControllerInput.B, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 29, 1)] = [InputResult(ControllerInput.B, KeyState.PRESS)]   
        key_mappings[KeyEvent(1, 56, 0)] = [InputResult(ControllerInput.Y, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 56, 1)] = [InputResult(ControllerInput.Y, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 42, 0)] = [InputResult(ControllerInput.X, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 42, 1)] = [InputResult(ControllerInput.X, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 28, 0)] = [InputResult(ControllerInput.START, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 28, 1)] = [InputResult(ControllerInput.START, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 97, 0)] = [InputResult(ControllerInput.SELECT, KeyState.RELEASE)]   
        key_mappings[KeyEvent(1, 97, 1)] = [InputResult(ControllerInput.SELECT, KeyState.PRESS)]   

        key_mappings[KeyEvent(1, 1, 0)] = [InputResult(ControllerInput.MENU, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 1, 1)] = [InputResult(ControllerInput.MENU, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 15, 0)] = [InputResult(ControllerInput.L2, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 15, 1)] = [InputResult(ControllerInput.L2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 20, 0)] = [InputResult(ControllerInput.R1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 20, 1)] = [InputResult(ControllerInput.R1, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 14, 0)] = [InputResult(ControllerInput.R2, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 14, 1)] = [InputResult(ControllerInput.R2, KeyState.PRESS)]  
        key_mappings[KeyEvent(1, 18, 0)] = [InputResult(ControllerInput.L1, KeyState.RELEASE)]  
        key_mappings[KeyEvent(1, 18, 1)] = [InputResult(ControllerInput.L1, KeyState.PRESS)]  

        key_mappings[KeyEvent(1, 103, 1)] = [InputResult(ControllerInput.DPAD_UP, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 103, 0)] = [InputResult(ControllerInput.DPAD_UP, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 108, 1)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 108, 0)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 105, 1)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 105, 0)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.RELEASE)]
        key_mappings[KeyEvent(1, 106, 1)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.PRESS)]
        key_mappings[KeyEvent(1, 106, 0)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.RELEASE)]

        
        return KeyWatcherController(event_path="/dev/input/event0", mapping_provider=DictKeyMappingProvider(key_mappings))

    def power_off_cmd(self):
        return self.miyoo_mini_specific_model_variables.poweroff_cmd

    def get_controller_interface(self):
        return self.controller_interface

    def init_gpio(self):
        #self.init_sleep_gpio()
        pass

    def init_sleep_gpio(self):
        try:
            if not os.path.exists("/sys/class/export"):
                with open("/sys/class/gpio/export", "w") as f:
                    f.write("4")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error exporting gpio 4 {e}")


    def are_headphones_plugged_in(self):
        try:
            with open("/sys/class/gpio/gpio150/value", "r") as f:
                value = f.read().strip()
                return "0" == value 
        except (FileNotFoundError, IOError) as e:
            return False
        
    def is_lid_closed(self):
        return False

    @throttle.limit_refresh(5)
    def is_hdmi_connected(self):
        return False

    def screen_width(self):
        return self.miyoo_mini_specific_model_variables.width

    def screen_height(self):
        return self.miyoo_mini_specific_model_variables.height
        
    def screen_rotation(self):
        return 0
    
    def output_screen_width(self):
        if(self.should_scale_screen()):
            return 1920
        else:
            return self.screen_height()
        
    def output_screen_height(self):
        if(self.should_scale_screen()):
            return 1080
        else:
            return self.screen_width()

    def get_scale_factor(self):
        if(self.is_hdmi_connected()):
            return 2.25
        else:
            return 1
    
    def _update_stock_config(self, key, value):
        path = "/appconfigs/system.json"

        try:
            # Only proceed if file exists
            if not os.path.isfile(path):
                PyUiLogger.get_logger().warning(f"{path} does not exist, cannot store {key}")
                return

            # On the OG Mini and the V4 this file is empty, which sent every write
            # through the sed fallback below where there was nothing to match. Say
            # so rather than spawning a sed per setting on every boot to no effect.
            if os.path.getsize(path) == 0:
                PyUiLogger.get_logger().warning(f"{path} is empty, cannot store {key}")
                return

            # Load existing JSON (fail silently if invalid)
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)

            # Only update if it's a dict
            if not isinstance(data, dict):
                return

            # Update saturation
            data[key] = value

            # Atomic write back to same file
            dir_name = os.path.dirname(path) or "."
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=dir_name,
                delete=False
            ) as tmp:
                json.dump(data, tmp, indent=2)
                tmp.flush()
                os.fsync(tmp.fileno())
                tmp_path = tmp.name

            os.replace(tmp_path, path)

        except Exception:
            try:
                import subprocess

                # Escape key for safety (basic)
                safe_key = key.replace('"', r'\"')

                # sed regex:
                # ("key"\s*:\s*)   -> capture key + colon + any whitespace
                # [^,}]*           -> match existing value (until , or })
                # replace with new value
                sed_expr = rf's/("{safe_key}"[[:space:]]*:[[:space:]]*)[^,}}]*/\1{value}/'

                ProcessRunner.run(
                    ["sed", "-i", "-r", sed_expr, path],
                    check=False,print=True
                )
            except Exception:
                pass
    BACKLIGHT_PWM_DUTY_CYCLE = "/sys/class/pwm/pwmchip0/pwm0/duty_cycle"

    def _set_lumination_to_config(self):
        # Miyoo internally has lumination but it does not work
        self._update_stock_config("brightness", self.system_config.backlight)
        self.miyoo_mini_flip_shared_memory_writer.set_brightness(self.system_config.backlight)
        self._write_backlight_pwm(self.system_config.backlight)

    def _write_backlight_pwm(self, backlight):
        """
        Drive the backlight ourselves.

        keymon is running and does pick up the shared memory write above, but on
        the OG Mini and the V4 that never reached the panel, so the backlight
        setting did nothing at all. Writing the pwm channel is what the sprig
        build does on this same hardware. Duty cycle matches what device_init
        sets at boot, against the same period of 1000.
        """
        if not os.path.exists(self.BACKLIGHT_PWM_DUTY_CYCLE):
            return

        try:
            duty_cycle = max(0, min(10, int(backlight))) * 10
            with open(self.BACKLIGHT_PWM_DUTY_CYCLE, "w") as f:
                f.write(str(duty_cycle))
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Could not set backlight pwm: {e}")

    DISPLAY_DEVICE = "/dev/mi_disp"
    DISPLAY_CONTROL_NODE = "/proc/mi_modules/mi_disp/mi_disp0"
    # Colour balance channels. Never 0: that is a black screen with no way back
    # from the menu.
    MIN_CHANNEL_GAIN = 24
    MAX_CHANNEL_GAIN = 255

    def _clamp_channel(self, value):
        return int(max(self.MIN_CHANNEL_GAIN, min(self.MAX_CHANNEL_GAIN, round(value))))

    _mi_disp_lib = None
    _mi_disp_lib_tried = False
    _mi_sys_lib = None

    def _load_mi_disp(self):
        """
        The MI display library, or None.

        Lives in /customer/lib on the device, which the startup script already has
        on LD_LIBRARY_PATH. Loaded lazily and only attempted once.
        """
        if self._mi_disp_lib_tried:
            return self._mi_disp_lib

        MiyooMiniCommon._mi_disp_lib_tried = True

        # libmi_disp.so does not carry its own dependencies -- loading it on its
        # own fails with "undefined symbol: MI_SYS_Mmap". Pull what it leans on
        # into the global symbol table first. They live in /config/lib, which the
        # startup script already puts on LD_LIBRARY_PATH.
        for dependency in ("libmi_sys.so", "libmi_common.so", "libmi_panel.so"):
            try:
                handle = ctypes.CDLL(dependency, mode=ctypes.RTLD_GLOBAL)
                if dependency == "libmi_sys.so":
                    MiyooMiniCommon._mi_sys_lib = handle
                PyUiLogger.get_logger().info(f"Loaded MI dependency {dependency}")
            except Exception as e:
                PyUiLogger.get_logger().info(f"MI dependency {dependency} not loaded: {e}")

        for name in ("libmi_disp.so", "/config/lib/libmi_disp.so"):
            try:
                MiyooMiniCommon._mi_disp_lib = ctypes.CDLL(name, mode=ctypes.RTLD_GLOBAL)
                PyUiLogger.get_logger().info(f"Loaded MI display library from {name}")
                return MiyooMiniCommon._mi_disp_lib
            except Exception as e:
                PyUiLogger.get_logger().info(f"Could not load {name}: {e}")

        PyUiLogger.get_logger().warning("No MI display library available")
        return None

    # Observed on the V4 the first time the params are read back. Only used if
    # the read fails, so that a bad read costs the settings rather than the
    # picture.
    DEFAULT_CSC_MATRIX = 3
    DEFAULT_SHARPNESS = 0

    _last_csc = None
    _lcd_output_ready = None

    def _read_lcd_param(self, lib, params):
        try:
            return lib.MI_DISP_GetLcdParam(0, ctypes.byref(params))
        except Exception as e:
            PyUiLogger.get_logger().warning(f"MI_DISP_GetLcdParam unavailable: {e}")
            return -1

    def _prepare_lcd_output(self):
        """
        Get the display device into a state where the lcd params can be read
        and written, once per process and as early as we can manage.

        Getting there disturbs the picture, which is why it matters that this
        happens here rather than on every apply. It used to run on all four of
        the settings restored at startup and again on every change from the
        menu. That is where the fuzzy static during boot came from, the flash
        in the menus whenever a setting was applied, and -- since the
        screensaver only redraws once a minute -- a single garbage frame left
        sitting on screen underneath the clock rather than being replaced.

        Deliberately left where it is, on the first apply, rather than moved
        into device init to get it done before SDL takes the display. That was
        tried: the settings applied, but the device hung on shutdown, with the
        screen stuck on the fuzz and needing the battery pulled. Moving it back
        after SDL is up shut down cleanly again. Not chased further than that,
        since with the device handed back below there is no longer a reason to
        want it earlier.

        Escalates rather than reconfiguring up front, since the cheapest step
        that works is the one that disturbs least. Only the last of these
        touches the display at all:

          1. Just read the params. If the device is already up, nothing else
             is needed and nothing gets touched.
          2. MI_SYS_Init first. Every MI module wants this before it will
             answer, and nothing in PyUI had called it -- SDL's mmiyoo backend
             does its own, but through its own handle. This is the step worth
             hoping for: it costs nothing on screen.
          3. MI_DISP_Enable on its own.
          4. MI_DISP_SetPubAttr as an lcd output, then enable. This is the
             step the V4 actually needs, and the only one that touches the
             display. Note it runs after step 3, which matters: on its own
             MI_DISP_GetPubAttr comes back rc=31 and the struct would go out
             zeroed, taking the panel timings with it, but following an enable
             it returns rc=0 and the timings are read back and sent again
             untouched.
        """
        if MiyooMiniCommon._lcd_output_ready is not None:
            return MiyooMiniCommon._lcd_output_ready

        MiyooMiniCommon._lcd_output_ready = False

        lib = self._load_mi_disp()
        if lib is None:
            return False

        params = MiDispLcdParam()

        rc = self._read_lcd_param(lib, params)
        if rc == 0:
            PyUiLogger.get_logger().info("MI display lcd params readable as is")
            MiyooMiniCommon._lcd_output_ready = True
            return True

        if self._mi_sys_lib is not None:
            try:
                rc_sys = self._mi_sys_lib.MI_SYS_Init()
                rc = self._read_lcd_param(lib, params)
                PyUiLogger.get_logger().info(
                    f"MI_SYS_Init rc={rc_sys}, GetLcdParam rc={rc}")
                if rc == 0:
                    MiyooMiniCommon._lcd_output_ready = True
                    return True
            except Exception as e:
                PyUiLogger.get_logger().info(f"MI_SYS_Init unavailable: {e}")

        try:
            rc_enable = lib.MI_DISP_Enable(0)
            rc = self._read_lcd_param(lib, params)
            PyUiLogger.get_logger().info(
                f"MI_DISP_Enable rc={rc_enable}, GetLcdParam rc={rc}")
            if rc == 0:
                MiyooMiniCommon._lcd_output_ready = True
                return True

            attrs = MiDispPubAttr()
            rc_get = lib.MI_DISP_GetPubAttr(0, ctypes.byref(attrs))
            attrs.eIntfType = E_MI_DISP_INTF_LCD
            attrs.eIntfSync = E_MI_DISP_OUTPUT_USER
            rc_set = lib.MI_DISP_SetPubAttr(0, ctypes.byref(attrs))
            rc_enable = lib.MI_DISP_Enable(0)
            rc = self._read_lcd_param(lib, params)
            PyUiLogger.get_logger().info(
                f"MI_DISP GetPubAttr rc={rc_get} SetPubAttr rc={rc_set} "
                f"Enable rc={rc_enable}, GetLcdParam rc={rc}")
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Could not enable MI display device: {e}")
            return False

        MiyooMiniCommon._lcd_output_ready = rc == 0
        if not MiyooMiniCommon._lcd_output_ready:
            PyUiLogger.get_logger().warning(
                "MI display lcd params unreadable, screen settings will not apply")
            return False

        self._release_display_if_params_survive(lib, params)
        return True

    def _release_display_if_params_survive(self, lib, params):
        """
        Hand the display device back if the lcd params can still be reached
        without it.

        Stock never has this device enabled. The bug report dump has DevStatus
        0 with no channels enabled, and everything worked that way: SDL's
        mmiyoo backend drives the panel through fb0 and gfx and leaves disp
        alone. Enabling it is a change that outlives the call -- it switches on
        a layer underneath an alpha blended osd (mi_fb0 reports ARGB8888 with
        Enable Alpha Blend=1) with nothing feeding it, so it scans out whatever
        was in that memory. That is the fuzz, and it is why the screensaver
        still showed it a minute after the one and only reconfigure.

        So put it back if we can. If the params can still be read and written
        with the device disabled then nothing was gained by holding it enabled,
        and the picture is left the way stock has it.

        Both directions get tested, not just the read: writing is what actually
        applies a setting, and it is the one that has to keep working. The
        write puts back exactly what was just read, so it changes nothing.
        """
        try:
            rc_disable = lib.MI_DISP_Disable(0)
            rc = self._read_lcd_param(lib, params)
            rc_write = lib.MI_DISP_SetLcdParam(0, ctypes.byref(params)) if rc == 0 else -1
        except Exception as e:
            PyUiLogger.get_logger().info(f"MI_DISP_Disable unavailable: {e}")
            return

        PyUiLogger.get_logger().info(
            f"MI_DISP_Disable rc={rc_disable}, GetLcdParam rc={rc}, "
            f"SetLcdParam rc={rc_write}")

        if rc == 0 and rc_write == 0:
            PyUiLogger.get_logger().info(
                "MI display params still reachable disabled, leaving it that way")
            return

        # Needed after all. Put it back and carry on, at the cost of the layer
        # underneath being whatever it is.
        try:
            rc_enable = lib.MI_DISP_Enable(0)
            rc = self._read_lcd_param(lib, params)
            PyUiLogger.get_logger().info(
                f"MI display params need it enabled, re-enabled rc={rc_enable}, "
                f"GetLcdParam rc={rc}")
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Could not re-enable MI display device: {e}")

    def _apply_lcd_csc(self, luma, contrast, hue, saturation):
        """
        Drive brightness, contrast, hue and saturation through the LCD output's
        colour space conversion.

        This is a different block from the one the proc 'csc' command reaches.
        That one sits on the video path and does nothing to the menu, which is
        why every attempt through it failed no matter which matrix was used.
        This one is only reachable through the MI library, and only once
        _prepare_lcd_output has had the device up.

        Nothing below that line touches how the display is configured. Writing
        the csc coefficients on their own is not what disturbs the picture;
        reconfiguring the output is, so that is done once and not from here.

        All four values are 0-100. Luma and contrast keep a floor so the panel
        cannot be driven to something unreadable from the menu.
        """
        if not self._prepare_lcd_output():
            return False

        lib = self._load_mi_disp()
        if lib is None:
            return False

        wanted = (
            self._clamp_csc(luma, floor=10),
            self._clamp_csc(contrast, floor=10),
            self._clamp_csc(hue),
            self._clamp_csc(saturation),
        )

        # Every setting restored at startup calls through here, so without this
        # the same four values get written three times over on every boot.
        if MiyooMiniCommon._last_csc == wanted:
            return True

        params = MiDispLcdParam()
        rc = self._read_lcd_param(lib, params)

        PyUiLogger.get_logger().info(
            f"MI_DISP_GetLcdParam rc={rc} matrix={params.stCsc.eCscMatrix} "
            f"luma={params.stCsc.u32Luma} contrast={params.stCsc.u32Contrast} "
            f"hue={params.stCsc.u32Hue} saturation={params.stCsc.u32Saturation} "
            f"sharpness={params.u32Sharpness}")

        if rc != 0:
            # The read came back empty, so the rest of the struct is zeroed and
            # writing it as is would clear the matrix along with everything else.
            # Fill in what the panel reported when the read did work.
            params.stCsc.eCscMatrix = self.DEFAULT_CSC_MATRIX
            params.u32Sharpness = self.DEFAULT_SHARPNESS
            PyUiLogger.get_logger().warning(
                f"MI_DISP_GetLcdParam failed rc={rc}, writing with matrix="
                f"{self.DEFAULT_CSC_MATRIX} sharpness={self.DEFAULT_SHARPNESS}")

        (params.stCsc.u32Luma,
         params.stCsc.u32Contrast,
         params.stCsc.u32Hue,
         params.stCsc.u32Saturation) = wanted

        try:
            rc = lib.MI_DISP_SetLcdParam(0, ctypes.byref(params))
        except Exception as e:
            PyUiLogger.get_logger().warning(f"MI_DISP_SetLcdParam unavailable: {e}")
            return False

        PyUiLogger.get_logger().info(
            f"MI_DISP_SetLcdParam rc={rc} luma={params.stCsc.u32Luma} "
            f"contrast={params.stCsc.u32Contrast} hue={params.stCsc.u32Hue} "
            f"saturation={params.stCsc.u32Saturation}")

        if rc == 0:
            MiyooMiniCommon._last_csc = wanted
        return rc == 0

    def _clamp_csc(self, value, floor=0):
        return int(max(floor, min(100, round(value))))


    _display_fd = None

    def _ensure_display_device_open(self):
        """
        Hold the display device open so its control node stays alive.

        /proc/mi_modules/mi_disp/mi_disp0 only exists while something has
        /dev/mi_disp open. On stock firmware MainUI holds it; spruce kills MainUI
        and renders through the framebuffer, so nothing did, the node was never
        there, and every contrast and saturation write went nowhere.

        It has to stay open rather than being opened per write: closing the device
        takes the node away again, and the display instance the csc values were
        applied to goes with it, so anything written is immediately undone. This
        is the same state stock runs in, and why sprig's shell script works on the
        Flip -- something over there is already holding the device.
        """
        if self._display_fd is not None:
            return True

        try:
            fd = os.open(self.DISPLAY_DEVICE, os.O_RDWR)
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Could not open {self.DISPLAY_DEVICE}: {e}")
            return False

        # Created by the driver's open handler, so it should already be there.
        for _ in range(20):
            if os.path.exists(self.DISPLAY_CONTROL_NODE):
                self._display_fd = fd
                PyUiLogger.get_logger().info(
                    f"Holding {self.DISPLAY_DEVICE} open so {self.DISPLAY_CONTROL_NODE} stays available")
                return True
            time.sleep(0.01)

        PyUiLogger.get_logger().warning(
            f"{self.DISPLAY_CONTROL_NODE} did not appear after opening {self.DISPLAY_DEVICE}")
        os.close(fd)
        return False

    def _set_screen_values_to_config(self):
        """
        Push brightness, contrast, hue, saturation and colour balance at the
        display engine.

        Two separate paths, because the panel only listens to each for its own
        half. Brightness, contrast, hue and saturation go through the LCD
        output's colour space conversion, reachable only via the MI library.
        Colour balance goes through the colortemp command on the disp proc node,
        whose per channel values are gains with 128 as unity.

        Config values run 0-20 and both interfaces want a different scale, so
        each is converted at the point of use.
        """
        self._apply_lcd_csc(
            luma=self.system_config.brightness * 5,
            contrast=self.system_config.contrast * 5,
            hue=self.system_config.hue * 5,
            saturation=self.system_config.saturation * 5,
        )

        red = self._clamp_channel(self.get_disp_red())
        green = self._clamp_channel(self.get_disp_green())
        blue = self._clamp_channel(self.get_disp_blue())
        colortemp = f"colortemp 0 0 0 0 {blue} {green} {red}"

        if not self._ensure_display_device_open():
            return

        try:
            with open(self.DISPLAY_CONTROL_NODE, "w") as f:
                f.write(colortemp + "\n")
            PyUiLogger.get_logger().info(f"Applied colour balance: [{colortemp}]")
        except Exception as e:
            PyUiLogger.get_logger().warning(
                f"Could not apply colour balance [{colortemp}]: {e}")

    def _set_contrast_to_config(self):
        self._update_stock_config("contrast", self.system_config.contrast)
        self._set_screen_values_to_config()

    def _set_saturation_to_config(self):
        self._update_stock_config("saturation", self.system_config.saturation)
        self._set_screen_values_to_config()

    def _set_brightness_to_config(self):
        self._update_stock_config("lumination", self.system_config.brightness)
        self._set_screen_values_to_config()

    def _set_hue_to_config(self):
        self._set_screen_values_to_config()

    def _set_disp_red_to_config(self):
        self._set_screen_values_to_config()

    def _set_disp_green_to_config(self):
        self._set_screen_values_to_config()

    def _set_disp_blue_to_config(self):
        self._set_screen_values_to_config()
    
    def take_snapshot(self, path):
        return None
    
    @throttle.limit_refresh(15)
    def get_ip_addr_text(self):
        if self.miyoo_mini_specific_model_variables.supports_wifi:
            if self.is_wifi_enabled():
                try:
                    # Run the system command to get wlan0 info
                    result = subprocess.run(
                        ["ip", "addr", "show", "wlan0"],
                        capture_output=True,
                        text=True
                    )

                    if result.returncode != 0:
                        return "Error"

                    # Look for an IPv4 address in the command output
                    for line in result.stdout.splitlines():
                        line = line.strip()
                        if line.startswith("inet "):  # Example: "inet 192.168.1.42/24 ..."
                            ip = line.split()[1].split("/")[0]  # Take "192.168.1.42" part
                            return ip

                    return "Connecting"  # wlan0 exists but no IP yet

                except Exception:
                    return "Error"

            return "Off"
        else:
            return "Unsupported"

    def supports_wifi(self):
        return self.miyoo_mini_specific_model_variables.supports_wifi

    def get_charge_status(self):
        return self.miyoo_mini_specific_model_variables.get_charge_status()

    @throttle.limit_refresh(15)
    def get_battery_percent(self):
        return self.miyoo_mini_specific_model_variables.get_battery_percent()
    

    def start_wifi_services(self,foreground_call=False):
        if(self.miyoo_mini_specific_model_variables.supports_wifi):
            try:
                # Check if system already has an IP address
                result = ProcessRunner.run(
                    ["ip", "route", "get", "1"],
                    print=True,
                    timeout=1
                )

                # Extract the last field (the IP) like `awk '{print $NF;exit}'`
                parts = result.stdout.strip().split()
                ip = parts[-1] if parts else ""

                if not ip:
                    PyUiLogger.get_logger().info("Wifi is disabled - trying to enable it...")
                    if(foreground_call):
                        Display.display_message("Loading WiFi driver\n(May take up to 5s)")
                    ProcessRunner.run(["insmod", "/mnt/SDCARD/spruce/miyoomini/drivers/8188fu.ko"], timeout=5, print=True)
                    if(foreground_call):
                        Display.display_message("Starting network loopback interface\n(May take up to 5s)")
                    ProcessRunner.run(["ifconfig", "lo", "up"], timeout=5, print=True)
                    if(foreground_call):
                        Display.display_message("Running miyoo-mini custom wifion script\n(May take up to 10s)")
                    ProcessRunner.run(["/customer/app/axp_test", "wifion"], timeout=10, print=True)
                    time.sleep(2)
                    if(foreground_call):
                        Display.display_message("Starting wlan0\n(May take up to 3s)")
                    ProcessRunner.run(["ifconfig", "wlan0", "up"], timeout=3, print=True)
                    if(foreground_call):
                        Display.display_message("Starting WiFi process\n(May take up to 20s)")
                    subprocess.Popen([
                        "wpa_supplicant",
                        "-B",
                        "-D", "nl80211",
                        "-i", "wlan0",
                        "-c", self.get_wpa_supplicant_conf_path()
                    ])
                    if(foreground_call):
                        Display.display_message("Starting ip address assignment process\n(May take up to 20s)")
                    subprocess.Popen(["udhcpc", "-i", "wlan0", "-s", "/etc/init.d/udhcpc.script", "-b"])
                    time.sleep(3)
                    os.system("clear")

            except Exception as e:
                PyUiLogger.get_logger().error(f"Error enabling WiFi: {e}")


    def set_wifi_power(self, value):
        if(self.miyoo_mini_specific_model_variables.supports_wifi):
            if(0 == value):
                ProcessRunner.run(["ifconfig", "wlan0", "down"], timeout=5)

    def get_bluetooth_scanner(self):
        return None
        
    def reboot_cmd(self):
        return self.miyoo_mini_specific_model_variables.reboot_cmd

    def get_wpa_supplicant_conf_path(self):
        return PyUiConfig.get_wpa_supplicant_conf_file_location("/appconfigs/wpa_supplicant.conf")

    def get_volume(self):
        try:
            return self.mainui_volume * 5
        except:
            return 0

    def volume_up(self):
        try:
            subprocess.run(
                ["send_event", "/dev/input/event0", "115:1"],
                check=False
            )
        except Exception as e:
            PyUiLogger.get_logger().exception(f"Failed to set volume via input events: {e}")

    def volume_down(self):
        try:
            subprocess.run(
                ["send_event", "/dev/input/event0", "114:1"],
                check=False
            )
        except Exception as e:
            PyUiLogger.get_logger().exception(f"Failed to set volume via input events: {e}")

    def run_game(self, rom_info: RomInfo) -> subprocess.Popen:
        preload_path = "/mnt/SDCARD/miyoo/app/../lib/libpadsp.so"
        if os.path.exists(preload_path):
            run_prefix = f"LD_PRELOAD={preload_path} "
        else:
            run_prefix = "LD_PRELOAD=/customer/lib/libpadsp.so "
            preload_path="/customer/lib/libpadsp.so"

        if(PyUiConfig.mimic_miyoo_mainui_mode()):
            MiyooTrimCommon.run_game(self, rom_info, run_prefix=run_prefix)
        else:
            from controller.controller import Controller
            menu_options = rom_info.game_system.game_system_config.get_menu_options()
            selected_core = self.get_selected_emulator(menu_options, self.device_name)
            if(selected_core is None):
                Display.display_message("No core found", 2_000)
                return

            selected_core = "/mnt/SDCARD/RetroArch/.retroarch/cores/" + selected_core + "_libretro.so"

            cmds = ["/mnt/SDCARD/RetroArch/retroarch",
                    "-v",
                    "--log-file","/mnt/SDCARD/Saves/spruce/retroarch.log",
                    "-L",selected_core,
                    rom_info.rom_file_path]

            directory = "/mnt/SDCARD/RetroArch"
            
            PyUiLogger.get_logger().debug(f"About to launch {cmds} from dir {directory}")
            Display.deinit_display()

            env = os.environ.copy()
            env["LD_PRELOAD"] = preload_path
            env["HOME"] = directory

            for v in [
                "SDL_VIDEODRIVER",
                "SDL_FBDEV",
                "SDL_AUDIODRIVER",
                "SDL_NOMOUSE",
                "DISPLAY"
            ]:
                env.pop(v, None)
            subprocess.run(cmds, cwd = directory, env=env)
            Display.init()

            # RetroArch brings the display up itself, so whatever csc it left
            # behind is not what we last wrote. Forget it so the next apply
            # actually reaches the panel rather than matching a stale cache.
            MiyooMiniCommon._last_csc = None

            Controller.clear_input_queue()

    def double_init_sdl_display(self):
        return True
            
    def max_texture_width(self):
        return 800
                    
    def max_texture_height(self):
        return 600

    def get_guaranteed_safe_max_text_char_count(self):
        return 35

    def supports_volume(self):
        return self.miyoo_mini_specific_model_variables.supports_volume

    def supports_analog_calibration(self):
        return False

    def supports_image_resizing(self):
        return True

    def supports_brightness_calibration(self):
        return True

    def supports_contrast_calibration(self):
        return True

    def supports_saturation_calibration(self):
        return True

    def supports_hue_calibration(self):
        return False
    
    def supports_popup_menu(self):
        return False
    
    def get_image_utils(self):
        return FfmpegImageUtils()

    def get_boxart_small_resize_dimensions(self):
        return 400,300

    def get_boxart_medium_resize_dimensions(self):
        return 400,300

    def get_boxart_large_resize_dimensions(self):
        return 400,300
    
    def get_device_name(self):
        return self.device_name
    
    # Timezone support is inherited from DeviceCommon. The Mini has no tz
    # database of its own and a read-only root, so it relies entirely on the
    # copy spruce ships and on TZ pointing at it. What used to be here was a
    # prompt that did nothing and a symlink into /mnt/SDCARD/miyoo285, a path
    # left over from Sprig that no spruce install has ever had.


    def get_fw_version(self):
        try:
            # Run fw_printenv and capture output
            result = subprocess.run(
                ["/etc/fw_printenv", "miyoo_version"],
                capture_output=True,
                text=True,
                check=True
            )
            
            output = result.stdout.strip()

            # Expected format: "miyoo_version=202510011046"
            if "=" in output:
                return output.split("=", 1)[1].strip()

            return output
        except Exception as e:
            PyUiLogger.get_logger().error(f"Could not read FW version : {e}")
            return "Unknown"

    def get_core_for_game(self, game_system_config, rom_file_path):
        core = game_system_config.get_effective_menu_selection("Emulator_MiyooMini", rom_file_path)
        if(core is None):
            core = game_system_config.get_effective_menu_selection("Emulator", rom_file_path)
        return core
    
    def get_core_name_overrides(self, core_name):
        return [core_name, core_name+"-32"]


    def animation_divisor(self):
        return self.get_system_config().animation_speed(2) 
