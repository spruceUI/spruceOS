import json
import os
import tempfile
import threading

from utils.logger import PyUiLogger


class UserConfig:
    FILEPATH = "/mnt/SDCARD/Saves/pyui-common.json"

    _lock = threading.Lock()
    config = {}

    @classmethod
    def reload_config(cls):
        with cls._lock:
            try:
                with open(cls.FILEPATH, 'r') as f:
                    cls.config = json.load(f)
            except json.JSONDecodeError as e:
                PyUiLogger.get_logger().error(f"Error loading pyui-common config {e}")
                cls.config = {}
            except FileNotFoundError:
                cls.config = {}

    @classmethod
    def save_config(cls):
        with cls._lock:
            try:
                dirpath = os.path.dirname(cls.FILEPATH)

                with tempfile.NamedTemporaryFile(
                    'w',
                    dir=dirpath,
                    delete=False
                ) as tmp:
                    json.dump(cls.config, tmp, indent=4)
                    tmp.flush()
                    os.fsync(tmp.fileno())
                    tempname = tmp.name

                os.replace(tempname, cls.FILEPATH)

            except Exception as e:
                raise RuntimeError(f"Failed to save config: {e}")

    @classmethod
    def get_ignore_articles_when_sorting(cls):
        return cls.config.get("ignoreArticlesWhenSorting", False)

    @classmethod
    def set_ignore_articles_when_sorting(cls, value):
        cls.config["ignoreArticlesWhenSorting"] = value
        cls.save_config()
