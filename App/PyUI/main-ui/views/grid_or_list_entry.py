

from typing import Callable, TypeVar

from menus.games.utils.rom_info import RomInfo


T = TypeVar('T')  # Generic input type

class GridOrListEntry:
    def __init__(
        self,
        primary_text,
        value_text=None,
        image_path=None,
        image_path_selected=None,
        description=None,
        icon=None,
        value : T =None,
        image_path_searcher: Callable[[T], str] = None,
        image_path_selected_searcher: Callable[[T], str] = None,
        icon_searcher: Callable[[T], str] = None
    ):        
        self.primary_text = primary_text
        self.value_text = value_text
        self.image_path = image_path
        self.image_path_searcher = image_path_searcher
        self.image_path_selected_searcher = image_path_selected_searcher
        self.icon_searcher = icon_searcher

        if(image_path_selected is None):
            self.image_path_selected = image_path
        else:
            self.image_path_selected = image_path_selected

        if(value is None): 
            self.value = primary_text
        else:
            self.value = value

        self.description = description
        self.icon = icon

    def get_image_path(self):
        if(self.image_path is None and self.image_path_searcher is not None):
            return self.image_path_searcher(self.value)
        return self.image_path
    
    def get_image_path_selected(self):
        if(self.image_path_selected is None and self.image_path_selected_searcher is not None):
            return self.image_path_selected_searcher(self.value)
        return self.image_path_selected
    
    def get_primary_text(self):
        return self.primary_text
    
    def get_value_text(self):
        return self.value_text
    
    def get_value(self):
        return self.value
    
    def get_description(self):
        return self.description

    def get_icon(self):
        if(self.icon is None and self.icon_searcher is not None):
            return self.icon_searcher(self.value)
        return self.icon
    
    def get_value(self):
        return self.value
