import os
import threading
import time

from utils.logger import PyUiLogger

class FileWatcher():

    def watch_file(self,path, callback, interval, repeat_trigger_for_mtime_granularity_issues):
        last_mtime = None
        prev_loop_executed_counter = 0.0
        last_mtime = os.stat(path).st_mtime_ns
        while True:
            try:
                mtime = os.stat(path).st_mtime_ns
                if mtime != last_mtime:
                    PyUiLogger.get_logger().info(f"{path} detection changed.")        
                    last_mtime = mtime
                    callback()
                    if repeat_trigger_for_mtime_granularity_issues:
                       prev_loop_executed_counter = 2.0
                elif(prev_loop_executed_counter > 0.0):
                    callback()
                    prev_loop_executed_counter -= interval
            except FileNotFoundError:
                PyUiLogger.get_logger().warning(f"{path} not found for file watcher.")        
            time.sleep(interval)

    def start_file_watcher(self,path, callback, interval=1.0, repeat_trigger_for_mtime_granularity_issues=False):
        stop_event = threading.Event()
        thread = threading.Thread(
            target=self.watch_file,
            args=(path, callback, interval, repeat_trigger_for_mtime_granularity_issues),
            daemon=True
        )
        thread.start()
        return thread, stop_event