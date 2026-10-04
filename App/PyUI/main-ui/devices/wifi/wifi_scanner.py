import re
import threading
from dataclasses import dataclass
from typing import Callable, List, Set, Tuple

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
    """Keeps a growing list of visible networks for the WiFi menu.

    The device supplies two callables: scan_fn returns the networks visible
    right now (one `wifiCmd scan`, which blocks for a few seconds), and
    connected_fn returns (ssid, frequency) of the joined network. A worker
    thread calls scan_fn every `delay` seconds and merges what it finds, so
    the menu's scan_networks() never blocks.
    """

    def __init__(
        self,
        scan_fn: Callable[[], List[WiFiNetwork]],
        connected_fn: Callable[[], Tuple[str | None, int | None]],
        delay=2,
    ):
        self._scan_fn = scan_fn
        self._connected_fn = connected_fn
        self.delay = delay

        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()

        self._lock = threading.Lock()
        self._known_ssids: Set[str] = set()
        self._known_bssids: Set[str] = set()
        self._networks: List[WiFiNetwork] = []

    def _scan_worker(self):
        log = PyUiLogger.get_logger()
        log.info("WiFi scan thread started")

        while not self._stop_event.is_set():
            try:
                self._scan_once_internal()
            except Exception:
                log.exception("WiFi scan worker error")

            self._stop_event.wait(self.delay)

        log.info("WiFi scan thread stopped")

    def _scan_once_internal(self):
        found = self._scan_fn()
        if self._stop_event.is_set():
            return

        with self._lock:
            for net in found:
                net.ssid = self._decode_ssid(net.ssid)
                if net.bssid not in self._known_bssids:
                    self._known_bssids.add(net.bssid)
                    self._known_ssids.add(net.ssid)
                    self._networks.append(net)

    @staticmethod
    def _decode_ssid(ssid: str) -> str:
        # wpa_supplicant escapes non-printable bytes in an SSID as \xHH.
        try:
            return re.sub(
                r'(\\x[0-9a-fA-F]{2})+',
                lambda m: bytes(
                    int(b, 16) for b in re.findall(r'\\x([0-9a-fA-F]{2})', m.group(0))
                ).decode('utf-8', errors='replace'),
                ssid
            )
        except Exception:
            PyUiLogger.get_logger().warning(f"Failed to decode escaped SSID: {ssid}")
            return ssid

    def scan_networks(self) -> List[WiFiNetwork]:
        """Non-blocking: starts the worker if needed and returns what is known."""
        if not self._thread or not self._thread.is_alive():
            self._start_thread()

        with self._lock:
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
        """Stops the worker thread and clears scanned networks."""
        PyUiLogger.get_logger().info("Stopping WiFi scan thread")
        self._stop_event.set()

        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5)

        self._thread = None

        with self._lock:
            self._known_ssids.clear()
            self._known_bssids.clear()
            self._networks.clear()

    def get_connected_ssid(self):
        try:
            ssid, freq = self._connected_fn()
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to get Wi-Fi details: {e}")
            return None, None
        if ssid:
            ssid = self._decode_ssid(ssid)
        return ssid, freq
