"""spruce asks the menu to reopen its audio output with SIGWINCH (docs/audio_reopen_readme.txt).

The handler only writes a byte to a pipe and a thread does the reopen, so the handler takes no lock. SIGWINCH is
ignored by default, so a request that reaches a helper-mode PyUI, or the menu before listen(), does nothing.
"""

import os
import signal
import threading

from utils.logger import PyUiLogger

_pipe = None


def _note_request(signum, frame):
    try:
        os.write(_pipe[1], b"r")
    except OSError:
        pass  # the pipe is full: a reopen is already waiting


def listen(reopen):
    """The menu only, on the main thread: call reopen() on a thread after each request (a burst makes one)."""
    global _pipe
    if _pipe is not None:
        return
    _pipe = os.pipe()
    os.set_blocking(_pipe[1], False)
    threading.Thread(target=_serve, args=(reopen,), name="AudioReopen", daemon=True).start()
    signal.signal(signal.SIGWINCH, _note_request)


def _serve(reopen):
    while True:
        os.read(_pipe[0], 64)
        try:
            reopen()
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Audio reopen on request failed: {e}")
