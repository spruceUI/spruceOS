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
MENU_LONG_PRESS_MAX_MOVE_PX = 48
DOUBLE_TAP_MAX_DISTANCE_PX = 48
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
      double tap in a top/bottom bar -> ControllerInput.A (confirm selection)
      double tap in game selection content -> ControllerInput.A without changing
                     the selected game; a single tap does not change selection
      swipe       -> DPAD presses in the direction the content should move
                     (one press per SWIPE_STEP_PX)
      long press -> ControllerInput.MENU on the left third of the top bar,
                    ControllerInput.X on the middle third, otherwise B (back)

    Raw coordinates are scaled to the panel from the device's reported ABS
    range and then mapped through the inverse of the rotation Display applies
    (screen_rotation()), so the point lands in the same logical space the
    views render in.
    """

    def __init__(self, event_path, device, event_format='llHHi'):
        self.event_path = event_path
        self.device = device
        self.system_config = device.get_system_config()
        self.event_format = event_format
        self.event_size = struct.calcsize(event_format)
        self.fd = None
        self._open()
        self.x_range = self._abs_range(ABS_MT_POSITION_X) or self._abs_range(ABS_X) or (0, max(1, self._panel_size()[0] - 1))
        self.y_range = self._abs_range(ABS_MT_POSITION_Y) or self._abs_range(ABS_Y) or (0, max(1, self._panel_size()[1] - 1))
        self.last_scroll_bar_tap = None
        self.last_popup_outside_tap = None
        self.pending_game_selection_tap = None
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
        self.long_press_triggered = False
        self.next_long_press_time = None
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
        self.touch_scroll_axis = None
        self.touch_edge_scroll_enabled = False
        self.touch_edge_scroll_axis = None
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
        self._maybe_trigger_long_press()
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
        if hasattr(view, "touch_edge_scroll_axis"):
            self.touch_edge_scroll_axis = view.touch_edge_scroll_axis()
            self.touch_edge_scroll_enabled = self.touch_edge_scroll_axis is not None
        if (
            hasattr(view, "touch_follows_finger_from_anywhere")
            and view.touch_follows_finger_from_anywhere(point)
        ):
            self.touch_drag_view = view
            self.touch_drag_index = view.selected
            return
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
            self.touch_scroll_axis = (
                view.touch_scroll_axis()
                if hasattr(view, "touch_scroll_axis")
                else "vertical"
            )
        elif index == view.selected:
            self.touch_drag_view = view
            self.touch_drag_index = index

    def _update_swipe(self, previous_point, point):
        dx = point[0] - previous_point[0]
        dy = point[1] - previous_point[1]
        if (
            self.start is not None
            and self._top_bar_long_press_input(self.start[:2]) is not None
            and math.hypot(
                point[0] - self.start[0],
                point[1] - self.start[1],
            ) < MENU_LONG_PRESS_MAX_MOVE_PX
        ):
            return

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
            if self.touch_scroll_axis == "horizontal" and abs(dy) > abs(dx):
                if (
                    hasattr(self.touch_scroll_view, "touch_scroll_other_axis_follows_finger")
                    and self.touch_scroll_view.touch_scroll_other_axis_follows_finger()
                ):
                    self.touch_drag_view = self.touch_scroll_view
                    self.touch_drag_index = self._touch_drag_index_at(
                        self.touch_scroll_view, self.start[:2]
                    )
                    self.touch_scroll_view = None
                    self._update_touch_drag(point)
                return
            if self.touch_scroll_axis == "vertical" and abs(dx) > abs(dy):
                if (
                    hasattr(self.touch_scroll_view, "touch_scroll_other_axis_follows_finger")
                    and self.touch_scroll_view.touch_scroll_other_axis_follows_finger()
                ):
                    self.touch_drag_view = self.touch_scroll_view
                    self.touch_drag_index = self.touch_scroll_view.touch_index_at(self.start[:2])
                    self.touch_scroll_view = None
                    self._update_touch_drag(point)
                return
            delta = dx if self.touch_scroll_axis == "horizontal" else dy
            self.touch_scroll_distance -= delta
            if self.touch_scroll_axis == "horizontal":
                forward_input = ControllerInput.TOUCH_SCROLL_LEFT
                backward_input = ControllerInput.TOUCH_SCROLL_RIGHT
            else:
                forward_input = ControllerInput.TOUCH_SCROLL_UP
                backward_input = ControllerInput.TOUCH_SCROLL_DOWN
            while self.touch_scroll_distance >= self.touch_scroll_step_size:
                self._inject(forward_input)
                self.touch_scroll_distance -= self.touch_scroll_step_size
            while self.touch_scroll_distance <= -self.touch_scroll_step_size:
                self._inject(backward_input)
                self.touch_scroll_distance += self.touch_scroll_step_size
            return

        if dx == 0 and dy == 0:
            return

        if abs(dx) >= abs(dy):
            # Content follows the finger: dragging right reveals what is to the left.
            direction = ControllerInput.DPAD_LEFT if dx > 0 else ControllerInput.DPAD_RIGHT
        else:
            direction = ControllerInput.DPAD_UP if dy > 0 else ControllerInput.DPAD_DOWN

        from controller.controller import Controller
        view = Controller.touch_navigation_view
        if view is not None and hasattr(view, "touch_swipe_direction"):
            direction = view.touch_swipe_direction(dx, dy)
        if direction is None:
            return

        if direction != self.swipe_direction:
            self.swipe_direction = direction
            self.swipe_distance = 0
            self.next_swipe_step_distance = TAP_MAX_MOVE_PX

        sensitivity = (
            view.touch_swipe_sensitivity()
            if view is not None and hasattr(view, "touch_swipe_sensitivity")
            else 1
        )
        self.swipe_distance += math.hypot(dx, dy) * sensitivity
        while self.swipe_distance >= self.next_swipe_step_distance:
            self.swipe_steps += 1
            self._inject(direction)
            self.next_swipe_step_distance = (
                2 * SWIPE_STEP_PX
                if self.next_swipe_step_distance == TAP_MAX_MOVE_PX
                else self.next_swipe_step_distance + SWIPE_STEP_PX
            )

    def _update_touch_drag(self, point):
        index = self._touch_drag_index_at(self.touch_drag_view, point)
        if index is None or index == self.touch_drag_index:
            return

        self._inject(ControllerInput.TOUCH_DRAG, point)
        self.touch_drag_index = index

    @staticmethod
    def _touch_drag_index_at(view, point):
        if hasattr(view, "touch_drag_index_at"):
            return view.touch_drag_index_at(point)
        return view.touch_index_at(point)

    def _update_touch_edge_scroll(self, point):
        if not self.touch_edge_scroll_enabled:
            return

        if self.touch_edge_scroll_axis == "horizontal":
            position = point[0]
            screen_size = self.device.screen_width()
            leading_direction = ControllerInput.DPAD_LEFT
            trailing_direction = ControllerInput.DPAD_RIGHT
        else:
            position = point[1]
            screen_size = self.device.screen_height()
            leading_direction = ControllerInput.DPAD_UP
            trailing_direction = ControllerInput.DPAD_DOWN

        edge_bounds = (
            self.touch_drag_view.touch_edge_scroll_bounds()
            if hasattr(self.touch_drag_view, "touch_edge_scroll_bounds")
            else None
        )
        if edge_bounds is not None and self.touch_edge_scroll_axis == "vertical":
            leading_edge, trailing_edge = edge_bounds
            if position < leading_edge:
                direction = leading_direction
            elif position >= trailing_edge:
                direction = trailing_direction
            else:
                direction = None
        else:
            margin = max(
                EDGE_SCROLL_MIN_MARGIN_PX,
                int(screen_size * self.system_config.get_touch_edge_scroll_margin_ratio())
            )
            if position < margin:
                direction = leading_direction
            elif position >= screen_size - margin:
                direction = trailing_direction
            else:
                direction = None

        if direction != self.touch_edge_direction:
            self.touch_edge_direction = direction
            self.next_touch_edge_scroll_time = (
                time.monotonic() + self.system_config.get_touch_edge_scroll_interval_seconds()
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
            if (
                hasattr(self.touch_drag_view, "touch_can_scroll")
                and not self.touch_drag_view.touch_can_scroll(self.touch_edge_direction)
            ):
                self.next_touch_edge_scroll_time = None
                return
            edge_scroll_input = {
                ControllerInput.DPAD_UP: ControllerInput.TOUCH_SCROLL_DOWN,
                ControllerInput.DPAD_DOWN: ControllerInput.TOUCH_SCROLL_UP,
                ControllerInput.DPAD_LEFT: ControllerInput.TOUCH_SCROLL_RIGHT,
                ControllerInput.DPAD_RIGHT: ControllerInput.TOUCH_SCROLL_LEFT,
            }[self.touch_edge_direction]
            self._inject(edge_scroll_input)
            self.next_touch_edge_scroll_time = now + self.system_config.get_touch_edge_scroll_interval_seconds()

    def _maybe_trigger_long_press(self):
        if (
            not self.down
            or self.start is None
            or self.last is None
            or self.swipe_steps
            or self.direct_drag
        ):
            self.next_long_press_time = None
            return

        sx, sy, started_at = self.start
        lx, ly = self.last
        max_move = (
            MENU_LONG_PRESS_MAX_MOVE_PX
            if self._top_bar_long_press_input((sx, sy)) is not None
            else TAP_MAX_MOVE_PX
        )
        if math.hypot(lx - sx, ly - sy) >= max_move:
            self.next_long_press_time = None
            return

        if self.next_long_press_time is None:
            if self.long_press_triggered:
                return
            self.next_long_press_time = started_at + self.system_config.get_touch_long_press_seconds()

        now = time.monotonic()
        if now >= self.next_long_press_time:
            self.long_press_triggered = True
            top_bar_input = self._top_bar_long_press_input((sx, sy))
            if top_bar_input is not None:
                self._inject(top_bar_input)
                self.next_long_press_time = None
            else:
                self._inject(ControllerInput.B)
                self.next_long_press_time = now + self.system_config.get_touch_long_press_seconds()

    def _top_bar_long_press_input(self, point):
        from display.display import Display

        x, y = point
        if not 0 <= y < Display.top_bar.get_top_bar_height():
            return None
        screen_width = self.device.screen_width()
        if 0 <= x < screen_width / 3:
            return ControllerInput.MENU
        if screen_width / 3 <= x < 2 * screen_width / 3:
            return ControllerInput.X
        return None

    def _gesture(self):
        if self.swipe_steps or self.direct_drag or self.long_press_triggered:
            self._clear_pending_game_selection_tap()
            self.last_popup_outside_tap = None
            self.last_scroll_bar_tap = None
            return

        sx, sy, t0 = self.start
        lx, ly = self.last
        dx, dy = lx - sx, ly - sy
        dist = math.hypot(dx, dy)
        held = time.monotonic() - t0
        if dist < TAP_MAX_MOVE_PX:
            if held >= self.system_config.get_touch_long_press_seconds():
                self._clear_pending_game_selection_tap()
                self.last_popup_outside_tap = None
                self._inject(ControllerInput.B)
                self.last_scroll_bar_tap = None
            else:
                point = (lx, ly)
                view = self._touch_navigation_view()
                if getattr(view, "touch_tap_activates_item", False):
                    self._clear_pending_game_selection_tap()
                    self.last_popup_outside_tap = None
                    self.last_scroll_bar_tap = None
                    if hasattr(view, "touch_tap_input"):
                        controller_input = view.touch_tap_input(point)
                        if controller_input is not None:
                            self._inject(controller_input)
                            return
                    self._inject(ControllerInput.TOUCH_TAP, point)
                    return
                if hasattr(view, "touch_point_is_inside_popup"):
                    self._clear_pending_game_selection_tap()
                    if view.touch_point_is_inside_popup(point):
                        self.last_popup_outside_tap = None
                        self.last_scroll_bar_tap = None
                        self._inject(ControllerInput.TOUCH_TAP, point)
                        return

                    now = time.monotonic()
                    previous_tap = self.last_popup_outside_tap
                    if (
                        previous_tap is not None
                        and previous_tap[0] is view
                        and now - previous_tap[1] <= self.system_config.get_touch_double_tap_seconds()
                    ):
                        self.last_popup_outside_tap = None
                        self._inject(ControllerInput.A)
                        return

                    self.last_popup_outside_tap = (view, now)
                    return

                self.last_popup_outside_tap = None
                is_tab_tap, tab_input = self._top_bar_tab_input(point)
                region = self._scroll_bar_region(point)
                if is_tab_tap:
                    self._clear_pending_game_selection_tap()
                    self.last_scroll_bar_tap = None
                elif region is not None:
                    self._clear_pending_game_selection_tap()
                    now = time.monotonic()
                    previous_tap = self.last_scroll_bar_tap
                    if (
                        previous_tap is not None
                        and previous_tap[0] == region
                        and now - previous_tap[2] <= self.system_config.get_touch_double_tap_seconds()
                        and math.hypot(
                            point[0] - previous_tap[1][0],
                            point[1] - previous_tap[1][1],
                        ) <= DOUBLE_TAP_MAX_DISTANCE_PX
                    ):
                        self.last_scroll_bar_tap = None
                        self._inject(ControllerInput.A)
                        return
                    self.last_scroll_bar_tap = (region, point, now)
                else:
                    self.last_scroll_bar_tap = None
                    if self._is_game_selection_content_tap():
                        now = time.monotonic()
                        previous_tap = self.pending_game_selection_tap
                        if (
                            previous_tap is not None
                            and previous_tap[0] is self._touch_navigation_view()
                            and now - previous_tap[2] <= self.system_config.get_touch_double_tap_seconds()
                            and math.hypot(
                                point[0] - previous_tap[1][0],
                                point[1] - previous_tap[1][1],
                            ) <= DOUBLE_TAP_MAX_DISTANCE_PX
                        ):
                            self.pending_game_selection_tap = None
                            self._inject(ControllerInput.A)
                            return
                        self._clear_pending_game_selection_tap()
                        self.pending_game_selection_tap = (
                            self._touch_navigation_view(),
                            point,
                            now,
                        )
                        return
                    self._clear_pending_game_selection_tap()

                if not is_tab_tap:
                    self._inject(ControllerInput.TOUCH_TAP, point)
                elif tab_input is not None:
                    self._inject(tab_input)
        else:
            self._clear_pending_game_selection_tap()
            self.last_popup_outside_tap = None
            self.last_scroll_bar_tap = None

    @staticmethod
    def _touch_navigation_view():
        from controller.controller import Controller

        return Controller.touch_navigation_view

    def _is_game_selection_content_tap(self):
        from utils.py_ui_state import PyUiState

        view = self._touch_navigation_view()
        return (
            PyUiState.get_in_game_selection_screen()
            and view is not None
        )

    def _clear_pending_game_selection_tap(self):
        self.pending_game_selection_tap = None

    def _scroll_bar_region(self, point):
        from display.display import Display

        y = point[1]
        if y < Display.top_bar.get_top_bar_height():
            return "top"
        if y >= self.device.screen_height() - Display.bottom_bar.get_bottom_bar_height():
            return "bottom"
        return None

    @staticmethod
    def _top_bar_tab_input(point):
        from display.display import Display
        from themes.theme import Theme
        if not Theme.skip_main_menu():
            return False, None

        top_bar = Display.top_bar
        tab = top_bar.touch_tab_at(point)
        if tab is None:
            return False, None
        if tab == top_bar.selected_tab:
            return True, None

        transitions = {
            "Game": {"App": ControllerInput.R1, "Setting": ControllerInput.L1},
            "App": {"Game": ControllerInput.L1, "Setting": ControllerInput.R1},
            "Setting": {"Game": ControllerInput.R1, "App": ControllerInput.L1},
        }
        return True, transitions.get(top_bar.selected_tab, {}).get(tab)

    def _inject(self, controller_input, touch_point=None):
        from controller.controller import Controller
        view = Controller.touch_navigation_view
        if (
            Controller.ignore_vertical_touch_swipes
            and view is not None
            and hasattr(view, "touch_ignores_vertical_swipes")
            and view.touch_ignores_vertical_swipes()
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
                if (
                    self.down
                    and self.start is not None
                    and self.next_long_press_time is not None
                    and not self.swipe_steps
                    and not self.direct_drag
                ):
                    timeout = max(
                        0.0,
                        min(timeout, self.next_long_press_time - time.monotonic()),
                    )
                if self.next_touch_edge_scroll_time is not None:
                    timeout = max(
                        0.0,
                        min(timeout, self.next_touch_edge_scroll_time - time.monotonic()),
                    )
                if self.pending_game_selection_tap is not None:
                    timeout = max(
                        0.0,
                        min(
                            timeout,
                            self.pending_game_selection_tap[2]
                            + self.system_config.get_touch_double_tap_seconds()
                            - time.monotonic(),
                        ),
                    )
                rlist, _, _ = select.select([self.fd], [], [], timeout)
                if not rlist:
                    self._maybe_trigger_long_press()
                    self._maybe_scroll_at_touch_edge()
                    self._flush_expired_game_selection_tap()
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
            self._flush_expired_game_selection_tap()

    def _flush_expired_game_selection_tap(self):
        if (
            self.pending_game_selection_tap is not None
            and time.monotonic() - self.pending_game_selection_tap[2]
            >= self.system_config.get_touch_double_tap_seconds()
        ):
            self._clear_pending_game_selection_tap()
