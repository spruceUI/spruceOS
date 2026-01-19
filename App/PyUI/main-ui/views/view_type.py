from enum import Enum, auto

class ViewType(Enum):
    ICON_AND_DESC = auto()
    FULLSCREEN_GRID = auto()
    GRID = auto()
    TEXT_AND_IMAGE = auto()
    TEXT_ONLY = auto()
    POPUP = auto()
    CAROUSEL = auto()

def get_next_view_type(current_view_type: ViewType, direction: int, exclude: list[ViewType] = [ViewType.POPUP]) -> ViewType:
    exclude = exclude or []

    # Build the filtered list of allowed view types
    view_types = [vt for vt in ViewType if vt not in exclude]

    if current_view_type not in view_types:
        raise ValueError(f"Current view type {current_view_type} is excluded or invalid.")

    current_index = view_types.index(current_view_type)
    next_index = (current_index + direction) % len(view_types)
    return view_types[next_index]