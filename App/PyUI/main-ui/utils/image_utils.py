
from abc import ABC, abstractmethod


class ImageUtils(ABC):
    @abstractmethod
    def convert_from_jpg_to_qoi(self, jpg_path: str, qoi_path: str) -> None:
        pass

    @abstractmethod
    def convert_from_jpg_to_png(self, jpg_path: str, png_path: str) -> None:
        pass

    @abstractmethod
    def shrink_image_if_needed(self, input_path: str, output_path: str, max_width: int, max_height: int) -> bool:
        pass

    @abstractmethod
    def resize_image(self, input_path: str, output_path: str, max_width: int, max_height: int, preserve_aspect_ratio=True, target_alpha_channel=None) -> None:
        pass

    @abstractmethod
    def get_image_dimensions(self, path: str) -> tuple[int, int]:
        pass

    @abstractmethod
    def convert_from_png_to_qoi(self, png_path: str, qoi_path: str | None = None) -> str | None:
        pass

    
