import threading

from devices.bluetooth.bluetooth_scanner import BluetoothDevice


class BluetoothCommand:
    """What the Bluetooth menu asks of a scanner, answered by bluetoothCmd.
    See App/PyUI/bluetooth_readme.txt."""

    def __init__(self, run):
        self._run = run
        self._devices = []
        self._lock = threading.Lock()
        self._stop_event = None

    def start(self):
        self.stop()
        self._stop_event = threading.Event()
        threading.Thread(target=self._scan_loop, args=(self._stop_event,), daemon=True).start()

    def stop(self):
        if self._stop_event is not None:
            self._stop_event.set()
            self._stop_event = None

    def scan_devices(self):
        with self._lock:
            return list(self._devices)

    def refresh_devices(self):
        self._store(self._run("devices"))

    def connect(self, device):
        """(ok, failed step, reason)."""
        answer = (self._run("pair", device.address, timeout=90) or "").strip()
        if answer == "ok":
            return True, None, None
        parts = answer.split(" ", 2)
        if len(parts) == 3 and parts[0] == "failed":
            return False, parts[1], parts[2]
        return False, "pair", answer

    def is_connected(self, device):
        for line in (self._run("devices") or "").splitlines():
            fields = line.split("\t", 3)
            if len(fields) == 4 and fields[0] == device.address:
                return fields[2] == "1"
        return False

    def disconnect(self, device):
        """(ok, output)."""
        answer = (self._run("disconnect", device.address, timeout=30) or "").strip()
        return answer == "ok", answer

    def forget(self, device):
        """(ok, output)."""
        answer = self._run("forget", device.address, timeout=30)
        return answer is not None, ""

    def _scan_loop(self, stop_event):
        while not stop_event.is_set():
            self._store(self._run("scan", timeout=30))
            stop_event.wait(1)

    def _store(self, output):
        if output is None:
            return
        devices = []
        for line in output.splitlines():
            fields = line.split("\t", 3)
            if len(fields) == 4:
                devices.append(BluetoothDevice(fields[0], fields[3], fields[1] == "1"))
        with self._lock:
            self._devices = devices
