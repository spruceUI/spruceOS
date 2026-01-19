from enum import Enum, auto

class FontPurpose(Enum):
    TOP_BAR_TEXT = auto()
    BATTERY_PERCENT = auto()
    LIST = auto()
    MESSAGE = auto()
    DESCRIPTIVE_LIST_TITLE = auto()
    DESCRIPTIVE_LIST_DESCRIPTION = auto()
    GRID_ONE_ROW = auto()
    GRID_MULTI_ROW = auto()
    LIST_INDEX = auto()
    LIST_TOTAL = auto()
    ON_SCREEN_KEYBOARD = auto()
    SHADOWED = auto()
    SHADOWED_BACKDROP = auto()
    SHADOWED_SMALL = auto()
    SHADOWED_BACKDROP_SMALL = auto()    