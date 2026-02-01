import subprocess
import json
import time
import threading
from dataclasses import dataclass
from typing import List, Set

from devices.device import Device
from devices.utils.process_runner import ProcessRunner
from utils.logger import PyUiLogger

@dataclass
class WiFiNetwork:
    id_str: str
    signal_level: int
    security: str
    ssid: str

    def requires_password(self) -> bool:
        return "psk" in self.security or "wep" in self.security

class ConnmanWiFiScanner:
    def __init__(self, interface="wlan0", delay=2):
        self.interface = interface
        self.delay = delay

        # Thread state
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()

        # Shared scan results
        self._lock = threading.Lock()
        self._known_ssids: Set[str] = set()
        self._known_id_str: Set[str] = set()
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

        result = ProcessRunner.run(["connmanctl", "scan", "wifi"])
        if "Scan completed" not in result.stdout:
            log.error("wlan0 seems broken, restarting and retrying")
            Device.get_device().wifi_error_detected()
            time.sleep(15)
            ProcessRunner.run(["connmanctl", "scan", "wifi"])

        time.sleep(self.delay)

        jdata = self._get_connman_services()
        new_networks: List[WiFiNetwork] = []

        for service in jdata:
            if 'Name' in service[1].keys():
                ssid = service[1]['Name']['data']
            else:
                continue

            id_str = service[0].split("/")[-1] # Connman uses it's own ID string
            signal = service[1]['Strength']['data']
            security = " ".join(service[1]['Security']['data'])

            network = WiFiNetwork(
                id_str=id_str,
                signal_level=int(signal),
                security=security,
                ssid=ssid,
            )

            new_networks.append(network)

        # Merge uniquely seen networks
        with self._lock:
            for net in new_networks:
                if net.id_str not in self._known_id_str:
                    self._known_id_str.add(net.id_str)
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
            self._known_id_str.clear()
            self._networks.clear()

    # ----------------------------
    # Other helpers (unchanged)
    # ----------------------------

    def get_connected_ssid(self):
        ssid = None

        jdata = self._get_connman_services()

        if jdata:
            for service in jdata:
                if service[1]['State']['data'] == "online":
                    ssid = service[1]['Name']['data']
                    break
        else:
            PyUiLogger.get_logger().error("Failed to get Wi-Fi details")

        return ssid

    def _get_connman_services(self):
        res = []
        try:
            result = ProcessRunner.run([
                "busctl", "-j", "--system",
                "call", "net.connman", "/",
                "net.connman.Manager", "GetServices"
            ])

            jdata = json.loads(result.stdout)
            res = jdata['data'][0]
        except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
            PyUiLogger.get_logger().error(f"Failed to get connman services: {e}")

        return res
