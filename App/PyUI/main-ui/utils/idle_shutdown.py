import functools
import os
import subprocess

from utils.logger import PyUiLogger

# spruce's hook for long jobs: "start" holds off the idle shutdown, "end"
# releases it and restarts the idle timer (see the script for details).
LONG_TASK = "/mnt/SDCARD/spruce/scripts/long_task.sh"


def _long_task(action, name):
    try:
        subprocess.run(["sh", LONG_TASK, action, name], timeout=10,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as e:
        PyUiLogger.get_logger().error(f"long_task.sh {action} failed: {e}")


def pauses_idle_shutdown(func):
    """Keep the idle shutdown from powering the device off mid-job.

    For long jobs that run inside PyUI with no button presses (box art
    optimizing / downloading). Wraps the job in long_task.sh start/end; the
    end runs however the job ends (done, aborted with B, or an exception).
    """
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        if not os.path.isfile(LONG_TASK):  # not on spruce: nothing to hold
            return func(*args, **kwargs)
        _long_task("start", func.__qualname__)
        try:
            return func(*args, **kwargs)
        finally:
            _long_task("end", func.__qualname__)
    return wrapper
