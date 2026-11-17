"""The A30's stick: spruce's joystickinput turns it into D-pad keys while PyUI runs (keyboard mode, SIGUSR2).
While Button Reader is open it asks for analog mode (SIGUSR1) and gives keyboard mode back at exit, as spruce's
PICO-8 and OpenBOR launchers do. Only a running joystickinput is touched.
"""
import os
import signal

NAME = "joystickinput"


class JoystickInput:
    def __init__(self, proc_root="/proc"):
        self.proc_root = proc_root
        self.pids = []

    def find(self):
        pids = []
        for entry in os.listdir(self.proc_root):
            if not entry.isdigit():
                continue
            try:
                with open(os.path.join(self.proc_root, entry, "comm"), errors="replace") as f:
                    comm = f.read().strip()
            except OSError:
                continue
            if comm == NAME:
                pids.append(int(entry))
        return pids

    def analog(self):
        """Switch every running joystickinput to analog mode; returns the pids it signalled."""
        self.pids = self.find()
        self.send(self.pids, signal.SIGUSR1)
        return self.pids

    def restore(self):
        """Keyboard mode again (the stick drives the menu), for whichever joystickinput runs now; returns its pids."""
        pids = self.find() if self.pids else []
        self.send(pids, signal.SIGUSR2)
        self.pids = []
        return pids

    def send(self, pids, sig):
        for pid in pids:
            try:
                os.kill(pid, sig)
            except OSError:
                pass
