import re

from devices.wifi.wifi_scanner import WiFiScanner, WiFiNetwork
from devices.utils.process_runner import ProcessRunner
from utils.logger import PyUiLogger


class NmcliWifiScanner(WiFiScanner):
    """WiFiScanner backed by NetworkManager.

    dArkMoss is Debian and runs NetworkManager, so there is no wpa_cli daemon
    for the base scanner to talk to. Override only the two methods that shell
    out - the periodic scan and the connected-network query - and reuse the
    base worker thread, dedup and locking unchanged.

    Terse output is one line per AP, colon separated:

        MyNetwork:78:2412 MHz:WPA2:A1\\:B2\\:C3\\:D4\\:E5\\:F6

    nmcli escapes any colon inside a value with a backslash, which matters
    because a BSSID is nothing but colons, so fields cannot be split naively.
    """

    # Split on colons that are not backslash-escaped.
    _FIELD_SPLIT = re.compile(r"(?<!\\):")

    _SCAN_FIELDS = "SSID,SIGNAL,FREQ,SECURITY,BSSID"

    @classmethod
    def _split(cls, line):
        return [
            part.replace("\\:", ":").replace("\\\\", "\\")
            for part in cls._FIELD_SPLIT.split(line)
        ]

    @staticmethod
    def _to_rssi(signal):
        """
        nmcli reports link quality 0-100; spruce classifies on RSSI in dBm.
        The usual mapping puts 100 at -50 dBm and 0 at -100.
        """
        try:
            quality = int(signal)
        except (TypeError, ValueError):
            return -100

        quality = max(0, min(100, quality))
        return (quality // 2) - 100

    @staticmethod
    def _to_mhz(freq):
        try:
            return int(str(freq).split()[0])
        except (TypeError, ValueError, IndexError):
            return 0

    def _parse_line(self, line):
        if not line.strip():
            return None

        parts = self._split(line)

        if len(parts) < 5:
            return None

        ssid, signal, freq, security, bssid = parts[0], parts[1], parts[2], parts[3], parts[4]

        # A blank SSID is a hidden network; the base scanner has nothing to
        # show for it and connecting needs the name anyway.
        if not ssid:
            return None

        return WiFiNetwork(
            bssid=bssid,
            frequency=self._to_mhz(freq),
            signal_level=self._to_rssi(signal),
            # The base class only asks whether this contains WPA or WEP.
            # nmcli says "WPA2", "WPA1 WPA2", "WEP" or "" for an open network.
            flags=security or "",
            ssid=ssid,
        )

    # ---- periodic scan (called by the base worker thread) ----
    def _scan_once_internal(self):
        # --rescan auto lets NetworkManager decide whether its cache is stale
        # enough to warrant hitting the radio. Forcing yes every time makes
        # the list flicker and can stall an in-progress association.
        result = ProcessRunner.run(
            [
                "nmcli", "-t", "-f", self._SCAN_FIELDS,
                "device", "wifi", "list", "--rescan", "auto",
            ],
            timeout=20,
        )

        if not result or result.returncode != 0:
            return

        found = []

        for line in (result.stdout or "").splitlines():
            net = self._parse_line(line)

            if net is not None:
                found.append(net)

        with self._lock:
            for net in found:
                if net.ssid and net.ssid not in self._known_ssids:
                    self._known_ssids.add(net.ssid)
                    self._networks.append(net)

    # ---- connected-network query (used for the status line) ----
    def get_connected_ssid(self):
        # "device wifi" triggers a radio scan (~4.5s on this hardware) and the
        # wifi menu calls this every loop, so navigating froze for seconds per
        # keypress. "device show" just reads the interface state - no scan. For
        # a wifi profile NetworkManager names the connection after the SSID.
        try:
            result = ProcessRunner.run(
                ["nmcli", "-t", "-f", "GENERAL.CONNECTION", "device", "show", "wlan0"],
                timeout=5,
            )

            for line in (result.stdout or "").splitlines():
                if line.startswith("GENERAL.CONNECTION:"):
                    name = line.split(":", 1)[1].strip()
                    if name and name != "--":
                        return name, None

        except Exception as e:
            PyUiLogger.get_logger().error(f"nmcli get_connected_ssid failed: {e}")

        return None, None
