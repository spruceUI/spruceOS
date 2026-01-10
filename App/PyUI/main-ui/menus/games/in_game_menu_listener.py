

import signal
import subprocess
import time
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.games.in_game_menu_popup import InGameMenuPopup
from menus.games.retroarch_in_game_menu_popup import RetroarchInGameMenuPopup
from menus.games.utils.rom_info import RomInfo
from utils.logger import PyUiLogger
import signal

class InGameMenuListener:
    def __init__(self):
        self.popup_menu = InGameMenuPopup()
        self.ra_popup_menu = RetroarchInGameMenuPopup()
            
    def send_signal(self, proc: subprocess.Popen, sig, timeout: float = 3.0):
        try:
            import psutil
            ps_proc = psutil.Process(proc.pid)

            # Send SIGTERM to all children
            children = ps_proc.children(recursive=True)
            for child in children:
                PyUiLogger.get_logger().debug(f"Sending signal {sig} to child PID {child.pid}")
                child.send_signal(sig)
                PyUiLogger.get_logger().debug(f"Sending signal {sig} to parent PID {ps_proc.pid}")
            ps_proc.send_signal(sig)

            if(signal.SIGTERM == sig):
                # Wait up to `timeout` seconds
                deadline = time.time() + timeout
                while time.time() < deadline:
                    if not ps_proc.is_running() and all(not child.is_running() for child in children):
                        return  # All terminated gracefully
                    time.sleep(0.1)
            
                # If still running, force kill
                for child in children:
                    if child.is_running():
                        PyUiLogger.get_logger().debug(f"For exitting child PID {child.pid}")
                        child.kill()
                if ps_proc.is_running():
                    PyUiLogger.get_logger().debug(f"For exitting PID {child.pid}")
                    ps_proc.kill()

        except Exception as e:
            PyUiLogger.get_logger().error(f"Error in send_signal: {e}")
    
    def game_launched(self, game_process: subprocess.Popen, game: RomInfo):
        support_menu_button_in_game = game.game_system.game_system_config.run_in_game_menu()
        uses_retroarch = game.game_system.game_system_config.uses_retroarch()
        while(game_process.poll() is None):
            if(Controller.get_input()):
                if (ControllerInput.MENU == Controller.last_input() and support_menu_button_in_game):
                    held_down = True
                    hold_start = time.time()
                    while(held_down and time.time() - hold_start < 0.3):   
                        held_down = Controller.still_held_down() and Controller.last_input() == ControllerInput.MENU
                        time.sleep(0.05)

                    if(held_down):
                        PyUiLogger.get_logger().debug(f"Held down detected, ignoring menu button")
                    else:
                        if(uses_retroarch):
                            self.ra_popup_menu.send_cmd_to_ra(b'PAUSE_TOGGLE')
                        else:
                            self.send_signal(game_process, signal.SIGSTOP)

                        PyUiLogger.get_logger().info(f"Taking snapshot before in-game menu")
                        snapshot = Device.get_device().take_snapshot("/tmp/screenshot.png")
                        PyUiLogger.get_logger().info(f"Finished Taking snapshot before in-game menu")
                        Device.get_device().capture_framebuffer()
                        Display.reinitialize(snapshot)
                        
                        PyUiLogger.get_logger().debug(f"In game menu opened")
                        if(uses_retroarch):
                            continue_running = self.ra_popup_menu.run_in_game_menu()
                        else:
                            continue_running = self.popup_menu.run_in_game_menu()
                        PyUiLogger.get_logger().debug(f"In game menu opened closed. Continue Running ? {continue_running}")

                        Display.deinit_display()
                        Device.get_device().restore_framebuffer()
                        if(continue_running):
                            self.send_signal(game_process, signal.SIGCONT)
                        else:
                            self.send_signal(game_process, signal.SIGCONT)
                            time.sleep(0.1)
                            self.send_signal(game_process, signal.SIGTERM)

        
        PyUiLogger.get_logger().debug(f"Game exit code was {game_process.poll()}")
