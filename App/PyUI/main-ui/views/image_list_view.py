import time
from typing import List
from devices.device import Device
from display.display import Display
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from display.x_render_option import XRenderOption
from display.y_render_option import YRenderOption
from themes.theme import Theme
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.non_descriptive_list_view import NonDescriptiveListView
from views.text_to_image_relationship import TextToImageRelationship

class ImageListView(NonDescriptiveListView):
    SHOW_ICONS = True
    DONT_SHOW_ICONS = False

    def __init__(self, top_bar_text,
                 options: List[GridOrListEntry], img_offset_x : int, img_offset_y : int, img_width : int, img_height: int,
                 selected_index : int, show_icons : bool, image_render_mode: RenderMode, selected_bg = None, usable_height = None,
                 text_to_image_relationship = TextToImageRelationship.LEFT_OF_IMAGE):
        super().__init__(top_bar_text=top_bar_text,
                         options=options,
                         selected_index=selected_index,
                         show_icons=show_icons,
                         image_render_mode=image_render_mode,
                         selected_bg=selected_bg,
                         usable_height=usable_height)

        self.img_offset_x = img_offset_x
        self.img_offset_y = img_offset_y
        self.img_width = img_width
        self.img_height = img_height
        self.text_to_image_relationship = text_to_image_relationship
        self.prev_index = -1
        self.scroll_text_amount = 0
        self.selected_same_entry_time = time.time()
        self.space_width, self.char_height = Display.get_text_dimensions(FontPurpose.LIST," ")
    
    def _render_text(self, visible_options):
        for visible_index, (imageTextPair) in enumerate(visible_options):
            actual_index = self.current_top + visible_index
            text_available_width = None #just take up as much space as needed
            text_pad = int(30 * Device.get_device().screen_height() / 480 )  #TODO get this from somewhere
            if(TextToImageRelationship.LEFT_OF_IMAGE == self.text_to_image_relationship):
                x_value = 0 
                y_value = self.base_y_offset + self.line_height//2
                text_available_width = self.get_img_x_starting() - text_pad*2
            elif(TextToImageRelationship.RIGHT_OF_IMAGE == self.text_to_image_relationship):
                x_value = self.img_width//2 + self.img_offset_x
                y_value = self.base_y_offset + self.line_height//2
                text_available_width = Device.get_device().screen_width() - self.img_width - text_pad*2
            elif(TextToImageRelationship.BELOW_IMAGE == self.text_to_image_relationship):
                x_value = 0 
                y_pad = 20 #TODO get from somewhere
                y_value = (Display.get_top_bar_height() + y_pad*2 + self.img_height)  + self.line_height//2
                text_available_width = Device.get_device().screen_width() - text_pad * 2
            elif(TextToImageRelationship.ABOVE_IMAGE == self.text_to_image_relationship):
                x_value = 0 
                y_value = self.base_y_offset + self.line_height//2
                text_available_width = Device.get_device().screen_width() - text_pad * 2
            elif(TextToImageRelationship.TEXT_AROUND_LEFT_IMAGE == self.text_to_image_relationship):
                x_value = 0
                y_value = self.base_y_offset + self.line_height//2
                text_available_width = Device.get_device().screen_width() - text_pad*2
            elif(TextToImageRelationship.TEXT_AROUND_RIGHT_IMAGE == self.text_to_image_relationship):
                x_value = 0 
                y_value = self.base_y_offset + self.line_height//2
                text_available_width = self.get_img_x_starting() - text_pad*2

            y_value += visible_index * self.line_height

            if(TextToImageRelationship.TEXT_AROUND_LEFT_IMAGE == self.text_to_image_relationship and self.is_y_coord_in_img_box(y_value)):
                x_value += self.img_width//2 + self.img_offset_x
                text_available_width = Device.get_device().screen_width() - self.img_width - text_pad*2
            elif(TextToImageRelationship.TEXT_AROUND_RIGHT_IMAGE == self.text_to_image_relationship and self.is_y_coord_in_img_box(y_value)):
                text_available_width = Device.get_device().screen_width() - self.img_width - text_pad*2

            text_x_value = x_value + text_pad

            render_mode=RenderMode.MIDDLE_LEFT_ALIGNED
            scroll_amt = 0

            if actual_index == self.selected:
                color = Theme.text_color_selected(FontPurpose.LIST)
                if(self.selected_bg is not None):
                    Display.render_image(self.selected_bg,x_value, y_value, render_mode,crop_w=text_available_width + text_pad * 2)
                if(self.prev_index == self.selected):
                    scroll_amt = self.scroll_text_amount
                    if(time.time() - self.selected_same_entry_time > 1):
                        self.scroll_text_amount += 1
                else:
                    self.scroll_text_amount = 0
                    self.selected_same_entry_time = time.time()
            else:
                color = Theme.text_color(FontPurpose.LIST)

            if(self.show_icons and imageTextPair.get_icon() is not None):
                icon_width, icon_height = Display.render_image(imageTextPair.get_icon(),text_x_value, y_value, render_mode)
                text_x_value += icon_width + 5 #TODO get 5 from somewhere

            Display.render_text(self.scroll_string(imageTextPair.get_primary_text(),scroll_amt, text_available_width), text_x_value, y_value, color, FontPurpose.LIST,
                                    render_mode, crop_w=text_available_width, crop_h=None)
        self.prev_index = self.selected

    def get_img_x_starting(self):
        if(XRenderOption.LEFT ==self.image_render_mode.x_mode):
            return self.img_offset_x
        elif(XRenderOption.CENTER ==self.image_render_mode.x_mode):
            return self.img_offset_x - self.img_width // 2
        elif(XRenderOption.RIGHT ==self.image_render_mode.x_mode):
            return self.img_offset_x - self.img_width 
        else:
            #Assume left as default?
            return self.img_offset_x


    def is_y_coord_in_img_box(self, y):
        img_y_min = self.img_offset_y
        img_y_max = self.img_offset_y
        
        if(YRenderOption.TOP ==self.image_render_mode.y_mode):
            img_y_min = self.img_offset_y
            img_y_max = self.img_offset_y + self.img_width
        if(YRenderOption.CENTER ==self.image_render_mode.y_mode):
            img_y_min = self.img_offset_y - self.img_width//2 
            img_y_max = self.img_offset_y + self.img_width//2
        if(YRenderOption.BOTTOM ==self.image_render_mode.y_mode):
            img_y_min = self.img_offset_y + self.img_width 
            img_y_max = self.img_offset_y + self.img_width*2

        return img_y_min <= y <= img_y_max

    def _render_image(self, visible_options):
        for visible_index, (imageTextPair) in enumerate(visible_options):
            actual_index = self.current_top + visible_index
            imagePath = imageTextPair.get_image_path_ideal(self.img_width, self.img_height) if actual_index == self.selected else imageTextPair.get_image_path()
            if(actual_index == self.selected and imagePath is not None):
                Display.render_image(imagePath, 
                                     self.img_offset_x, 
                                     self.img_offset_y,
                                     self.image_render_mode,
                                     self.img_width,
                                     self.img_height)
