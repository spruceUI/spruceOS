import time
from typing import List
from display.display import Display
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.non_descriptive_list_view import NonDescriptiveListView

class TextListView(NonDescriptiveListView):
    SHOW_ICONS = True
    DONT_SHOW_ICONS = False

    def __init__(self, top_bar_text,
                 options: List[GridOrListEntry], 
                 selected_index : int, show_icons : bool, image_render_mode: RenderMode, selected_bg = None, usable_height = None,
                 allow_scrolling=False):
        super().__init__(top_bar_text=top_bar_text,
                         options=options,
                         selected_index=selected_index,
                         show_icons=show_icons,
                         image_render_mode=image_render_mode,
                         selected_bg=selected_bg,
                         usable_height=usable_height)
        self.starting_x_offset = 20  #TODO get this from somewhere
        self.view_x = 0
        self.view_y = 0
        self.scroll_text_amount = 0
        text_pad = 20  #TODO get this from somewhere
        self.text_available_width = text_pad*2 #just take up as much space as needed
        self.selected_same_entry_time = time.time()
        self.prev_index = 0
        self.allow_scrolling = allow_scrolling

    def _render_text(self, visible_options):
        for visible_index, (imageTextPair) in enumerate(visible_options):
            actual_index = self.current_top + visible_index
           
            x_value = self.starting_x_offset
            y_value = self.base_y_offset + visible_index * self.line_height

            scroll_amt = 0

            if actual_index == self.selected:
                if(self.selected_bg is not None):
                    Display.render_image(self.selected_bg,self.view_x, y_value)
                color = Theme.text_color_selected(FontPurpose.LIST)

                scroll_amt = self.scroll_text_amount

                if(self.prev_index == actual_index):
                    scroll_amt = self.scroll_text_amount
                    if(time.time() - self.selected_same_entry_time > 1):
                        self.scroll_text_amount += 1
                else:
                    self.scroll_text_amount = 0
                    self.selected_same_entry_time = time.time()

            else:
                color = Theme.text_color(FontPurpose.LIST)

            if(self.show_icons and imageTextPair.get_icon() is not None):
                icon_width, icon_height = Display.render_image(imageTextPair.get_icon(),x_value, y_value)
                x_value += icon_width
            else:
                pass

            display_text = imageTextPair.get_primary_text()
            if(self.allow_scrolling):
                display_text = self.scroll_string(imageTextPair.get_primary_text(),scroll_amt, self.text_available_width)
                
            Display.render_text(display_text, x_value, y_value + self.line_height//2, color, FontPurpose.LIST,
                                    RenderMode.MIDDLE_LEFT_ALIGNED)
        self.prev_index = self.selected


    def _render_image(self, visible_options):
        pass
