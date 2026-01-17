from concurrent.futures import ThreadPoolExecutor
import os
import threading
from typing import Callable, TypeVar

from devices.device import Device
from utils.cached_exists import CachedExists

T = TypeVar('T')  # Generic input type

class GridOrListEntry:
    
    # Shared ThreadPoolExecutor for all instances 
    _desc_executor = ThreadPoolExecutor(max_workers=1)

    def __init__(
        self,
        primary_text,
        value_text=None,
        image_path=None,
        image_path_selected=None,
        description=None,
        icon=None,
        value: T = None,
        image_path_searcher: Callable[[T], str] = None,
        image_path_selected_searcher: Callable[[T], str] = None,
        icon_searcher: Callable[[T], str] = None,
        primary_text_long=None,
        extra_data=None
    ):        
        self.primary_text = primary_text
        self.primary_text_long = primary_text_long
        self.value_text = value_text
        self.image_path = image_path
        self.image_path_searcher = image_path_searcher
        self.image_path_selected_searcher = image_path_selected_searcher
        self.icon_searcher = icon_searcher

        self.image_path_selected = image_path_selected or image_path
        self.value = value if value is not None else primary_text
        self.icon = icon

        self._description = None
        self._description_func = None
        self._description_event = threading.Event()
        self.extra_data = extra_data
        if callable(description):
            self._description_func = description
            # Submit to thread pool and get Future
            self._description_future = self._desc_executor.submit(self._load_description_func)
        else:
            self._description_future = None
            self._description = description
            self._description_event.set()  # No async loading needed

    def _load_description_func(self):
        try:
            desc = self._description_func()
        except Exception as e:
            desc = f"[Error loading description: {e}]"
        self._description = desc
        self._description_event.set()
        return desc

    def get_description(self):
        # If description is loading asynchronously, block here until done
        if self._description_future is not None:
            # Wait for future to complete if it hasn't yet
            self._description_future.result()
        else:
            # If no future, make sure event is set
            self._description_event.wait()

        return self._description


    def __str__(self) -> str:
        return self.primary_text

    def __repr__(self) -> str:
        return f"<GridOrListEntry {self.primary_text!r}>"
    
    def get_image_path(self):
        if self.image_path is None and self.image_path_searcher is not None:
            self.image_path = self.image_path_searcher(self.value)
            self.image_path_searcher = None

        return self.image_path
    
    def get_image_path_selected(self):
        if self.image_path_selected is None and self.image_path_selected_searcher is not None:
            self.image_path_selected = self.image_path_selected_searcher(self.value)
            self.image_path_selected_searcher = None
        return self.image_path_selected
        
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
        return self.primary_text
    
    def get_primary_text_long(self):
        return self.primary_text_long or self.primary_text
    
    def get_value_text(self):
        return self.value_text
    
    def get_value(self):
        return self.value
    
    def get_icon(self):
        if self.icon is None and self.icon_searcher is not None:
            return self.icon_searcher(self.value)
        return self.icon
    
    def __eq__(self, other):
        if not isinstance(other, GridOrListEntry):
            return NotImplemented
        return self.value == other.value

    def get_extra_data(self):
        return self.extra_data