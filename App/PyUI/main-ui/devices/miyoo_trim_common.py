
import json
import os
from pathlib import Path
import re
import subprocess
import time
from devices.device import Device
from devices.utils.process_runner import ProcessRunner
from display.font_purpose import FontPurpose
from menus.games.utils.rom_info import RomInfo
from themes.theme import Theme
from utils.logger import PyUiLogger


class MiyooTrimCommon():
        
    @staticmethod
    def convert_game_path_to_miyoo_path(original_path, remap_sdcard_path):
        # Define the base directories we want to convert
        # (currently do not update/map secondary sdcards)
        base_dirs = {
            "/mnt/SDCARD/": "/media/sdcard0/"
        }
        for base_dir, sdcard_mount in base_dirs.items():
            # Check if the original path starts with the base directory
            if original_path.startswith(base_dir):
                # Extract the subdirectory after Roms/
                subdirectory = original_path[len(base_dir+"/Roms"):].split(os.sep, 1)[0]

                # Construct the new path using the desired format
                new_path = original_path.replace(f"Roms{os.sep}{subdirectory}", f"Emu{os.sep}{subdirectory}{os.sep}..{os.sep}..{os.sep}Roms{os.sep}{subdirectory}")
                if(remap_sdcard_path):
                    new_path = new_path.replace(base_dir, sdcard_mount)

                PyUiLogger.get_logger().info(f"Converted {original_path} to {new_path}")
                return new_path        
            
        # If no matching base directory found
        PyUiLogger.get_logger().error(f"Unable to convert {original_path} to miyoo path")
        return original_path


                
    @staticmethod
    def write_cmd_to_run(command):
        with open('/tmp/cmd_to_run.sh', 'w') as file:
            file.write(command)
            PyUiLogger.get_logger().info(f"Writing cmd to run: {command}")


    @staticmethod
    def delete_cmd_to_run():
        try:
            os.remove('/tmp/cmd_to_run.sh')
        except FileNotFoundError:
            pass  # File doesn't exist, no action needed
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to delete file: {e}")

    @staticmethod
    def run_game(device, rom_info: RomInfo, remap_sdcard_path = False, run_prefix ="") -> subprocess.Popen:
        Theme.check_and_create_ra_assets()
        launch_path = os.path.join(rom_info.game_system.game_system_config.get_emu_folder(),rom_info.game_system.game_system_config.get_launch())
        
        #file_path = /mnt/SDCARD/Roms/FAKE08/Alpine Alpaca.p8
        #miyoo maps it to /media/sdcard0/Emu/FAKE08/../../Roms/FAKE08/Alpine Alpaca.p8
        miyoo_app_path = MiyooTrimCommon.convert_game_path_to_miyoo_path(rom_info.rom_file_path, remap_sdcard_path)
        escaped_path = re.sub(r'([$`"\\])', r'\\\1', miyoo_app_path)        
        MiyooTrimCommon.write_cmd_to_run(f'''chmod a+x "{launch_path}";{run_prefix}"{launch_path}" "{escaped_path}"''')
        Device.get_device().fix_sleep_sound_bug()


        Device.get_device().exit_pyui()
        #try:
        #    return subprocess.Popen([launch_path,rom_info.rom_file_path], stdin=subprocess.DEVNULL,
        #         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        #except Exception as e:
        #    PyUiLogger.get_logger().error(f"Failed to launch game {rom_info.rom_file_path}: {e}")
        #    return None
        
    @staticmethod
    def run_cmd(device, args, dir = None):
        Device.get_device().fix_sleep_sound_bug()
        PyUiLogger.get_logger().debug(f"About to launch app {args} from dir {dir}")
        subprocess.run(args, cwd = dir)

    @staticmethod
    def run_app(device, folder,launch, run_prefix =""):
        Device.get_device().fix_sleep_sound_bug()
        #cd /mnt/SDCARD/App/Commander_Italic; chmod a+x ./launch.sh; LD_PRELOAD=/mnt/SDCARD/miyoo/app/../lib/libpadsp.so   ./launch.sh 
        if '"' in launch:
            MiyooTrimCommon.write_cmd_to_run(f'cd "{folder}"; {run_prefix}{launch}''')
        else:
            MiyooTrimCommon.write_cmd_to_run(f'cd "{folder}"; chmod a+x "{launch}"; {run_prefix}"{launch}"''')
        Device.get_device().exit_pyui()

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
        Device.get_device().set_wifi_power(0)


    @staticmethod
    def start_wpa_supplicant(device):
        try:
            # Check if wpa_supplicant is running using ps -f
            result = Device.get_device().get_running_processes()
            if 'wpa_supplicant' in result.stdout:
                return

            # If not running, start it in the background
            subprocess.Popen([
                'wpa_supplicant',
                '-B',
                '-D', 'nl80211',
                '-i', 'wlan0',
                '-c', Device.get_device().get_wpa_supplicant_conf_path()
            ])
            time.sleep(0.5)  # Wait for it to initialize
            PyUiLogger.get_logger().info("wpa_supplicant started.")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error starting wpa_supplicant: {e}")

    @staticmethod
    def ensure_wpa_supplicant_conf(wpa_supplicant_path):
        try:
            conf_path = Path(wpa_supplicant_path)
            
            if not conf_path.exists():
                conf_path.parent.mkdir(parents=True, exist_ok=True)  # Ensure /userdata/cfg exists
                conf_content = (
                    "ctrl_interface=/var/run/wpa_supplicant\n"
                    "update_config=1\n\n"
                )
                with conf_path.open("w") as f:
                    f.write(conf_content)
                PyUiLogger.get_logger().info("Created missing wpa_supplicant.conf.")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error creating {wpa_supplicant_path}: {e}")

    def should_scale_screen(self):
        return self.is_hdmi_connected()
    
    @staticmethod
    def disable_wifi(device):
        Device.get_device().system_config.reload_config()
        Device.get_device().system_config.set_wifi(0)
        Device.get_device().system_config.save_config()
        ProcessRunner.run(["ifconfig","wlan0","down"])
        Device.get_device().stop_wifi_services()
        Device.get_device().get_wifi_status.force_refresh()
        Device.get_device().get_ip_addr_text.force_refresh()

    @staticmethod
    def enable_wifi(device):
        Device.get_device().system_config.reload_config()
        Device.get_device().system_config.set_wifi(1)
        Device.get_device().system_config.save_config()
        ProcessRunner.run(["ifconfig","wlan0","up"])
        Device.get_device().start_wifi_services()
        Device.get_device().get_wifi_status.force_refresh()
        Device.get_device().get_ip_addr_text.force_refresh()

    @staticmethod
    def run_analog_stick_calibration(device, stick_name, joystick, file_path, leftOrRight):
        from display.display import Display
        
        Display.clear("Stick Calibration")
        Display.display_message(f"Rotate {stick_name}")
        Display.present()
       
        rotate_stats = joystick.sample_axes_stats()
        
        Display.clear("Stick Calibration")
        Display.display_message(f"Leave {stick_name} Still")
        Display.present()

        centered_stats = joystick.sample_axes_stats()
        PyUiLogger.get_logger().info(
            "rotate_stats keys: %s",
            list(rotate_stats.keys())
        )

        PyUiLogger.get_logger().info(
            "centered_stats keys: %s",
            list(centered_stats.keys())
        )        
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
        PyUiLogger.get_logger().info("Calibration Complete")


    @staticmethod
    def set_theme(json_path, theme_path: str):
        try:
            # Read the existing JSON
            try:
                with open(json_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
            except FileNotFoundError:
                data = {}  # start with empty if file doesn't exist

            # Update the "Theme" entry
            data["theme"] = theme_path

            # Write back to the file
            with open(json_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=4)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Could not set theme in {json_path} : {e}")