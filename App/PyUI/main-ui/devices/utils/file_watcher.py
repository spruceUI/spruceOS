import os
import threading
import time

from utils.logger import PyUiLogger

class FileWatcher():

    def watch_file(self,path, callback, interval=1.0):
        last_mtime = None
        while True:
            try:
                mtime = os.path.getmtime(path)
                if last_mtime is None:
                    last_mtime = mtime
                elif mtime != last_mtime:
                    last_mtime = mtime
                    callback()
            except FileNotFoundError:
                PyUiLogger.get_logger().warning(f"{path} not found for file watcher.")        
            time.sleep(interval)

    def start_file_watcher(self,path, callback, interval=1.0):
        stop_event = threading.Event()
        thread = threading.Thread(
            target=self.watch_file,
            args=(path, callback, interval),
            daemon=True
        )
        thread.start()
        return thread, stop_event