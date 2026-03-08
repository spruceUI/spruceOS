

import subprocess

from utils.logger import PyUiLogger


class StdInBasedSendEventBinaryHelper:
    @staticmethod
    def send_key_down_and_up(path, code):
        try:
            proc = subprocess.Popen(
                ["sendevent", path],
                stdin=subprocess.PIPE,
                text=True
            )

            proc.stdin.write(f"1 {code} 1\n")
            proc.stdin.write(f"1 {code} 0\n")
            proc.stdin.write("0 0 0\n")
            proc.stdin.flush()
            proc.stdin.close()

            proc.wait()
        except Exception as e:
            PyUiLogger.get_logger().exception(
                f"Failed to call sendevent : {e}"
            )

