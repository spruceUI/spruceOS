from dataclasses import dataclass
import re
import select
import subprocess
import time
from typing import List, Set

@dataclass
class BluetoothDevice:
    address: str
    name: int
    def __init__(self, address: str, name: str):
        self.address = address
        self.name = name

class BluetoothScanner:
    def __init__(self, delay=2, max_idle_scans=3):
        self.delay = delay
        self.max_idle_scans = max_idle_scans

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

        print(f"Scanning for {duration} seconds...")
        start_time = time.time()
        seen_devices = {}

        try:
            while time.time() - start_time < duration:
                # Check if there is data ready to be read from stdout
                rlist, _, _ = select.select([process.stdout], [], [], 0.1)
                if rlist:
                    line = process.stdout.readline().strip()
                    print(f"{line}")  # Debug line read
                    line = self.remove_ansi_escape_sequences(line)  # Remove escape sequences
                    if line.startswith('[NEW] Device '):
                        parts = line.split(' ', 3)
                        if len(parts) >= 4:
                            addr = parts[2].strip()  # Ensure no extra spaces
                            name = parts[3].strip()  # Ensure no extra spaces
                            #print(f"Parsed addr: {addr}, name: {name}")  # Debug parsed output
                            if addr not in seen_devices:
                                seen_devices[addr] = BluetoothDevice(address=addr, name=name)
                                print(f"Found: {seen_devices[addr]}")
                            else:
                                print(f"Device {addr} already seen.")  # Debug already seen device
        finally:
            send('scan off')
            send('exit')
            process.terminate()

        return list(seen_devices.values())
    
    def scan_devices(self) -> List[BluetoothDevice]:
        print("Starting Bluetooth Scan")
        return self.scan_once()
    
            
    def connect_to_device(self,device_address):
        print(f"Attempting to connect to {device_address}")
        try:
            # Start bluetoothctl as a subprocess
            process = subprocess.Popen(
                ['bluetoothctl'],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )

            # Send the necessary commands to pair and connect to the device
            process.stdin.write('power on\n')
            time.sleep(1)
            process.stdin.write('agent on\n')
            time.sleep(1)
            process.stdin.write(f'pair {device_address}\n')
            process.stdin.flush()

            # Read the output to ensure it's connected
            output, error = process.communicate()

            # Check if the connection was successful by looking at the output
            if "Connection successful" in output:
                print(f"Successfully connected to {device_address}")
            else:
                print(f"Failed to connect to {device_address}. Output: {output}, Error: {error}")

        except Exception as e:
            print(f"Error while connecting to the device: {str(e)}")