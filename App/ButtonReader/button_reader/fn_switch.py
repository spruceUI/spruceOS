"""The Fn switch on the TrimUIs: a GPIO, not an input event, read through spruce's device_get_switch_position
so each device's own file names the pin. A read is a short sh run that the loop polls, never waits on.
"""
import subprocess
import time

HELPERS = "/mnt/SDCARD/spruce/scripts/helperFunctions.sh"


class FnSwitch:
    def __init__(self, command=None):
        self.command = command or ["sh", "-c", f". {HELPERS} >/dev/null 2>&1; device_get_switch_position"]
        self.value = None  # "0" or "1" once read
        self.readable = None  # None until the first read ends; False on a device without a reader
        self.proc = None
        self.next_read = 0.0

    def poll(self, now, interval):
        """Start or collect a read; returns (old, new) when the position changed since the last read."""
        if self.proc is not None:
            if self.proc.poll() is None:
                return None
            out = self.proc.stdout.read().strip()
            self.proc.stdout.close()
            self.proc = None
            self.next_read = now + interval
            if out not in ("0", "1"):
                if self.readable is None:
                    self.readable = False
                return None
            old = self.value
            self.value = out
            self.readable = True
            return (old, out) if old is not None and old != out else None
        if self.readable is not False and now >= self.next_read:
            try:
                self.proc = subprocess.Popen(self.command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                             text=True)
            except OSError:
                self.readable = False
        return None

    def wait_first(self, timeout):
        """Wait (at most timeout s) for the first read, so the guided steps know whether to ask for the switch."""
        end = time.monotonic() + timeout
        while self.readable is None and time.monotonic() < end:
            self.poll(time.monotonic(), 0.0)
            time.sleep(0.02)
        return self.readable

    def close(self):
        if self.proc is not None:
            self.proc.kill()
            self.proc.wait()
            self.proc.stdout.close()
            self.proc = None
