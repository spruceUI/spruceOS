
import threading
from typing import Optional
from apps.app_config import AppConfig
from menus.app.apps_list_manager import AppListManager

class AppsManager:
    _appsManager = Optional[AppListManager]
    _init_event = threading.Event()  # signals when initialize() has been called

    @classmethod
    def initialize(cls, apps_config_path: str):
        cls._appsManager = AppListManager(apps_config_path)
        cls._init_event.set()  # unblock waiting methods
    
    @classmethod
    def _wait_for_init(cls):
        cls._init_event.wait()  # blocks until initialize() happens

    @classmethod
    def hide_app(cls, app_config: AppConfig):
        cls._wait_for_init()
        cls._appsManager.get_app(app_config).hidden = True
        cls._appsManager.save_to_file()

    @classmethod
    def show_app(cls, app_config: AppConfig):
        cls._wait_for_init()
        cls._appsManager.get_app(app_config).hidden = False
        cls._appsManager.save_to_file()

    @classmethod
    def is_hidden(cls, app_config: AppConfig) -> bool:
        cls._wait_for_init()
        app_entry = cls._appsManager.get_app(app_config)
        if(app_entry is None):
            return False
        else:
            return app_entry.hidden
