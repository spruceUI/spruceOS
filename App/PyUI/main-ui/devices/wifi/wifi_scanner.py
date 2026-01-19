import subprocess
import time
import threading
from dataclasses import dataclass
from typing import List, Set

from devices.device import Device
from devices.utils.process_runner import ProcessRunner
from display.display import Display
from utils.logger import PyUiLogger


@dataclass
class WiFiNetwork:
    bssid: str
    frequency: int
    signal_level: int
    flags: str
    ssid: str

    def requires_password(self) -> bool:
        return "WPA" in self.flags or "WEP" in self.flags


class WiFiScanner:
    def __init__(self, interface="wlan0", delay=2):
        self.interface = interface
        self.delay = delay

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
            self._stop_event.wait(self.delay)

        log.info("WiFi scan thread stopped")

    def _scan_once_internal(self):
        """
        Runs inside worker thread only.
        """
        log = PyUiLogger.get_logger()

        result = ProcessRunner.run(["wpa_cli", "-i", self.interface, "scan"])
        if "Failed to connect to" in result.stderr:
            log.error("wlan0 seems broken, restarting and retrying")
            Device.get_device().wifi_error_detected()
            time.sleep(15)
            ProcessRunner.run(["wpa_cli", "-i", self.interface, "scan"])

        # Let wpa_supplicant populate results
        time.sleep(self.delay)

        result = ProcessRunner.run(["wpa_cli", "-i", self.interface, "scan_results"])
        lines = result.stdout.strip().splitlines()

        new_networks: List[WiFiNetwork] = []

        for line in lines[1:]:  # Skip header
            parts = line.strip().split("\t")
            if len(parts) < 5:
                continue

            bssid, freq, signal, flags, ssid = parts[:5]

            try:
                network = WiFiNetwork(
                    bssid=bssid,
                    frequency=int(freq),
                    signal_level=int(signal),
                    flags=flags,
                    ssid=ssid,
                )
            except ValueError:
                continue

            new_networks.append(network)

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
        ssid = None
        freq = None
        try:
            result = ProcessRunner.run(["wpa_cli", "status"])
            for line in result.stdout.splitlines():
                if line.startswith("ssid="):
                    ssid = line.split("=", 1)[1]
                elif line.startswith("freq="):
                    freq = int(line.split("=", 1)[1])
        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Failed to get Wi-Fi details: {e}")

        return ssid, freq
