import errno
import fcntl
import math
import os
import select
import struct
import time

from controller.controller_inputs import ControllerInput
from utils.logger import PyUiLogger

# Linux input constants
EV_SYN = 0x00
EV_KEY = 0x01
EV_ABS = 0x03
SYN_REPORT = 0
BTN_TOUCH = 0x14a
ABS_X = 0x00
ABS_Y = 0x01
ABS_MT_SLOT = 0x2f
ABS_MT_POSITION_X = 0x35
ABS_MT_POSITION_Y = 0x36
ABS_MT_TRACKING_ID = 0x39

# Gesture thresholds, in logical (UI) pixels and seconds
TAP_MAX_MOVE_PX = 24
SWIPE_STEP_PX = 90
LONG_PRESS_SECONDS = 0.6


class TouchWatcher:
    """Turns a touchscreen's evdev stream into controller inputs.

    Reads /dev/input/eventN directly, like KeyWatcher does for keys, so it does
    not depend on SDL seeing the touchscreen (the A133P PyUI builds take input
    from evdev, not SDL). Gestures, decided when the finger lifts:

      tap         -> ControllerInput.TOUCH_TAP with the point stored on the
                     Controller; list and grid views select the tapped item and
                     confirm it when it was already selected
      swipe       -> DPAD presses in the direction the content should move
                     (one press per SWIPE_STEP_PX)
      long press  -> ControllerInput.B (back)

    Raw coordinates are scaled to the panel from the device's reported ABS
    range and then mapped through the inverse of the rotation Display applies
    (screen_rotation()), so the point lands in the same logical space the
    views render in.
    """

    def __init__(self, event_path, device, event_format='llHHi'):
        self.event_path = event_path
        self.device = device
        self.event_format = event_format
        self.event_size = struct.calcsize(event_format)
        self.fd = None
        self._open()
        self.x_range = self._abs_range(ABS_MT_POSITION_X) or self._abs_range(ABS_X) or (0, max(1, self._panel_size()[0] - 1))
        self.y_range = self._abs_range(ABS_MT_POSITION_Y) or self._abs_range(ABS_Y) or (0, max(1, self._panel_size()[1] - 1))
        self._reset_contact()
        PyUiLogger.get_logger().info(
            f"Touch on {event_path}: x {self.x_range} y {self.y_range} rotation {device.screen_rotation()}")

    # ----- device -----
    def _open(self):
        try:
            self.fd = os.open(self.event_path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError as e:
            PyUiLogger.get_logger().warning(f"Unable to open touchscreen {self.event_path}: {e}")
            self.fd = None

    def _abs_range(self, axis):
        """(min, max) from EVIOCGABS, or None if the axis is absent."""
        if self.fd is None:
            return None
        # _IOR('E', 0x40 + axis, struct input_absinfo[24 bytes])
        request = 0x80184540 + axis
        buf = bytearray(24)
        try:
            fcntl.ioctl(self.fd, request, buf)
        except OSError:
            return None
        _value, minimum, maximum, _fuzz, _flat, _res = struct.unpack('6i', bytes(buf))
        if maximum <= minimum:
            return None
        return (minimum, maximum)

    def _panel_size(self):
        w, h = self.device.screen_width(), self.device.screen_height()
        if self.device.screen_rotation() % 360 in (90, 270):
            return h, w
        return w, h

    # ----- geometry -----
    def _to_logical(self, raw_x, raw_y):
        panel_w, panel_h = self._panel_size()
        px = (raw_x - self.x_range[0]) * panel_w / (self.x_range[1] - self.x_range[0] + 1)
        py = (raw_y - self.y_range[0]) * panel_h / (self.y_range[1] - self.y_range[0] + 1)
        w, h = self.device.screen_width(), self.device.screen_height()
        rot = self.device.screen_rotation() % 360
        # Display.rotate_canvas draws the logical canvas rotated clockwise by rot
        # onto the panel; invert that so the point is in logical coordinates.
        if rot == 90:
            lx, ly = py, (h - 1) - px
        elif rot == 270:
            lx, ly = (w - 1) - py, px
        elif rot == 180:
            lx, ly = (w - 1) - px, (h - 1) - py
        else:
            lx, ly = px, py
        return int(max(0, min(w - 1, lx))), int(max(0, min(h - 1, ly)))

    # ----- contact tracking -----
    def _reset_contact(self):
        self.down = False
        self.raw_x = None
        self.raw_y = None
        self.start = None      # (lx, ly, t)
        self.last = None       # (lx, ly)
        self.pending_up = False

    def _handle(self, event_type, code, value):
        if event_type == EV_ABS:
            if code in (ABS_MT_POSITION_X, ABS_X):
                self.raw_x = value
            elif code in (ABS_MT_POSITION_Y, ABS_Y):
                self.raw_y = value
            elif code == ABS_MT_TRACKING_ID:
                if value == -1:
                    self.pending_up = True
                else:
                    self.down = True
        elif event_type == EV_KEY and code == BTN_TOUCH:
            if value:
                self.down = True
            else:
                self.pending_up = True
        elif event_type == EV_SYN and code == SYN_REPORT:
            self._sync()

    def _sync(self):
        if self.down and self.raw_x is not None and self.raw_y is not None:
            point = self._to_logical(self.raw_x, self.raw_y)
            if self.start is None:
                self.start = (point[0], point[1], time.monotonic())
            self.last = point
        if self.pending_up:
            if self.start is not None and self.last is not None:
                self._gesture()
            self._reset_contact()

    def _gesture(self):
        sx, sy, t0 = self.start
        lx, ly = self.last
        dx, dy = lx - sx, ly - sy
        dist = math.hypot(dx, dy)
        held = time.monotonic() - t0
        from controller.controller import Controller
        if dist < TAP_MAX_MOVE_PX:
            if held >= LONG_PRESS_SECONDS:
                self._inject(ControllerInput.B)
            else:
                Controller.set_touch_point(lx, ly)
                self._inject(ControllerInput.TOUCH_TAP)
            return
        steps = max(1, int(dist // SWIPE_STEP_PX))
        if abs(dx) >= abs(dy):
            # content follows the finger: dragging right reveals what is to the left
            direction = ControllerInput.DPAD_LEFT if dx > 0 else ControllerInput.DPAD_RIGHT
        else:
            direction = ControllerInput.DPAD_UP if dy > 0 else ControllerInput.DPAD_DOWN
        for _ in range(steps):
            self._inject(direction)

    def _inject(self, controller_input):
        from controller.controller import Controller
        interface = Controller.controller_interface
        if interface is None:
            return
        interface.inject_input(controller_input)

    # ----- thread body -----
    def poll(self):
        logger = PyUiLogger.get_logger()
        while True:
            if self.fd is None:
                time.sleep(1.0)
                self._open()
                continue
            try:
                rlist, _, _ = select.select([self.fd], [], [], 1.0)
                if not rlist:
                    continue
                data = os.read(self.fd, self.event_size * 64)
            except OSError as e:
                if e.errno in (errno.EAGAIN, errno.EINTR):
                    continue
                logger.warning(f"Touchscreen read failed ({e}); reopening")
                try:
                    os.close(self.fd)
                except OSError:
                    pass
                self.fd = None
                continue
            for offset in range(0, len(data) - self.event_size + 1, self.event_size):
                _sec, _usec, event_type, code, value = struct.unpack(
                    self.event_format, data[offset:offset + self.event_size])
                try:
                    self._handle(event_type, code, value)
                except Exception as e:
                    logger.exception(f"Error processing touch event: {e}")
