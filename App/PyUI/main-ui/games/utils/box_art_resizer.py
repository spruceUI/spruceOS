

import os
import shutil
import threading
import time
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from utils.cached_exists import CachedExists
from utils.logger import PyUiLogger


class BoxArtResizer():
    _last_display_time = 0  # class-level timestamp
    _aborted = False
    _monitoring = False
    _to_delete = []

    @classmethod
    def patch_boxart(cls):
        cls.process_rom_folders()

    @classmethod
    def monitor_for_input(cls):
        while (cls._monitoring):
            if (Controller.get_input() and Controller.last_input() == ControllerInput.B):
                cls._monitoring = False
                cls._aborted = True

    @classmethod
    def process_image(cls, full_path):
        CachedExists.clear()
        target_medium_width, target_medium_height = Device.get_device().get_boxart_medium_resize_dimensions()
        target_small_width, target_small_height = Device.get_device().get_boxart_small_resize_dimensions()
        target_large_width, target_large_height = Device.get_device().get_boxart_large_resize_dimensions()

        qoi_full_path = os.path.splitext(full_path)[0] + ".qoi"
        if os.path.exists(qoi_full_path):
            # If so this has been already optimized
            return False

        cls.patched_count = cls.patched_count + 1

        now = time.time()
        if now - cls._last_display_time >= 1.0:
            Display.display_message_multiline(
                [f"Optimizing boxart {os.path.basename(full_path)}", f"Scanned {cls.scan_count}, Patched {cls.patched_count}", "", "Press B to Abort"])
            cls._last_display_time = now

        try:
            # Replace 'Imgs' with 'Imgs_large' in the path
            large_image_path = full_path.replace("Imgs", "Imgs_large", 1)
            qoi_large_path = qoi_full_path
            cls.create_interim_folders(full_path)
            if (not cls.scale_and_convert_image(full_path, large_image_path, target_large_width, target_large_height, qoi_large_path)):
                # Convert it
                try:
                    Device.get_device().get_image_utils().convert_from_png_to_qoi(full_path)
                    qoi_full_path = os.path.splitext(full_path)[0] + ".qoi"
                except Exception as e:
                    PyUiLogger().get_logger().warning(
                        f"Unable to convert {full_path} : {e}")
                    return False

                large_image_path = full_path
            else:
                qoi_full_path = os.path.splitext(full_path)[0] + ".qoi"
                shutil.move(qoi_full_path, qoi_large_path)

        except Exception as e:
            PyUiLogger.get_logger().warning(
                f"Issue converting for large image {full_path} : {e}")
            return False


        try:
            # Replace 'Imgs' with 'Imgs_med' in the path
            medium_image_path = full_path.replace("Imgs", "Imgs_med", 1)
            if (not cls.scale_and_convert_image(large_image_path, medium_image_path, target_medium_width, target_medium_height)):
                medium_image_path = full_path
        except Exception as e:
            PyUiLogger.get_logger().warning(
                f"Issue converting for medium image {full_path} : {e}")
            return False

        try:
            # Replace 'Imgs' with 'Imgs_small' in the path
            small_image_path = full_path.replace("Imgs", "Imgs_small", 1)
            cls.scale_and_convert_image(
                medium_image_path, small_image_path, target_small_width, target_small_height)
        except Exception as e:
            PyUiLogger.get_logger().warning(
                f"Issue converting for small image {full_path} : {e}")
            return False

        os.remove(full_path)
        for output_path in cls._to_delete:
            try:
                os.remove(output_path)
            except Exception as e:
                PyUiLogger.get_logger().warning(
                    f"Issue deleting {output_path}")

        return True
    
    @classmethod
    def create_interim_folders(cls, img_path):
        parts = img_path.split(os.sep)
        if "Imgs" in parts:
            idx = parts.index("Imgs")
            # Take everything up to the parent of 'Imgs'
            parent_folder = os.sep.join(parts[:idx])

            for size in ["Imgs_small", "Imgs_med", "Imgs_large"]:
                new_folder = os.path.join(parent_folder, size)
                os.makedirs(new_folder, exist_ok=True)
        else:
            PyUiLogger.get_logger().warning(f"'Imgs' folder not found in path: {img_path}")

    @classmethod
    def clear_interim_folders(cls, img_path):
        parts = img_path.split(os.sep)
        if "Imgs" in parts:
            idx = parts.index("Imgs")
            folder_path = os.sep.join(parts[:idx - 1]) if idx > 1 else os.sep

            target_medium_width, target_medium_height = Device.get_device().get_boxart_medium_resize_dimensions()
            target_small_width, target_small_height = Device.get_device().get_boxart_small_resize_dimensions()
            target_large_width, target_large_height = Device.get_device().get_boxart_large_resize_dimensions()

            # This is always temporary
            shutil.rmtree(os.path.join(folder_path, "Imgs_large"), ignore_errors=True)
            # If medium and large are the same size, get rid of Imgs_med as it unused
            if (target_large_width == target_medium_width and target_large_height == target_medium_height):
                shutil.rmtree(os.path.join(folder_path, "Imgs_med"), ignore_errors=True)

            # If small and medium are the same size, get rid of Imgs_small as it unused
            if (target_medium_width == target_small_width and target_medium_height == target_small_height):
                shutil.rmtree(os.path.join(folder_path, "Imgs_small"), ignore_errors=True)



    @classmethod
    def patch_boxart_list(cls, image_list):
        cls.scan_count = len(image_list)
        cls.patched_count = 0
        threading.Thread(target=cls.monitor_for_input, daemon=True).start()

        for path in image_list:
            cls.create_interim_folders(path)
            cls.process_image(path)
            if (cls._aborted):
                Display.display_message(f"Aborting boxart patching", 2000)
                cls._monitoring = False
                return

        for path in image_list:
            cls.clear_interim_folders(path)

        cls._monitoring = False
        Display.display_message(f"All boxart is optimized", 2000)

    @classmethod
    def process_rom_folders(cls):
        """Search through ROM directories and scale images inside Imgs folders."""
        Display.display_message(f"Starting boxart patching", 500)
        rom_paths = ["/mnt/SDCARD/Roms/", "/media/sdcard1/Roms/"]
        target_medium_width, target_medium_height = Device.get_device().get_boxart_medium_resize_dimensions()
        target_small_width, target_small_height = Device.get_device().get_boxart_small_resize_dimensions()
        target_large_width, target_large_height = Device.get_device().get_boxart_large_resize_dimensions()
        cls._aborted = False
        cls._monitoring = True
        cls.scan_count = 0
        cls.patched_count = 0

        threading.Thread(target=cls.monitor_for_input, daemon=True).start()
        for base_path in rom_paths:
            if not os.path.exists(base_path):
                continue

            cls.scan_count = 0
            cls.patched_count = 0
            for folder_name in os.listdir(base_path):
                folder_path = os.path.join(base_path, folder_name)
                if not os.path.isdir(folder_path):
                    continue

                imgs_path = os.path.join(folder_path, "Imgs")
                if not os.path.exists(imgs_path):
                    continue
                cls.create_interim_folders(imgs_path)
                for root, _, files in os.walk(imgs_path):
                    for file in files:
                        if file.lower().endswith((".png", ".jpg", ".jpeg", ".bmp", ".webp")):
                            cls.scan_count = cls.scan_count + 1
                            cls._to_delete = []
                            if (cls._aborted):
                                Display.display_message(f"Aborting boxart patching", 2000)
                                cls._monitoring = False
                                return

                            full_path = os.path.join(root, file)
                            cls.process_image(full_path)

                # This is always temporary
                shutil.rmtree(os.path.join(folder_path, "Imgs_large"), ignore_errors=True)
                # If medium and large are the same size, get rid of Imgs_med as it unused
                if (target_large_width == target_medium_width and target_large_height == target_medium_height):
                    shutil.rmtree(os.path.join(folder_path, "Imgs_med"), ignore_errors=True)

                # If small and medium are the same size, get rid of Imgs_small as it unused
                if (target_medium_width == target_small_width and target_medium_height == target_small_height):
                    shutil.rmtree(os.path.join(folder_path, "Imgs_small"), ignore_errors=True)

        cls._monitoring = False
        Display.display_message(f"All boxart is optimized", 2000)

    # Don't want to clean this up but be aware resize_png_path will be deleted

    @classmethod
    def scale_and_convert_image(cls, image_file, resize_png_path, target_width, target_height, qoi_path=None):
        """Open an image and shrink it (preserving aspect ratio) to fit within target size."""

        if (qoi_path is None):
            # Early return if the QOI version already exists
            qoi_path = os.path.splitext(resize_png_path)[0] + ".qoi"

        if os.path.exists(qoi_path):
            return True

        needed_shrink = Device.get_device().get_image_utils().shrink_image_if_needed(
            image_file, resize_png_path, target_width, target_height)
        if (needed_shrink):
            try:
                Device.get_device().get_image_utils().convert_from_png_to_qoi(resize_png_path, qoi_path)
                cls._to_delete.append(resize_png_path)
                return needed_shrink
            except Exception as e:
                PyUiLogger().get_logger().warning(
                    f"Unable to convert {resize_png_path} : {e}")

        return needed_shrink
