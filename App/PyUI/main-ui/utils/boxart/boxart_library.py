import os
import random
import threading

from devices.device import Device
from utils.logger import PyUiLogger


class BoxArtLibrary:
    """
    Collects every box art image on the card so the screensaver can cycle through them.

    The scan walks <roms dir>/<System>/<Imgs>/ recursively, which is where the scraper
    writes mirrored box art. Only the canonical Imgs folder is descended into, so the
    Imgs_med/Imgs_small/Imgs_large siblings left behind by BoxArtResizer don't produce
    duplicate covers.

    Scanning happens on a daemon thread the first time it's needed, never at startup,
    since most users won't turn the boxart screensaver on. Until it finishes next_image()
    returns None and the caller falls back to a plain background.
    """

    IMAGE_EXTS = (".qoi", ".png", ".jpg", ".jpeg", ".bmp", ".webp")
    SECONDARY_ROMS_DIR = "/media/sdcard1/Roms/"

    _images = []
    _order = []
    _position = 0
    _scan_started = False
    _scan_complete = False

    @classmethod
    def ensure_scanned(cls):
        if cls._scan_started:
            return
        cls._scan_started = True
        threading.Thread(target=cls._scan, daemon=True).start()

    @classmethod
    def is_scanning(cls):
        return cls._scan_started and not cls._scan_complete

    @classmethod
    def next_image(cls):
        if not cls._scan_complete or not cls._images:
            return None

        if cls._position >= len(cls._order):
            cls._reshuffle()

        if not cls._order:
            return None

        image = cls._order[cls._position]
        cls._position += 1
        return image

    @classmethod
    def discard(cls, image_path):
        """Drop an image that failed to load so it isn't picked again."""
        try:
            cls._images.remove(image_path)
        except ValueError:
            pass
        try:
            cls._order.remove(image_path)
            cls._position = max(0, cls._position - 1)
        except ValueError:
            pass

    @classmethod
    def reset(cls):
        """Restart the shuffled walk. Keeps the scanned list, which is the expensive part."""
        cls._order = []
        cls._position = 0

    @classmethod
    def _reshuffle(cls):
        cls._order = list(cls._images)
        random.shuffle(cls._order)
        cls._position = 0

    @classmethod
    def _get_roms_dirs(cls):
        dirs = []
        try:
            roms_dir = Device.get_device().get_roms_dir()
            if roms_dir:
                dirs.append(roms_dir)
        except Exception as e:
            PyUiLogger.get_logger().error(f"BoxArtLibrary could not resolve roms dir: {e}")

        if cls.SECONDARY_ROMS_DIR not in dirs and os.path.isdir(cls.SECONDARY_ROMS_DIR):
            dirs.append(cls.SECONDARY_ROMS_DIR)

        return dirs

    @classmethod
    def _scan(cls):
        images = []
        try:
            imgs_folder_name = Device.get_device().get_game_images_folder_name()
            for roms_dir in cls._get_roms_dirs():
                if not os.path.isdir(roms_dir):
                    continue
                for system_name in os.listdir(roms_dir):
                    imgs_path = os.path.join(roms_dir, system_name, imgs_folder_name)
                    if not os.path.isdir(imgs_path):
                        continue
                    for root, _, files in os.walk(imgs_path):
                        for file in files:
                            if file.startswith('.'):
                                continue
                            if file.lower().endswith(cls.IMAGE_EXTS):
                                images.append(os.path.join(root, file))
        except Exception as e:
            PyUiLogger.get_logger().error(f"BoxArtLibrary scan failed: {e}")

        # Single assignment so readers never see a partial list
        cls._images = images
        cls._scan_complete = True
        PyUiLogger.get_logger().info(f"BoxArtLibrary found {len(images)} box art images")
