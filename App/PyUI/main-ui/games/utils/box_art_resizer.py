

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
        target_width, target_height = Device.get_boxart_resize_dimensions()
        target_small_width, target_small_height = Device.get_boxart_small_resize_dimensions()

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
                os.makedirs(os.path.join(folder_path, "Imgs_small"), exist_ok=True)
                os.makedirs(os.path.join(folder_path, "Imgs_med"), exist_ok=True)

                for root, _, files in os.walk(imgs_path):
                    for file in files:
                        if file.lower().endswith((".png", ".jpg", ".jpeg")):
                            full_path = os.path.join(root, file)
                            try:
                                # Replace 'Imgs' with 'Imgs_small' in the path
                                small_image_path = full_path.replace(
                                    os.path.join(folder_path, "Imgs"),
                                    os.path.join(folder_path, "Imgs_small"),
                                )

                                if os.path.exists(small_image_path):
                                    cls.scale_image(small_image_path,small_image_path, target_small_width, target_small_height)
                                else:
                                    cls.scale_image(full_path,small_image_path, target_small_width, target_small_height)
                            except Exception as e:
                                print(f"Error processing {full_path}: {e}")

                            try:
                                # Replace 'Imgs' with 'Imgs_med' in the path
                                medium_image_path = full_path.replace(
                                    os.path.join(folder_path, "Imgs"),
                                    os.path.join(folder_path, "Imgs_med"),
                                )
                                if os.path.exists(medium_image_path):
                                    cls.scale_image(medium_image_path,medium_image_path, target_small_width, target_small_height)
                                else:
                                    cls.scale_image(full_path,medium_image_path, target_small_width, target_small_height)
                            except Exception as e:
                                print(f"Error processing {full_path}: {e}")



    @classmethod
    def scale_image(cls, image_file, output_path, target_width, target_height):
        """Open an image and shrink it (preserving aspect ratio) to fit within target size."""

        now = time.time()
        if now - cls._last_display_time >= 1.0:
            Display.display_message(f"Patching {os.path.basename(image_file)}")
            Display.present()
            cls._last_display_time = now

        Device.get_image_utils().shrink_image_if_needed(image_file,output_path,target_width, target_height)
