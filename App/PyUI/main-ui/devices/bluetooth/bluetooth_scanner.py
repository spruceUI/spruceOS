from dataclasses import dataclass
import os
import re
import select
import subprocess
import threading
import time
from typing import List

from display.font_purpose import FontPurpose
from utils.logger import PyUiLogger

@dataclass
class BluetoothDevice:
    address: str
    name: int
    def __init__(self, address: str, name: str):
        self.address = address
        self.name = name

class BluetoothScanner:
    def __init__(self):
        self.seen_devices = {}


    def start(self):
        self.process = subprocess.Popen(
            ['bluetoothctl'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )


        self.send('power on')
        time.sleep(1)
        self.send('scan on')

    def stop(self):
        self.send('scan off')
        time.sleep(0.25)
        self.send('exit')
        self.process.terminate()

    def remove_ansi_escape_sequences(self,text):
        # Remove ANSI escape sequences (for coloring and formatting in terminal)
        text = re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', text)
        # Remove non-printable characters
        text = ''.join(c for c in text if c.isprintable())
        return text
    
    def send(self, cmd):
        self.process.stdin.write(cmd + '\n')
        PyUiLogger.get_logger().info(f"Running cmd : {cmd}")
        self.process.stdin.flush()

    def get_device_name_from_address(self, addr: str) -> str:
        base_path = "/var/lib/bluetooth"
        controllers = [d for d in os.listdir(base_path) if os.path.isdir(os.path.join(base_path, d))]
        if not controllers:
            PyUiLogger.get_logger().error(f"No directories found in {base_path}")
            return f"Unknown ({addr})"
       
        controller_dir = os.path.join(base_path, controllers[0])  # assume only one controller folder
        cache_dir = os.path.join(controller_dir, "cache")
        cache_file_path = os.path.join(cache_dir, addr.upper())

        if not os.path.isfile(cache_file_path):
            PyUiLogger.get_logger().error(f"Cannot find cache file : {cache_file_path}")
            return f"Unknown ({addr})"

        with open(cache_file_path, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("Name="):
                    name = line[len("Name="):].strip()
                    return name

        PyUiLogger.get_logger().error(f"No name line found in : {cache_file_path}")


    def scan_devices(self) -> List[BluetoothDevice]:
        rlist, _, _ = select.select([self.process.stdout], [], [], 0.1)
        if rlist:
            line = self.process.stdout.readline().strip()
            PyUiLogger.get_logger().info(f"{line}")  # Debug line read
            line = self.remove_ansi_escape_sequences(line)  # Remove escape sequences

            if line.startswith('[NEW] Device '):
                parts = line.split(' ', 3)
                if len(parts) >= 4:
                    addr = parts[2].strip()
                    name = parts[3].strip()
                    if addr not in self.seen_devices:
                        self.seen_devices[addr] = BluetoothDevice(address=addr, name=name)
                        PyUiLogger.get_logger().error(f"Found: {self.seen_devices[addr]}")
                    else:
                        PyUiLogger.get_logger().error(f"Device {addr} already seen.")

            elif '[CHG] Device ' in line:
                parts = line.split()
                if len(parts) >= 4:
                    addr = parts[2].strip()
                    if addr not in self.seen_devices:
                        name = self.get_device_name_from_address(addr)
                        self.seen_devices[addr] = BluetoothDevice(address=addr, name=name)
                        PyUiLogger.get_logger().error(f"Found device: {self.seen_devices[addr]}")
                    else:
                        PyUiLogger.get_logger().error(f"Controller {addr} already seen.")

        return list(self.seen_devices.values())
    
    def connect_to_device(self, device_address):
        from display.display import Display
        from devices.device import Device
        from themes.theme import Theme
        from controller.controller import Controller
        PyUiLogger.get_logger().info(f"Attempting to connect to {device_address}")
        Display.clear("Bluetooth Connection")
        Display.render_text_centered(f"Attempting to connect to {device_address}",Device.screen_width()//2, Device.screen_height()//2,Theme.text_color_selected(FontPurpose.LIST), purpose=FontPurpose.LIST)
        Display.present()

        try:
            process = subprocess.Popen(
                ['bluetoothctl'],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1
            )

            output_lines = []

            def read_output():
                while True:
                    line = process.stdout.readline()
                    if not line:
                        break
                    PyUiLogger.get_logger().info(f"[BTCTL] {line.strip()}")
                    output_lines.append(line)
                    if "Connection successful" in line or "Failed to connect" in line or "Authentication Failed" in line:
                        break

            thread = threading.Thread(target=read_output)
            thread.start()

            # Send commands
            cmds = [
                'power on\n',
                'agent on\n',
                'default-agent\n',
                f'pair {device_address}\n',
                f'trust {device_address}\n',
                f'connect {device_address}\n'
            ]
            for cmd in cmds:
                process.stdin.write(cmd)
                process.stdin.flush()
                time.sleep(2)  # allow time for each step to complete

            thread.join(timeout=20)  # wait up to 20 seconds for output reading

            # Stop the process
            process.stdin.write('quit\n')
            process.stdin.flush()
            process.terminate()

            # Check if connection succeeded
            all_output = ''.join(output_lines)
            if "Connection successful" in all_output:
                PyUiLogger.get_logger().info(f"Successfully connected to {device_address}")
                Display.clear("Bluetooth Connection")
                Display.render_text_centered(f"Successfully connected to {device_address}",Device.screen_width()//2, Device.screen_height()//2,Theme.text_color_selected(FontPurpose.LIST), purpose=FontPurpose.LIST)
                Display.present()
                while(not Controller.get_input()):
                    pass
                return True
            else:
                PyUiLogger.get_logger().info(f"Failed to connect to {device_address}. Output:\n{all_output}")
                Display.clear("Bluetooth Connection")
                Display.render_text_centered(f"Failed to connect to {device_address}",Device.screen_width()//2, Device.screen_height()//2,Theme.text_color_selected(FontPurpose.LIST), purpose=FontPurpose.LIST)
                Display.present()
                while(not Controller.get_input()):
                    pass
                return False

        except Exception as e:
            PyUiLogger.get_logger().error(f"Error while connecting to the device: {str(e)}")
            return False
