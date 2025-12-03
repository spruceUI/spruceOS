

from enum import Enum, auto


class ResizeType(Enum):
    FIT = auto(), #e.g. aspect ratio will remain identical
    ZOOM = auto(), #e.g.  The smaller dimension will be used as the base and the larger dimension cropped
    NONE = auto(), #e.g. no resizing, image will be the same size as the passed in asset

def get_next_resize_type(current_type: ResizeType, direction: int, exclude: list[ResizeType] = []) -> ResizeType:
    exclude = exclude or []

    # Build the filtered list of allowed view types
    the_types = [typ for typ in ResizeType if typ not in exclude]

    if current_type not in the_types:
        raise ValueError(f"Current view type {current_type} is excluded or invalid.")

    current_index = the_types.index(current_type)
    next_index = (current_index + direction) % len(the_types)
    return the_types[next_index]