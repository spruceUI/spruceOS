
from typing import List
from controller.controller import Controller
from devices.device import Device
from display.display import Display
from display.render_mode import RenderMode
from themes.theme import Theme
from views.descriptive_list_view import DescriptiveListView
from views.grid_or_list_entry import GridOrListEntry
from views.grid_view import GridView
from views.image_list_view import ImageListView
from views.text_list_view import TextListView
from views.view_type import ViewType


class ViewCreator():

    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme):
        self.display = display
        self.controller = controller
        self.device = device
        self.theme = theme

    def create_view(self, 
                    view_type: ViewType, 
                    options: List[GridOrListEntry], 
                    top_bar_text, 
                    selected_index : int = None, 
                    cols=None, 
                    rows=None):
        match view_type:
            case ViewType.DESCRIPTIVE_LIST_VIEW:
                selected_bg = self.theme.get_list_small_selected_bg()
                for option in options:
                    icon = option.get_icon()
                    if icon is not None:
                        selected_bg = self.theme.get_list_large_selected_bg()

                return DescriptiveListView(
                    display=self.display, 
                    controller=self.controller, 
                    device=self.device, 
                    theme=self.theme, 
                    top_bar_text=top_bar_text,
                    options=options,
                    selected=selected_index,
                    selected_bg=selected_bg
                )
            case ViewType.TEXT_AND_IMAGE_LIST_VIEW:
                img_offset_x = self.device.screen_width - 10
                img_offset_y = (self.device.screen_height - self.display.get_top_bar_height() + self.display.get_bottom_bar_height())//2 + self.display.get_top_bar_height() - self.display.get_bottom_bar_height()
                return ImageListView(
                    display=self.display, 
                    controller=self.controller, 
                    device=self.device, 
                    theme=self.theme,
                    top_bar_text=top_bar_text,
                    options=options,
                    img_offset_x=img_offset_x,
                    img_offset_y=img_offset_y,
                    img_width=self.theme.rom_image_width,
                    img_height=self.theme.rom_image_height,
                    selected_index=selected_index,
                    show_icons=ImageListView.SHOW_ICONS,
                    image_render_mode=RenderMode.MIDDLE_RIGHT_ALIGNED,
                    selected_bg=self.theme.get_list_small_selected_bg()
                )            
            case ViewType.TEXT_LIST_VIEW:
                img_offset_x = self.device.screen_width - 10
                img_offset_y = (self.device.screen_height - self.display.get_top_bar_height() + self.display.get_bottom_bar_height())//2 + self.display.get_top_bar_height() - self.display.get_bottom_bar_height()
                return TextListView(
                    display=self.display, 
                    controller=self.controller, 
                    device=self.device, 
                    theme=self.theme,
                    top_bar_text=top_bar_text,
                    options=options,
                    img_offset_x=img_offset_x,
                    img_offset_y=img_offset_y,
                    img_width=self.theme.rom_image_width,
                    img_height=self.theme.rom_image_height,
                    selected_index=selected_index,
                    show_icons=ImageListView.DONT_SHOW_ICONS,
                    image_render_mode=RenderMode.MIDDLE_RIGHT_ALIGNED,
                    selected_bg=self.theme.get_list_small_selected_bg()
                )
            case ViewType.GRID_VIEW:
                return GridView(
                    display=self.display, 
                    controller=self.controller, 
                    device=self.device, 
                    theme=self.theme,
                    top_bar_text=top_bar_text,
                    options=options,
                    cols=cols,
                    rows=rows,
                    selected_bg=self.theme.get_grid_bg(rows,cols),
                    selected_index=selected_index
                )
            case _:
                print(f"Error: unrecognized view_type {view_type}")

                pass