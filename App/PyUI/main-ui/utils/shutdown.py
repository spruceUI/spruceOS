"""The menu's farewell frame at power-off (docs/shutdown_readme.txt).

The SIGURG handler only notes the request. The main thread draws the farewell at
its next checkpoint (an input wait or a present) and then sleeps there until the
shell kills it.
"""

import signal
import threading

from utils.logger import PyUiLogger

_requested = False
_ui_thread = None
_show_farewell = None


def _note_request(signum, frame):
    # Only a flag: drawing or locking here could deadlock the UI code. Python also
    # writes the signal to the wakeup fd (see arm), which ends an idle input wait.
    global _requested
    _requested = True


def listen():
    """Note power-off requests from now on. The menu only, on the main thread."""
    signal.signal(signal.SIGURG, _note_request)


def arm(show_farewell, wakeup_fd=None):
    """Let the calling (main) thread's checkpoints call show_farewell(), at once if
    power-off was already requested. wakeup_fd (ControllerInterface.signal_wakeup_fd)
    wakes an idle input wait; without one the menu notices at its next redraw."""
    global _ui_thread, _show_farewell
    if wakeup_fd is not None:
        signal.set_wakeup_fd(wakeup_fd, warn_on_full_buffer=False)
    _show_farewell = show_farewell
    _ui_thread = threading.get_ident()
    checkpoint()


def checkpoint():
    """Once power-off is requested, on the UI thread: show the farewell and never return."""
    global _ui_thread
    if not _requested or threading.get_ident() != _ui_thread:
        return
    _ui_thread = None  # drawing the farewell must not come back here
    try:
        _show_farewell()
    except Exception:
        PyUiLogger.get_logger().exception("Could not show the farewell frame")
    # Keep the frame on screen until the shell kills us. SIGTERM still exits.
    while True:
        signal.pause()
