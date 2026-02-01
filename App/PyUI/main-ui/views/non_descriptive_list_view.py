from abc import abstractmethod
from typing import List
from display.display import Display
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from views.grid_or_list_entry import GridOrListEntry
from views.list_view import ListView

class NonDescriptiveListView(ListView):
    SHOW_ICONS = True
    DONT_SHOW_ICONS = False

    def __init__(self, top_bar_text,
                 options: List[GridOrListEntry],
                 selected_index : int, show_icons : bool, image_render_mode: RenderMode, selected_bg = None, usable_height = None):
        super().__init__()
        self.top_bar_text = top_bar_text
        self.set_options(options)
        self.selected = selected_index
        while(self.selected > len(options) and self.selected > 0):
            self.selected -= 1

        self.current_top = 0
        self.base_y_offset = Display.get_top_bar_height() + 5
        #TODO get line height padding from theme
        self.show_icons = show_icons
        self.image_render_mode = image_render_mode
        self.selected_bg = selected_bg
        self.line_height = self._calculate_line_height()   
        if(usable_height is None):
            usable_height = Display.get_usable_screen_height()
        self.max_rows = usable_height // self.line_height
        self.current_bottom = min(self.max_rows,len(options))
        self.center_selection()

    def set_options(self, options):
        self.options = options
        self.options_are_sorted = self.is_alphabetized(options)

    def options_are_alphabetized(self):
        return self.options_are_sorted
    
    def _calculate_line_height(self):
        text_line_height = Display.get_line_height(FontPurpose.LIST) + 10  # add 10px padding between lines
        icon_line_height = 0
        if(self.show_icons):
            for gridOrListEntry in self.options:
                if(gridOrListEntry.get_icon() is not None):
                    icon_w, icon_h = Display.get_image_dimensions(gridOrListEntry.get_icon())
                    icon_line_height = max(icon_line_height, icon_h)

        bg_height = 0
        if(self.selected_bg is not None):
            bg_w, bg_height = Display.get_image_dimensions(self.selected_bg)

        return max(text_line_height, icon_line_height, bg_height)



    @abstractmethod
    def _render_text(self, visible_options):
        pass

    @abstractmethod
    def _render_image(self, visible_options):
        pass

    def _render(self):
        visible_options = self.options[self.current_top:self.current_bottom]

        #ensure image is rendered last so it is on top of the text
        self._render_text(visible_options)
        self._render_image(visible_options)