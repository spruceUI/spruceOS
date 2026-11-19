import fcntl
import glob
import os
import struct
import time

from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher_controller import HorizontalStickAxis, KeyWatcherController, VerticalStickAxis
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent
from devices.darkmoss.v10 import V10, V10KeyMappingProvider
from utils.logger import PyUiLogger

PAD_NAME = "OpenSimHardware OSH PB Controller"


# spruce's pad proxy (spruce/scripts/platform/darkmoss/rg351p_padproxy.py)
# mirrors the pad into a virtual device with this phys, which survives the
# pad's re-enumeration on every wake; the real pad is grabbed meanwhile.
PROXY_PHYS = "rg351p-padproxy"


def find_pad_node():
    """The pad is a USB device with no fixed by-path link: find it by name,
    preferring the proxy's virtual pad over the real one."""
    try:
        entries = sorted(os.listdir("/sys/class/input"))
    except OSError:
        return None
    real = None
    for entry in entries:
        if not entry.startswith("event"):
            continue
        try:
            with open(f"/sys/class/input/{entry}/device/name") as f:
                if f.read().strip() != PAD_NAME:
                    continue
        except OSError:
            continue
        try:
            with open(f"/sys/class/input/{entry}/device/phys") as f:
                if f.read().strip() == PROXY_PHYS:
                    return f"/dev/input/{entry}"
        except OSError:
            pass
        if real is None:
            real = f"/dev/input/{entry}"
    return real


def wait_for_pad_node(tries=25, interval=0.2):
    """The pad sits behind the internal USB hub: give it a moment (~5 s) to
    enumerate before PyUI resolves its node and reads its axis ranges."""
    for _ in range(tries):
        node = find_pad_node()
        if node:
            return node
        time.sleep(interval)
    return None


# EVIOCGABS(code) = _IOR('E', 0x40 + code, struct input_absinfo), six s32s.
EVIOCGABS_BASE = 0x80184540
ABSINFO_FORMAT = "6i"


def read_abs_range(node, code):
    """(min, max) of an ABS axis, read from the kernel; None if unavailable."""
    if not node:
        return None
    try:
        fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return None
    try:
        buf = bytearray(struct.calcsize(ABSINFO_FORMAT))
        fcntl.ioctl(fd, EVIOCGABS_BASE + code, buf)
        _value, minimum, maximum, _fuzz, _flat, _res = struct.unpack(ABSINFO_FORMAT, bytes(buf))
    except OSError:
        return None
    finally:
        os.close(fd)
    if maximum > minimum:
        return (minimum, maximum)
    return None


class RG351PKeyMappingProvider(V10KeyMappingProvider):
    """The V10's SELECT+START menu chord on the RG351P's USB pad.

    Codes are ArkOS's RG351P EmulationStation config. The d-pad is a hat
    (ABS_HAT0X/Y), looked up straight from the key map; each hat press first
    releases the opposite direction, since the hat can go from -1 to 1
    without a 0 in between. The sticks (left ABS_Z/ABS_RX, right
    ABS_RY/ABS_RZ) navigate like the d-pad, as on the other dArkMoss
    two-stick devices. Their range is read from the kernel (EVIOCGABS), not
    assumed: the centre is the middle of the range and the deadzone a quarter
    of the full span, so a stick at rest never scrolls the menus. The left
    stick is reversed in hardware on both axes (leftx:a0~, lefty:a1~ in
    AmberELEC's gamecontrollerdb and our own RG351P.cfg SDL map), so its
    directions are swapped. An axis whose range cannot be read is ignored.
    One stick click is MENU, per Button Settings > Menu button (the V10
    provider's _menu_thumb_code); the other stays L3/R3.
    """

    SELECT_KEY = 311
    START_KEY = 310
    L3_KEY = 312
    R3_KEY = 313
    ABS_HAT0X = 16
    ABS_HAT0Y = 17
    ABS_Z = 2
    ABS_RX = 3
    ABS_RY = 4
    ABS_RZ = 5

    # code -> axis. HorizontalStickAxis presses its first argument on negative
    # values, VerticalStickAxis likewise: the left stick's pairs are swapped
    # because that stick is inverted.
    STICK_AXES = {
        ABS_Z: HorizontalStickAxis(ControllerInput.LEFT_STICK_RIGHT, ControllerInput.LEFT_STICK_LEFT),
        ABS_RX: VerticalStickAxis(ControllerInput.LEFT_STICK_DOWN, ControllerInput.LEFT_STICK_UP),
        ABS_RY: HorizontalStickAxis(ControllerInput.RIGHT_STICK_LEFT, ControllerInput.RIGHT_STICK_RIGHT),
        ABS_RZ: VerticalStickAxis(ControllerInput.RIGHT_STICK_UP, ControllerInput.RIGHT_STICK_DOWN),
    }

    # The V10 provider sets these on the first SELECT press only; START
    # pressed first would read them unset.
    select_down = False
    menu_down = False
    select_released_by_chord = False

    THUMB_FALLBACK = {
        L3_KEY: ControllerInput.L3,
        R3_KEY: ControllerInput.R3,
    }

    def __init__(self, key_mappings, stick_axes=None):
        super().__init__(key_mappings)
        # code -> (axis, center, deadzone), for the axes whose range was read.
        self.stick_ranges = dict(stick_axes or {})

    def load_stick_ranges(self, node):
        """Read the range of every stick axis not loaded yet. Ranges do not
        change when the pad re-enumerates, so each is read once."""
        loaded = []
        for code, axis in self.STICK_AXES.items():
            if code in self.stick_ranges:
                continue
            rng = read_abs_range(node, code)
            if rng is None:
                continue
            lo, hi = rng
            center = (lo + hi) // 2
            deadzone = max(1, (hi - lo) // 4)
            self.stick_ranges[code] = (axis, center, deadzone)
            loaded.append(f"{code}:{lo}..{hi} c{center} dz{deadzone}")
        if loaded:
            PyUiLogger.get_logger().info(f"RG351P stick ranges from {node}: {', '.join(loaded)}")
        missing = [code for code in self.STICK_AXES if code not in self.stick_ranges]
        if missing:
            PyUiLogger.get_logger().warning(f"RG351P: no range for stick axes {missing} at {node}, ignored")

    def reset_chord_state(self):
        self.select_down = False
        self.menu_down = False
        self.select_released_by_chord = False

    def get_mapped_events(self, key_event):
        if key_event.event_type == self.EV_ABS:
            if key_event.code in (self.ABS_HAT0X, self.ABS_HAT0Y):
                return self.key_mappings.get(key_event)
            stick = self.stick_ranges.get(key_event.code)
            if stick is not None:
                axis, center, deadzone = stick
                return axis.get_mapped_events(key_event.value - center, deadzone)
            return None
        return super().get_mapped_events(key_event)


class RG351PKeyWatcher(KeyWatcherController):
    """KeyWatcherController that follows the USB pad by name.

    The pad re-enumerates on every wake (and can be late at boot), and its
    eventN can change if another USB input device took the number meanwhile.
    event_path is looked up by name each time it is read, so the base class's
    reopen after ENODEV/EIO finds the pad wherever it came back. The path
    given at construction is used only for the base constructor's first
    open; after that the pad is found by name only, so a stale eventN now
    held by another input device (a keyboard plugged in during sleep) is
    never opened. If the pad is missing when PyUI starts, the input thread
    waits for it instead of exiting.
    """

    @property
    def fd(self):
        return self.__dict__.get("_fd")

    @fd.setter
    def fd(self, value):
        # Every reopen (the base class's after ENODEV/EIO as well as the wait
        # below) closes the dead fd and forgets what was held: the release
        # events the kernel sends on disconnect never reach a dead fd, and a
        # stick or hat has none. The old fd is closed only after the new one
        # exists, so select() can never be handed a reused number. The base
        # constructor's first assignment (old is None) runs before lock exists.
        old = self.__dict__.get("_fd")
        self.__dict__["_fd"] = value
        if old is None or value is None or old == value:
            return
        try:
            os.close(old)
        except OSError:
            pass
        lock = self.__dict__.get("lock")
        if lock is not None:
            with lock:
                self.held_controller_inputs.clear()
        provider = self.mapping_provider
        if hasattr(provider, "reset_chord_state"):
            provider.reset_chord_state()
        thumbs = getattr(provider, "thumb_pressed_as", None)
        if thumbs is not None:
            thumbs.clear()

    @property
    def event_path(self):
        # "" makes os.open raise FileNotFoundError, which every caller
        # already treats as "not there yet, retry".
        return find_pad_node() or getattr(self, "_fallback_path", None) or ""

    @event_path.setter
    def event_path(self, value):
        self._fallback_path = value

    def poll_keyboard(self):
        # This thread starts after the base constructor's open of the
        # construction-time path, so dropping the fallback here is race-free.
        self._fallback_path = ""
        if self.fd is None:
            logger = PyUiLogger.get_logger()
            logger.warning("RG351P: pad not open yet, waiting for it")
            while self.fd is None:
                path = self.event_path
                try:
                    if not path:
                        raise OSError("no pad node")
                    self.fd = os.open(path, os.O_RDONLY)
                except OSError:
                    time.sleep(1.0)
                    continue
            logger.info(f"RG351P: pad opened at {path}")
            with self.lock:
                self.held_controller_inputs.clear()
            provider = self.mapping_provider
            if hasattr(provider, "reset_chord_state"):
                provider.reset_chord_state()
            if hasattr(provider, "load_stick_ranges"):
                pad = find_pad_node()
                if pad:
                    provider.load_stick_ranges(pad)
        return super().poll_keyboard()

    def signal_wakeup_fd(self):
        # The base returns None while the pad is not open because its thread
        # would have exited; this one keeps waiting and then services the pipe.
        return self._signal_write_fd


class RG351P(V10):
    """Anbernic RG351P on dArkMoss: the V10's panel and board, a USB pad."""

    JOYPAD_NODE = "/dev/input/event2"
    SYSTEM_JSON_NAME = "rg351p-system.json"
    SELECT_KEY = 311
    START_KEY = 310

    def _resolve_joypad(self):
        node = find_pad_node()
        if node:
            PyUiLogger.get_logger().info(f"{self.device_name}: joypad '{PAD_NAME}' at {node}")
            return node
        PyUiLogger.get_logger().error(
            f"{self.device_name}: no '{PAD_NAME}' input device yet, waiting for it"
        )
        # Never a numbered node: event2 may belong to another input device,
        # which would never fail with ENODEV and so never hand over to the
        # pad. "" leaves fd None and the watcher thread waits for the pad by name.
        return ""

    def _button_mappings(self):
        key_mappings = {}

        def bind(code, control):
            key_mappings[KeyEvent(1, code, 1)] = [InputResult(control, KeyState.PRESS)]
            key_mappings[KeyEvent(1, code, 0)] = [InputResult(control, KeyState.RELEASE)]

        bind(304, ControllerInput.A)
        bind(305, ControllerInput.B)
        bind(306, ControllerInput.X)
        bind(307, ControllerInput.Y)
        bind(308, ControllerInput.L1)
        bind(309, ControllerInput.R1)
        bind(314, ControllerInput.L2)
        bind(315, ControllerInput.R2)
        bind(self.START_KEY, ControllerInput.START)
        bind(self.SELECT_KEY, ControllerInput.SELECT)

        # Each hat press releases the opposite direction first: the hat can go
        # from -1 to 1 without reporting 0 in between.
        hat_y, hat_x = RG351PKeyMappingProvider.ABS_HAT0Y, RG351PKeyMappingProvider.ABS_HAT0X
        key_mappings[KeyEvent(3, hat_y, -1)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.RELEASE),
                                                InputResult(ControllerInput.DPAD_UP, KeyState.PRESS)]
        key_mappings[KeyEvent(3, hat_y, 1)] = [InputResult(ControllerInput.DPAD_UP, KeyState.RELEASE),
                                               InputResult(ControllerInput.DPAD_DOWN, KeyState.PRESS)]
        key_mappings[KeyEvent(3, hat_y, 0)] = [InputResult(ControllerInput.DPAD_UP, KeyState.RELEASE),
                                               InputResult(ControllerInput.DPAD_DOWN, KeyState.RELEASE)]
        key_mappings[KeyEvent(3, hat_x, -1)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.RELEASE),
                                                InputResult(ControllerInput.DPAD_LEFT, KeyState.PRESS)]
        key_mappings[KeyEvent(3, hat_x, 1)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.RELEASE),
                                               InputResult(ControllerInput.DPAD_RIGHT, KeyState.PRESS)]
        key_mappings[KeyEvent(3, hat_x, 0)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.RELEASE),
                                               InputResult(ControllerInput.DPAD_RIGHT, KeyState.RELEASE)]
        return key_mappings

    def _mapping_provider(self, key_mappings):
        # The event node is resolved separately (get_controller_interface), so
        # look the pad up here too for its stick ranges.
        provider = RG351PKeyMappingProvider(key_mappings)
        provider.load_stick_ranges(find_pad_node())
        return provider

    def get_controller_interface(self):
        # Same as DarkmossDevice's, with the watcher that follows the pad by
        # name. Wait for the pad first so the node and ranges below find it.
        wait_for_pad_node()
        return RG351PKeyWatcher(
            # Signed: the default unsigned format reads negative axis values as huge positives.
            event_format="llHHi",
            event_path=self._resolve_joypad(),
            mapping_provider=self._mapping_provider(self._button_mappings()),
        )

    def supports_wifi(self):
        # The radio is a USB dongle that may or may not be plugged in. The top
        # bar asks this every frame, so check sysfs as RG351P.sh's
        # device_has_wifi_radio does and only ask the shell (which may also
        # have marked the session radio-less) while WiFi is switched on.
        if not (glob.glob("/sys/class/net/*/phy80211") or glob.glob("/sys/class/net/*/wireless")):
            return False
        if not self.is_wifi_enabled():
            return True
        return self._wifi_status().get("radio", "1") == "1"

    # The internal output's volume is a hardware wheel after the codec: the
    # codec stays at full, with no volume setting or indicator (RG351P.sh's
    # set_volume pins it the same way on the shell side). A Bluetooth headset
    # sits outside the wheel, so while one is routed (RG351P.sh's
    # device_on_bt_audio_route keeps BT_ROUTE_FILE) the volume setting is
    # shown and its level goes to the headset.
    BT_ROUTE_FILE = "/tmp/rg351p_bt_route"

    def _bt_routed(self):
        return os.path.exists(self.BT_ROUTE_FILE)

    def supports_volume(self):
        return self._bt_routed()

    def _set_volume(self, volume):
        return super()._set_volume(volume if self._bt_routed() else 100)

    def change_volume(self, amount):
        if self._bt_routed():
            return super().change_volume(amount)
        # Internal output: keep the codec at full and leave the saved level
        # alone, so the headset level survives time on the speaker.
        self._set_volume(100)
