import functools
import os
import subprocess

from utils.logger import PyUiLogger

# spruce's idle-shutdown timer: idle_watchdog.sh (re)starts idlemon from the
# Battery Settings "Shutdown while idle" values.
IDLE_WATCHDOG = "/mnt/SDCARD/spruce/scripts/idle_watchdog.sh"


def pauses_idle_shutdown(func):
    """Keep the idle-shutdown timer from powering the device off mid-job.

    For long jobs that run inside PyUI with no button presses (box art
    optimizing / downloading). spruce's long-running apps do the same with
    `killall -q idlemon`; they get the timer back when PyUI restarts after
    the app and principal.sh re-runs idle_watchdog.sh. A job inside PyUI has
    no such restart, so the timer is restarted here when the job ends,
    however it ends (done, aborted with B, or an exception).
    """
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        if not os.path.isfile(IDLE_WATCHDOG):  # not on spruce: nothing to pause
            return func(*args, **kwargs)
        for proc in ("idlemon", "idle_watchdog.sh"):
            subprocess.run(["killall", "-q", proc],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            return func(*args, **kwargs)
        finally:
            try:
                subprocess.Popen(["sh", IDLE_WATCHDOG], start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError as e:
                PyUiLogger.get_logger().error(f"Could not restart the idle timer: {e}")
    return wrapper
