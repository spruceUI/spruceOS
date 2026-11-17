"""What only spruce's platform functions know, asked once in one short sh run (with a time limit) and kept:
whether the board has Bluetooth (device_bluetooth_supported; the radio may be off, so no hci device shows).
"""
import subprocess

HELPERS = "/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
SCRIPT = (f". {HELPERS} >/dev/null 2>&1; "
          "if device_bluetooth_supported >/dev/null 2>&1; then echo bluetooth=1; else echo bluetooth=0; fi")


class SpruceQuery:
    def __init__(self, command=None, timeout=4.0):
        self.command = command or ["sh", "-c", SCRIPT]
        self.timeout = timeout
        self.answers = None

    def get(self, key):
        """The answer ("1"/"0"...) for key, or None when spruce couldn't be asked."""
        if self.answers is None:
            self.answers = {}
            try:
                proc = subprocess.Popen(self.command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                try:
                    out = proc.communicate(timeout=self.timeout)[0]
                except subprocess.TimeoutExpired:
                    proc.kill()  # a child it started may still hold the pipe: don't read after this
                    proc.stdout.close()
                    proc.wait()
                    out = ""
            except OSError:
                out = ""
            for line in (out or "").splitlines():
                name, _, value = line.partition("=")
                if value:
                    self.answers[name.strip()] = value.strip()
        return self.answers.get(key)
