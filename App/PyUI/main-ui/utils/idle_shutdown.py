import functools
import os
import subprocess

from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig

# The CFW's hook for long jobs (longTaskCmd in py-ui-config.json; spruce's is
# long_task.sh): "start" holds off the idle shutdown, "end" releases it and
# restarts the idle timer.


def _long_task(cmd, action, name):
    try:
        subprocess.run(["sh", cmd, action, name], timeout=10,
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
        cmd = PyUiConfig.get_long_task_cmd()
        if not cmd or not os.path.isfile(cmd):  # no hook configured: nothing to hold
            return func(*args, **kwargs)
        _long_task(cmd, "start", func.__qualname__)
        try:
            return func(*args, **kwargs)
        finally:
            _long_task(cmd, "end", func.__qualname__)
    return wrapper
