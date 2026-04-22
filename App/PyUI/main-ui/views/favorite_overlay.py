from display.display import Display
from display.render_mode import RenderMode
from display.x_render_option import XRenderOption
from display.y_render_option import YRenderOption
from views.grid_or_list_entry import GridOrListEntry


def render_favorite_overlay(entry: GridOrListEntry,
                            image_x: int,
                            image_y: int,
                            image_render_mode: RenderMode,
                            image_width,
                            image_height):
    if image_width is None or image_height is None:
        return
    if image_width <= 0 or image_height <= 0:
        return

    icon_path = entry.get_icon()
    if icon_path is None:
        return

    if image_render_mode.x_mode == XRenderOption.LEFT:
        image_right = image_x + image_width
    elif image_render_mode.x_mode == XRenderOption.CENTER:
        image_right = image_x + image_width // 2
    else:
        image_right = image_x

    if image_render_mode.y_mode == YRenderOption.TOP:
        image_top = image_y
    elif image_render_mode.y_mode == YRenderOption.CENTER:
        image_top = image_y - image_height // 2
    else:
        image_top = image_y - image_height

    size = max(int(min(image_width, image_height) * 0.22), 16)
    inset = size // 4
    overlay_cx = image_right - size // 2 - inset
    overlay_cy = image_top + size // 2 + inset

    Display.render_image(
        icon_path,
        overlay_cx,
        overlay_cy,
        RenderMode.MIDDLE_CENTER_ALIGNED,
        target_width=size,
        target_height=size,
    )
