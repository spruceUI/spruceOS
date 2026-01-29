from enum import Enum, auto

class TextToImageRelationship(Enum):
    LEFT_OF_IMAGE = auto()
    RIGHT_OF_IMAGE = auto()
    ABOVE_IMAGE = auto()
    BELOW_IMAGE = auto()
    TEXT_AROUND_LEFT_IMAGE = auto()
    TEXT_AROUND_RIGHT_IMAGE = auto()
