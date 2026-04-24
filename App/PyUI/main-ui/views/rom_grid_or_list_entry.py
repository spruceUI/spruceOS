import os
from typing import Callable, TypeVar

from devices.device import Device
from devices.miyoo.user_config import UserConfig
from utils.cached_exists import CachedExists
from views.util.image_searcher import ImageSearcher

T = TypeVar('T')  # Generic input type

class RomGridOrListEntry:
    __slots__ = (
        "display_name",
        "folder_name",
        "value",
        "game_entry",
        "prefer_savestate_screenshot",
        "get_image_path_fn",
        "image_path",
        "searched_image_path",
        "get_favorite_icon",
        "icon",
        "searched_icon")
        
    def __init__(
        self,
        display_name,
        folder_name,
        rom_info,
        game_entry,
        prefer_savestate_screenshot,
        get_image_path_fn,
        get_favorite_icon
    ):        
        self.display_name = display_name
        self.folder_name = folder_name
        self.value = rom_info
        self.game_entry = game_entry
        self.prefer_savestate_screenshot = prefer_savestate_screenshot
        self.get_image_path_fn = get_image_path_fn
        self.image_path=None
        self.searched_image_path = False
        self.get_favorite_icon = get_favorite_icon
        self.icon = None
        self.searched_icon = False

    def get_description(self):
        return self.folder_name


    def __str__(self) -> str:
        return self.display_name

    def __repr__(self) -> str:  
        return f"<RomGridOrListEntry {self.display_name!r}>"    
    
    def get_image_path(self):
        if not self.searched_image_path:
            self.searched_image_path = True
            if self.get_image_path_fn is not None:
                self.image_path = self.get_image_path_fn(self.value, self.game_entry, self.prefer_savestate_screenshot)

        return self.image_path
    
    def get_image_path_selected(self):
        if not self.searched_image_path:
            self.searched_image_path = True
            if self.get_image_path_fn is not None:
                self.image_path = self.get_image_path_fn(self.value, self.game_entry, self.prefer_savestate_screenshot)
        return self.image_path
        
    def get_image_path_variant(self, image_path: str, variant_name: str):
        if image_path is None:
            return image_path

        # Check if it contains the base "Imgs" directory
        marker = os.path.sep + "Imgs" + os.path.sep
        if marker in image_path:
            variant_path = image_path.replace(
                marker, os.path.sep + f"Imgs_{variant_name}" + os.path.sep
            )

            if CachedExists.exists(variant_path):
                return variant_path

        if("small" == variant_name):
            return self.get_image_path_variant(image_path,"med")
        else:
            return image_path

    def get_image_path_small(self,image_path: str):
        return self.get_image_path_variant(image_path,"small")

    def get_image_path_medium(self,image_path: str):
        return self.get_image_path_variant(image_path, "med")
    
    def get_image_path_ideal(self, target_width, target_height):
        return self.get_properly_sized_image(self.get_image_path(), target_width, target_height)
    
    def get_image_path_selected_ideal(self, target_width, target_height):
        return self.get_properly_sized_image(self.get_image_path_selected(), target_width, target_height)

    def get_properly_sized_image(self, image_path, target_width, target_height):
        small_width, small_height = Device.get_device().get_boxart_small_resize_dimensions()
        medium_width, medium_height = Device.get_device().get_boxart_medium_resize_dimensions()

        if(target_width is not None and target_width <= small_width):
            #PyUiLogger.get_logger().info(f"Going with small due to width {target_width} <= {small_width}")
            return self.get_image_path_small(image_path)
        elif(target_height is not None and target_height <= small_height):
            #PyUiLogger.get_logger().info(f"Going with small due to height {target_height} <= {small_height}")
            return self.get_image_path_small(image_path)
        elif(target_width is not None and target_width <= medium_width):
            #PyUiLogger.get_logger().info(f"Going with medium due to width {target_width} <= {medium_width}")
            return self.get_image_path_medium(image_path)
        elif(target_height is not None and target_height <= medium_height):
            #PyUiLogger.get_logger().info(f"Going with medium due to width {target_height} <= {medium_height}")
            return self.get_image_path_medium(image_path)
        else :
            #PyUiLogger.get_logger().info(f"Going with full size image. Target dimensions are  {target_width} x {target_height}")
            return image_path

    def get_primary_text(self):
        return self.display_name
    
    def get_primary_text_long(self):
        return self.display_name
    
    def get_sort_key(self):
        text = self.get_primary_text().strip() or ""
        lower = text.lower()

        if(UserConfig.get_ignore_articles_when_sorting()):
            for article in ("the ", "a ", "an "):
                if lower.startswith(article):
                    return (text[len(article):] + ", " + article.strip()).lower()
                    
        return lower        

    def get_value_text(self):
        return None
    
    def get_value(self):
        return self.value
    
    def get_icon(self):
        if not self.searched_icon:
            self.searched_icon = True
            if self.get_favorite_icon is not None:
                self.icon = self.get_favorite_icon(self.value)
        return self.icon
    
    def __eq__(self, other):
        if not isinstance(other, RomGridOrListEntry):
            return NotImplemented
        return self.value == self.value

    def get_extra_data(self):
        return self.extra_data
    
    def contains_potential_icon(self):
        return self.icon is not None or self.icon_searcher is not None