
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
from views.popup_text_list_view import PopupTextListView
from views.text_list_view import TextListView
from views.text_to_image_relationship import TextToImageRelationship
from views.view_type import ViewType


class ViewCreator():

    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme):
        self.display = display
        self.controller = controller
        self.device = device
        self.theme = theme

    def get_usable_height_for_text_above_or_below_image(self, img_height, y_pad):
        return self.display.get_usable_screen_height() - y_pad - img_height

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
                text_and_image_list_view_mode = self.theme.text_and_image_list_view_mode
                img_width = self.theme.rom_image_width
                img_height = self.theme.rom_image_height

                if("TEXT_LEFT_IMAGE_RIGHT" == text_and_image_list_view_mode):
                    img_offset_x = self.device.screen_width - 10 - img_width//2
                    img_offset_y = (self.device.screen_height - self.display.get_top_bar_height() + self.display.get_bottom_bar_height())//2 + self.display.get_top_bar_height() - self.display.get_bottom_bar_height()
                    image_render = RenderMode.MIDDLE_CENTER_ALIGNED
                    text_to_image_relationship = TextToImageRelationship.LEFT_OF_IMAGE
                    usable_height = None # auto-determine
                elif("TEXT_RIGHT_IMAGE_LEFT" == text_and_image_list_view_mode):
                    img_offset_x = 10 + img_width//2
                    img_offset_y = (self.device.screen_height - self.display.get_top_bar_height() + self.display.get_bottom_bar_height())//2 + self.display.get_top_bar_height() - self.display.get_bottom_bar_height()
                    image_render = RenderMode.MIDDLE_CENTER_ALIGNED
                    text_to_image_relationship = TextToImageRelationship.RIGHT_OF_IMAGE
                    usable_height = None  # auto-determine
                elif("TEXT_BELOW_IMAGE" == text_and_image_list_view_mode):
                    img_offset_x = self.device.screen_width // 2
                    y_pad = 20 #TODO get from somewhere
                    img_offset_y = self.display.get_top_bar_height() + y_pad
                    image_render = RenderMode.TOP_CENTER_ALIGNED
                    text_to_image_relationship = TextToImageRelationship.BELOW_IMAGE
                    usable_height = self.get_usable_height_for_text_above_or_below_image(img_height, y_pad)
                elif("TEXT_ABOVE_IMAGE" == text_and_image_list_view_mode):
                    img_offset_x = self.device.screen_width // 2
                    y_pad = 20 #TODO get from somewhere
                    img_offset_y = self.device.screen_height - self.display.get_bottom_bar_height() - y_pad
                    image_render = RenderMode.BOTTOM_CENTER_ALIGNED
                    text_to_image_relationship = TextToImageRelationship.ABOVE_IMAGE
                    usable_height = self.get_usable_height_for_text_above_or_below_image(img_height, y_pad)
                elif("TEXT_AROUND_LEFT_IMAGE" == text_and_image_list_view_mode):
                    img_offset_x = 10 + img_width//2
                    img_offset_y = (self.device.screen_height - self.display.get_top_bar_height() + self.display.get_bottom_bar_height())//2 + self.display.get_top_bar_height() - self.display.get_bottom_bar_height()
                    image_render = RenderMode.MIDDLE_CENTER_ALIGNED
                    text_to_image_relationship = TextToImageRelationship.TEXT_AROUND_LEFT_IMAGE
                    usable_height = None  # auto-determine
                elif("TEXT_AROUND_RIGHT_IMAGE" == text_and_image_list_view_mode):
                    img_offset_x = self.device.screen_width - 10 - img_width//2
                    img_offset_y = (self.device.screen_height - self.display.get_top_bar_height() + self.display.get_bottom_bar_height())//2 + self.display.get_top_bar_height() - self.display.get_bottom_bar_height()
                    image_render = RenderMode.MIDDLE_CENTER_ALIGNED
                    text_to_image_relationship = TextToImageRelationship.TEXT_AROUND_RIGHT_IMAGE
                    usable_height = None # auto-determine
                    
                return ImageListView(
                    display=self.display, 
                    controller=self.controller, 
                    device=self.device, 
                    theme=self.theme,
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
                    selected_bg=self.theme.get_list_small_selected_bg(),
                    usable_height=usable_height
                )            
            case ViewType.TEXT_LIST_VIEW:
                return TextListView(
                    display=self.display, 
                    controller=self.controller, 
                    device=self.device, 
                    theme=self.theme,
                    top_bar_text=top_bar_text,
                    options=options,
                    selected_index=selected_index,
                    show_icons=ImageListView.DONT_SHOW_ICONS,
                    image_render_mode=RenderMode.MIDDLE_RIGHT_ALIGNED,
                    selected_bg=self.theme.get_list_small_selected_bg()
                )   
            case ViewType.POPUP_TEXT_LIST_VIEW:
                return PopupTextListView(
                    display=self.display, 
                    controller=self.controller, 
                    device=self.device, 
                    theme=self.theme,
                    options=options,
                    selected_index=selected_index,
                    show_icons=ImageListView.DONT_SHOW_ICONS,
                    image_render_mode=RenderMode.MIDDLE_RIGHT_ALIGNED,
                    selected_bg=self.theme.get_popup_menu_selected_bg()
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
                PyUiLogger.get_logger().error(f"Error: unrecognized view_type {view_type}")

                pass