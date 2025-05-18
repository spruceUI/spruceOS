from typing import List
from display.display import Display
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
import sdl2
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.non_descriptive_list_view import NonDescriptiveListView

class TextListView(NonDescriptiveListView):
    SHOW_ICONS = True
    DONT_SHOW_ICONS = False

    def __init__(self, top_bar_text,
                 options: List[GridOrListEntry], 
                 selected_index : int, show_icons : bool, image_render_mode: RenderMode, selected_bg = None, usable_height = None):
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

    def _render_text(self, visible_options):
        for visible_index, (imageTextPair) in enumerate(visible_options):
            actual_index = self.current_top + visible_index
           
            x_value = self.starting_x_offset
            y_value = self.base_y_offset + visible_index * self.line_height

            if actual_index == self.selected:
                color = Theme.text_color_selected(FontPurpose.LIST)
                if(self.selected_bg is not None):
                    Display.render_image(self.selected_bg,self.view_x, y_value)
            else:
                color = Theme.text_color(FontPurpose.LIST)

            if(self.show_icons and imageTextPair.get_icon() is not None):
                icon_width, icon_height = Display.render_image(imageTextPair.get_icon(),x_value, y_value)
                x_value += icon_width
            else:
                pass

            Display.render_text(imageTextPair.get_primary_text(), x_value, y_value + self.line_height//2, color, FontPurpose.LIST,
                                    RenderMode.MIDDLE_LEFT_ALIGNED)


    def _render_image(self, visible_options):
        pass
