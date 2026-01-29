
from abc import ABC, abstractmethod


class ImageUtils(ABC):
    @abstractmethod
    def convert_from_jpg_to_qoi(self, jpg_path, png_path):
        pass

    @abstractmethod
    def convert_from_jpg_to_png(self, jpg_path, png_path):
        pass

    @abstractmethod
    def shrink_image_if_needed(self, input_path, output_path, width, height):
        pass

    @abstractmethod
    def resize_image(self, input_path, output_path, width, height, preserve_aspect_ratio=True, target_alpha_channel=None):
        pass

    @abstractmethod
    def get_image_dimensions(self, path):
        pass

    @abstractmethod
    def convert_from_png_to_qoi(self, png_path,qoi_path=None):
        pass

    