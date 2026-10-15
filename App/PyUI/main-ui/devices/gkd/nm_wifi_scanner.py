import time
import threading
from typing import List, Set

from devices.utils.process_runner import ProcessRunner
from utils.logger import PyUiLogger
from devices.wifi.wifi_scanner import WiFiNetwork

class NmWiFiScanner:
    def __init__(self, interface="wlan0", delay=2):
        self.interface = interface
        self.delay = delay
        self.connected_network = None

        # Thread state
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()

        # Shared scan results
        self._lock = threading.Lock()
        self._known_ssids: Set[str] = set()
        self._known_bssids: Set[str] = set()
        self._networks: List[WiFiNetwork] = []

    # ----------------------------
    # Worker thread
    # ----------------------------

    def _scan_worker(self):
        log = PyUiLogger.get_logger()
        log.info("WiFi scan thread started")

        while not self._stop_event.is_set():
            try:
                self._scan_once_internal()
            except Exception:
                log.exception("WiFi scan worker error")

            # Cooperative sleep so stop() reacts immediately
            log.info("Scanning...")
            self._stop_event.wait(self.delay)

        log.info("WiFi scan thread stopped")

    def _scan_once_internal(self):
        """
        Runs inside worker thread only.
        """
        log = PyUiLogger.get_logger()

        result = ProcessRunner.run(["nmcli", "dev", "wifi", "rescan", "ifname", self.interface])
        if "Error:" in result.stdout:
            log.error(f"networkmanager scan failed, retrying")
            time.sleep(15)
            ProcessRunner.run(["nmcli", "dev", "wifi", "rescan", "ifname", self.interface])

        time.sleep(self.delay)

        result = ProcessRunner.run(["nmcli", "-t", "device", "wifi", "list"])
        lines = result.stdout.replace("\\:", "-").splitlines()

        new_networks: List[WiFiNetwork] = []

        for line in lines:
            parts = line.split(":")

            bssid = parts[1].replace("-", ":")
            ssid = parts[2]
            freq = 5100 if int(parts[4]) > 30 else 2400
            signal = int(parts[6])
            flags = parts[8]

            network = WiFiNetwork(
                    bssid=bssid,
                    frequency=freq,
                    signal_level=signal,
                    flags=flags,
                    ssid=ssid,
            )

            new_networks.append(network)

            if parts[0] == "*":
                self.connected_network = network

        # Merge uniquely seen networks
        with self._lock:
            for net in new_networks:
                if net.bssid not in self._known_bssids:
                    self._known_bssids.add(net.bssid)
                    self._known_ssids.add(net.ssid)
                    self._networks.append(net)

    # ----------------------------
    # Public API
    # ----------------------------

    def scan_networks(self) -> List[WiFiNetwork]:
        """
        Non-blocking.
        Starts the worker thread if not already running and
        returns currently known networks immediately.
        """
        if not self._thread or not self._thread.is_alive():
            self._start_thread()

        with self._lock:
            # Return a snapshot copy
            return list(self._networks)

    def _start_thread(self):
        PyUiLogger.get_logger().info("Starting WiFi scan thread")
        self._stop_event.clear()
        self._thread = threading.Thread(
            target=self._scan_worker,
            name="WiFiScannerThread",
            daemon=True,
        )
        self._thread.start()

    def stop(self):
        """
        Stops the worker thread and clears scanned networks.
        """
        log = PyUiLogger.get_logger()
        log.info("Stopping WiFi scan thread")
        self._stop_event.set()

        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5)

        self._thread = None

        with self._lock:
            self._known_ssids.clear()
            self._known_bssids.clear()
            self._networks.clear()

    # ----------------------------
    # Other helpers (unchanged)
    # ----------------------------

    def get_connected_ssid(self):
        if self.connected_network:
            return self.connected_network.ssid, self.connected_network.frequency
        else:
            return None, None