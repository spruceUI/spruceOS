import ctypes
import time
from collections import deque
from datetime import datetime

import sdl2

from controller.controller_inputs import ControllerInput
from controller.controller_interface import ControllerInterface
from devices.desktop.desktop_script import Capture, Press, Wait
from utils.logger import PyUiLogger

# RetroArch's keyboard layout plus M for Menu, by scancode so it does not depend on the OS
# keyboard layout.
KEYBOARD = {
    sdl2.SDL_SCANCODE_UP: ControllerInput.DPAD_UP,
    sdl2.SDL_SCANCODE_DOWN: ControllerInput.DPAD_DOWN,
    sdl2.SDL_SCANCODE_LEFT: ControllerInput.DPAD_LEFT,
    sdl2.SDL_SCANCODE_RIGHT: ControllerInput.DPAD_RIGHT,
    sdl2.SDL_SCANCODE_X: ControllerInput.A,
    sdl2.SDL_SCANCODE_Z: ControllerInput.B,
    sdl2.SDL_SCANCODE_S: ControllerInput.X,
    sdl2.SDL_SCANCODE_A: ControllerInput.Y,
    sdl2.SDL_SCANCODE_Q: ControllerInput.L1,
    sdl2.SDL_SCANCODE_W: ControllerInput.R1,
    sdl2.SDL_SCANCODE_1: ControllerInput.L2,
    sdl2.SDL_SCANCODE_2: ControllerInput.R2,
    sdl2.SDL_SCANCODE_RETURN: ControllerInput.START,
    sdl2.SDL_SCANCODE_RSHIFT: ControllerInput.SELECT,
    sdl2.SDL_SCANCODE_M: ControllerInput.MENU,
}
QUIT_KEY = sdl2.SDL_SCANCODE_ESCAPE
SCREENSHOT_KEY = sdl2.SDL_SCANCODE_F8  # RetroArch's screenshot key

# SDL reports Xbox positions; spruce devices use the Nintendo layout, so map by position.
GAMEPAD = {
    sdl2.SDL_CONTROLLER_BUTTON_DPAD_UP: ControllerInput.DPAD_UP,
    sdl2.SDL_CONTROLLER_BUTTON_DPAD_DOWN: ControllerInput.DPAD_DOWN,
    sdl2.SDL_CONTROLLER_BUTTON_DPAD_LEFT: ControllerInput.DPAD_LEFT,
    sdl2.SDL_CONTROLLER_BUTTON_DPAD_RIGHT: ControllerInput.DPAD_RIGHT,
    sdl2.SDL_CONTROLLER_BUTTON_B: ControllerInput.A,
    sdl2.SDL_CONTROLLER_BUTTON_A: ControllerInput.B,
    sdl2.SDL_CONTROLLER_BUTTON_Y: ControllerInput.X,
    sdl2.SDL_CONTROLLER_BUTTON_X: ControllerInput.Y,
    sdl2.SDL_CONTROLLER_BUTTON_LEFTSHOULDER: ControllerInput.L1,
    sdl2.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: ControllerInput.R1,
    sdl2.SDL_CONTROLLER_BUTTON_START: ControllerInput.START,
    sdl2.SDL_CONTROLLER_BUTTON_BACK: ControllerInput.SELECT,
    sdl2.SDL_CONTROLLER_BUTTON_GUIDE: ControllerInput.MENU,
}

WAIT_TICK_MS = 1000 // 12  # a script's wait:N is N ticks of at least this

_INPUT_EVENTS = (sdl2.SDL_KEYDOWN, sdl2.SDL_KEYUP, sdl2.SDL_CONTROLLERBUTTONDOWN)


class DesktopQuit(SystemExit):
    """The window was closed or Esc pressed."""

    def __init__(self):
        super().__init__(0)


class ScriptFinished(SystemExit):
    """The script ran out and the run was asked to end with it (headless runs)."""

    def __init__(self):
        super().__init__(0)


class DesktopControllerInterface(ControllerInterface):
    """Input from the keyboard, the first SDL game controller, or a script.

    Scripted steps come first, and live input is ignored while they last. Once the script is
    used up the run either ends (exit_when_script_ends) or carries on with live input.
    on_script_progress gets the steps still to play each time one is used.
    """

    def __init__(self, script=(), on_capture=None, exit_when_script_ends=False,
                 on_script_progress=None):
        self._script = deque(script)
        self._scripted = bool(self._script)
        self._polling_hotkey = False
        self._on_capture = on_capture
        self._exit_when_script_ends = exit_when_script_ends
        self._on_script_progress = on_script_progress
        self._event = sdl2.SDL_Event()
        self._gamepad = None
        self._held_key = None
        self._held_button = None
        self.init_controller()

    @property
    def unplayed(self):
        """Script steps not used yet, e.g. because the app exited before reaching them."""
        return list(self._script)

    def init_controller(self):
        sdl2.SDL_InitSubSystem(sdl2.SDL_INIT_GAMECONTROLLER)
        for index in range(sdl2.SDL_NumJoysticks()):
            if sdl2.SDL_IsGameController(index):
                self._gamepad = sdl2.SDL_GameControllerOpen(index)
                PyUiLogger.get_logger().info(
                    f"Desktop gamepad: {sdl2.SDL_GameControllerName(self._gamepad)}")
                return

    def re_init_controller(self):
        self.close()
        self.init_controller()

    def close(self):
        if self._gamepad:
            sdl2.SDL_GameControllerClose(self._gamepad)
            self._gamepad = None

    def still_held_down(self):
        # Drives PyUI's turbo (holding a direction keeps scrolling); never for scripts.
        if self._scripted:
            return False
        # SDL updates key and button state only when it pumps events, and Controller.get_input
        # asks this before reading any: without the pump a released key stayed held for good,
        # so get_input kept returning at once and nothing else was ever read (a freeze).
        sdl2.SDL_PumpEvents()
        if self._held_key is not None:
            state = sdl2.SDL_GetKeyboardState(None)
            return bool(state[self._held_key])
        if self._held_button is not None and self._gamepad:
            return bool(sdl2.SDL_GameControllerGetButton(self._gamepad, self._held_button))
        return False

    def force_refresh(self):
        sdl2.SDL_PumpEvents()

    def get_input(self, timeout):
        """The next input, waiting up to timeout ms for live input; None on a timeout."""
        if self._scripted:
            if self._polling_hotkey:
                # PyUI is checking whether Menu is part of a button combination: answer "no
                # other button" rather than handing it the next scripted tap.
                time.sleep((max(timeout, 0) + 1) / 1000)
                return None
            return self._next_scripted(timeout)
        if not sdl2.SDL_WasInit(sdl2.SDL_INIT_GAMECONTROLLER):
            # Display.deinit_display (before apps and games) quits SDL, gamepad included.
            self._gamepad = None
            self.init_controller()
        if not sdl2.SDL_WaitEventTimeout(ctypes.byref(self._event), max(timeout, 1)):
            return None
        return self._translate(self._event)

    def _next_scripted(self, timeout):
        while self._script:
            step = self._script.popleft()
            if isinstance(step, Wait) and step.ticks > 1:
                self._script.appendleft(Wait(step.ticks - 1))
            if self._on_script_progress is not None:
                self._on_script_progress(list(self._script))
            if isinstance(step, Wait):
                # One idle tick of 1/12 s, then the view redraws before the next step. It may
                # be waiting longer (an unchanged screen waits up to a second), so end its wait.
                time.sleep(WAIT_TICK_MS / 1000)
                from controller.controller import Controller
                Controller.request_redraw()
                return None
            if isinstance(step, Capture):
                if self._on_capture is not None:
                    self._on_capture(step.name)
                continue
            if isinstance(step, Press):
                return ControllerInput[step.button]
        if self._exit_when_script_ends:
            raise ScriptFinished()
        self._scripted = False
        return None

    def _translate(self, event):
        if event.type == sdl2.SDL_QUIT:
            raise DesktopQuit()
        if event.type == sdl2.SDL_KEYDOWN and not event.key.repeat:
            scancode = event.key.keysym.scancode
            if scancode == QUIT_KEY:
                raise DesktopQuit()
            if scancode == SCREENSHOT_KEY:
                if self._on_capture is not None:
                    self._on_capture(datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
                return None
            mapped = KEYBOARD.get(scancode)
            if mapped is not None:
                self._held_key, self._held_button = scancode, None
            return mapped
        if event.type == sdl2.SDL_CONTROLLERBUTTONDOWN:
            mapped = GAMEPAD.get(event.cbutton.button)
            if mapped is not None:
                self._held_key, self._held_button = None, event.cbutton.button
            return mapped
        if event.type == sdl2.SDL_CONTROLLERDEVICEADDED and not self._gamepad:
            self.init_controller()
        return None

    def clear_input(self):
        self._event.type = 0

    def wake(self):
        if self._scripted:
            return  # scripted steps don't wait on SDL
        # Any event ends SDL_WaitEventTimeout; _translate maps a user event to no input.
        event = sdl2.SDL_Event()
        event.type = sdl2.SDL_USEREVENT
        sdl2.SDL_PushEvent(ctypes.byref(event))

    def clear_input_queue(self):
        # Live events only: scripted steps stay queued.
        sdl2.SDL_PumpEvents()
        for event_type in _INPUT_EVENTS:
            sdl2.SDL_FlushEvent(event_type)

    def cache_last_event(self):
        # Controller calls this pair around its Menu button combination check.
        self._polling_hotkey = True

    def restore_cached_event(self):
        self._polling_hotkey = False
