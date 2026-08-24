import subprocess
import time

from devices.utils.process_runner import ProcessRunner
from devices.wifi.wifi_scanner import WiFiNetwork, WiFiScanner
from utils.logger import PyUiLogger


class ConnmanWifiScanner(WiFiScanner):
    """WiFiScanner backed by connman instead of wpa_supplicant.

    The RGB30 (and any JELOS-lineage host) runs connman, which owns the radio
    and does its own DHCP. wpa_cli has no daemon to talk to there, so the base
    scanner's `wpa_cli scan` finds nothing. This overrides the two methods that
    shell out - the periodic scan and the connected-network query - and reuses
    everything else (the worker thread, dedup, locking) unchanged.

    connmanctl output for `services` is one line per network:

        *AO MyNetwork          wifi_a1b2_managed_psk
            MyOther            wifi_a1b2_managed_psk
                              wifi_a1b2_hidden_managed_psk

    Column 1 is a 4-char state field ("*A"=connected/associated, "*O"=online,
    "  "=idle); then the human name; then the service id, whose suffix gives the
    security (…_psk, …_none, …_ieee8021x). A blank name is a hidden network.
    """

    # ---- periodic scan (called by the base worker thread) ----
    def _scan_once_internal(self):
        # Ask connman to rescan; ignore failure, the cached service list is
        # still worth parsing.
        ProcessRunner.run(["connmanctl", "scan", "wifi"], timeout=15)

        result = ProcessRunner.run(["connmanctl", "services"], timeout=5)
        if not result or result.returncode != 0:
            return

        found = []
        for line in (result.stdout or "").splitlines():
            net = self._parse_service_line(line)
            if net is not None:
                found.append(net)

        with self._lock:
            for net in found:
                if net.ssid and net.ssid not in self._known_ssids:
                    self._known_ssids.add(net.ssid)
                    self._networks.append(net)

    def _parse_service_line(self, line):
        # The first two columns are the fixed-width state field. A service id is
        # the last token and always starts with "wifi_".
        parts = line.split()
        if not parts or not parts[-1].startswith("wifi_"):
            return None

        service_id = parts[-1]

        # Name is everything between the state field and the service id. The
        # state markers only appear in the first two characters of the line, so
        # slice by fixed width rather than by token to keep names with spaces.
        # connmanctl's state field is a fixed 4-column prefix ("*AO ", "*A  ",
        # "    "), so the name begins at column 4. Slicing at 2 left the "O"
        # online marker glued to the connected network's name.
        body = line[4:].rsplit(service_id, 1)[0].strip() if len(line) > 4 else ""
        ssid = body
        if not ssid:
            return None  # hidden network, nothing to show

        # Security from the service-id suffix.
        if service_id.endswith("_none"):
            flags = ""
        elif service_id.endswith("_ieee8021x"):
            flags = "WPA-EAP"
        else:
            flags = "WPA-PSK"

        return WiFiNetwork(
            bssid=service_id,      # connman has no BSSID; the id is the stable key
            frequency=0,
            signal_level=0,
            flags=flags,
            ssid=ssid,
        )

    # ---- connected-network query (used for the status line) ----
    def get_connected_ssid(self):
        try:
            result = ProcessRunner.run(["connmanctl", "services"], timeout=5)
            for line in (result.stdout or "").splitlines():
                state = line[:4]
                # A = associated/ready, O = online.
                if "A" in state or "O" in state:
                    net = self._parse_service_line(line)
                    if net is not None:
                        return net.ssid, None
        except Exception as e:
            PyUiLogger.get_logger().error(f"connman get_connected_ssid failed: {e}")
        return None, None
