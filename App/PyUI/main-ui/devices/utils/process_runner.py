

import subprocess
from utils.logger import PyUiLogger


class ProcessRunner:
    @classmethod
    def run_and_print(cls, args, check = False, timeout=None):
        PyUiLogger.debug(f"Executing {args}")
        result = subprocess.run(args, capture_output=True, text=True, check=check, timeout=timeout)
        if result.stdout:
            PyUiLogger.debug(f"stdout: {result.stdout.strip()}")
        if result.stderr:
            PyUiLogger.error(f"stderr: {result.stderr.strip()}")

        return result
