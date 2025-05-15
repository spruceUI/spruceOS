from enum import Enum, auto

class ViewType(Enum):
    DESCRIPTIVE_LIST_VIEW = auto()
    GRID_VIEW = auto()
    TEXT_AND_IMAGE_LIST_VIEW = auto()
    TEXT_LIST_VIEW = auto()
    POPUP_TEXT_LIST_VIEW = auto()