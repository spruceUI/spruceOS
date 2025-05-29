
import os
from pathlib import Path
import subprocess
import time
from devices.utils.process_runner import ProcessRunner
from display.font_purpose import FontPurpose
from menus.games.utils.rom_info import RomInfo
from utils.logger import PyUiLogger


class MiyooTrimCommon():
        
    @staticmethod
    def convert_game_path_to_miyoo_path(original_path):
        # Define the part of the path to be replaced
        base_dir = "/mnt/SDCARD/Roms/"

        # Check if the original path starts with the base directory
        if original_path.startswith(base_dir):
            # Extract the subdirectory after Roms/
            subdirectory = original_path[len(base_dir):].split(os.sep, 1)[0]
            
            # Construct the new path using the desired format
            new_path = original_path.replace(f"Roms{os.sep}{subdirectory}", f"Emu{os.sep}{subdirectory}{os.sep}..{os.sep}..{os.sep}Roms{os.sep}{subdirectory}")
            new_path = new_path.replace("/mnt/SDCARD/", "/media/sdcard0/")
            return new_path
        else:
            PyUiLogger.get_logger().error(f"Unable to convert {original_path} to miyoo path")
            return original_path

                
    @staticmethod
    def write_cmd_to_run(command):
        with open('/tmp/cmd_to_run.sh', 'w') as file:
            file.write(command)

    @staticmethod
    def delete_cmd_to_run():
        try:
            os.remove('/tmp/cmd_to_run.sh')
        except FileNotFoundError:
            pass  # File doesn't exist, no action needed
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to delete file: {e}")

    @staticmethod
    def run_game(device, rom_info: RomInfo) -> subprocess.Popen:
        launch_path = os.path.join(rom_info.game_system.game_system_config.get_emu_folder(),rom_info.game_system.game_system_config.get_launch())
        
        #file_path = /mnt/SDCARD/Roms/FAKE08/Alpine Alpaca.p8
        #miyoo maps it to /media/sdcard0/Emu/FAKE08/../../Roms/FAKE08/Alpine Alpaca.p8
        miyoo_app_path = MiyooTrimCommon.convert_game_path_to_miyoo_path(rom_info.rom_file_path)
        MiyooTrimCommon.write_cmd_to_run(f'''chmod a+x "{launch_path}";"{launch_path}" "{miyoo_app_path}"''')

        device.fix_sleep_sound_bug()
        try:
            return subprocess.Popen([launch_path,rom_info.rom_file_path], stdin=subprocess.DEVNULL,
                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to launch game {rom_info.rom_file_path}: {e}")
            return None
        
    @staticmethod
    def run_app(device, args, dir = None):
        device.fix_sleep_sound_bug()
        PyUiLogger.get_logger().debug(f"About to launch app {args} from dir {dir}")
        subprocess.run(args, cwd = dir)

    @staticmethod
    def stop_wifi_services(device):
        PyUiLogger.get_logger().info("Stopping WiFi Services")
        ProcessRunner.run(['killall', '-15', 'wpa_supplicant'])
        time.sleep(0.1)  
        ProcessRunner.run(['killall', '-9', 'wpa_supplicant'])
        time.sleep(0.1)  
        ProcessRunner.run(['killall', '-15', 'udhcpc'])
        time.sleep(0.1)  
        ProcessRunner.run(['killall', '-9', 'udhcpc'])
        time.sleep(0.1)  
        device.set_wifi_power(0)


    @staticmethod
    def start_wpa_supplicant(device):
        try:
            # Check if wpa_supplicant is running using ps -f
            result = device.get_running_processes()
            if 'wpa_supplicant' in result.stdout:
                return

            # If not running, start it in the background
            subprocess.Popen([
                'wpa_supplicant',
                '-B',
                '-D', 'nl80211',
                '-i', 'wlan0',
                '-c', '/userdata/cfg/wpa_supplicant.conf'
            ])
            time.sleep(0.5)  # Wait for it to initialize
            PyUiLogger.get_logger().info("wpa_supplicant started.")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error starting wpa_supplicant: {e}")

    @staticmethod
    def ensure_wpa_supplicant_conf():
        conf_path = Path("/userdata/cfg/wpa_supplicant.conf")
        
        if not conf_path.exists():
            conf_path.parent.mkdir(parents=True, exist_ok=True)  # Ensure /userdata/cfg exists
            conf_content = (
                "ctrl_interface=/var/run/wpa_supplicant\n"
                "update_config=1\n\n"
            )
            with conf_path.open("w") as f:
                f.write(conf_content)
            PyUiLogger.get_logger().info("Created missing wpa_supplicant.conf.")
        else:
            PyUiLogger.get_logger().info("wpa_supplicant.conf already exists.")

    def should_scale_screen(self):
        return self.is_hdmi_connected()
    
    @staticmethod
    def disable_wifi(device):
        device.system_config.reload_config()
        device.system_config.set_wifi(0)
        device.system_config.save_config()
        ProcessRunner.run(["ifconfig","wlan0","down"])
        device.stop_wifi_services()
        device.get_wifi_status.force_refresh()
        device.get_ip_addr_text.force_refresh()

    @staticmethod
    def enable_wifi(device):
        device.system_config.reload_config()
        device.system_config.set_wifi(1)
        device.system_config.save_config()
        ProcessRunner.run(["ifconfig","wlan0","up"])
        device.start_wifi_services()
        device.get_wifi_status.force_refresh()
        device.get_ip_addr_text.force_refresh()

    @staticmethod
    def run_analog_stick_calibration(device, stick_name, joystick, file_path, leftOrRight):
        from display.display import Display
        from themes.theme import Theme
        
        Display.clear("Stick Calibration")
        Display.render_text_centered(f"Rotate {stick_name}",device.screen_width//2, device.screen_height//2,Theme.text_color_selected(FontPurpose.LIST), purpose=FontPurpose.LIST)
        Display.present()
       
        rotate_stats = joystick.sample_axes_stats()
        
        Display.clear("Stick Calibration")
        Display.render_text_centered(f"Leave {stick_name} Still",device.screen_width//2, device.screen_height//2,Theme.text_color_selected(FontPurpose.LIST), purpose=FontPurpose.LIST)
        Display.present()

        centered_stats = joystick.sample_axes_stats()
        print("rotate_stats keys:", rotate_stats.keys())
        print("centered_stats keys:", rotate_stats.keys())
        
        x_min = f"x_min={round(rotate_stats['axisX'+leftOrRight]['min'])}"
        x_max = f"x_max={round(rotate_stats['axisX'+leftOrRight]['max'])}"
        x_zero = f"x_zero={round(centered_stats['axisX'+leftOrRight]['avg'])}"

        y_min = f"y_min={round(rotate_stats['axisY'+leftOrRight]['min'])}"
        y_max = f"y_max={round(rotate_stats['axisY'+leftOrRight]['max'])}"
        y_zero = f"y_zero={round(centered_stats['axisY'+leftOrRight]['avg'])}" 

        # Log each
        PyUiLogger.get_logger().info(x_min)
        PyUiLogger.get_logger().info(x_max)
        PyUiLogger.get_logger().info(y_min)
        PyUiLogger.get_logger().info(y_max)
        PyUiLogger.get_logger().info(x_zero)
        PyUiLogger.get_logger().info(y_zero)
        with open(file_path, 'w') as f:
            # Write to file
            f.write(x_min + "\n")
            f.write(x_max + "\n")
            f.write(y_min + "\n")
            f.write(y_max + "\n")
            f.write(x_zero + "\n")
            f.write(y_zero + "\n")
