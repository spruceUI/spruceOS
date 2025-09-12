from enum import Enum, auto

class KeyState(Enum):
    PRESS = auto()
    RELEASE = auto()
    REPEAT = auto()