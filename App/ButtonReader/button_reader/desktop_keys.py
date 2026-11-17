"""On PyUI's DESKTOP device: the keyboard as a fake pad node (PyUI's desktop keys, plus C/V L3/R3,
-/= volume, T/F/G/H and I/J/K/L sticks; Esc leaves).
"""
import ctypes

from button_reader.evdev import PipeNode
from button_reader.names import EV_ABS, EV_KEY

FULL = 32767
# (SDL scancode name, kernel code, cfg variable)
KEYS = [("UP", 544, "B_UP"), ("DOWN", 545, "B_DOWN"), ("LEFT", 546, "B_LEFT"), ("RIGHT", 547, "B_RIGHT"),
        ("X", 305, "B_A"), ("Z", 304, "B_B"), ("S", 307, "B_X"), ("A", 308, "B_Y"),
        ("Q", 310, "B_L1"), ("W", 311, "B_R1"), ("1", 312, "B_L2"), ("2", 313, "B_R2"),
        ("C", 317, "B_L3"), ("V", 318, "B_R3"), ("RSHIFT", 314, "B_SELECT"), ("RETURN", 315, "B_START"),
        ("M", 316, "B_MENU"), ("MINUS", 114, "B_VOLDOWN"), ("EQUALS", 115, "B_VOLUP")]
# (scancode name, axis, direction)
STICK_KEYS = [("T", 1, -1), ("G", 1, 1), ("F", 0, -1), ("H", 0, 1),
              ("I", 4, -1), ("K", 4, 1), ("J", 3, -1), ("L", 3, 1)]
ENV = dict({var: f"{EV_KEY} {code}" for _k, code, var in KEYS}, B_HOME="DOESNT_EXIST", B_POWER="DOESNT_EXIST",
           STICK_RIGHT="3 0 32767", STICK_DOWN="3 1 32767", STICK_RIGHT_2="3 3 32767",
           STICK_DOWN_2="3 4 32767", DEVICE_NUM_ANALOG_STICKS="2", PLATFORM="DESKTOP")


class DesktopKeyboard(PipeNode):
    def __init__(self):
        axes = {a: {"min": -FULL, "max": FULL, "fuzz": 16, "flat": 128} for a in (0, 1, 3, 4)}
        super().__init__("desktop-keys", "Desktop keyboard (Button Reader)", [c for _k, c, _v in KEYS], axes,
                         ident=(0x06, 0, 0, 0))
        import sdl2
        self.sdl2 = sdl2
        self.keys = sorted(c for _k, c, _v in KEYS)
        self.by_scancode = {getattr(sdl2, f"SDL_SCANCODE_{k}"): c for k, c, _v in KEYS}
        self.stick = {getattr(sdl2, f"SDL_SCANCODE_{k}"): (a, d) for k, a, d in STICK_KEYS}
        self.held_stick = set()
        self.quit = False

    def pump(self):
        sdl2 = self.sdl2
        event = self.sdl2.SDL_Event()
        while sdl2.SDL_PollEvent(ctypes.byref(event)):
            if event.type == sdl2.SDL_QUIT:
                self.quit = True
            elif event.type in (sdl2.SDL_KEYDOWN, sdl2.SDL_KEYUP) and not event.key.repeat:
                down = event.type == sdl2.SDL_KEYDOWN
                scancode = event.key.keysym.scancode
                if scancode == sdl2.SDL_SCANCODE_ESCAPE:
                    self.quit = True
                elif scancode in self.by_scancode:
                    self.send(EV_KEY, self.by_scancode[scancode], 1 if down else 0)
                elif scancode in self.stick:
                    (self.held_stick.add if down else self.held_stick.discard)(scancode)
                    axis = self.stick[scancode][0]
                    value = sum(d for s, (a, d) in self.stick.items() if a == axis and s in self.held_stick)
                    self.send(EV_ABS, axis, value * FULL)
