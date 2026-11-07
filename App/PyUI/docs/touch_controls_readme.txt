PyUI touch controls
===================

Overview
--------

Touch input is read directly from a Linux evdev touchscreen device by
main-ui/controller/touch_watcher.py. It does not rely on SDL receiving touch
events. The watcher converts raw input events into logical-screen coordinates,
recognizes taps, swipes, drags, long presses and edge scrolling, then injects
ControllerInput events through the active controller interface. The normal
view/controller loop handles those inputs alongside physical controls.

Device setup
------------

EnvVarDevice starts the watcher only in main UI mode and when supports_touch()
is true, which for this device means TOUCH_EVENT_PATH is set. The path must
also exist; otherwise touch is left off and a warning is logged. Device
launch configuration should set TOUCH_EVENT_PATH to the touchscreen's
/dev/input/eventN node.

The dArkMoss RG353M implementation discovers its touchscreen by scanning
/sys/class/input/*/device/capabilities/abs for an absolute-axis capability
bit, then starts the same watcher. Other device implementations may provide
their own detection and startup behavior.

TouchWatcher opens the event node non-blocking and reads Linux EV_ABS,
EV_KEY and EV_SYN events. It uses multitouch position axes when present and
falls back to ABS_X/ABS_Y; contact start/end is tracked using
ABS_MT_TRACKING_ID and/or BTN_TOUCH. If opening or reading the device fails,
the watcher logs the issue and retries/reopens it.

Coordinates and contact tracking
---------------------------------

The watcher queries each axis's absolute minimum and maximum with EVIOCGABS.
If an axis range is unavailable, the panel dimensions provide a fallback.
Raw positions are scaled to the physical panel, transformed through the
inverse of the display rotation, and clamped to the logical screen bounds.
Views therefore hit-test the same coordinate space they use for rendering.

One contact is tracked at a time. A SYN_REPORT updates the current point;
finger-up finalizes the gesture and resets the contact state. The implementation
uses monotonic time for gesture durations and timers.

Gesture behavior
----------------

Tap
  Movement under 24 logical pixels is considered tap-sized. TOUCH_TAP carries
  its logical point through the controller input queue. List and grid views
  hit-test that point: a list tap selects a different row, and confirms the
  already-selected row; a grid tap selects and confirms the hit cell.
  Carousel and popup views also have view-specific touch hit testing.

  Some views mark taps as immediate activation and may map a tap to another
  controller input. A tap inside a popup is delivered to its contents. A
  double tap outside a popup confirms with A. In game-selection content, a
  single tap is deferred and discarded; a second tap on the same active view
  within the configured interval and 48 logical pixels sends A without
  changing the selected game. Top and bottom bars likewise use a same-bar
  double tap, within 48 pixels, to send A. In themes that skip the main menu,
  tapping a different top-bar tab switches tabs using L1/R1.

Swipe navigation
  A swipe injects a D-pad input in the direction that moves the content as
  intended; the active view can choose or suppress the direction. Each swipe
  starts dispatching after 24 logical pixels, then dispatches another step
  for each additional 90 pixels. View-provided sensitivity can adjust this
  distance. Some views restrict swipe navigation to a specific region.

Direct drag
  Starting on the selected item (or on a view that follows the finger) allows
  dragging through items. Once movement reaches 24 pixels, crossing to a
  different hit-tested item injects TOUCH_DRAG with the current point.

Touch scrolling
  On views that opt in, dragging from an unselected item scrolls the viewport
  rather than changing selection directly. Each view provides the scroll axis
  and step size; accumulated finger movement injects TOUCH_SCROLL_UP/DOWN or
  LEFT/RIGHT. Grid and list views update their visible range while preserving
  the selection's relative position where possible.

Edge scrolling
  A direct drag held near a view's leading or trailing edge periodically
  scrolls the view. Views provide the applicable axis and may provide custom
  edge bounds or report whether more scrolling is possible. The default edge
  margin is the greater of 24 logical pixels and 15 percent of the relevant
  screen dimension. The default repeat interval is 0.30 seconds.

Long press
  A stationary press reaches the default 0.50-second threshold to activate a
  long press. On the top bar, the left third sends MENU and the middle third
  sends X (once). Elsewhere, including the right third of the top bar, it
  sends B repeatedly at the long-press interval until release. Movement beyond
  the tap threshold cancels a regular long press; top-bar long presses allow
  up to 48 pixels of movement.

Configuration
-------------

The touch timing values are read from the system configuration via
devices/miyoo/device_user_config.py and saved by its setters:

  touchLongPressSeconds             default 0.50 seconds
  touchDoubleTapSeconds             default 0.35 seconds
  touchEdgeScrollIntervalSeconds    default 0.30 seconds
  touchEdgeScrollMarginRatio        default 0.15 (15 percent)

When Device.supports_touch() is true, Controller Settings exposes controls
for these values. The UI allows long press from 0.2 to 2.0 seconds, double tap
from 0.10 to 1.0 seconds, edge-scroll interval from 0.10 to 1.0 seconds, and
edge margin ratio from 0.05 to 0.25.

Implementation map
------------------

  main-ui/controller/touch_watcher.py
      evdev reading, coordinate transforms, gesture recognition and injection
  main-ui/controller/controller_inputs.py
      TOUCH_TAP, TOUCH_DRAG and TOUCH_SCROLL input identifiers
  main-ui/controller/controller.py
      current touch navigation view and pending touch-point storage
  main-ui/controller/key_watcher_controller.py
      queues injected input and its optional touch point
  main-ui/views/list_view.py, grid_view.py, carousel_view.py
      touch hit-testing and view behavior
  main-ui/menus/settings/controller_settings_menu.py
      touch timing and edge-scroll settings
