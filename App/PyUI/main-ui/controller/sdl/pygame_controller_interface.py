"""
Pygame (SDL1.2) implementation of controller interface
For use with legacy hardware like Miyoo Mini
"""

import time
import pygame
from devices.device import Device
from controller.controller_interface import ControllerInterface
from utils.logger import PyUiLogger
from utils.time_logger import log_timing


class PygameControllerInterface(ControllerInterface):

    def __init__(self):
        with log_timing("Pygame Controller initialization", PyUiLogger.get_logger()):
            # Initialize pygame joystick module
            pygame.init()
            pygame.joystick.init()

            self.joystick = None
            self.print_key_changes = False
            self.last_event = None

            self.clear_input_queue()
            self.init_controller()

    def print_key_state_changes(self):
        self.print_key_changes = True

    def init_controller(self):
        """Initialize joystick/controller"""
        count = pygame.joystick.get_count()
        PyUiLogger.get_logger().info(f"Found {count} joystick(s)")

        if count > 0:
            self.joystick = pygame.joystick.Joystick(0)
            self.joystick.init()
            self.index = 0
            self.name = self.joystick.get_name()
            PyUiLogger.get_logger().info(f"Opened Joystick 0: {self.name}")
        else:
            PyUiLogger.get_logger().warning("No joystick found")

    def re_init_controller(self):
        """Reinitialize controller (e.g., after Bluetooth pairing)"""
        if self.joystick:
            self.joystick.quit()
            self.joystick = None

        pygame.joystick.quit()
        time.sleep(0.2)
        pygame.joystick.init()

        # Pump events to detect new controllers
        for _ in range(10):
            pygame.event.pump()
            time.sleep(0.1)

        self.init_controller()

    def close(self):
        """Close controller"""
        if self.joystick:
            self.joystick.quit()
            self.joystick = None

    def still_held_down(self):
        """Check if last button is still held"""
        if self.last_event is None:
            return False

        if self.last_event.type == pygame.JOYBUTTONDOWN:
            if self.joystick:
                return self.joystick.get_button(self.last_event.button)
        elif self.last_event.type == pygame.JOYAXISMOTION:
            if self.joystick:
                current_value = self.joystick.get_axis(self.last_event.axis)
                # Check if axis is still in the same direction
                threshold = 16000 / 32767.0  # Normalize to -1.0 to 1.0
                if abs(self.last_event.value) > threshold:
                    return abs(current_value) > threshold
        elif self.last_event.type == pygame.JOYHATMOTION:
            if self.joystick:
                current_hat = self.joystick.get_hat(self.last_event.hat)
                return current_hat == self.last_event.value

        return False

    def force_refresh(self):
        """Force event queue update"""
        pygame.event.pump()

    def get_input(self, timeout):
        """
        Wait for input event with timeout
        timeout: timeout in milliseconds
        Returns: mapped input or None
        """
        # Convert timeout to seconds for pygame
        timeout_sec = timeout / 1000.0
        start_time = time.time()

        while True:
            # Check for timeout
            if timeout_sec > 0:
                elapsed = time.time() - start_time
                if elapsed >= timeout_sec:
                    return None

            # Pump events
            pygame.event.pump()

            # Get events
            for event in pygame.event.get([
                pygame.JOYBUTTONDOWN,
                pygame.JOYBUTTONUP,
                pygame.JOYAXISMOTION,
                pygame.JOYHATMOTION,
                pygame.JOYDEVICEADDED
            ]):

                if event.type == pygame.JOYDEVICEADDED:
                    PyUiLogger.get_logger().info("New controller detected")
                    self.init_controller()
                    continue

                # Store the event
                self.last_event = event

                # Print if enabled
                self.print_last_event()

                # Return mapped input
                return self.last_input()

            # Small sleep to prevent CPU spinning
            time.sleep(0.005)

        return None

    def print_last_event(self):
        """Print last event for debugging"""
        if not self.print_key_changes or self.last_event is None:
            return

        if self.last_event.type == pygame.JOYBUTTONDOWN:
            mapping = Device.get_device().map_digital_input(self.last_event.button)
            if mapping is not None:
                print(f"KEY,{mapping},PRESS")
        elif self.last_event.type == pygame.JOYBUTTONUP:
            mapping = Device.get_device().map_digital_input(self.last_event.button)
            if mapping is not None:
                print(f"KEY,{mapping},RELEASE")
        elif self.last_event.type == pygame.JOYAXISMOTION:
            mapping = Device.get_device().map_analog_input(self.last_event.axis, int(self.last_event.value * 32767))
            if mapping is not None:
                print(f"ANALOG,{mapping}")

    def last_input(self):
        """Get mapped input from last event"""
        if self.last_event is None:
            return None

        if self.last_event.type == pygame.JOYBUTTONDOWN:
            return Device.get_device().map_digital_input(self.last_event.button)
        elif self.last_event.type == pygame.JOYAXISMOTION:
            # Convert pygame axis value (-1.0 to 1.0) to SDL2 format (-32768 to 32767)
            sdl2_value = int(self.last_event.value * 32767)
            return Device.get_device().map_analog_input(self.last_event.axis, sdl2_value)
        elif self.last_event.type == pygame.JOYHATMOTION:
            # Map hat to digital input
            # Hat value is (x, y) where each is -1, 0, or 1
            hat_x, hat_y = self.last_event.value
            if hat_y == 1:  # Up
                return Device.get_device().map_digital_input(100)  # Arbitrary hat up code
            elif hat_y == -1:  # Down
                return Device.get_device().map_digital_input(101)
            elif hat_x == -1:  # Left
                return Device.get_device().map_digital_input(102)
            elif hat_x == 1:  # Right
                return Device.get_device().map_digital_input(103)

        return None

    def clear_input(self):
        """Clear last input"""
        self.last_event = None

    def cache_last_event(self):
        """Cache the last event (for hotkey detection)"""
        self.cached_event = self.last_event
        self.clear_input()

    def restore_cached_event(self):
        """Restore cached event"""
        self.last_event = self.cached_event

    def clear_input_queue(self):
        """Clear the input event queue"""
        pygame.event.clear([
            pygame.JOYBUTTONDOWN,
            pygame.JOYBUTTONUP,
            pygame.JOYAXISMOTION,
            pygame.JOYHATMOTION
        ])

    def get_left_analog_x(self):
        """Get left analog stick X axis value"""
        pygame.event.pump()
        if self.joystick:
            # Axis 0 is typically left X
            value = self.joystick.get_axis(0)
            return int(value * 32767)
        return 0

    def get_left_analog_y(self):
        """Get left analog stick Y axis value"""
        pygame.event.pump()
        if self.joystick:
            # Axis 1 is typically left Y
            value = self.joystick.get_axis(1)
            return int(value * 32767)
        return 0

    def get_right_analog_x(self):
        """Get right analog stick X axis value"""
        pygame.event.pump()
        if self.joystick:
            # Axis 2 is typically right X
            if self.joystick.get_numaxes() > 2:
                value = self.joystick.get_axis(2)
                return int(value * 32767)
        return 0

    def get_right_analog_y(self):
        """Get right analog stick Y axis value"""
        pygame.event.pump()
        if self.joystick:
            # Axis 3 is typically right Y
            if self.joystick.get_numaxes() > 3:
                value = self.joystick.get_axis(3)
                return int(value * 32767)
        return 0
