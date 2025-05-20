
from typing import List
from devices.device import Device
from display.display import Display
from display.render_mode import RenderMode
from display.resize_type import ResizeType
from themes.theme import Theme
from views.descriptive_list_view import DescriptiveListView
from views.grid_or_list_entry import GridOrListEntry
from views.grid_view import GridView
from views.image_list_view import ImageListView
from views.popup_text_list_view import PopupTextListView
from views.text_list_view import TextListView
from views.text_to_image_relationship import TextToImageRelationship
from views.view_type import ViewType

class ViewCreator:

    @staticmethod
    def get_usable_height_for_text_above_or_below_image(img_height, y_pad):
        return Display.get_usable_screen_height() - y_pad - img_height

    @staticmethod
    def create_view(view_type: ViewType,
                    options: List[GridOrListEntry],
                    top_bar_text,
                    selected_index: int = None,
                    cols=None,
                    rows=None,
                    use_mutli_row_grid_select_as_backup_for_single_row_grid_select=False,
                    hide_grid_bg=False,
                    show_grid_text=True,
                    grid_resized_width=None,
                    grid_resized_height=None,
                    set_top_bar_text_to_selection=False,
                    grid_selected_bg=None,
                    grid_resize_type=None) -> object:
        match view_type:
            case ViewType.ICON_AND_DESC:
                selected_bg = Theme.get_list_small_selected_bg()
                for option in options:
                    icon = option.get_icon()
                    if icon is not None:
                        selected_bg = Theme.get_list_large_selected_bg()

                return DescriptiveListView(
                    top_bar_text=top_bar_text,
                    options=options,
                    selected=selected_index,
                    selected_bg=selected_bg
                )

            case ViewType.TEXT_AND_IMAGE:
                text_and_image_list_view_mode = Theme.text_and_image_list_view_mode()
                img_width = Theme.get_game_select_img_width()
                img_height = Theme.get_game_select_img_height()

                if text_and_image_list_view_mode == "TEXT_LEFT_IMAGE_RIGHT":
                    img_offset_x = Device.screen_width() - 10 - img_width // 2
                    img_offset_y = ((Device.screen_height() - Display.get_top_bar_height() +
                                     Display.get_bottom_bar_height()) // 2 +
                                    Display.get_top_bar_height() - Display.get_bottom_bar_height())
                    image_render = RenderMode.MIDDLE_CENTER_ALIGNED
                    text_to_image_relationship = TextToImageRelationship.LEFT_OF_IMAGE
                    usable_height = None

                elif text_and_image_list_view_mode == "TEXT_RIGHT_IMAGE_LEFT":
                    img_offset_x = 10 + img_width // 2
                    img_offset_y = ((Device.screen_height() - Display.get_top_bar_height() +
                                     Display.get_bottom_bar_height()) // 2 +
                                    Display.get_top_bar_height() - Display.get_bottom_bar_height())
                    image_render = RenderMode.MIDDLE_CENTER_ALIGNED
                    text_to_image_relationship = TextToImageRelationship.RIGHT_OF_IMAGE
                    usable_height = None

                elif text_and_image_list_view_mode == "TEXT_BELOW_IMAGE":
                    img_offset_x = Device.screen_width() // 2
                    y_pad = 20  # TODO: get from somewhere
                    img_offset_y = Display.get_top_bar_height() + y_pad
                    image_render = RenderMode.TOP_CENTER_ALIGNED
                    text_to_image_relationship = TextToImageRelationship.BELOW_IMAGE
                    usable_height = ViewCreator.get_usable_height_for_text_above_or_below_image(img_height, y_pad)

                elif text_and_image_list_view_mode == "TEXT_ABOVE_IMAGE":
                    img_offset_x = Device.screen_width() // 2
                    y_pad = 20  # TODO: get from somewhere
                    img_offset_y = Device.screen_height() - Display.get_bottom_bar_height() - y_pad
                    image_render = RenderMode.BOTTOM_CENTER_ALIGNED
                    text_to_image_relationship = TextToImageRelationship.ABOVE_IMAGE
                    usable_height = ViewCreator.get_usable_height_for_text_above_or_below_image(img_height, y_pad)

                elif text_and_image_list_view_mode == "TEXT_AROUND_LEFT_IMAGE":
                    img_offset_x = 10 + img_width // 2
                    img_offset_y = ((Device.screen_height() - Display.get_top_bar_height() +
                                     Display.get_bottom_bar_height()) // 2 +
                                    Display.get_top_bar_height() - Display.get_bottom_bar_height())
                    image_render = RenderMode.MIDDLE_CENTER_ALIGNED
                    text_to_image_relationship = TextToImageRelationship.TEXT_AROUND_LEFT_IMAGE
                    usable_height = None

                elif text_and_image_list_view_mode == "TEXT_AROUND_RIGHT_IMAGE":
                    img_offset_x = Device.screen_width() - 10 - img_width // 2
                    img_offset_y = ((Device.screen_height() - Display.get_top_bar_height() +
                                     Display.get_bottom_bar_height()) // 2 +
                                    Display.get_top_bar_height() - Display.get_bottom_bar_height())
                    image_render = RenderMode.MIDDLE_CENTER_ALIGNED
                    text_to_image_relationship = TextToImageRelationship.TEXT_AROUND_RIGHT_IMAGE
                    usable_height = None

                return ImageListView(
                    top_bar_text=top_bar_text,
                    options=options,
                    img_offset_x=img_offset_x,
                    img_offset_y=img_offset_y,
                    img_width=img_width,
                    img_height=img_height,
                    selected_index=selected_index,
                    show_icons=ImageListView.SHOW_ICONS,
                    image_render_mode=image_render,
                    text_to_image_relationship=text_to_image_relationship,
                    selected_bg=Theme.get_list_small_selected_bg(),
                    usable_height=usable_height
                )

            case ViewType.TEXT_ONLY:
                return TextListView(
                    top_bar_text=top_bar_text,
                    options=options,
                    selected_index=selected_index,
                    show_icons=ImageListView.DONT_SHOW_ICONS,
                    image_render_mode=RenderMode.MIDDLE_RIGHT_ALIGNED,
                    selected_bg=Theme.get_list_small_selected_bg()
                )

            case ViewType.POPUP:
                return PopupTextListView(
                    options=options,
                    selected_index=selected_index,
                    show_icons=ImageListView.DONT_SHOW_ICONS,
                    image_render_mode=RenderMode.MIDDLE_RIGHT_ALIGNED,
                    selected_bg=Theme.get_popup_menu_selected_bg()
                )

            case ViewType.GRID:
                if(hide_grid_bg):
                    grid_selected_bg = None
                elif(grid_selected_bg is None):
                    grid_selected_bg = Theme.get_grid_bg(rows, cols, use_mutli_row_grid_select_as_backup_for_single_row_grid_select)
                return GridView(
                    top_bar_text=top_bar_text,
                    options=options,
                    cols=cols,
                    rows=rows,
                    selected_bg=grid_selected_bg,
                    selected_index=selected_index,
                    show_grid_text=show_grid_text,
                    resized_width=grid_resized_width,
                    resized_height=grid_resized_height,
                    set_top_bar_text_to_selection=set_top_bar_text_to_selection,
                    resize_type=grid_resize_type
                )

            case _:
                PyUiLogger.get_logger().error(f"Error: unrecognized view_type {view_type}")
