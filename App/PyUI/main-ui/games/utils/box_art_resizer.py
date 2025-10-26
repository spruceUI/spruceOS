

import os
import time
from devices.device import Device
from display.display import Display
from display.font_purpose import FontPurpose
from themes.theme import Theme
from utils.logger import PyUiLogger


class BoxArtResizer():
    _last_display_time = 0  # class-level timestamp

    @classmethod
    def patch_boxart(cls):
        cls.process_rom_folders()

    @classmethod
    def process_rom_folders(cls):
        """Search through ROM directories and scale images inside Imgs folders."""
        rom_paths = ["/mnt/SDCARD/Roms/", "/media/sdcard1/Roms/"]
        target_width = 294
        target_height = 294

        for base_path in rom_paths:
            if not os.path.exists(base_path):
                continue

            for folder_name in os.listdir(base_path):
                folder_path = os.path.join(base_path, folder_name)
                if not os.path.isdir(folder_path):
                    continue

                imgs_path = os.path.join(folder_path, "Imgs")
                if not os.path.exists(imgs_path):
                    continue

                for root, _, files in os.walk(imgs_path):
                    for file in files:
                        if file.lower().endswith((".png", ".jpg", ".jpeg")):
                            full_path = os.path.join(root, file)
                            try:
                                PyUiLogger().get_logger().info(f"Checking {full_path} for resizing")
                                cls.scale_image(
                                    full_path, target_width, target_height)
                            except Exception as e:
                                print(f"Error processing {full_path}: {e}")

    @classmethod
    def scale_image(cls, image_file, target_width, target_height):
        """Open an image and shrink it (preserving aspect ratio) to fit within target size."""

        now = time.time()
        if now - cls._last_display_time >= 1.0:
            Display.display_message(f"Patching {os.path.basename(image_file)}")
            Display.present()
            cls._last_display_time = now

        Device.get_image_utils().shrink_image_if_needed(image_file,image_file,target_width, target_height)
