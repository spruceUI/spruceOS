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
EDGE_SCROLL_INTERVAL_SECONDS = 0.35
EDGE_SCROLL_MARGIN_RATIO = 0.10
EDGE_SCROLL_MIN_MARGIN_PX = 24


class TouchWatcher:
    """Turns a touchscreen's evdev stream into controller inputs.

    Reads /dev/input/eventN directly, like KeyWatcher does for keys, so it does
    not depend on SDL seeing the touchscreen (the A133P PyUI builds take input
    from evdev, not SDL). Swipe navigation is dispatched as the drag crosses
    its thresholds; taps and long presses are decided when the finger lifts:

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
        self.swipe_direction = None
        self.swipe_steps = 0
        self.swipe_distance = 0
        self.next_swipe_step_distance = TAP_MAX_MOVE_PX
        self.touch_drag_view = None
        self.touch_drag_index = None
        self.direct_drag = False
        self.touch_scroll_view = None
        self.touch_scroll_step_size = 0
        self.touch_scroll_distance = 0
        self.touch_edge_scroll_enabled = False
        self.touch_edge_direction = None
        self.next_touch_edge_scroll_time = None

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
                previous_point = None
                self._begin_touch_drag(point)
            else:
                previous_point = self.last
            self.last = point
            if previous_point is not None:
                self._update_swipe(previous_point, point)
        if self.pending_up:
            if self.start is not None and self.last is not None:
                self._gesture()
            self._reset_contact()

    def _begin_touch_drag(self, point):
        from controller.controller import Controller
        view = Controller.touch_navigation_view
        if view is None:
            return
        index = view.touch_index_at(point)
        self.touch_edge_scroll_enabled = not hasattr(view, "rows") or view.rows > 1
        if hasattr(view, "touch_uses_dpad_swipe") and view.touch_uses_dpad_swipe(point):
            return
        starts_scroll = (
            view.touch_starts_scroll(point)
            if hasattr(view, "touch_starts_scroll")
            else index is not None and index != view.selected
        )
        if starts_scroll and hasattr(view, "touch_scroll_step_size"):
            self.touch_scroll_view = view
            self.touch_scroll_step_size = max(1, view.touch_scroll_step_size())
        elif index == view.selected:
            self.touch_drag_view = view
            self.touch_drag_index = index

    def _update_swipe(self, previous_point, point):
        dx = point[0] - previous_point[0]
        dy = point[1] - previous_point[1]
        if self.touch_drag_view is not None:
            sx, sy, _t0 = self.start
            if not self.direct_drag and math.hypot(point[0] - sx, point[1] - sy) < TAP_MAX_MOVE_PX:
                return
            self.direct_drag = True
            self._update_touch_drag(point)
            self._update_touch_edge_scroll(point)
            return

        if self.touch_scroll_view is not None:
            sx, sy, _t0 = self.start
            if math.hypot(point[0] - sx, point[1] - sy) >= TAP_MAX_MOVE_PX:
                self.direct_drag = True
            if abs(dy) > abs(dx):
                self.touch_scroll_distance -= dy
                while self.touch_scroll_distance >= self.touch_scroll_step_size:
                    self._inject(ControllerInput.TOUCH_SCROLL_UP)
                    self.touch_scroll_distance -= self.touch_scroll_step_size
                while self.touch_scroll_distance <= -self.touch_scroll_step_size:
                    self._inject(ControllerInput.TOUCH_SCROLL_DOWN)
                    self.touch_scroll_distance += self.touch_scroll_step_size
            return

        if dx == 0 and dy == 0:
            return

        if abs(dx) >= abs(dy):
            # Content follows the finger: dragging right reveals what is to the left.
            direction = ControllerInput.DPAD_LEFT if dx > 0 else ControllerInput.DPAD_RIGHT
        else:
            direction = ControllerInput.DPAD_UP if dy > 0 else ControllerInput.DPAD_DOWN

        if direction != self.swipe_direction:
            self.swipe_direction = direction
            self.swipe_distance = 0
            self.next_swipe_step_distance = TAP_MAX_MOVE_PX

        self.swipe_distance += math.hypot(dx, dy)
        while self.swipe_distance >= self.next_swipe_step_distance:
            self.swipe_steps += 1
            self._inject(direction)
            self.next_swipe_step_distance = (
                2 * SWIPE_STEP_PX
                if self.next_swipe_step_distance == TAP_MAX_MOVE_PX
                else self.next_swipe_step_distance + SWIPE_STEP_PX
            )

    def _update_touch_drag(self, point):
        index = self.touch_drag_view.touch_index_at(point)
        if index is None or index == self.touch_drag_index:
            return

        self._inject(ControllerInput.TOUCH_DRAG, point)
        self.touch_drag_index = index

    def _update_touch_edge_scroll(self, point):
        if not self.touch_edge_scroll_enabled:
            return

        screen_height = self.device.screen_height()
        margin = max(EDGE_SCROLL_MIN_MARGIN_PX, int(screen_height * EDGE_SCROLL_MARGIN_RATIO))
        if point[1] < margin:
            direction = ControllerInput.DPAD_UP
        elif point[1] >= screen_height - margin:
            direction = ControllerInput.DPAD_DOWN
        else:
            direction = None

        if direction != self.touch_edge_direction:
            self.touch_edge_direction = direction
            self.next_touch_edge_scroll_time = (
                time.monotonic() + EDGE_SCROLL_INTERVAL_SECONDS
                if direction is not None
                else None
            )

    def _maybe_scroll_at_touch_edge(self):
        if (
            not self.down
            or not self.direct_drag
            or self.touch_drag_view is None
            or self.touch_edge_direction is None
            or self.next_touch_edge_scroll_time is None
        ):
            return

        now = time.monotonic()
        if now >= self.next_touch_edge_scroll_time:
            self._inject(self.touch_edge_direction)
            self.next_touch_edge_scroll_time = now + EDGE_SCROLL_INTERVAL_SECONDS

    def _gesture(self):
        if self.swipe_steps or self.direct_drag:
            return

        sx, sy, t0 = self.start
        lx, ly = self.last
        dx, dy = lx - sx, ly - sy
        dist = math.hypot(dx, dy)
        held = time.monotonic() - t0
        if dist < TAP_MAX_MOVE_PX:
            if held >= LONG_PRESS_SECONDS:
                self._inject(ControllerInput.B)
            else:
                self._inject(ControllerInput.TOUCH_TAP, (lx, ly))

    def _inject(self, controller_input, touch_point=None):
        from controller.controller import Controller
        if (
            Controller.ignore_vertical_touch_swipes
            and controller_input in (ControllerInput.DPAD_UP, ControllerInput.DPAD_DOWN)
        ):
            return
        interface = Controller.controller_interface
        if interface is None:
            return
        if touch_point is None:
            interface.inject_input(controller_input)
        else:
            interface.inject_touch_input(controller_input, touch_point)

    # ----- thread body -----
    def poll(self):
        logger = PyUiLogger.get_logger()
        while True:
            if self.fd is None:
                time.sleep(1.0)
                self._open()
                continue
            try:
                timeout = 1.0
                if self.next_touch_edge_scroll_time is not None:
                    timeout = max(
                        0.0,
                        min(timeout, self.next_touch_edge_scroll_time - time.monotonic()),
                    )
                rlist, _, _ = select.select([self.fd], [], [], timeout)
                if not rlist:
                    self._maybe_scroll_at_touch_edge()
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
            self._maybe_scroll_at_touch_edge()
