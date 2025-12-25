
from dataclasses import dataclass

from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState


@dataclass
class InputResult:
    controller_input: ControllerInput
    key_state: KeyState

@dataclass(frozen=True)
class KeyEvent:
    event_type: int
    code: int
    value: int

    