import subprocess
import time
from dataclasses import dataclass
from typing import List, Set

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
    def __init__(self, interface="wlan0", delay=2, max_idle_scans=3):
        self.interface = interface
        self.delay = delay
        self.max_idle_scans = max_idle_scans

    def scan_once(self) -> List[WiFiNetwork]:
        subprocess.run(["wpa_cli", "-i", self.interface, "scan"], stdout=subprocess.DEVNULL)
        time.sleep(self.delay)

        result = subprocess.run(
            ["wpa_cli", "-i", self.interface, "scan_results"],
            capture_output=True,
            text=True
        )

        lines = result.stdout.strip().splitlines()
        networks = []

        for line in lines[1:]:  # Skip the header line
            parts = line.strip().split("\t")
            if len(parts) >= 5:
                bssid, freq, signal, flags, ssid = parts[:5]
                network = WiFiNetwork(
                    bssid=bssid,
                    frequency=int(freq),
                    signal_level=int(signal),
                    flags=flags,
                    ssid=ssid
                )
                networks.append(network)

        return networks

    def scan_networks(self) -> List[WiFiNetwork]:
        print("Starting WiFi Scan")
        known_ssids: Set[str] = set()
        known_bssids: Set[str] = set()
        all_networks: List[WiFiNetwork] = []

        idle_count = 0

        scan_count = 0
        while idle_count < self.max_idle_scans:
            scan_count+=1
            print(f"    Scan # {scan_count}")
            new_networks = self.scan_once()
            added = False

            for net in new_networks:
                if net.bssid not in known_bssids:
                    known_bssids.add(net.bssid)
                    known_ssids.add(net.ssid)
                    all_networks.append(net)
                    added = True

            if added:
                idle_count = 0
            else:
                idle_count += 1

        return all_networks
    
    def get_connected_ssid(self):
        ssid = None
        freq = None
        try:
            result = subprocess.run(
                ["wpa_cli", "status"],
                capture_output=True,
                text=True,
                check=True
            )
            for line in result.stdout.splitlines():
                if line.startswith("ssid="):
                    ssid = line.split("=", 1)[1]
                elif line.startswith("freq="):
                    freq = int(line.split("=", 1)[1])
        
        except subprocess.CalledProcessError as e:
            print(f"Failed to get Wi-Fi details: {e}")        

        return ssid, freq
    
    def reload_wpa_supplicant_config(self):
        try:
            # Trigger the reconfiguration to reload wpa_supplicant.conf
            subprocess.run(["wpa_cli", "reconfigure"], check=True)
            print("wpa_supplicant.conf reloaded successfully.")
        except subprocess.CalledProcessError as e:
            print(f"Error reloading wpa_supplicant.conf: {e}")
            