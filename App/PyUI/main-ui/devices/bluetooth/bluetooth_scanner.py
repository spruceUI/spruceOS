from dataclasses import dataclass
import re
import select
import subprocess
import threading
import time
from typing import List, Set

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
        pass

    def remove_ansi_escape_sequences(self,text):
        # Remove ANSI escape sequences (for coloring and formatting in terminal)
        text = re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', text)
        # Remove non-printable characters
        text = ''.join(c for c in text if c.isprintable())
        return text
    
    def scan_once(self, duration=10) -> List[BluetoothDevice]:
        process = subprocess.Popen(
            ['bluetoothctl'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        def send(cmd):
            process.stdin.write(cmd + '\n')
            process.stdin.flush()

        send('power on')
        time.sleep(1)
        send('scan on')

        PyUiLogger.get_logger().info(f"Scanning for {duration} seconds...")
        start_time = time.time()
        seen_devices = {}

        try:
            while time.time() - start_time < duration:
                # Check if there is data ready to be read from stdout
                rlist, _, _ = select.select([process.stdout], [], [], 0.1)
                if rlist:
                    line = process.stdout.readline().strip()
                    PyUiLogger.get_logger().info(f"{line}")  # Debug line read
                    line = self.remove_ansi_escape_sequences(line)  # Remove escape sequences
                    if line.startswith('[NEW] Device '):
                        parts = line.split(' ', 3)
                        if len(parts) >= 4:
                            addr = parts[2].strip()  # Ensure no extra spaces
                            name = parts[3].strip()  # Ensure no extra spaces
                            #print(f"Parsed addr: {addr}, name: {name}")  # Debug parsed output
                            if addr not in seen_devices:
                                seen_devices[addr] = BluetoothDevice(address=addr, name=name)
                                PyUiLogger.get_logger().error(f"Found: {seen_devices[addr]}")
                            else:
                                PyUiLogger.get_logger().error(f"Device {addr} already seen.")  # Debug already seen device
        finally:
            send('scan off')
            send('exit')
            process.terminate()

        return list(seen_devices.values())
    
    def scan_devices(self) -> List[BluetoothDevice]:
        PyUiLogger.get_logger().info("Starting Bluetooth Scan")
        return self.scan_once()
    
                
    def connect_to_device(self, device_address):
        PyUiLogger.get_logger().info(f"Attempting to connect to {device_address}")

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
            else:
                PyUiLogger.get_logger().info(f"Failed to connect to {device_address}. Output:\n{all_output}")

        except Exception as e:
            PyUiLogger.get_logger().error(f"Error while connecting to the device: {str(e)}")
