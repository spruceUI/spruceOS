import subprocess
import sys
import time
from dataclasses import dataclass
from typing import List, Set

from devices.utils.process_runner import ProcessRunner
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
    def __init__(self, interface="wlan0", delay=2, max_idle_scans=3):
        self.interface = interface
        self.delay = delay
        self.max_idle_scans = max_idle_scans

    def scan_once(self, device) -> List[WiFiNetwork]:
        result = ProcessRunner.run(["wpa_cli", "-i", self.interface, "scan"])
        if "Failed to connect to" in result.stderr:
            PyUiLogger.get_logger().error("wlan0 seems broken, restarting and retrying")
            device.wifi_error_detected()
            time.sleep(15)
            ProcessRunner.run(["wpa_cli", "-i", self.interface, "scan"])
        
        time.sleep(self.delay)

        result = ProcessRunner.run(["wpa_cli", "-i", self.interface, "scan_results"])

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

    def scan_networks(self, device) -> List[WiFiNetwork]:
        PyUiLogger.get_logger().info("Starting WiFi Scan")
        known_ssids: Set[str] = set()
        known_bssids: Set[str] = set()
        all_networks: List[WiFiNetwork] = []

        idle_count = 0

        scan_count = 0
        while idle_count < self.max_idle_scans:
            scan_count+=1
            PyUiLogger.get_logger().info(f"    Scan # {scan_count}")
            new_networks = self.scan_once(device)
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
            
            result = ProcessRunner.run(["wpa_cli", "status"])
            for line in result.stdout.splitlines():
                if line.startswith("ssid="):
                    ssid = line.split("=", 1)[1]
                elif line.startswith("freq="):
                    freq = int(line.split("=", 1)[1])
        
        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Failed to get Wi-Fi details: {e}")        

        return ssid, freq
    
    def reload_wpa_supplicant_config(self):
        try:
            # Trigger the reconfiguration to reload wpa_supplicant.conf
            ProcessRunner.run(["wpa_cli", "reconfigure"])
            PyUiLogger.get_logger().info("wpa_supplicant.conf reloaded successfully.")
        except subprocess.CalledProcessError as e:
            PyUiLogger.get_logger().error(f"Error reloading wpa_supplicant.conf: {e}")
            