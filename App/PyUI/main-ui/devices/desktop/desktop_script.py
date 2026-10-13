from dataclasses import dataclass

# Script token -> ControllerInput member name.
BUTTONS = {
    "up": "DPAD_UP",
    "down": "DPAD_DOWN",
    "left": "DPAD_LEFT",
    "right": "DPAD_RIGHT",
    "a": "A",
    "b": "B",
    "x": "X",
    "y": "Y",
    "l1": "L1",
    "r1": "R1",
    "l2": "L2",
    "r2": "R2",
    "start": "START",
    "select": "SELECT",
    "menu": "MENU",
}

_CAPTURE_PREFIX = "shot:"
_WAIT_PREFIX = "wait:"


@dataclass(frozen=True)
class Press:
    """Press and release one button (a ControllerInput member name)."""
    button: str


@dataclass(frozen=True)
class Capture:
    """Save the frame on screen as <name>.png."""
    name: str


@dataclass(frozen=True)
class Wait:
    """Let PyUI run idle input ticks, of 1/12 s or the view's input timeout if longer, e.g.
    while something loads."""
    ticks: int


class ScriptError(ValueError):
    pass


def parse_script(text):
    """Parse "down, down, a, shot:game_select, wait:12" into Press/Capture/Wait steps.

    Tokens are button names (BUTTONS, case-insensitive), shot:<name> captures and
    wait:<ticks> idle ticks. Empty tokens are ignored.
    """
    steps = []
    for raw in (text or "").split(","):
        token = raw.strip()
        if not token:
            continue
        if token.lower().startswith(_WAIT_PREFIX):
            count = token[len(_WAIT_PREFIX):].strip()
            if not count.isdigit() or int(count) < 1:
                raise ScriptError(f"invalid wait in {token!r}")
            steps.append(Wait(int(count)))
            continue
        if token.lower().startswith(_CAPTURE_PREFIX):
            name = token[len(_CAPTURE_PREFIX):].strip()
            if not name or "/" in name or "\\" in name:
                raise ScriptError(f"invalid capture name in {token!r}")
            steps.append(Capture(name))
            continue
        button = BUTTONS.get(token.lower())
        if button is None:
            raise ScriptError(f"unknown button {token!r}; expected one of {sorted(BUTTONS)}")
        steps.append(Press(button))
    return steps
