"""The menu's farewell frame at power-off (docs/shutdown_readme.txt).

The SIGURG handler only notes the request. The main thread draws the farewell at
its next checkpoint (an input wait or a present) and then sleeps there until the
shell kills it.

SIGWINCH uses the same wake-up mechanism for an optional external message.
"""

import os
import signal
import threading

from utils.logger import PyUiLogger

_requested = False
_message_requested = False
_message_active = False
_ui_thread = None
_show_farewell = None
_show_message = None
_message_path = None


def _note_request(signum, frame):
    # Only a flag: drawing or locking here could deadlock the UI code. Python also
    # writes the signal to the wakeup fd (see arm), which ends an idle input wait.
    global _requested
    _requested = True


def _note_message_request(signum, frame):
    global _message_requested
    _message_requested = True


def _take_message():
    if not _message_path:
        return None

    claimed_path = f"{_message_path}.{os.getpid()}"

    try:
        os.replace(_message_path, claimed_path)
    except FileNotFoundError:
        return None
    except OSError:
        PyUiLogger.get_logger().exception(
            "Could not claim the external message"
        )
        return None

    try:
        with open(claimed_path, "r", encoding="utf-8") as source:
            return source.read().strip()
    except Exception:
        PyUiLogger.get_logger().exception(
            "Could not read the external message"
        )
        return None
    finally:
        try:
            os.unlink(claimed_path)
        except FileNotFoundError:
            pass


def listen(message_path=None):
    """Note power-off requests from now on. The menu only, on the main thread."""

    global _message_path

    signal.signal(signal.SIGURG, _note_request)

    _message_path = message_path

    if _message_path and hasattr(signal, "SIGWINCH"):
        # Do not show a message left by an earlier PyUI instance.
        try:
            os.unlink(_message_path)
        except FileNotFoundError:
            pass

        signal.signal(signal.SIGWINCH, _note_message_request)


def arm(show_farewell, wakeup_fd=None, show_message=None):
    """Let the calling (main) thread's checkpoints call show_farewell(), at once if
    power-off was already requested. wakeup_fd (ControllerInterface.signal_wakeup_fd)
    wakes an idle input wait; without one the menu notices at its next redraw."""

    global _ui_thread, _show_farewell, _show_message

    if wakeup_fd is not None:
        signal.set_wakeup_fd(wakeup_fd, warn_on_full_buffer=False)

    _show_farewell = show_farewell
    _show_message = show_message
    _ui_thread = threading.get_ident()
    checkpoint()


def checkpoint():
    """Handle pending power-off and external message requests on the UI thread."""

    global _ui_thread
    global _message_requested
    global _message_active

    if threading.get_ident() != _ui_thread:
        return

    if _requested:
        _ui_thread = None  # drawing the farewell must not come back here
        try:
            _show_farewell()
        except Exception:
            PyUiLogger.get_logger().exception(
                "Could not show the farewell frame"
            )
        # Keep the frame on screen until the shell kills us. SIGTERM still exits.
        while True:
            signal.pause()

    if (
        not _message_requested
        or _message_active
        or _show_message is None
    ):
        return

    _message_requested = False
    message = _take_message()

    if not message:
        return

    _message_active = True

    try:
        _show_message(message)
    except Exception:
        PyUiLogger.get_logger().exception(
            "Could not show the external message"
        )
    finally:
        _message_active = False
