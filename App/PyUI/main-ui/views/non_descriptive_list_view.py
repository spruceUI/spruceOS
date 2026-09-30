from abc import abstractmethod
from typing import List
from display.display import Display
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.list_view import ListView

class NonDescriptiveListView(ListView):
    USE_ICONS_FOR_LINE_HEIGHT_CALC = True
    DONT_USE_ICONS_FOR_LINE_HEIGHT_CALC = False

    def __init__(self, top_bar_text,
                 options: List[GridOrListEntry],
                 selected_index : int, use_icons_to_calculate_line_height : bool, image_render_mode: RenderMode, selected_bg = None, usable_height = None):
        super().__init__()
        self.top_bar_text = top_bar_text
        self.set_options(options)
        self.selected = selected_index
        while(self.selected > len(options) and self.selected > 0):
            self.selected -= 1

        self.current_top = 0
        self.base_y_offset = Display.get_top_bar_height() + 5
        #TODO get line height padding from theme
        self.use_icons_to_calculate_line_height = use_icons_to_calculate_line_height
        self.image_render_mode = image_render_mode
        self.selected_bg = selected_bg
        self.line_height = self._calculate_line_height(include_description_line=False)   
        if(usable_height is None):
            usable_height = Display.get_usable_screen_height()
        self.max_rows = usable_height // self.line_height
        self.current_bottom = min(self.max_rows,len(options))
        self.center_selection()

    def get_row_geometry(self):
        return self.base_y_offset, self.line_height

    def set_options(self, options):
        self.options = options
        self.options_are_sorted = self.is_alphabetized(options)

    def options_are_alphabetized(self):
        return self.options_are_sorted
    

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