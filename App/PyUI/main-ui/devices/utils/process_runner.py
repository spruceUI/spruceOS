

import inspect
import os
import subprocess
from utils.logger import PyUiLogger

def get_caller_info(skip=2):
    frame = inspect.stack()[skip]
    filename = os.path.basename(frame.filename)
    func_name = frame.function
    lineno = frame.lineno
    return f"{filename}:{lineno} in {func_name}()"

class ProcessRunner:
    @classmethod
    def run(cls, args, check = False, timeout=None, print=False):
        caller = get_caller_info()
        if(print):
            PyUiLogger.get_logger().debug(f"{caller} Executing {args}")
        result = subprocess.run(args, capture_output=True, text=True, check=check, timeout=timeout)
        if(print):
            if result.stdout:
                PyUiLogger.get_logger().info(f"{caller} stdout: {result.stdout.strip()}")
            if result.stderr:
                PyUiLogger.get_logger().warning(f"{caller} stderr: {result.stderr.strip()}")

        return result

    @classmethod
    def run_cmd(cls, caller, cmd, log_stdout=True) -> str:
        """Runs command and returns stdout text (never raises)."""
        if(log_stdout):
            PyUiLogger.get_logger().info(f"{caller}: running cmd: {' '.join(cmd)}")

        try:
            proc = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=10
            )
            if proc.stdout and log_stdout:
                PyUiLogger.get_logger().info(f"{caller}(cmd): {proc.stdout.strip()}")
            return proc.stdout or ""
        except subprocess.TimeoutExpired:
            PyUiLogger.get_logger().info(f"{caller}: command timed out: {' '.join(cmd)}")
        except Exception as e:
            PyUiLogger.get_logger().info(f"{caller}: command failed: {e}")

        return ""
