

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
        target_width = 1280
        target_height = 768

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
                                cls.scale_image(
                                    full_path, target_width, target_height)
                            except Exception as e:
                                print(f"Error processing {full_path}: {e}")

    @classmethod
    def scale_image(cls, image_file, target_width, target_height):
        """Open an image and shrink it (preserving aspect ratio) to fit within target size."""
        from PIL import Image

        now = time.time()
        if now - cls._last_display_time >= 1.0:
            Display.clear("Box Art Resizer")
            Display.render_text_centered(f"Patching {image_file}",Device.screen_width()//2, Device.screen_height()//2,Theme.text_color_selected(FontPurpose.LIST), purpose=FontPurpose.LIST)
            Display.present()
            cls._last_display_time = now

        img = Image.open(image_file)
        width, height = img.size

        # Only shrink if necessary
        if width > target_width or height > target_height:
            aspect_ratio = width / height
            if width / target_width > height / target_height:
                # Width is the limiting factor
                new_width = target_width
                new_height = int(target_width / aspect_ratio)
            else:
                # Height is the limiting factor
                new_height = target_height
                new_width = int(target_height * aspect_ratio)

            img = img.resize((new_width, new_height), Image.LANCZOS)
            img.save(image_file)
            print(f"Scaled: {image_file} -> {new_width}x{new_height}")
