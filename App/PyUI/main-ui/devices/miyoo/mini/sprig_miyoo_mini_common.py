

from devices.miyoo.mini.miyoo_mini_flip_specific_model_variables import MiyooMiniSpecificModelVariables
from devices.miyoo.mini.miyoo_mini_common import MiyooMiniCommon
from devices.utils.process_runner import ProcessRunner
from devices.utils.file_watcher import FileWatcher
from utils.logger import PyUiLogger
from display.display import Display
import subprocess


class SprigMiyooMiniCommon(MiyooMiniCommon):
    def __init__(self, device_name, main_ui_mode, miyoo_mini_specific_model_variables: MiyooMiniSpecificModelVariables):
        super().__init__(device_name, main_ui_mode, miyoo_mini_specific_model_variables)
        self.sprig_config_path = "/mnt/SDCARD/Saves/mini-flip-system.json"
        self.last_volume = None
        self.last_backlight = None
        if(main_ui_mode):
            self.sprig_config_thread, self.sprig_config_thread_stop_event = FileWatcher().start_file_watcher(
                self.sprig_config_path, self.on_sprig_config_change, interval=0.2)
    
    
    def startup_init(self, include_wifi=True):
        super().startup_init()
        config_volume = self.system_config.get_volume()
        self._set_volume(config_volume)
        self._set_screen_values_to_config()

    def on_sprig_config_change(self):
        """Called when button_watchdog or other scripts change the config"""
        try:
            self.system_config.reload_config()
            current_volume = self.system_config.get_volume()
            current_backlight = self.system_config.get_backlight()
            
            if self.last_volume != current_volume:
                self.last_volume = current_volume
                Display.volume_changed(current_volume)
                PyUiLogger.get_logger().info(f"External volume change detected: {current_volume}")
            
            if self.last_backlight != current_backlight:
                self.last_backlight = current_backlight
                PyUiLogger.get_logger().info(f"External backlight change detected: {current_backlight}")
                
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Error reading Sprig config: {e}")

    def _set_lumination_to_config(self):
        """Set backlight using direct hardware control for instant feedback"""
        try:
            backlight = self.system_config.backlight
            
            # Hardware backlight mapping (same as helperFunctions.sh)
            backlight_map = {
                0: 3, 1: 4, 2: 5, 3: 8, 4: 13, 5: 20,
                6: 30, 7: 45, 8: 60, 9: 80, 10: 100
            }
            backlight_raw = backlight_map.get(backlight, 3)
            
            try:
                with open("/sys/class/pwm/pwmchip0/pwm0/duty_cycle", "w") as f:
                    f.write(str(backlight_raw))
            except Exception as e:
                PyUiLogger.get_logger().warning(f"Direct PWM control failed, falling back to shell: {e}")
                # Fallback to shell script if hardware access fails
                subprocess.run([
                    "/bin/sh", "-c",
                    f". /mnt/SDCARD/sprig/helperFunctions.sh && set_backlight {backlight}"
                ], check=False)
            
            PyUiLogger.get_logger().info(f"Sprig backlight set to {backlight} (raw:{backlight_raw})")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to set Sprig backlight: {e}")

    def get_volume(self):
        """Get volume from system config, always reload to catch external changes"""
        return self.system_config.get_volume()
    
    @property
    def lumination(self):
        """Get backlight from system config, always reload to catch external changes"""
        return self.system_config.get_backlight()

    def change_volume(self, amount):
        """Override to handle Sprig's 0-50 volume range (displays as 0-10)"""
        from display.display import Display
        
        # Get current volume (0-50 range for display as 0-10)
        volume = self.get_volume() + amount
        
        # Clamp to 0-50 for Sprig
        if volume < 0:
            volume = 0
        elif volume > 50:
            volume = 50
        
        self._set_volume(volume)
        
        Display.volume_changed(self.get_volume())
        PyUiLogger.get_logger().info(f"Volume changed by {amount} to {volume}")

    def _set_volume(self, volume: int) -> int:
        """Set volume using direct hardware control for instant feedback"""
        try:
            # Clamp volume between 0 and 50 (displays as 0-10)
            volume = max(0, min(50, volume))
            
            # Scale from 0-50 to 0-20 for hardware
            volume_hw = int(volume * 20 / 50)  # Maps 0-50 to 0-20
            
            # Hardware volume mapping (same as helperFunctions.sh)
            volume_map = {
                0: -60, 1: -44, 2: -37, 3: -32, 4: -29, 5: -26,
                6: -24, 7: -22, 8: -20, 9: -18, 10: -17, 11: -15,
                12: -14, 13: -13, 14: -12, 15: -11, 16: -10,
                17: -9, 18: -8, 19: -7, 20: -6
            }
            volume_raw = volume_map.get(volume_hw, -60)
            
            try:
                with open("/proc/mi_modules/mi_ao/mi_ao0", "w") as f:
                    f.write(f"set_ao_volume 0 {volume_raw}dB\n")
                    f.write(f"set_ao_volume 1 {volume_raw}dB\n")
                    
                    # Handle mute state
                    if volume_raw <= -60:
                        f.write("set_ao_mute 1\n")
                    else:
                        f.write("set_ao_mute 0\n")
            except Exception as e:
                PyUiLogger.get_logger().warning(f"Direct hardware control failed, falling back to shell: {e}")
                # Fallback if hw access fails
                subprocess.run([
                    "/bin/sh", "-c",
                    f". /mnt/SDCARD/sprig/helperFunctions.sh && set_volume {volume_hw}"
                ], check=False)
            
            # Update system config
            self.system_config.set_volume(volume)
            self.system_config.save_config()
            
            PyUiLogger.get_logger().info(f"Sprig volume set to {volume} (hw:{volume_hw}, raw:{volume_raw}dB)")
            return volume
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to set Sprig volume: {e}")
            return volume

    def supports_saturation_calibration(self):
        return True
    
    def supports_contrast_calibration(self):
        return True
    
    def supports_hue_calibration(self):
        return True
    
    def supports_brightness_calibration(self):
        return True

    
    def _set_screen_values_to_config(self):
        #Config is 1-20
        #Device is 0-100
        #max is to ensure screen isn't on but just black
        #Do not need to worry about min all maxed as it still is usable
        brightness = max(5,self.system_config.brightness) * 5
        contrast = max(5,self.system_config.contrast) * 5
        saturation = self.system_config.saturation * 5
        hue = self.system_config.hue * 5
        red = max(48,self.get_disp_red())
        green = max(48,self.get_disp_green())
        blue = max(48,self.get_disp_blue())
        
        ProcessRunner.run(["/mnt/SDCARD/sprig/scripts/display_control.sh", 
                           str(brightness),str(saturation),str(contrast),str(hue),
                           str(red),str(green),str(blue)])


    def _set_contrast_to_config(self):
        self._set_screen_values_to_config()
    
    def _set_saturation_to_config(self):
        self._set_screen_values_to_config()

    def _set_brightness_to_config(self):
        self._set_screen_values_to_config()

    def _set_hue_to_config(self):
        self._set_screen_values_to_config()

    def supports_rgb_calibration(self):
        return True
    
    def _set_disp_red_to_config(self):
        self._set_screen_values_to_config()

    def _set_disp_blue_to_config(self):
        self._set_screen_values_to_config()

    def _set_disp_green_to_config(self):
        self._set_screen_values_to_config()

    def supports_timezone_setting(self):
        return False
