

import inspect
import os
import subprocess
import sys
from utils.logger import PyUiLogger

def get_caller_info(skip=2):
    frame = inspect.stack()[skip]
    filename = os.path.basename(frame.filename)
    func_name = frame.function
    lineno = frame.lineno
    return f"{filename}:{lineno} in {func_name}()"

class ProcessRunner:
    @classmethod
    def run(cls, args, check = False, timeout=None, print=True):
        caller = get_caller_info()
        if(print):
            PyUiLogger.get_logger().debug(f"{caller} Executing {args}")
        result = subprocess.run(args, capture_output=True, text=True, check=check, timeout=timeout)
        if(print):
            if result.stdout:
                PyUiLogger.get_logger().info(f"{caller} stdout: {result.stdout.strip()}")
            if result.stderr:
                PyUiLogger.get_logger().error(f"{caller} stderr: {result.stderr.strip()}")

        return result
